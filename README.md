# Redstone Desktop

An experimental native macOS app exploring a block world beneath real Finder desktop icons. This is an early prototype, not an MVP. `SPEC.md` is the source of truth; development follows its roadmap one slice at a time.

## Current scope

Slices 0–1 provide a SwiftUI editor placeholder and tested domain primitives for coordinates, camera, directions, power, and component identity. Domain files use only the Swift standard library and do not depend on AppKit or SpriteKit.

Slice 2 adds an optional SpriteKit checkerboard in a borderless, click-through AppKit window on the main display. It starts disabled. The editor button or Window → Enable/Disable Desktop World controls it. The owner confirmed the Slice 2 manual checks on 2026-10-07; The corresponding MANUAL checkboxes are checked based on the owner's report.

Slice 3 adds a tested `CoordinateMapper` and `ScreenDescriptor`. Coordinates use logical points, with the camera origin at the canvas's lower-left corner. Negative positions floor to tiles; backing scale does not affect occupancy.

Slice 4 samples global pointer position at 30 Hz while the checker is enabled. A subtle outline marks the world tile under the cursor; the editor shows screen position, world position, tile, display ID, and camera values. The outline hides outside the active display. Checker geometry and highlight placement both go through `CoordinateMapper`. Pointer sampling stops when the desktop world is disabled.

The owner confirmed the Slice 4 alignment and Finder-interaction checks on 2026-10-07. Slice 5 adds a global left-mouse-down observer and a 0.3-second amber tile flash. The editor shows a click count and last clicked tile. Disabling the world or quitting removes the observer and stops pointer sampling. Duplicate starts do not install duplicate observers; late callbacks from removed registrations are ignored. These are diagnostic flashes only; no circuit or file actions exist yet.

The owner confirmed Slice 5 desktop clicks, including the expected flash beneath a Finder folder icon, on 2026-10-07. Slice 6 introduced **Finder Diagnostics…** in the editor. Its **Read Finder Items** button explicitly queries Finder through `DesktopItemProviding`. Opening the app or diagnostics window does not contact Finder. Permission denial and malformed responses display different errors, and failed reads clear the list instead of retaining stale positions. The owner reported Slice 6 working on 2026-10-07.

Slice 7 adds pink rings/crosshairs behind Finder icon centers, plus mapped screen/center and world-tile columns. After a successful read and enabling Desktop World, **Start Polling (2 Hz)** enables serialized live updates. **Stop Polling** freezes the last snapshot; disabling the world or quitting also stops polling. Errors pause polling until you explicitly retry. Identical snapshots do not publish new item arrays or redraw markers. The owner reported all Slice 7 checks working on 2026-10-07, establishing the center mapping on their Mac. This is owner-reported evidence, not an independent check on other configurations. The corresponding MANUAL checkboxes are checked based on the owner's report.

Slice 8 groups icon centers into world tiles using a pure `DesktopOccupancyResolver`. Green tiles contain one item; red tiles contain multiple items. Finder Diagnostics lists every item in ambiguous tiles. Items with centers outside the active display are excluded. Unread or failed Finder data is unavailable, distinct from an empty tile. Polling updates occupancy; stopping polling freezes the last snapshot. Slice 9 first established the fixed feasibility circuit described below; Slice 11 now supplies its general simulator.

Manual acceptance through Slice 8 is complete based on the owner's confirmations on 2026-10-07. The roadmap records those reports separately from automated validation. Future manual checks will be checked off as the owner confirms them.

**Slice 9 is complete; feasibility Gate A passed:** on 2026-10-07 the owner confirmed activation, occupant opening, no target after moving the item away, and opening a different replacement item. All five roadmap manual checks are checked based on those real-Mac reports. The associated-window gate resolved the prior rejections in their tested configuration. The last code revision built successfully and passed 64 automated tests. Slice 10 (World model) is implemented below.

Slice 9 adds a fixed **PRESS (2, 3) → four dust tiles → OUTPUT (7, 3)** circuit. When the interaction gate accepts a PRESS click, it refreshes Finder positions, then starts a 20-tick pulse at 20 Hz. Dust turns yellow, the button/output turn orange, and the output flashes white. A separate `OpenItemAction` uses [NSWorkspace.open](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:)) to request normal macOS opening of exactly one current occupant. The editor reports the request result; acceptance by macOS does not prove the target application's UI opened correctly.

