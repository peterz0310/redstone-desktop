# Build and prepare a release

Redstone Desktop 0.1.0 is an early preview. Local builds and automated tests are ready to review; public distribution still needs the [release checklist](RELEASE_CHECKLIST.md). No public download or hosted CI success is implied by a local build.

## Build from source

The locally verified toolchain is **Xcode 27.0**, Swift 6 language mode, **XcodeGen 2.46.0** (minimum 2.44) and Python 3. Install full Xcode, open it once to finish its setup, and check `xcode-select -p` points to that Xcode. The app targets **macOS 14+**; development was tested on Apple Silicon/macOS 27. Older macOS and Intel execution remain physical checks.

```sh
git clone https://github.com/peterz0310/redstone-desktop.git
cd redstone-desktop
brew install xcodegen
xcodegen generate --spec project.yml
xcodebuild -project RedstoneDesktop.xcodeproj -scheme RedstoneDesktop -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RedstoneDesktop.xcodeproj -scheme RedstoneDesktop -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
python3 -m unittest discover -s scripts/tests -v
python3 scripts/check-docs.py
```

To run, open the generated project, choose **RedstoneDesktop → My Mac**, and press **⌘R**. Or open `build/Build/Products/Debug/RedstoneDesktop.app` directly. Xcode helps with debugging; normal installed users don't need it. Quit older copies first. Normal launches use your actual library; tests use isolated data.

`project.yml` is the checked-in project definition. Regenerate after adding source files. There is no backend, required Java installation, downloaded pack or script dependency for a build. Build products and generated projects are ignored.

## Package a local review build

```sh
scripts/release.sh
```

The script checks documentation, builds optimized arm64/x86_64 Release, verifies the app, ZIP and read-only mounted DMG, and produces:

```text
build/releases/RedstoneDesktop-0.1.0-macOS.dmg
build/releases/RedstoneDesktop-0.1.0-macOS.zip
build/releases/RedstoneDesktop-0.1.0-macOS-symbols.zip
build/releases/RedstoneDesktop-0.1.0-macOS.json
```

Each ZIP/DMG also has a `.sha256` sidecar. The DMG contains the app, an Applications shortcut, install instructions, README/media, release notes, license/notices and guides. ZIP contains the same files in a `RedstoneDesktop` folder. Matching dSYM UUIDs are checked and archived separately; **retain symbols and the manifest privately for crash reports**, not as the ordinary customer download. The manifest records the actual artifact hashes, source commit/dirty status, version/build, toolchain and signing mode. It records notarization as not performed; hashing is not a trust signature.

Default packages are **unsigned local review artifacts**, not Gatekeeper-ready downloads. The linker may add an ad-hoc signature; that is not Developer ID distribution. `--output DIRECTORY` changes their location. Unique staging is cleaned on exit and validation finishes before replacing existing packages. Rebuilding the same version replaces generated artifacts; preserve the exact app, manifest and symbols if investigating a crash.

Read-only checks:

```sh
python3 scripts/verify-release.py build/releases/RedstoneDesktop-0.1.0-macOS.dmg
python3 scripts/verify-release.py build/releases/RedstoneDesktop-0.1.0-macOS.zip
(cd build/releases && shasum -a 256 -c RedstoneDesktop-0.1.0-macOS.dmg.sha256)
```

Verification checks identity/version/build/copyright, macOS target and permission explanations, native light/dark icon variants, licensing, both actual Mach-O slices, documentation links/images and the absence of local saves/imports/scripts/audio. ZIP traversal, duplicate/case-colliding entries and unexpected symbolic links are refused. DMG checks use a unique read-only mount, do not open Finder/app windows, and detach afterwards. It never launches the app or uses your saved library. The installer uses HFS+ for the supported older Macs; macOS 27 emits deprecation warnings for hdiutil, but creation/verification/read-only mounting passed locally.

## Sign and notarize for public download

You need Apple Developer membership, an installed **Developer ID Application** certificate/private key, and notarization credentials. Keep credentials in Keychain; never put them in this repository. The development Mac currently has no Developer ID Application identity. Follow Apple's [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

```sh
# Use your exact installed Developer ID identity.
scripts/release.sh --sign "Developer ID Application: Your Name (TEAMID)"
# Configure this Keychain profile using Apple's instructions first.
xcrun notarytool submit build/releases/RedstoneDesktop-0.1.0-macOS.dmg --keychain-profile "RedstoneDesktop-notary" --wait
```

