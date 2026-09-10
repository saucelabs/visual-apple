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
  # Only choose an eligible destination reported by this Xcode and this scheme.
  # A missing runtime or changed output fails rather than skipping a platform.
  xcodebuild "${args[@]}" -showdestinations > "$run/destinations.log" 2>&1
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
    }' "$run/destinations.log")
  [[ -n "$udid" ]] || fail "No eligible $2 simulator. See $run/destinations.log."
  destination="platform=$platform,id=$udid"
fi
printf 'Distribution: %s; destination: %s\n' "$1" "$destination" | tee "$run/destination.log"
xcodebuild "${args[@]}" test -configuration Debug -destination "$destination" \
  -destination-timeout 180 -parallel-testing-enabled NO \
  -resultBundlePath "$run/TestResults.xcresult" 2>&1 | tee "$run/tests.log"
# Inspect the result bundle, not just xcodebuild's exit status. The legacy object
# representation is also readable by Xcode 15.2 (the Swift 5.9 producer).
result_args=(get --path "$run/TestResults.xcresult" --format json)
major=$(awk '/^Xcode / { split($2, parts, "."); print parts[1] }' "$run/toolchain.log")
[[ $major =~ ^[0-9]+$ ]] || fail 'Cannot identify the selected Xcode.'
if [[ $major -ge 16 ]]; then
  result_args=(get object --legacy --path "$run/TestResults.xcresult" --format json)
fi
xcrun xcresulttool "${result_args[@]}" > "$run/results.json"
tests=$(plutil -extract metrics.testsCount._value raw -o - "$run/results.json")
if ! failed=$(plutil -extract metrics.testsFailedCount._value raw -o - "$run/results.json" 2>/dev/null); then failed=0; fi
if ! skipped=$(plutil -extract metrics.testsSkippedCount._value raw -o - "$run/results.json" 2>/dev/null); then skipped=0; fi
[[ $tests =~ ^[0-9]+$ && $failed =~ ^[0-9]+$ && $skipped =~ ^[0-9]+$ ]] || fail 'Unrecognized test-result metrics.'
# 20 actor + 4 Swift bridge + 9 Objective-C + 1 compiled example tests.
# Increasing coverage does not require changing this minimum.
[[ $tests -ge 34 && $failed -eq 0 && $skipped -eq 0 ]] || fail "Expected at least 34 tests without failures/skips; got $tests/$failed/$skipped"
printf 'Passed: %s tests; no failures or skips.\n' "$tests"