Each rising pulse requests one open. Pressing again while powered extends the pulse without another activation. Empty, ambiguous, and unavailable outputs open nothing. An initial explicit Finder read is required. A busy Finder read asks you to retry rather than queueing presses. The world remains click-through. Normal component clicks require the captured recipient to be Finder's desktop window at the public desktop-icon level. The monitor carries NSEvent.windowNumber plus public CGEvent handling-window and target-process fields. The gate prefers [NSEvent.windowNumber](https://developer.apple.com/documentation/appkit/nsevent/windownumber) as the window associated with the event, using the handling-window field only when it is absent. It queries that window's metadata, checks its owner, and rejects ordinary Finder/application windows. Target PID is diagnostic data; it need not match the window owner. Missing identity produces a diagnostic message rather than guessing. Unrelated Dock windows do not participate in this decision. No screenshots are used. A conservative one-tile margin around PRESS protects nearby Finder icon/label interaction because center-only scripting data does not establish exact hit regions. Keep PRESS and its neighboring tiles clear. Disabling the desktop invalidates pending activation reads and stops the pulse timer. Slice 9 introduced no script execution or general circuit engine; Slice 11 replaces its pulse engine below.

Slice 10 adds pure Swift `World`, `Tile`, `TerrainID`, `DecorationID`, and `CircuitWorld` value types. Terrain tiles and coordinate-keyed circuit components are separate data, and runtime power is supplied separately to the renderer. The existing demo is now a model fixture; `DesktopScene` contains no fixed test-circuit coordinates. It draws visible model tiles, decoration labels, components, and dust paths, and clears/rebuilds them as the model or viewport changes. The six demo tiles have simple grass-color fills; the checker remains behind unspecified tiles. At that revision, there was no procedural terrain or general simulator. Its Debug build and all 72 tests passed, including the existing fake Finder/open integration.


Slice 11 replaces the fixed pulse with a pure, deterministic `CircuitSimulator`. Buttons and levers supply power 15, cardinal dust attenuates by one per dust-to-dust step, and outputs emit one event when power rises from zero. The entire network settles within each tick using a bounded queue; loops cannot retain power after sources turn off. A separate scheduler requests 20 ticks per second. The original button row remains at y=3, and a second **LEVER (2, 5) → four dust tiles → OUTPUT (7, 5)** row demonstrates continuous power. The editor displays button-row dust strengths. Output actions wait for busy reads and refresh Finder occupancy before opening; simulation and rendering never launch files. Disabling resets runtime state; world persistence comes later. Debug build and all **86 tests** pass. The owner confirmed the Mac regression on 2026-10-07; repeaters remain for Slice 12.


Slice 12 adds directional repeaters with model-configured **1–4 redstone ticks** of delay (2/4/6/8 simulation ticks). They read only behind their arrow, restore positive incoming power to 15, and emit only forward. Both edges are delayed equally; aligned chains add their delays. Bounded input histories and the existing iterative dust solver preserve deterministic behavior in loops. The renderer shows arrow/delay and powered color. A third **PRESS (2, 7) → dust → REPEATER (5, 7), → 4t → dust → OUTPUT (7, 7)** row provides a visible delayed demo. It opens the fresh occupant when output power rises, using the existing action adapter. Debug build and all **101 tests** pass; the owner confirmed the Mac regression on 2026-10-07. Repeater placement, rotation, and delay controls in a general editor remain for later slices.


Slice 13 extracts a snapshot-driven `CircuitRenderer` and adds original cached textures for every circuit component's off/on state. PRESS/DOWN and lever OFF/ON are now distinct; repeater images rotate with their arrow and retain delay labels. Dust follows actual cardinal ports, with no line into a repeater's sides. OUTPUT shows **EMPTY** (gray), **ITEM** (green), **MANY** (red), or **N/A** (purple), independently of power. Separate output flashes can coexist. Occupancy survives power refreshes and viewport resize. The renderer has no Finder-query or action-execution dependency. Texture scaling uses SpriteKit's documented [nearest filtering](https://developer.apple.com/documentation/spritekit/sktexture/filteringmode). Debug build and all **107 tests** pass; the owner confirmed the Slice 13 visual-state MANUAL check on 2026-10-07.

