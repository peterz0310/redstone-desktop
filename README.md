# Redstone Desktop

An experimental native macOS app exploring a block world beneath real Finder desktop icons. This is an early prototype, not an MVP. `SPEC.md` is the source of truth; development follows its roadmap one slice at a time.

## Current scope

Slices 0–1 provide a SwiftUI editor placeholder and tested domain primitives for coordinates, camera, directions, power, and component identity. Domain files use only the Swift standard library and do not depend on AppKit or SpriteKit.

Slice 2 adds an optional SpriteKit checkerboard in a borderless, click-through AppKit window on the main display. It starts disabled. The editor button or Window → Enable/Disable Desktop World controls it. The owner confirmed the Slice 2 manual checks on 2026-10-07; MANUAL checkboxes remain unchecked under the spec's agent rules.

Slice 3 adds a tested `CoordinateMapper` and `ScreenDescriptor`. Coordinates use logical points, with the camera origin at the canvas's lower-left corner. Negative positions floor to tiles; backing scale does not affect occupancy.

Slice 4 samples global pointer position at 30 Hz while the checker is enabled. A subtle outline marks the world tile under the cursor; the editor shows screen position, world position, tile, display ID, and camera values. The outline hides outside the active display. Checker geometry and highlight placement both go through `CoordinateMapper`. Pointer sampling stops when the desktop world is disabled.

The owner confirmed the Slice 4 alignment and Finder-interaction checks on 2026-10-07. Slice 5 adds a global left-mouse-down observer and a 0.3-second amber tile flash. The editor shows a click count and last clicked tile. Disabling the world or quitting removes the observer and stops pointer sampling. Duplicate starts do not install duplicate observers; late callbacks from removed registrations are ignored. These are diagnostic flashes only; no circuit or file actions exist yet.

The owner confirmed Slice 5 desktop clicks, including the expected flash beneath a Finder folder icon, on 2026-10-07. Slice 6 introduced **Finder Diagnostics…** in the editor. Its **Read Finder Items** button explicitly queries Finder through `DesktopItemProviding`. Opening the app or diagnostics window does not contact Finder. Permission denial and malformed responses display different errors, and failed reads clear the list instead of retaining stale positions. The owner reported Slice 6 working on 2026-10-07.

Slice 7 adds pink rings/crosshairs behind Finder icon centers, plus mapped screen/center and world-tile columns. After a successful read and enabling Desktop World, **Start Polling (2 Hz)** enables serialized live updates. **Stop Polling** freezes the last snapshot; disabling the world or quitting also stops polling. Errors pause polling until you explicitly retry. Identical snapshots do not publish new item arrays or redraw markers. The owner reported all Slice 7 checks working on 2026-10-07, establishing the center mapping on their Mac. This is owner-reported evidence, not an independent check on other configurations. MANUAL checkboxes remain unchecked.

Slice 8 groups icon centers into world tiles using a pure `DesktopOccupancyResolver`. Green tiles contain one item; red tiles contain multiple items. Finder Diagnostics lists every item in ambiguous tiles. Items with centers outside the active display are excluded. Unread or failed Finder data is unavailable, distinct from an empty tile. Polling updates occupancy; stopping polling freezes the last snapshot. Simulation and output actions remain future slices.

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

No new permissions are expected: position comes from Apple's public [NSEvent.mouseLocation](https://developer.apple.com/documentation/appkit/nsevent/mouselocation) property. The owner reported these checks passing; automated tests use fake pointer positions, and MANUAL checkboxes remain unchecked under the agent rules.

## Manual validation — Slice 5

1. Quit the previous app with Command-Q and open the latest build using the command above. Confirm the footer says “Slice 5 · Global click observation”.
2. Enable the desktop world and move the editor aside. Single-click blank desktop: the clicked square should briefly flash amber, then fade away. Move the pointer immediately after clicking to confirm the flash stays at the clicked square.
3. Select a desktop icon, then click blank desktop. Finder should still handle its normal selection/deselection. Click an icon again and confirm it selects normally; drag it and double-click a harmless file/folder as an additional check.
4. Watch the editor's “Clicks observed” readout: one single desktop click should add one, and “Last tile” should match the clicked square. Clicking this app's own editor does not count because a global monitor observes events delivered to other apps.
5. Disable/re-enable the world two or three times, then click blank desktop once. The reset counter should become 1, with one flash. When disabled, the checker and click readout should disappear.
6. Quit while enabled, relaunch, and enable again. Confirm clicks work once each and Finder is still usable.
7. If you have another display, click there and confirm the active display has no flash or counter change.

The observer uses Apple's public [global event monitor](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html), which cannot consume or modify clicks. It observes other-app clicks anywhere on the active display; flashes under ordinary application windows may be obscured by those windows. It does not yet determine Finder icon occupancy, and flashes have no action consequences. If macOS shows a permission prompt or desktop clicks fail to register, report that observation before proceeding to Slice 6.

## Manual validation — Slice 6

