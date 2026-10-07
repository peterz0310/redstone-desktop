# Redstone Desktop

An experimental native macOS app exploring a block world beneath real Finder desktop icons. This is an early prototype, not an MVP. `SPEC.md` is the source of truth; development follows its roadmap one slice at a time.

## Current scope

Slices 0–1 provide a SwiftUI editor placeholder, an app-hosted XCTest smoke test, and tested domain primitives for coordinates, camera, directions, power, and component identity. Domain files use only the Swift standard library and do not depend on AppKit or SpriteKit. Desktop rendering, Finder access, coordinate mapping, simulation, and actions are not implemented yet. The app does not request privacy permissions at this stage.

## Development

Requirements: macOS 14 or newer, Xcode with Swift 6 support, and XcodeGen 2.44 or newer. This bootstrap was built and tested with Xcode 27.0 on macOS 27.0; the minimum deployment version has not been tested on an older Mac.

Install the development-only project generator:

```sh
brew install xcodegen
```

Generate the Xcode project from the checked-in definition:

```sh
xcodegen generate --spec project.yml
```

Build locally without a signing account:

```sh
xcodebuild -project RedstoneDesktop.xcodeproj -scheme RedstoneDesktop -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

Run the test suite:

```sh
xcodebuild -project RedstoneDesktop.xcodeproj -scheme RedstoneDesktop -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

Launch the built application:

```sh
open build/Build/Products/Debug/RedstoneDesktop.app
```

Alternatively, open the generated `RedstoneDesktop.xcodeproj` and run the `RedstoneDesktop` scheme. The generated project and build products are ignored by Git. `project.yml` is the editable project definition. The bundle identifier stays stable for later macOS permission testing.

## Manual validation — Slice 0

1. Launch the application with the command above.
2. Confirm a normal window titled “Redstone Desktop” appears, with “Editor placeholder” and “Slice 0 · Repository bootstrap”.
3. Confirm the window resizes and closes normally; quit using Redstone Desktop → Quit or Command-Q.

An automated hosting test does not prove the visible window is correct. Every `MANUAL` checkbox in the spec remains for the owner to verify.

## License and assets

Licensed under the owner-selected MIT license; see `LICENSE`. No Minecraft assets are bundled. Future built-in assets must be original; resource packs will be data only.