The three existing demo rows keep their positions. Future test circuits will extend to their **right**, rather than above them. After you confirm a slice, the confirmation and next implementation will be handled in one turn.


Slice 14 adds pure terrain capabilities and one shared placement evaluator/transaction. Components cannot be placed on water, unspecified terrain, decorations, or an occupied circuit cell. Rejected attempts preserve the entire world, and accepted placements preserve existing terrain and unrelated components. **Developer Placement…** opens a small SwiftUI rule-testing form with component/test-tile selection, repeater configuration, preview feedback, placement, and patch-only reset. Its explicit terrain patch is to the right at x=10–15. Disable Desktop World to edit, then enable it to inspect/use the placed components. Configuration lasts across enable/disable during this app session; relaunch starts from the fixture because persistence comes later. Debug build and all **123 tests** pass; the owner confirmed the placement-form regression on 2026-10-07. This is the roadmap's developer UI; the general canvas editor is Slice 15.

Slice 15 replaces the main placeholder with a SwiftUI editor and SpriteKit canvas: Select, Pan, Dust, Button, Lever, Repeater, Output, and Erase tools; anchored scroll/button zoom; an inspector with repeater direction/delay; and green/red placement previews with rejection reasons. Its independent camera leaves the real desktop unchanged. Editing requires Desktop World disabled, while selection and browsing remain available when running. Existing diagnostic controls are in **Desktop Controls…**. A finite grass construction area occupies x=10–25, y=7–11 to the right of the existing circuits. The editor displays cached output occupancy without querying Finder. Debug build and all **135 tests** pass; the owner confirmed useful-circuit authoring on their Mac on 2026-10-07. Slice 16 adds persistence below.

Slice 16 adds versioned Codable JSON persistence, an atomic WorldStore, debounced autosave and quit-time flush. Circuit components, repeater configuration, desktop camera and lever positions restore from `~/Library/Application Support/RedstoneDesktop/world.json`. The terrain fixture is recreated by version, not saved tile-by-tile. Desktop World always starts disabled; Finder data and transient simulation/actions are excluded. The footer reports pending/saved/error status, and **Save Now** retries failed writes. Corrupt/unsupported documents are preserved with saving disabled for that session. Debug build and all **148 tests** pass; the owner confirmed quit/reopen validation on 2026-10-07.

Slice 17 adds a pure, stateless deterministic terrain generator, versioned UInt64 seed settings, integer hash/smooth 2D noise, elevation/moisture/temperature, biome selection, all six terrain types and four decorations, and 32×32 chunk sampling. Negative and extreme integer coordinates are tested. Fixed version-1 fingerprints protect reproducibility, and adjacent chunks use the same global fields. Debug build and all **157 tests** pass. The live app still renders its persisted fixture: chunked terrain rendering is Slice 18, and seed browsing is Slice 19. A standalone comparison image can be generated with `scripts/terrain-preview.sh`.

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

An automated hosting test does not prove the visible window is correct. `MANUAL` checkboxes are checked only after the owner confirms the corresponding checks passed on their Mac.

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

No new permissions are expected: position comes from Apple's public [NSEvent.mouseLocation](https://developer.apple.com/documentation/appkit/nsevent/mouselocation) property. The owner reported these checks passing; automated tests use fake pointer positions, and the corresponding MANUAL checkboxes record the owner's confirmation.

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

Apple documents [NSAppleScript as main-thread-only](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html), so this feasibility spike executes each explicit query there. Finder events use a 10-second timeout; a slow reply or permission interaction can delay this app's UI. Tests exercise the runner with harmless scripts and the UI model with fake providers; they do not query your real Finder or prove TCC permission behavior. Automatic polling and coordinate calibration were added in Slice 7.

## Manual validation — Slice 7

