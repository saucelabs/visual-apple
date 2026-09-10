#!/bin/bash
# Run the SAME Swift and Objective-C consumer tests against source SPM or a binary.
set -euo pipefail
export LC_ALL=C
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 2 ]] || fail 'Usage: Scripts/test.sh {source|binary} {iphone|ipad|tvos|macos}'
case "$1" in source) project=Source;; binary) project=Binary;; *) fail 'Unknown distribution';; esac
case "$2" in
  iphone) scheme=iOS; platform='iOS Simulator'; prefix=iPhone;;
  ipad) scheme=iOS; platform='iOS Simulator'; prefix=iPad;;
  tvos) scheme=tvOS; platform='tvOS Simulator'; prefix='Apple TV';;
  macos) scheme=macOS; platform=macOS; prefix='My Mac';;
  *) fail 'Unknown device family';;
esac
[[ $(uname -s) == Darwin ]] || fail 'A Mac with full Xcode is required.'
root=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$root"
[[ ! -L build ]] || fail 'Refusing a symlinked build directory.'
mkdir -p build
run=$(mktemp -d "$root/build/test-$1-$2.XXXXXXXX")
trap 'status=$?; printf "Results and logs: %s\n" "$run"; exit "$status"' EXIT
xcodebuild -version > "$run/toolchain.log"
xcode_version=$(sed -n 's/^Xcode //p' "$run/toolchain.log")
xcode_major=${xcode_version%%.*}
[[ $xcode_major =~ ^[0-9]+$ ]] || fail 'Unrecognized Xcode version.'
[[ $xcode_major -ge 26 ]] || fail 'Select Xcode 26 or newer.'
xcrun swift --version >> "$run/toolchain.log"
cat "$run/toolchain.log"
if [[ $1 == binary ]]; then
  [[ -d dist/SauceVisual.xcframework ]] || fail 'Build or unpack dist/SauceVisual.xcframework first.'
fi
args=(-project "$root/Tests/Integration/$project.xcodeproj" -scheme "Consumer-$scheme"
      -derivedDataPath "$run/DerivedData" CODE_SIGNING_ALLOWED=NO)
if [[ $2 == macos ]]; then
  destination="platform=macOS,arch=$(uname -m)"
else
  # Start CoreSimulator discovery and retain its inventory for failed CI runs.
  simulator_diagnostics() {
    xcrun simctl list runtimes > "$run/simulator-runtimes.log" 2>&1 || true
    xcrun simctl list devices available > "$run/simulator-devices.log" 2>&1 || true
  }
  simulator_diagnostics
  udid=''
  for attempt in 1 2 3 4 5 6; do
    attempt_log="$run/destinations-attempt-$attempt.log"
    if xcodebuild "${args[@]}" -showdestinations > "$attempt_log" 2>&1; then
      udid=$(awk -v platform="$platform" -v prefix="$prefix" -v requested="${SIMULATOR_UDID:-}" '
        /Available destinations/ { available=1; next }
        /Ineligible destinations/ { available=0 }
        available && /\{/ {
          p=""; id=""; name=""
          count=split($0, fields, ",")
          for (i=1; i<=count; i++) {
            field=fields[i]; sub(/^[[:space:]{]+/, "", field); sub(/[[:space:]}]+$/, "", field)
            if (field ~ /^platform:/) { sub(/^platform:[[:space:]]*/, "", field); p=field }
            if (field ~ /^id:/) { sub(/^id:[[:space:]]*/, "", field); id=field }
            if (field ~ /^name:/) { sub(/^name:[[:space:]]*/, "", field); name=field }
          }
          if (!found && p==platform && index(name,prefix)==1 && length(id)==36 &&
              id ~ /^[0-9A-Fa-f-]+$/ && (requested=="" || requested==id)) {
            print id; found=1
          }
        }' "$attempt_log")
    fi
    cp "$attempt_log" "$run/destinations.log"
    if [[ -n "$udid" ]]; then break; fi
    if [[ $attempt -lt 6 ]]; then
      printf 'No eligible %s simulator on discovery attempt %s/6; retrying in 5 seconds.\n' "$2" "$attempt" >&2
      sleep 5
    fi
  done
  if [[ -z "$udid" ]]; then
    simulator_diagnostics
    cat "$run/destinations.log" "$run/simulator-runtimes.log" "$run/simulator-devices.log" >&2
    fail "No eligible $2 simulator after 6 discovery attempts. See $run."
  fi
  destination="platform=$platform,id=$udid"
fi
printf 'Distribution: %s; destination: %s\n' "$1" "$destination" | tee "$run/destination.log"
xcodebuild "${args[@]}" test -configuration Debug -destination "$destination" \
  -destination-timeout 180 -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 120 \
  -resultBundlePath "$run/TestResults.xcresult" 2>&1 | tee "$run/tests.log"
# Read the modern test summary. Missing or malformed metrics fail the run.
plist() { plutil -extract "$2" raw -o - "$1"; }
xcrun xcresulttool get test-results summary --path "$run/TestResults.xcresult" --compact > "$run/results.json"
result=$(plist "$run/results.json" result)
tests=$(plist "$run/results.json" totalTestCount)
passed=$(plist "$run/results.json" passedTests)
failed=$(plist "$run/results.json" failedTests)
skipped=$(plist "$run/results.json" skippedTests)
[[ $tests =~ ^[0-9]+$ && $passed =~ ^[0-9]+$ && $failed =~ ^[0-9]+$ && $skipped =~ ^[0-9]+$ ]] || fail 'Unrecognized test-result metrics.'
[[ $result == Passed && $tests -ge 35 && $passed -eq $tests && $failed -eq 0 && $skipped -eq 0 ]] || fail "Expected at least 35 passing tests without failures/skips; got $result: $passed/$tests passed, $failed failed, $skipped skipped"
# Retain named passing cases and require all four suites.
# An aggregate count alone must not let extra actor tests hide removal of the actual Objective-C fixture.
sed -n "s/^Test Case '\(.*\)' passed (.*/\1/p" "$run/tests.log" > "$run/passed-tests.log"
awk '!/^-\[[[:alpha:]_][[:alnum:]_.]* test[[:alnum:]_]+\]$/ {exit 1}' "$run/passed-tests.log" || fail 'Malformed named test record.'
recorded=$(wc -l < "$run/passed-tests.log" | tr -d '[:space:]')
unique=$(sort -u "$run/passed-tests.log" | wc -l | tr -d '[:space:]')
[[ $recorded -eq $tests && $unique -eq $tests ]] || fail 'Named passing cases do not match the result count.'
while IFS='|' read -r suite minimum; do
  count=$(awk -v suite="$suite" '{name=$1; sub(/^-\[/, "", name); sub(/^.*\./, "", name); if (name==suite) count++} END {print count+0}' "$run/passed-tests.log")
  [[ $count -ge $minimum ]] || fail "Missing required coverage in $suite: $count/$minimum"
done <<'SUITES'
VisualSessionTests|20
ObjectiveCBridgeTests|5
ObjectiveCConsumerTests|9
ExampleTests|1
SUITES
printf 'Passed: %s tests across all four suites; no failures or skips.\n' "$tests"
