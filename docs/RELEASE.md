# Build and release engineering

This is an experimental prototype. A passing archive/build is not physical-Mac MVP acceptance. Review [TESTING.md](TESTING.md), [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) and the licensing notice before distribution.

## Required tools and clean checkout

The supported, locally verified contributor toolchain is **Xcode 27.0 or newer**, **Swift 6 language mode**, and **XcodeGen 2.44+** (verified with 2.46.0), plus Python 3 for archive verification. Install full Xcode, open it once to finish setup/license installation, and ensure `xcode-select -p` points at its Developer directory. Command Line Tools alone do not provide the full app build/test environment. Older Xcode versions have not been validated for this final tree.

The **app deployment target is macOS 14.0**, independent of the OS/Xcode needed to develop it. Local tests ran on Apple Silicon/macOS 27.0; older macOS and Intel runtime behavior remain unverified. The Release script builds both arm64 and x86_64 slices; cross-compilation is not Intel runtime acceptance.

From a new checkout:

```sh
git clone https://github.com/peterz0310/redstone-desktop.git
cd redstone-desktop
brew install xcodegen
xcodebuild -version
xcrun swift --version
xcodegen generate --spec project.yml
xcodebuild -project RedstoneDesktop.xcodeproj -scheme RedstoneDesktop -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RedstoneDesktop.xcodeproj -scheme RedstoneDesktop -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
open build/Build/Products/Debug/RedstoneDesktop.app
```

Alternatively open the generated Xcode project, select RedstoneDesktop/My Mac and press **⌘R**. Quit older running copies first. `project.yml` is the checked-in project definition; regenerate after adding files. Build products/generated projects are ignored. No backend, Java installation, downloaded texture pack or script is required for builds/tests/default art. Tests isolate owner stores/preferences and use synthetic/fake adapters; ordinary app launch uses the production library and starts Desktop stopped.

## Permissions and distribution identity

Bundle ID: `org.redstonedesktop.RedstoneDesktop`. This native app is intentionally **not App Sandbox enabled**: public Finder Apple Events and explicitly approved user script execution use normal account access. Script actions are distinct from simulation/rendering, execute only supported exact targets after approval, and have bounded process/output/cancellation handling. It is not an App Store submission configuration.

- **Automation → Finder**: explicitly connecting/starting tracking reads names, paths, icon positions and view settings. `NSAppleEventsUsageDescription` and the Apple Events entitlement explain/permit this under hardened runtime.
- **Files & Folders → Desktop Folder**: explicit script choice/check/opt-in requests folder access. `NSDesktopFolderUsageDescription` explains it. Opening ordinary occupants and Finder Automation are separate from script reading.
- **Per-script confirmation**: app-owned exact-file approval, separate from TCC; remembered approval starts checked but can be unchecked/revoked. Automatic script/open routing remains opt-in.
- No Accessibility, microphone, camera, screen-recording or blanket Full Disk Access permission is requested. The desktop input gate uses documented public event/window metadata, without private APIs or input interception in normal mode.

macOS chooses prompt timing and stores privacy decisions across reinstall/reset. Signing identity/path changes may affect permission attribution; retest with the actual signed app. Start Over resets app data, not TCC; see [RECOVERY.md](RECOVERY.md). Do not distribute developer fixture scripts as app content.

## Licensing

Project code/original world art/sound: [MIT](../LICENSE). No third-party runtime packages/backend are bundled; SwiftUI/AppKit/SpriteKit/AVFoundation are system frameworks. XcodeGen is a development tool, not part of the app.

App/menu/Dust-tool identity uses the owner-provided logo; all other toolbar icons use native SF Symbols. No Minecraft artwork/audio or game-derived icons are shipped. [Artwork notices](../THIRD_PARTY_NOTICES.md) record the unchanged source PNG, hash and derivation. World textures, particles and audio remain optional local imports and are absent from releases. Pack data is validated images/PCM/metadata; no resource-pack code executes. MIT/license and notices are embedded inside the app and included in the review ZIP. The release verifier inspects the actual compiled Assets.car with the macOS developer tool `assetutil`, in both the app and ZIP, and rejects the retired game-derived image sets. Optional asset imports must never be added to a release to make a demo work.

## Local Release archive

```sh
scripts/release.sh
```

This generates the project, builds an optimized **universal arm64/x86_64** Release app, stages only that app/license/notices/public guides, validates actual bundle/ZIP contents, and creates:

