#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
identity=""
output="$PWD/build/releases"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign) [[ $# -ge 2 && -n "$2" ]] || { echo 'Missing signing identity' >&2; exit 2; }; identity="$2"; shift 2 ;;
    --output) [[ $# -ge 2 && -n "$2" ]] || { echo 'Missing output directory' >&2; exit 2; }; output="$2"; shift 2 ;;
    --help) echo 'Usage: scripts/release.sh [--sign "Developer ID Application: Name (TEAM)"] [--output DIRECTORY]'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
xcodegen generate --spec project.yml
mkdir -p build "$output"
xcodebuild -project RedstoneDesktop.xcodeproj -scheme RedstoneDesktop -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build-release \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' build > build/release-build.log 2>&1 || {
  tail -60 build/release-build.log >&2; exit 1;
}
staging=$(mktemp -d "$output/.redstone-release.XXXXXX")
trap 'rm -rf "$staging"' EXIT
package="$staging/RedstoneDesktop"
mkdir -p "$package"
ditto build-release/Build/Products/Release/RedstoneDesktop.app "$package/RedstoneDesktop.app"
app="$package/RedstoneDesktop.app"
if [[ -n "$identity" ]]; then
  # Current app has no nested helpers/frameworks. Refuse unsupported new layouts.
  if [[ -d "$app/Contents/Frameworks" ]] && [[ -n "$(ls -A "$app/Contents/Frameworks")" ]]; then
    echo 'Nested frameworks require inside-out signing/Xcode export; see docs/RELEASE.md.' >&2; exit 1
  fi
  codesign --force --options runtime --timestamp --entitlements RedstoneDesktop/Resources/RedstoneDesktop.entitlements --sign "$identity" "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
fi
cp LICENSE THIRD_PARTY_NOTICES.md README.md "$package/"
ditto docs "$package/docs"
python3 scripts/verify-release.py "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
archive="$output/RedstoneDesktop-$version-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$package" "$staging/archive.zip"
python3 scripts/verify-release.py "$staging/archive.zip"
mv "$staging/archive.zip" "$archive"
(cd "$output" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "Release archive: $archive"
if [[ -z "$identity" ]]; then echo 'Unsigned local review build; not notarized. See docs/RELEASE.md before distribution.'; fi