1. Quit the previous app and open the latest build with the command above. Confirm the footer says “Slice 7 · Finder coordinate calibration”.
2. Enable Desktop World, open **Finder Diagnostics…**, and click **Read Finder Items**. Pink rings/crosshairs should appear behind real icons on the active display. Move/minimize the diagnostics window to see them. A crosshair's arms extend beyond the icon so its center remains assessable even when Finder covers the middle.
3. Check that each ring/crosshair is centered on the icon image, not its text label. Compare raw position, mapped screen/assumed center, and world tile in the table. Recheck the owner-validated conversion; report any consistent offset.
4. Click **Start Polling (2 Hz)** and drag an icon. Its marker should follow the latest Finder position, possibly only after Finder commits the drag/drop. Polling is two reads per second; perfectly smooth tracking during the drag is not promised. Report whether it updates during dragging or only after release.
5. Move a harmless test icon near each screen edge and corner, then check alignment after dropping it. Use icons with different image shapes if available. Keep normal Finder selection, drag, and double-click behavior intact.
6. Click blank desktop to make Finder active. Open Finder's View → Show View Options (Command-J) and change **Icon size**. After Finder settles, check marker centers again. Restore your preferred size afterward. Finder may rearrange icons; the app should follow the actual new positions.
7. Click **Stop Polling**, move an icon, and confirm the snapshot stays frozen until **Read Finder Items** or restarting polling. Disable/re-enable Desktop World: polling should remain paused until explicitly restarted.
8. Report offsets with a description such as “markers are 20 points below every icon”, and copy that item's raw/mapped coordinates. Also report UI stutters, delayed reads, missing markers, or errors. If alignment is wrong, stop here: document the observation and adjust the coordinate contract before occupancy is implemented.

