#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
identity=""
layout=false
output="$PWD/build/releases"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign) [[ $# -ge 2 && "$2" == "Developer ID Application:"* ]] || { echo 'Use an installed Developer ID Application identity for distribution, not Apple Development.' >&2; exit 2; }; identity="$2"; shift 2 ;;
    --layout) layout=true; shift ;;
    --output) [[ $# -ge 2 && -n "$2" ]] || { echo 'Missing output directory' >&2; exit 2; }; output="$2"; shift 2 ;;
    --help) echo 'Usage: scripts/release.sh [--sign "Developer ID Application: Name (TEAM)"] [--output DIRECTORY] [--layout]'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
python3 scripts/check-docs.py
xcodegen generate --spec project.yml
mkdir -p build "$output"
xcodebuild -project RedstoneDesktop.xcodeproj -scheme RedstoneDesktop -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build-release \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' build > build/release-build.log 2>&1 || {
  tail -60 build/release-build.log >&2; exit 1;
}
staging=$(mktemp -d "$output/.redstone-release.XXXXXX")
mount=""
cleanup() {
  if [[ -n "$mount" ]] && mountpoint_output=$(hdiutil info) && [[ "$mountpoint_output" == *"$mount"* ]]; then
    hdiutil detach "$mount" >&2 || { echo "Eject the installer volume at $mount before removing its staging directory." >&2; return; }
  fi
  rm -rf "$staging"
}
trap cleanup EXIT
package="$staging/RedstoneDesktop"
mkdir -p "$package"
ditto build-release/Build/Products/Release/RedstoneDesktop.app "$package/Redstone Desktop.app"
app="$package/Redstone Desktop.app"
mode="unsigned-review"
if [[ -n "$identity" ]]; then
  if [[ -d "$app/Contents/Frameworks" ]] && [[ -n "$(ls -A "$app/Contents/Frameworks")" ]]; then
    echo 'Nested frameworks require inside-out signing before signing the app.' >&2; exit 1
  fi
  codesign --force --options runtime --timestamp --entitlements RedstoneDesktop/Resources/RedstoneDesktop.entitlements --sign "$identity" "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
  mode="developer-id"
fi
ln -s /Applications "$package/Applications"
python3 scripts/verify-release.py "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
base="RedstoneDesktop-$version-macOS"
ditto -c -k --sequesterRsrc --keepParent "$package" "$staging/archive.zip"
python3 scripts/verify-release.py "$staging/archive.zip"
if $layout; then
  mkdir -p "$package/.background"
  xcrun swift scripts/InstallerArtwork.swift "$package/.background/background.png"
  hdiutil create -fs HFS+ -volname 'Redstone Desktop' -srcfolder "$package" -format UDRW "$staging/writable.dmg"
  mount="$staging/mount"
  mkdir -p "$mount"
  hdiutil attach -nobrowse -noautoopen -mountpoint "$mount" "$staging/writable.dmg"
  # Finder's documented scripting interface writes its own layout metadata.
  # This option is for a local interactive Mac, not a headless CI runner.
  if ! osascript scripts/InstallerLayout.applescript "$mount"; then
    hdiutil detach "$mount"
    echo 'Finder could not apply the installer layout; see the error above. Retry --layout after resolving it.' >&2
    exit 1
  fi
  sync
  hdiutil detach "$mount"
  hdiutil convert "$staging/writable.dmg" -format UDZO -o "$staging/installer.dmg"
else
  hdiutil create -fs HFS+ -volname 'Redstone Desktop' -srcfolder "$package" -format UDZO "$staging/installer.dmg"
fi
if [[ -n "$identity" ]]; then
  codesign --force --timestamp --sign "$identity" "$staging/installer.dmg"
  codesign --verify --strict --verbose=2 "$staging/installer.dmg"
fi
python3 scripts/verify-release.py "$staging/installer.dmg"
symbols="build-release/Build/Products/Release/RedstoneDesktop.app.dSYM"
[[ -d "$symbols" ]] || { echo 'Release debug symbols are missing.' >&2; exit 1; }
dwarfdump --uuid "$app/Contents/MacOS/RedstoneDesktop" > "$staging/app-uuids.txt"
dwarfdump --uuid "$symbols" > "$staging/symbol-uuids.txt"
python3 - "$staging/app-uuids.txt" "$staging/symbol-uuids.txt" <<'PY'
import re,sys
from pathlib import Path
pattern = r'UUID: ([A-F0-9-]+) \(([^)]+)\)'
app, symbols = [set(re.findall(pattern, Path(path).read_text())) for path in sys.argv[1:]]
if len(app) != 2 or app != symbols: raise SystemExit('App and debug-symbol UUIDs do not match.')
PY
ditto -c -k --keepParent "$symbols" "$staging/symbols.zip"
# Publish only fully validated local artifacts; staging is removed on any earlier failure.
mv "$staging/archive.zip" "$output/$base.zip"
mv "$staging/installer.dmg" "$output/$base.dmg"
mv "$staging/symbols.zip" "$output/$base-symbols.zip"
for name in "$base.zip" "$base.dmg" "$base-symbols.zip"; do
  (cd "$output" && shasum -a 256 "$name" > "$name.sha256")
done
python3 scripts/release-manifest.py "$output/$base.json" "$app" "$mode" "$output/$base.zip" "$output/$base.dmg" "$output/$base-symbols.zip"
echo "Release packages: $output/$base.dmg and $output/$base.zip"
echo 'Keep the matching symbols ZIP and manifest for crash reports.'
if [[ -z "$identity" ]]; then echo 'Unsigned local review packages; public distribution still needs Developer ID signing, notarization and Mac acceptance.'; fi