1. Quit the older app with Command-Q, then open the latest build using the command above. Confirm the footer says “Slice 6 · Finder automation spike”.
2. Click **Finder Diagnostics…**. The new window should initially say “Finder Automation: Not requested”. Opening it should not show a permission prompt.
3. Click **Read Finder Items**. On a fresh permission state, macOS should ask whether Redstone Desktop can control Finder. This app's fixed query only reads names, paths, and positions. Accept the request.
4. Confirm the list includes real Finder desktop items with plausible paths and raw `(x, y)` values. If your desktop is empty, put a harmless test folder there first, then read again. Note that values are deliberately not matched to world tiles yet.
5. Drag a desktop item to a different position, then click **Read Finder Items** again. Confirm that item's raw coordinates change. Reads are manual in this slice; there is no polling.
6. Test denial: open System Settings → Privacy & Security → Automation, expand Redstone Desktop if needed, and turn off Finder access. Read again. Confirm a denial message appears, the item list clears, and the editor/checker still work. Re-enable Finder access and read again to confirm recovery. You may also choose **Don't Allow** on the first prompt and then enable access here afterward.
7. Report missing items, incorrect paths, unchanging positions, a missing/unexpected permission prompt, errors, or a prolonged UI stall. Do not proceed to calibration until these observations are resolved.

`NSAppleEventsUsageDescription` is included in the built app. The Apple Events entitlement is configured for signed builds; the documented local build continues to use `CODE_SIGNING_ALLOWED=NO`. The bundle ID and build path stay stable. macOS may remember an earlier permission decision and omit a new prompt; use the Automation settings to inspect the current choice. No Accessibility or Full Disk Access permission is requested by this feature.

Apple documents [NSAppleScript as main-thread-only](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html), so this feasibility spike executes each explicit query there. Finder events use a 10-second timeout; a slow reply or permission interaction can delay this app's UI. Tests exercise the runner with harmless scripts and the UI model with fake providers; they do not query your real Finder or prove TCC permission behavior. Automatic polling and coordinate calibration are scheduled for Slice 7.

## Manual validation — Slice 7

1. Quit the previous app and open the latest build with the command above. Confirm the footer says “Slice 7 · Finder coordinate calibration”.
2. Enable Desktop World, open **Finder Diagnostics…**, and click **Read Finder Items**. Pink rings/crosshairs should appear behind real icons on the active display. Move/minimize the diagnostics window to see them. A crosshair's arms extend beyond the icon so its center remains assessable even when Finder covers the middle.
3. Check that each ring/crosshair is centered on the icon image, not its text label. Compare raw position, mapped screen/assumed center, and world tile in the table. The conversion is provisional; do not accept a consistent offset as “close enough”.
4. Click **Start Polling (2 Hz)** and drag an icon. Its marker should follow the latest Finder position, possibly only after Finder commits the drag/drop. Polling is two reads per second; perfectly smooth tracking during the drag is not promised. Report whether it updates during dragging or only after release.
5. Move a harmless test icon near each screen edge and corner, then check alignment after dropping it. Use icons with different image shapes if available. Keep normal Finder selection, drag, and double-click behavior intact.
6. Click blank desktop to make Finder active. Open Finder's View → Show View Options (Command-J) and change **Icon size**. After Finder settles, check marker centers again. Restore your preferred size afterward. Finder may rearrange icons; the app should follow the actual new positions.
7. Click **Stop Polling**, move an icon, and confirm the snapshot stays frozen until **Read Finder Items** or restarting polling. Disable/re-enable Desktop World: polling should remain paused until explicitly restarted.
8. Report offsets with a description such as “markers are 20 points below every icon”, and copy that item's raw/mapped coordinates. Also report UI stutters, delayed reads, missing markers, or errors. If alignment is wrong, stop here: document the observation and adjust the coordinate contract before occupancy is implemented.

Current hypothesis: Finder's raw point is the icon center, measured in logical points right/down from the primary display's upper-left corner. `CoordinateMapper` converts it to `(primary.minX + rawX, primary.maxY - rawY)` with no additional offset. [Apple documents the primary screen as `NSScreen.screens[0]`](https://developer.apple.com/documentation/appkit/nsscreen/screens); this differs from the active-window screen returned by `NSScreen.main`. Finder's origin and center semantics are not established by that API documentation and remain subject to the manual checks above. This slice covers one active renderer; display reconfiguration and multi-display behavior remain later work.

## License and assets

Licensed under the owner-selected MIT license; see `LICENSE`. No Minecraft assets are bundled. Future built-in assets must be original; resource packs will be data only.

## Manual validation — Slice 8

1. Quit the old app with **Command-Q**. In Terminal, run:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm the editor footer says **Slice 8 · Desktop occupancy**. Click **Enable Desktop World**, open **Finder Diagnostics…**, click **Read Finder Items**, then **Start Polling (2 Hz)**.
3. Check that each pink icon-center crosshair sits in a green tile. Drag one icon so its center crosses a checkerboard boundary, then release it. Within the next poll, its new tile should turn green and its old tile should clear (unless another icon remains there). Compare the table's world tile. Finder may report positions only after dropping an icon; smooth updates during the drag are not required.
4. Repeat across a horizontal boundary. The icon image or label overlapping a boundary should not move occupancy before its center crosses it.
5. If Finder allows two icon centers inside the same 64-point tile, put two there. That tile should be red. Expand **Ambiguous tiles (red) — all occupants** and confirm both names and paths appear. Move one away; the remaining tile should turn green. Report if Finder's snapping prevents this arrangement.
6. Confirm normal Finder selection, dragging, and double-clicking still work. **Stop Polling** should freeze the markers and occupancy; restarting should refresh them. Disabling Desktop World should remove the overlay.

Report whether the center-boundary transition matches the expected tile. Slice 9 waits for that check. No MANUAL checkbox is marked complete by the agent.
