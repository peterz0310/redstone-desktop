# Redstone Desktop

An experimental native macOS app exploring a block world beneath real Finder desktop icons. This is an early prototype, not an MVP. `SPEC.md` is the source of truth; development follows its roadmap one slice at a time.

## Current scope

Slices 0–1 provide a SwiftUI editor placeholder and tested domain primitives for coordinates, camera, directions, power, and component identity. Domain files use only the Swift standard library and do not depend on AppKit or SpriteKit.

Slice 2 adds an optional SpriteKit checkerboard in a borderless, click-through AppKit window on the main display. It starts disabled. The editor button or Window → Enable/Disable Desktop World controls it. The owner confirmed the Slice 2 manual checks on 2026-10-07; MANUAL checkboxes remain unchecked under the spec's agent rules.

Slice 3 adds a tested `CoordinateMapper` and `ScreenDescriptor`. Coordinates use logical points, with the camera origin at the canvas's lower-left corner. Negative positions floor to tiles; backing scale does not affect occupancy. Finder access, simulation, and actions are not implemented yet. The app does not request privacy permissions at this stage.

Slice 4 samples global pointer position at 30 Hz while the checker is enabled. A subtle outline marks the world tile under the cursor; the editor shows screen position, world position, tile, display ID, and camera values. The outline hides outside the active display. Checker geometry and highlight placement both go through `CoordinateMapper`. Pointer sampling stops when the desktop world is disabled.

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

When new source files are added, regenerate the project before building. A build compiles the source into the `.app`; a test run builds it and runs XCTest checks. Neither command requires changing anything in Xcode. If an earlier version is running, quit it with Command-Q before opening the new build so you see the latest code.

## Manual validation — Slice 0

1. Launch the application with the command above.
2. Confirm a normal window titled “Redstone Desktop” appears with “Editor placeholder”. The footer identifies the current slice.
3. Confirm the window resizes and closes normally; quit using Redstone Desktop → Quit or Command-Q.

An automated hosting test does not prove the visible window is correct. Every `MANUAL` checkbox in the spec remains for the owner to verify.

## Manual validation — Slice 2

1. Quit the earlier running app, then launch the latest build with the `open` command above.
2. Click **Enable Desktop World** in the editor. Move the editor aside or minimize it to see your desktop.
3. Confirm a teal checkerboard appears above your wallpaper and **below real Finder icons and their labels**. Ordinary app windows should cover the checkerboard.
4. Click a desktop icon to select it; drag it and then double-click a harmless folder/file. Confirm Finder behaves normally throughout.
5. Return to the editor and click **Disable Desktop World**, or use the app's Window menu. Confirm your wallpaper is visible again. Repeat enable/disable once.
6. Quit the app while the checker is enabled. Confirm the checker disappears.
7. If you use Spaces, Mission Control, or Stage Manager, try them with the checker enabled and report whether it disappears, covers anything it should not, or behaves oddly. These behaviors are unverified.

Report the five Slice 2 acceptance results: above wallpaper, below icons, icons selectable, icons draggable, and below application windows. If any fail, stop here for investigation before further slices. Display hot-plug/resolution handling is scheduled for Slice 21; this spike uses the main display's frame at enable time.

The window level is calculated from public `CGWindowLevelForKey(.desktopWindow) + 1`, rather than a hard-coded private level. Tests verify that it falls below `.desktopIconWindow`, but those tests cannot prove Finder's visible stacking behavior. API references: [Apple window-level keys](https://developer.apple.com/documentation/coregraphics/cgwindowlevelkey) and [ignoresMouseEvents](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents).

## Manual validation — Slice 4

1. Quit the older running app with Command-Q, then launch the latest build using the `open` command above. The footer should say “Slice 4 · Cursor highlight”.
2. Click **Enable Desktop World** and move the editor aside so blank desktop is visible. Move the pointer slowly across horizontal and vertical checker edges. The outline must always occupy the square under the pointer and switch at the visible boundary.
3. Move around the display edges and corners. The highlight must stay aligned. If you have another display, move the pointer there: the outline on the active display should disappear and the editor should report that the pointer is outside the active display. Move back and confirm it returns.
4. With the editor visible, watch the screen/world/tile values update as you move the pointer. The tile coordinates should change when you cross checker boundaries. `(0, 0)` is the lower-left tile; each tile is 64 logical points.
5. Select, drag, and double-click a harmless Finder desktop item. The outline must not interfere with Finder or bring Redstone Desktop to the foreground.
6. Disable and re-enable the world; confirm pointer updates resume normally. Disable it again and confirm the debug pointer readout disappears.

No new permissions are expected: position comes from Apple's public [NSEvent.mouseLocation](https://developer.apple.com/documentation/appkit/nsevent/mouselocation) property. Manual alignment and Finder-usability checks remain open until the owner reports results; automated tests use fake pointer positions.

## License and assets

Licensed under the owner-selected MIT license; see `LICENSE`. No Minecraft assets are bundled. Future built-in assets must be original; resource packs will be data only.