Owner-validated mapping: Finder's raw point is the icon center, measured in logical points right/down from the primary display's upper-left corner. `CoordinateMapper` converts it to `(primary.minX + rawX, primary.maxY - rawY)` with no additional offset. [Apple documents the primary screen as `NSScreen.screens[0]`](https://developer.apple.com/documentation/appkit/nsscreen/screens); this differs from the active-window screen returned by `NSScreen.main`. Finder's origin and center semantics are not established by that API documentation and were confirmed by the owner on their Mac using the checks above. This slice covers one active renderer; display reconfiguration and multi-display behavior remain later work.

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

The owner confirmed Slice 8 with “It works!” on 2026-10-07. Its boundary-transition MANUAL checkbox is checked based on that report. Slice 9 is next.

## Manual validation — Slice 9

1. Quit the old app with **Command-Q**, then launch the new build:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm the footer says **Slice 9 · Button-to-output circuit**. Click **Enable Desktop World**, then **Finder Diagnostics… → Read Finder Items**. Polling is optional for this test: each accepted button press refreshes Finder itself. Leave polling stopped initially to avoid the busy-read retry message.
3. Move or minimize the editor/diagnostics windows so the **PRESS** and **OUTPUT** desktop blocks are exposed. Move any icons on or within one tile of PRESS away. Click blank desktop to activate Finder.
4. Drag a harmless folder (or ordinary document/app alias) so its pink center crosshair sits inside **OUTPUT**, tile **(7, 3)**. Click **Read Finder Items** to verify the table's tile, or temporarily enable polling. If Finder automatically rearranges the icon, disable its sorting before positioning it; restore your preferred settings afterward.
5. With Finder active, single-click **PRESS**, tile **(2, 3)**. The path should turn yellow, the button/output orange, and OUTPUT briefly flash white. The occupant should open normally. The pulse should end after about one second. In the editor, check the named item in the open-request result.
6. Close/move the opened window, return to the exposed desktop, and wait until the path is off before pressing again. A new pulse should issue one new open request. Repeated presses during an active pulse should extend it without another request; the result explains this.
7. Move the item away from OUTPUT and immediately press again after the pulse ends. Nothing should open; the result should say the output is empty. Move a different harmless item onto OUTPUT, then press again. The new item should open, even if polling was stopped.
8. Check that icons remain selectable/draggable and that clicking one on or near PRESS does not power the circuit. Place a normal window over PRESS, including a Finder folder window, and click inside it: the hidden circuit must not activate. If a click is ignored, return to blank desktop first and keep the PRESS area clear.
9. If two centers can fit in OUTPUT, confirm it opens neither and reports ambiguity. Disable Desktop World and confirm the circuit disappears. Re-enable and confirm it starts unpowered.

Report any wrong target, unexpected repeated opening, window click activating a hidden button, or delayed/missing pulse. All five Slice 9 MANUAL acceptance items are owner-confirmed and checked in SPEC. Gate A passed on 2026-10-07; these instructions remain available for regression checks.

### Slice 9 recipient-gate validation

Clicking the checkerboard is clicking the real Finder desktop: the overlay is click-through. Quit the old app and reopen the latest build before testing. Enable Desktop World, read Finder items, and leave polling stopped initially. Expose PRESS and keep its neighboring tiles clear of icons.

1. Click blank checkerboard, then PRESS at tile (2, 3). Even with OUTPUT empty, the path should light for one second and the result should say the output is empty.
2. Put a harmless folder/document center on OUTPUT (7, 3), wait for the path to turn off, then press again. Confirm that item opens. Move it away and replace it to validate the remaining Slice 9 manual checks.
3. Confirm clicking inside a Finder folder window or another app window covering PRESS does not activate the circuit.
4. If PRESS is still rejected, report the full message and the Press clicks count. The editor now shows event-window, handling-window, target-PID, selected-window, owner bundle/PID, and layer values for every PRESS attempt, including accepted attempts. Copy that complete metadata line and the result if activation still fails.

The separate command-line probe did not receive the owner's clicks and provides no recipient-field evidence. Validation must use the app's actual monitor. Do not infer working desktop activation from the fixture tests.

## Manual regression check — Slice 10

The owner confirmed this regression check on 2026-10-07: the demo works as before, with the expected green grass tiles beneath the circuit. Slice 10 has no new roadmap MANUAL acceptance checkbox. These instructions remain available for future regression checks.

1. Quit the previous app with **Command-Q**, then launch the latest build:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm the footer says **Slice 10 · World model**. Enable Desktop World, open Finder Diagnostics, and read Finder items. Leave polling stopped initially.
3. Expose PRESS at (2, 3), keeping its neighboring tiles clear. The wire still leads to OUTPUT at (7, 3). The tiles under the circuit have plain grass-color fills; this is expected placeholder model rendering.
4. Click PRESS with OUTPUT empty: the path should light for about one second and nothing should open. Put a harmless folder/document center on OUTPUT, then press after the path turns off: the item should open. Move it away or replace it and confirm the corresponding result still changes.
5. Confirm Finder selection/dragging still works and disabling/re-enabling removes/restores the world with an unpowered circuit. Report any changed click behavior, missing wire segments, or misplaced components.

These were the Slice 10 checks. For the current build, use the Slice 11 walkthrough below.


## Manual regression check — Slice 11

The owner confirmed this regression on 2026-10-07, reporting that it works as expected. This is owner-reported Mac validation, separate from the 86 passing automated tests. Slice 11 has no roadmap MANUAL checkbox. These steps remain available for future regression checks; the older walkthroughs above describe their respective builds.

1. Quit the previous Redstone Desktop app with **Command-Q**. In Terminal, launch the new build:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm the editor footer says **Slice 11 · Circuit simulator**. Click **Enable Desktop World**, then **Finder Diagnostics… → Read Finder Items**. Leave polling stopped initially. Expose both input blocks and keep their neighboring tiles clear of Finder items. Hover over a block and use the editor's tile coordinates to identify it: PRESS is (2, 3), LEVER is (2, 5), two rows above PRESS.
3. With the original OUTPUT (7, 3) empty, click PRESS. Its row should light briefly, the dust values should show **15, 14, 13, 12**, and the result should report an empty output. Once it turns off, put a harmless folder/document center on that OUTPUT and press again: it should open once. Re-pressing while the row is still powered extends the pulse without another open; pressing after it turns off opens again. Finder reads can delay visible timing, so report long pauses rather than measuring exactly one second.
4. With the upper OUTPUT (7, 5) empty, click LEVER. That row should remain lit for several seconds and report an empty output. Click LEVER again: it should turn off. Place a harmless folder/document center on the upper OUTPUT, then turn LEVER on: it should open once. Return to the desktop and leave it powered; there should be no repeated opens. Close or move any window covering LEVER before clicking it again.
5. While LEVER stays on, replace or move the output item: this alone should not open anything. Turn LEVER off, then on; it should open the newly occupying item, or report empty/ambiguous occupancy if applicable. Each activation reads Finder again even with polling stopped.
6. Confirm normal Finder selection/dragging still works and clicking an ordinary Finder/application window covering an input does not activate it. Disable and re-enable Desktop World: both rows should start unpowered, and the button-row dust values should return to zero.

Please report whether these checks pass, and copy the editor's result/metadata if an input is rejected or an item fails to open. Long dust lines, cyclic networks, and arbitrary world fixtures are exercised by automated tests; there is no circuit authoring UI yet. Slice 12 adds repeater behavior next.


## Manual regression check — Slice 12

The owner confirmed this regression on 2026-10-07, reporting “It works!” separately from the 101 passing automated tests. Slice 12 has no roadmap MANUAL checkbox. These steps remain available for future regression checks; earlier walkthroughs describe earlier builds.

1. Quit the previous Redstone Desktop app with **Command-Q**, then launch the latest build from Terminal:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm the footer says **Slice 12 · Repeater**. Enable Desktop World, open Finder Diagnostics, and click **Read Finder Items**. Leave polling stopped initially. Expose the third row, two rows above LEVER: PRESS (2, 7), repeater (5, 7), OUTPUT (7, 7). Keep PRESS and its neighboring tiles clear of Finder icons. Hover and use the editor's tile coordinates to identify the correct blocks.
3. Start with the third OUTPUT empty. The repeater should show **→ 4t** on a gray block. Here `t` means a 100 ms redstone tick, so four ticks is nominally 0.4 seconds. Click this row's PRESS. Dust to its left should light first; the repeater should then turn orange, and dust/output to its right should light after the delay. The editor's repeater/output powers should become **15**. The result should report empty output.
4. Watch the row turn off: its left side turns off first, then its repeater/right side after the same delay. Finder reads/main-thread activity can stretch visible wall-clock timing; the automated tests establish exact simulation-tick timing. Report a missing sequence or a long pause instead of trying to measure milliseconds manually.
5. Put a harmless folder or document center on OUTPUT **(7, 7)**. Wait until the circuit is fully off, then press its button again. The item should open once after the delayed activation. Move it away or replace it; a later press should report empty or open the new occupant. Merely moving an item should not activate an output.
6. Press this row's button with an empty output, then quickly disable Desktop World. Re-enable it and wait: all rows should remain off, with no delayed activation left over. The repeater arrow/delay label should return correctly.
7. Confirm the original PRESS row at y=3 and continuous LEVER row at y=5 still behave as before, normal Finder selection/dragging works, and ordinary windows covering an input do not activate it.

Please confirm these checks or copy the editor result/metadata for any failure. The demo uses one east-facing, four-tick repeater; all four directions/delays, chains, and feedback loops are covered by automated fixtures because there is no circuit authoring UI yet. Slice 13 (Circuit renderer) is next.


## Manual acceptance — Slice 13

The owner confirmed this visual walkthrough on 2026-10-07, reporting “Looks good!” The roadmap's **MANUAL: visual state tracks simulation correctly** is checked based on that Mac report, separate from the 107 passing automated tests. These instructions remain available for regression; use the same three rows.

1. Quit the previous app with **Command-Q**, then launch the latest build:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm **Slice 13 · Circuit renderer** in the footer. Enable Desktop World. Before a Finder read, OUTPUT blocks should have a purple **N/A** badge/border. Read Finder items; empty outputs should switch to **EMPTY** with a gray border. Leave input blocks and their neighboring tiles clear of icons.
3. Click PRESS **(2, 3)** with an empty output. Its icon should change from raised **PRESS** to depressed **DOWN**, dust from red to yellow, and output should light and flash white once. The row should return to its off appearance after the pulse.
4. Click the lever **(2, 5)**. Its handle should flip and label change **OFF → ON**, with its wire staying yellow. A second click should return it to OFF and the wire to red. A held output should not flash/open repeatedly.
5. Test the repeater row at **y=7**: its arrow should still point right with **→ 4t**, change from gray to lit after the delay, and restore its off image after the delayed falling edge. Opening an item on OUTPUT **(7, 7)** should still happen once per rising edge.
6. Move a harmless folder/document onto a visible output and refresh Finder items (or enable polling). Its border/badge should change to green **ITEM**; moving it away should return it to **EMPTY**. Real Finder icons stay above the renderer and can cover parts of these badges. If you can conveniently put two item centers in one output tile, its state should be red **MANY**, and no item should open; ambiguity is also covered by automated fixtures.
7. Confirm Finder selection/dragging and ordinary-window click rejection still work. Disable/re-enable: all circuits should return unpowered, output occupancy should reflect the last successful Finder snapshot, and no stale white flash should remain.

Please report whether visual states follow the circuit correctly, or describe any unreadable labels, missing segments, stale badge, or unexpected opening. On confirmation, the next implementation is Slice 14 (Placement rules), with new demo circuits placed to the right if needed.


## Developer placement walkthrough — Slice 14

Debug build and 123 tests passed for this revision. The owner confirmed the walkthrough on 2026-10-07 with “Looks good! Continue.” Slice 14 has no roadmap MANUAL checkbox.

1. Quit the old app with **Command-Q**, then launch the latest build:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm **Slice 14 · Placement rules** in the footer. Leave Desktop World disabled and click **Developer Placement…**. This opens a separate scrollable window; placement itself does not require reading Finder.
3. Select **Dust** and **grass (10, 3)**. The preview should say **Placement allowed**. Click **Place component**; the result should confirm placement and the patch contents should show `dust` on grass.
4. On that same grass tile, choose **Lever** and click **Place component**. It should refuse because a component already exists. The contents should still show `dust`; nothing should be overwritten.
5. Choose **Dust** and try **shallowWater (14, 3)**, then **deepWater (15, 3)**. Both should report that components cannot be placed on water, and stay empty. Try **tree (10, 5)**, **flower (11, 5)**, **rock (12, 5)**, and **reed (13, 5)**: each should report its blocking decoration and stay empty. **unspecified (14, 5)** should report no specified solid terrain.
6. Enable Desktop World in the main editor. The terrain patch should appear to the **right** of the original circuits, with your red dust on grass (10, 3). Hover to check coordinates if needed. The three original circuits should stay in place and work as before. While enabled, the developer window's placement/reset buttons should be disabled.
7. Disable the world again. Click **Reset test placements** in the developer window; the patch list should return to empty. Enable the world and confirm the placed dust is gone, while terrain/decorations and the original circuits remain.
8. Optional: with the world disabled, place a repeater on a dry test tile and choose its direction/delay. Enable the world and check the matching arrow/delay label. Reset afterwards if desired.

Changes are temporary for this app session. This walkthrough remains available for regression; the current main window is the Slice 15 editor below.


## Basic editor walkthrough — Slice 15

This revision built and passed all 135 tests. The owner confirmed the walkthrough on 2026-10-07 with “It works! Thats neat.” The corresponding Slice 15 MANUAL checkbox is checked based on that Mac report. These steps remain for regression; the current footer is Slice 16.

1. Quit the old app with **Command-Q**, then launch this build:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm **Slice 15 · Basic editor** in the footer. Keep Desktop World disabled. You should see tools on the left, the world canvas in the middle, and the Inspector on the right. The original three circuits should remain at x=2–7; the new grass construction area is to their right.
3. Choose **Pan**, then drag the canvas. Try scrolling and the **+ / −** buttons to zoom. **Reset view** returns the editor to its starting view. These controls should move only the editor view, not the real desktop.
4. Build the following row on the grass area. Choose each tool, move over the canvas, and check the Inspector's **Hover (x, y)** before clicking. A green preview means placement is allowed. For the repeater, choose **East** and **2 redstone ticks** in the Inspector before placing it.

   | Tile | Tool |
   | --- | --- |
   | (10, 7) | Button |
   | (11, 7) | Dust |
   | (12, 7) | Repeater, East, 2 redstone ticks |
   | (13, 7) | Dust |
   | (14, 7) | Output |

   After placement, a red preview on that same tile is expected because it is now occupied. The status should confirm successful placement. If you make a mistake, use **Erase** to remove the component, then place it again. The grass should remain.
5. Choose **Select**, then click the repeater at (12, 7). Check its terrain, component and stored settings. Change its direction/delay and click **Apply direction/delay**; confirm the arrow and delay label change. Return it to **East, 2 redstone ticks** for the circuit test. Selecting the button/output in the editor should not activate it or open anything.
6. Choose **Dust** and hover over water at (14, 3), then the tree at (10, 5). Both should show red previews and a reason for rejection. Clicking should leave them unchanged. An occupied circuit tile should also refuse replacement.
7. Open **Finder Diagnostics…** and click **Read Finder Items**. Enable Desktop World. Editing tools and inspector edit buttons should be disabled; Select/Pan/zoom should still work. Minimize or move the editor and diagnostic windows so they do not cover the real desktop circuit. Ordinary application windows intentionally block desktop activation beneath them.
8. On the **real desktop**, put a harmless folder on OUTPUT (14, 7), and keep PRESS (10, 7) and its neighboring tiles clear of Finder icons. Use **Desktop Controls…** to inspect pointer tile coordinates if necessary. Press the real desktop button: the circuit should light up, with about a **0.2-second repeater delay**, then request opening the folder once. Try it with the output empty too: the circuit should still light up without opening anything. The original circuits should continue working.
9. Disable Desktop World and confirm your new circuit remains editable. Erase one component and verify its terrain stays intact. Please confirm whether you could author and run this circuit using only the UI, and report any missing hover preview, wrong tile placement, or layout/input problem.

Slice 15 changes were temporary. The current Slice 16 build saves circuit edits as described below; editor pan/zoom still resets on reopening.


## Saving and restart walkthrough — Slice 16

1. Quit the old app with **Command-Q**, then launch the new build:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm **Slice 16 · Persistence** in the footer. On your first launch of this version there is no saved world yet, so the initial fixture appears. Edits made in the previous temporary build cannot be recovered.
3. Keep Desktop World disabled. Rebuild your circuit from the Slice 15 table above, or place a few components on the right-hand grass. Select a repeater and apply a distinctive direction/delay, such as **East, 3 redstone ticks**. Erase one original or newly placed component if you want to verify deletions too.
4. Watch the footer: it should briefly say **Unsaved changes…**, then **Saved.** after about 0.75 seconds. **Save Now** also saves pending changes immediately. Pan/zoom does not save because it is temporary browsing, separate from the desktop camera.
5. Quit with **Command-Q**, then launch using the same command. The footer should report **World restored. Desktop World starts disabled.** Confirm that placements, erased cells and repeater direction/delay match your edits. Terrain should remain intact. It is expected that the editor view resets and no file opens on startup.
6. Make another component edit and quit immediately, before the debounce has time to finish. Reopen and confirm that edit also survived; quitting should flush it.
7. Optional lever check: read Finder items, enable Desktop World, and turn a clear desktop lever ON. Disable and quit, then reopen. Read Finder items and explicitly enable Desktop World again: the lever should resume ON. **A saved ON lever can activate its output when you enable the world.** Use a harmless folder or empty output for this check. Turn it OFF and confirm the OFF position survives another restart.

The saved file is outside the repository:

```text
~/Library/Application Support/RedstoneDesktop/world.json
```

If restoration fails, the footer explains the problem and saving is disabled so the original file stays untouched. To recover, quit, use Finder's **Go → Go to Folder…** to open the directory above, and move `world.json` somewhere safe as a backup before relaunching. The app will start a new fixture; keep that backup for diagnosis. Corrupted-file handling has automated coverage, so deliberately damaging your saved circuit is not required for the Mac acceptance check.

Please confirm that both normal quit/reopen and immediate quit after editing restore the correct circuit. The owner confirmed the restart checks on 2026-10-07 with “Works!” The Slice 16 MANUAL checkbox is checked based on that report. This walkthrough remains available for regression.


## Generator regression and preview — Slice 17

This slice implements the generator without replacing your saved terrain/circuit. There is no new roadmap MANUAL checkbox. Please check the existing app still behaves correctly:

1. Quit the old app with **Command-Q**, then launch:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm **Slice 17 · Terrain generator** in the footer. Your saved components and repeater settings should remain, and Desktop World should start disabled. The canvas should still show the previous fixture and construction area; procedural terrain is not yet connected to the live renderer.
3. Enable Desktop World and check your existing circuit as before. Try an edit while disabled, quit/reopen, and verify persistence still works. New chunks must not appear or replace tiles beneath your circuit in this revision.

To see the generator's current output, run these commands from the repository directory:

```sh
./scripts/terrain-preview.sh
open build/terrain-preview.svg
```

This creates a comparison image outside the source/bundle: seed **42** on the left, seed **2026** on the right. Both cover x/y **−64…63**. Colors indicate terrain; dark dots indicate decorations; faint lines mark 32-tile chunk boundaries. The seeds should have different land/water layouts, and the faint chunk lines should not create artificial breaks in terrain. Re-running produces identical output. These previews are developer data plots, not an interactive seed browser or polished terrain art.

The generator's fixed snapshot, chunk consistency, negative-coordinate and seed-diversity checks are automated. The next implementation is **Slice 18 — Chunked terrain renderer**.
