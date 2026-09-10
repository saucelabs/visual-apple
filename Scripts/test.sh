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
  -resultBundlePath "$run/TestResults.xcresult" 2>&1 | tee "$run/tests.log"
# Inspect the completed result bundle using Xcode's test summary API.
xcrun xcresulttool get test-results summary --path "$run/TestResults.xcresult" --compact > "$run/results.json"
result=$(plutil -extract result raw -o - "$run/results.json")
tests=$(plutil -extract totalTestCount raw -o - "$run/results.json")
passed=$(plutil -extract passedTests raw -o - "$run/results.json")
failed=$(plutil -extract failedTests raw -o - "$run/results.json")
skipped=$(plutil -extract skippedTests raw -o - "$run/results.json")
[[ $tests =~ ^[0-9]+$ && $passed =~ ^[0-9]+$ && $failed =~ ^[0-9]+$ && $skipped =~ ^[0-9]+$ ]] || fail 'Unrecognized test-result metrics.'
[[ $result == Passed && $tests -ge 34 && $passed -eq $tests && $failed -eq 0 && $skipped -eq 0 ]] || fail "Expected at least 34 passing tests without failures/skips; got $result: $passed/$tests passed, $failed failed, $skipped skipped"
printf 'Passed: %s tests; no failures or skips.\n' "$tests"
