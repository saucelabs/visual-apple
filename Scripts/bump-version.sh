#!/bin/bash
# Sets the SDK version for a release and prints it. The version lives in two places, which must match:
# MARKETING_VERSION (the framework's Info.plist) and sauceVisualVersion (the API User-Agent).
set -euo pipefail
export LC_ALL=C
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 1 ]] || fail 'Usage: Scripts/bump-version.sh major|minor|patch'
root=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$root"

xcconfig=Configuration/SDK.xcconfig
swift=Sources/SauceVisual/API/GraphQLTransport.swift

current=$(sed -n 's/^MARKETING_VERSION = \([0-9][0-9.]*\)$/\1/p' "$xcconfig")
[[ $current =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || fail "Invalid MARKETING_VERSION in $xcconfig."
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}

case "$1" in
  major) version="$((major + 1)).0.0" ;;
  minor) version="$major.$((minor + 1)).0" ;;
  patch) version="$major.$minor.$((patch + 1))" ;;
  *) fail "Unknown release type: $1" ;;
esac

# SwiftPM caches what a tag points to, so a released version is never reused.
if git rev-parse -q --verify "refs/tags/$version" > /dev/null; then
  fail "Version $version is already tagged."
fi

sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $version/" "$xcconfig"
sed -i '' "s/^internal let sauceVisualVersion = \".*\"/internal let sauceVisualVersion = \"$version\"/" "$swift"
grep -qx "MARKETING_VERSION = $version" "$xcconfig" || fail "Could not update $xcconfig."
grep -qx "internal let sauceVisualVersion = \"$version\"" "$swift" || fail "Could not update $swift."

echo "$version"