Signing enables hardened runtime, timestamps and the Apple Events entitlement on the app, and signs the DMG too. Apple Development identities are refused by the distribution script. Inspect notarization's result and log; stop on rejection. No submission/upload is done automatically by the packaging script.

After **Accepted**, staple the **same DMG** without rebuilding:

```sh
xcrun stapler staple build/releases/RedstoneDesktop-0.1.0-macOS.dmg
xcrun stapler validate build/releases/RedstoneDesktop-0.1.0-macOS.dmg
python3 scripts/verify-release.py build/releases/RedstoneDesktop-0.1.0-macOS.dmg
spctl --assess --type open --context context:primary-signature --verbose=2 build/releases/RedstoneDesktop-0.1.0-macOS.dmg
(cd build/releases && shasum -a 256 RedstoneDesktop-0.1.0-macOS.dmg > RedstoneDesktop-0.1.0-macOS.dmg.sha256)
```

Stapling changes the DMG's hash. Update its manifest hash/size and notarization record only after successful ticket/Gatekeeper checks; retain the submission ID and matching symbols. The packaging manifest is a pre-notarization build record until then. Do not advertise the independently generated ZIP as notarized/stapled: a ZIP cannot be stapled, and this path submits the DMG. For offline ZIP distribution, staple the accepted app separately, verify it, then repackage/checksum that exact app. The current bundle has no nested helpers/frameworks; future nested code requires inside-out signing, not a `--deep` workaround.

The release's actual app should also pass `codesign --verify --deep --strict` and `spctl --assess --type execute` after installation. Test a downloaded/quarantined copy on a clean account/Mac; local mounting is not Gatekeeper acceptance. Publish only after the remaining [manual gates](RELEASE_CHECKLIST.md) pass.

## Permissions and privacy

Bundle ID: `org.redstonedesktop.RedstoneDesktop`. The app is intentionally **not sandboxed**, and this is not an App Store submission setup. Finder Apple Events and explicitly approved scripts use normal account access.

- Finder Automation reads names, paths, icon positions and view settings when you connect/start tracking.
- Optional script access requests Desktop-folder consent separately; each new/changed script still needs exact-file approval. Automatic script/open routing is opt-in.
- No Accessibility, microphone, camera, screen-recording or Full Disk Access permission is requested.

macOS controls prompt timing and retains privacy decisions through reset/reinstall. Retest permissions with the actual signed app. Start Over resets app-owned data, not TCC. See [recovery](RECOVERY.md) and [script behavior](SCRIPT_OUTPUTS.md).

## Artwork and icons

Code, original world art/sound and original examples are MIT licensed. Identity uses the owner-provided logo; other toolbar icons use native SF Symbols. No Minecraft art, sound, game code or resource-pack code is bundled. Imports remain local. See [artwork notices](../THIRD_PARTY_NOTICES.md).

The unchanged source is `RedstoneDesktop/Resources/Assets.xcassets/Logo.imageset/logo.png`. Regenerate derived identity/README images with:

```sh
swiftc -swift-version 6 -parse-as-library RedstoneDesktop/App/AppIdentityArtwork.swift scripts/GenerateAppIcons.swift -o /tmp/redstone-generate-icons
/tmp/redstone-generate-icons "$PWD"
scripts/readme-previews.sh
```

`AppIcon.icon` is a native [Icon Composer](https://developer.apple.com/icon-composer/) document with light/dark backgrounds and a static fallback for older macOS. On macOS 26+, **System Settings → Appearance → Icon & widget style** controls icon appearance separately from window appearance; see [Apple's appearance guide](https://support.apple.com/guide/mac-help/change-appearance-settings-mchlp1225/mac). Debug builds include both variants. Menu/Dust uses a template silhouette. Regeneration preserves source bytes/proportions; update the notice/hash test if replacing the logo.

README scenery and lighting examples use original art and offscreen rendering. The generation scripts use isolated/synthetic state and never query Finder, play through speakers, import owner game assets or write your library. Keep game-derived screenshots and local assets out of releases.

## CI and final records

`.github/workflows/macos.yml` uses [GitHub's Xcode 27 preview image](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), pinned action commits, read-only repository permission and no persisted checkout credentials. It checks guides/Python tests, builds Debug, runs XCTest and builds/verifies unsigned universal ZIP/DMG packages. Logs, xcresult, packages, checksums, symbols and manifest are retained for 14 days. It never publishes or notarizes a release; hosted success remains unclaimed until GitHub executes it.

Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` for a future release; update [release notes](../CHANGELOG.md), build/test from the intended clean commit, and retain exact hashes/symbols. Replace README's coming-soon text with a real download link only when the signed release is actually published.