```
build/releases/RedstoneDesktop-0.1.0-macOS.zip
build/releases/RedstoneDesktop-0.1.0-macOS.zip.sha256
```

The ZIP contains a `RedstoneDesktop` folder with the app, README, LICENSE, notices and `docs/`. A matching SHA-256 sidecar is for integrity comparison, not a trust signature. Default output is a local **unsigned/not-notarized** review build (a linker may add an ad-hoc signature). No Internet release is published. A DMG is optional and unnecessary for this slice. `--output DIRECTORY` changes the archive location; temporary staging is unique and cleaned on exit. Rebuilding replaces the generated versioned archive. `build/release-build.log` records build details.

Read-only verification can be repeated:

```sh
python3 scripts/verify-release.py build/releases/RedstoneDesktop-0.1.0-macOS.zip
shasum -a 256 build/releases/RedstoneDesktop-0.1.0-macOS.zip
```

Checks include identity/target/permission descriptions/icon/license/notices, both Mach-O architectures, required guides and absence of local saves/imports/source archives/scripts. Open/extract manually only after validation. Quit the development copy before launching the extracted app; normal copies share the same production library. For a clean first-launch test use another macOS account or the isolated Debug maintenance harness, not an unannounced reset of existing builds.

Unsigned downloaded software may be refused by Gatekeeper. This local artifact is not presented as trusted distribution; use a signed/notarized package for public users rather than disabling system protections.

## Optional Developer ID signing and notarization

This requires your own Apple Developer membership, installed **Developer ID Application** certificate/private key and notarization credentials. None is supplied, used, printed or committed by these tasks. Follow Apple's [notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

```sh
# Use the exact installed identity; verify it in Keychain Access first.
scripts/release.sh --sign "Developer ID Application: Your Name (TEAMID)"
# Configure a Keychain profile using Apple's notarytool instructions; never commit credentials.
xcrun notarytool submit build/releases/RedstoneDesktop-0.1.0-macOS.zip --keychain-profile "RedstoneDesktop-notary" --wait
```

Signing enables hardened runtime, timestamps and the Apple Events entitlement, then verifies the copied staged app. The current bundle has no nested helpers/frameworks; the script refuses a new nested-framework layout that requires inside-out signing/Xcode archive export. Do not use `codesign --deep` to paper over signing failures. Notarization is deliberately a separate explicit command; inspect its result/log and stop on rejection.

After acceptance, extract the **same signed ZIP**, staple and validate its app ticket, then repackage the same `RedstoneDesktop` folder and regenerate the checksum (replace the example location with your extraction folder):

```sh
xcrun stapler staple "/absolute/path/to/extracted/RedstoneDesktop/RedstoneDesktop.app"
xcrun stapler validate "/absolute/path/to/extracted/RedstoneDesktop/RedstoneDesktop.app"
codesign --verify --deep --strict --verbose=2 "/absolute/path/to/extracted/RedstoneDesktop/RedstoneDesktop.app"
spctl --assess --type execute --verbose=2 "/absolute/path/to/extracted/RedstoneDesktop/RedstoneDesktop.app"
ditto -c -k --sequesterRsrc --keepParent "/absolute/path/to/extracted/RedstoneDesktop" build/releases/RedstoneDesktop-0.1.0-macOS-notarized.zip
shasum -a 256 build/releases/RedstoneDesktop-0.1.0-macOS-notarized.zip > build/releases/RedstoneDesktop-0.1.0-macOS-notarized.zip.sha256
```

Do not rebuild between submission and stapling. Actual Developer ID/notary/Gatekeeper acceptance remains untested until performed with your credentials. Signing/notarization does not resolve artwork redistribution rights.

## GitHub Actions

`.github/workflows/macos.yml` runs on push to main, pull requests and manual dispatch. It uses [GitHub's documented Xcode 27 runner](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), currently a preview image, to match the validated local toolchain. It generates the project, builds Debug, runs isolated XCTest and builds/validates the unsigned universal Release archive. Pinned checkout/upload action commits, read-only repository permission and no persisted checkout credentials/signing secrets keep this a build/review pipeline; it never publishes a release or resets privacy.

Logs, xcresult and unsigned ZIP/checksum are retained as artifacts for 14 days. A hosted run is not claimed until GitHub actually executes it. If the preview image changes/disappears, update the runner using official runner-image evidence and revalidate; do not silently claim a different compiler/OS passed.
