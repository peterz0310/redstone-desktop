# Redstone Desktop

An experimental native macOS app exploring a block world beneath real Finder desktop icons. This is an early prototype, not an MVP. `SPEC.md` is the source of truth; development follows its roadmap one slice at a time.

## Current build and next steps

**Implemented: Slices 0–29 plus the requested appearance/navigation follow-ups (27A/28A/28B/28C/29A).** Debug build and all **356 automated tests** pass. Slice 28 adds explicitly entered Desktop Build Mode with a temporary transparent input window, hotbar and mouse-accessible exits; its real Finder/input checks remain pending. Slices 26/27 add optional validated texture/sound packs and local Minecraft Java texture importing. Original built-in assets remain complete defaults; imported game art stays in local Application Support, outside Git and app bundles. Read the [resource-pack format guide](docs/RESOURCE_PACKS.md) and [Java import guide](docs/JAVA_TEXTURE_IMPORT.md) before making/sharing packs.

Slices 20/21 and 23–25 are owner-accepted, along with corrected Slice 22 icon-size/marker behavior and the 19C bookmark/context-menu follow-up. Earlier detailed 19B/19C checks, Slice 22's real Output-after-resize check and the other specific Slices 26/27 checks and new 27A appearance checks remain pending. Local Java importing is owner-accepted.

The editor now shows **Worlds** in a left sidebar and **Areas in [world]** as a preview shelf below the canvas. Build tools and the inspector sit on the right. The top shows the world/area being edited, the separate desktop assignment, **Start/Stop Desktop** and **Advanced**. New World, Save Current View and rename use focused sheets; seed/creation fields are no longer permanently visible.

Configuration still saves to `~/Library/Application Support/RedstoneDesktop/library.json`; the earlier world.json stays a legacy backup. Select a world/area to browse it, **Save Current View…** to bookmark a new view, and **Update Current Area** to replace the selected bookmark's view without creating another. **Activate on Desktop** assigns the selected saved camera. Panning does not change what Activate targets. Inactive worlds stay editable while another runs; stop the desktop to edit its active world. Startup restores the active area but starts stopped.

**Right-click a world → Delete World…** removes an inactive world and all its builds/areas after confirmation. **Right-click an area → Delete Bookmark…** removes only that view, leaving components on the map. The desktop world/area and final world/bookmark are protected. Activate another saved area first if you want to delete the assigned one. Deletions save atomically before publication; failure preserves records and never queues a delayed deletion. Finder files are unaffected.

Finder Diagnostics remains useful for permission/alignment problems, and Desktop Details for input rejection/action results. They moved to **Advanced**. The obsolete Developer Placement window and fixed-demo diagnostic rows are removed; automated tests and migration fixtures remain, and no existing saved circuits were cleared. Shelf previews remain bounded schematic terrain/circuit snapshots. Finder markers now appear separately in the main editor canvas when enabled.

**Next: run the [Slice 29A settings/permission walkthrough](docs/SCRIPT_OUTPUTS.md#slice-29a-settings-and-earlier-permission-walkthrough).** Basic Slice 29 prompt/run/target-movement behavior is owner-accepted; repeater-specific timing remains pending. Finder responsiveness is owner-accepted; other detailed adapter checks remain pending. Desktop Finder crosshairs are removed. Slice 30 (simplified torches) remains untouched.

## Adopted plan: worlds and saved areas

This plan is approved in [SPEC.md](SPEC.md). **Slice 19A implemented independent worlds and save migration; 19B added activation; 19C makes navigation clearer and adds previews/deletion.**

| Concept | Meaning |
| --- | --- |
| World | A named saved map with a fixed seed and its own components and lever positions |
| Saved area | A named camera bookmark into a world; it stores no separate circuit |
| Editor selection | The world/area you are browsing or editing |
| Active desktop area | The one saved area assigned to your desktop; it runs only while Desktop World is enabled |

For example, save **Morning shortcuts** and **Project launcher** in your seed-42 world, and **Experiments** in your seed-2026 world. Components stay where you built them. Overlapping areas in one world share the same components. Two independently created worlds with the same seed share terrain generation but have separate builds; reopen them through the Worlds sidebar.

The current flow is:

1. Click **+** beside Worlds, enter a name/seed, optionally Preview/Random, then choose **Create World** to save a new empty world. This selects it for editing without activating it.
2. Build, pan and explore. **Save Current View…** creates a named bookmark; **Update Current Area** replaces the selected bookmark's saved view, preserving its name and ID. Stop Desktop to update its active bookmark. Updating that stopped assigned bookmark prepares the camera for the next explicit start; updating another bookmark leaves the desktop assignment unchanged.
3. Select any world/area from the sidebar or area shelf to browse it. You can edit an inactive world while another world runs. To edit the active world, disable Desktop World first.
4. Choose **Activate on Desktop** to use the selected saved area's camera and circuit. Unsaved browsing changes are not applied; save another area first. Enabling/disabling controls whether the assigned area is running.
5. Quit/reopen: all worlds/areas and the active selection restore, but Desktop World starts disabled. Temporary editor browsing is not saved.

Inactive worlds remain paused. The active world's whole circuit simulates, including wires outside the visible area; only visible output tiles can dispatch desktop actions. Switching resets transient pulses/delays and cancels pending work from the old session. Saved ON levers resume and can activate outputs when you explicitly enable or switch areas. Re-activating the same world/camera does not restart it.

Real Finder files stay on your actual desktop. They are neither copied into worlds nor repositioned when you switch; their occupancy is recalculated against the active area's camera. Enabled editor ghosts show a projection against the selected area's proposed camera.

Slice 19A migrates your current world into `~/Library/Application Support/RedstoneDesktop/library.json`, retaining your existing identity, chosen seed, circuit, levers, terrain patches and camera as the first **Desktop** area. The old world.json stays untouched as a backup. New worlds get empty procedural terrain and a default **Home** area rather than your existing demo circuits/grass patches. A valid library takes precedence over the backup; failed/corrupt restoration preserves saved data and blocks writes. Selecting a new world never activates it; use Activate on Desktop to assign its saved area.

Slice 19C adds previews and confirmed deletion. Copying circuits between worlds and terrain regeneration remain deferred. Detailed tasks, migration rules and acceptance checks are in SPEC.md Sections 3.8, 7.1, 25, 29 and the roadmap.

## Implemented slice history

The entries below describe behavior/evidence at each slice's implementation. Use **Current build and next steps** above and the **Slice 19C walkthrough** below for today's app. Manual Finder reads became automatic in Slice 18; Slice 19A replaced the earlier seed-replacement behavior with independent fixed-seed worlds.

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

Slice 18 connects the generator to a bounded chunk renderer in the editor and desktop. Original code-drawn 8×8 placeholders are baked into one nearest-filtered sprite per 32×32 chunk. Only visible chunks plus a margin remain cached; camera moves reuse overlapping chunks, and power/occupancy updates do not regenerate terrain. The footer reports retained chunks/nodes and cumulative generation/texture counts. Format-1 saves migrate to format 2 with default seed **2026**, preserving original fixture tiles and circuits over generated surroundings; generated tiles are not saved individually. **Enabling Desktop World now reads Finder automatically and starts serialized 2 Hz polling.** Read Finder Items remains available for diagnosis/retry; denied access pauses automatic reads. Debug build and all **169 tests** pass; the owner confirmed the visible long-pan and idle checks on 2026-10-07.

Slice 19 adds a seed browser with Preview/Random/Cancel and **Use This Area**. Seed previews and editor pan/zoom leave the live desktop unchanged. Orange outlines the proposed physical desktop area, blue outlines the current one. The proposed origin is the editor view's lower-left world origin; desktop tile size is preserved. Applying saves seed/camera, updates a running desktop through its normal lifecycle, and recalculates Finder occupancy. A seed that invalidates existing components is refused with a warning, preserving the circuit. Debug build and all **178 tests** pass; the owner confirmed seed/location and restart validation on 2026-10-07.

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

## Historical validation walkthroughs

These walkthroughs retain owner acceptance evidence for their respective builds. Earlier footer labels, temporary-save behavior and manual Finder-read instructions are historical. Today's app uses the Slice 19A footer, library persistence and automatic Finder refresh; its current walkthrough is below. Slice 19B will receive its own walkthrough when implemented. Do not reset saved data or undo later functionality to reproduce an old build.

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

These were the Slice 10 checks. For the current build, use the Slice 19C walkthrough below.


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

Please report whether visual states follow the circuit correctly, or describe any unreadable labels, missing segments, stale badge, or unexpected opening. Slice 14 followed this historical revision; future demo circuits continue to the right.


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

Changes are temporary for this app session. This describes the Slice 14 build; the current editor is described in the Slice 19C walkthrough below.


## Basic editor walkthrough — Slice 15

This revision built and passed all 135 tests. The owner confirmed the walkthrough on 2026-10-07 with “It works! Thats neat.” The corresponding Slice 15 MANUAL checkbox is checked based on that Mac report. These describe the Slice 15 build; the current editor is described in Slice 19C.

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

Slice 15 changes were temporary. Slice 16 introduced saving circuit edits as described below; editor pan/zoom still resets on reopening.


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

The generator's fixed snapshot, chunk consistency, negative-coordinate and seed-diversity checks are automated. Slice 18 subsequently connected this generator to the renderer; Slice 19A now adds independent saved worlds; Slice 19B adds saved-area activation; its Mac acceptance is pending.


## Chunked terrain and automatic Finder walkthrough — Slice 18

The owner confirmed the Slice 17 regression on 2026-10-07. This revision adds visible generated terrain and the requested automatic Finder refresh. Older walkthroughs asking you to press Read Finder Items are superseded by the enable-time automatic read.

1. Quit the old app with **Command-Q**, then launch:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm **Slice 18 · Chunked terrain** in the footer. You should see colored generated land/water/decorations around the original fixture. Your saved components, repeater settings, original three rows and right-hand grass construction area should remain in place. The original grass beneath circuits and developer test terrain are deliberate overrides, so rectangular patch boundaries are expected; they are not generated chunk seams.
3. Choose **Pan**, then repeatedly drag across the world for a minute or two. Try zooming out with **−**. Terrain should continue beyond the original patch, including negative coordinates. Watch **cached chunks** and **chunk nodes** in the footer: counts can vary with zoom/position but should stay in a similar bounded range, rather than growing with every visited area. **Generated** and **textures** are cumulative work counts and are expected to rise while exploring.
4. Stop panning/zooming and note the generated/texture numbers. Wait about 15 seconds, then move the pointer over the canvas without panning. Those numbers should remain unchanged. Changing selection/hover or powering the circuit should not rebuild terrain textures. There should be no cracks or empty strips at 32-tile chunk boundaries.
5. Click **Reset view**. Enable Desktop World **without pressing Read Finder Items**. Allow the initial refresh to finish, then minimize/move editor windows out of the way and press a clear desktop button. With a harmless folder on its output, it should open as before. If Finder permission has never been granted, enabling may show macOS's permission prompt; accept to test the feature.
6. Optional: open Finder Diagnostics to inspect the automatic read/polling state. Move an icon and confirm its marker/occupancy follows. Disabling Desktop World should stop polling. If access is denied or a read fails, the editor should show the error and polling should pause; use the diagnostics read/retry controls after resolving access. There should be no repeating permission-prompt loop.
7. With Desktop World disabled, edit a component and quit/reopen. Verify placements/settings survive migration to format 2. You can now place on generated dry terrain when it is free of decorations; generated water/decorations must reject placement. Future test circuits should still go to the right of the originals.

Please confirm whether **long panning keeps retained chunk/node counts bounded**, **idle generated/texture counts stay fixed**, and **enabling works without manually reading Finder**. The owner confirmed these checks on 2026-10-07 with “Great! it works”; both Slice 18 MANUAL checkboxes are checked based on that report.

Your save remains at `~/Library/Application Support/RedstoneDesktop/world.json`. Legacy saves are migrated in memory; the next edit/save writes format 2 atomically. At the Slice 18 revision there was no seed control; the current Slice 19 build adds it below.


## Seed browser and choose area — Slice 19

1. Quit the old app with **Command-Q**, then launch:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm **Slice 19 · Seed browser** in the footer. Your saved seed/camera and circuit should still be present. Enable Desktop World so you can compare the real desktop with the editor while browsing.
3. Enter **42** in the Seed field and click **Preview**, or try **Random**. The editor terrain should change while the real desktop remains unchanged. The seed preview keeps your circuit and fixture patches. Circuit editing is paused while previewing a different seed; **Cancel Preview** restores the current terrain.
4. Choose **Pan**, drag left to explore areas to the right of the original circuits, and zoom out with **−** until you can see the orange rectangle. You can also explore negative coordinates. **Orange** outlines the desktop area that will be applied; **blue** outlines the current one. They overlap when origins match. Editor zoom does not change the desktop's tile size.
5. Note recognizable terrain inside the orange rectangle, then click **Use This Area**. The live desktop should now show that seed/area, and the blue rectangle should match orange. Minimize/move the editor window to inspect the real desktop. A running circuit's transient button pulse resets during the renderer/input rebuild; saved ON levers resume as usual.
6. If a seed would invalidate a component you placed on generated terrain, applying should refuse and show the invalid-tile count. The current desktop/circuit should remain intact. Choose another seed or Cancel Preview; components are never silently removed. This warning may not appear for the original circuits because their grass is protected by fixture overrides.
7. Confirm Finder automatically refreshes after applying and still maps real icons. Their world tile coordinates can change because the desktop camera moved. Circuits retain their global coordinates, so old rows may be outside your chosen view; they have not been deleted.
8. Wait for **Saved.**, quit and reopen. Confirm the seed field restores the chosen seed. Click **Show desktop area** to browse to the saved desktop origin, then enable Desktop World and confirm it shows the same terrain/location.
9. To return the desktop to its original location, click **Reset view**, then **Use This Area**. Reset view alone changes only browsing; applying sets desktop origin back to (0, 0). To restore the original surrounding terrain too, preview seed **2026** before applying. Your original circuits and right-hand construction area should be visible again.

The owner confirmed this earlier walkthrough on 2026-10-07; Slice 19’s MANUAL checkbox is complete. It described the single-world prototype. **Slice 19A below supersedes seed replacement:** existing worlds keep their seeds, and new seeds become independent empty worlds. Slice 19B replaces Use This Area with Save Area / Activate on Desktop.


## World library and migration walkthrough — Slice 19A

This revision builds and passes **194 automated tests**. The owner confirmed its three Mac acceptance checks on 2026-10-07 with “Yes it works!” This is a historical walkthrough; use Slice 19B below for the current controls. The initial application test host performed migration before test isolation was fixed; your original world.json remains intact, and the final build/test run left both owner save files unchanged. Your first normal launch should therefore report **Library restored**, rather than migrating again.

1. Quit the old app with **Command-Q** before opening this build. In Terminal run:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Confirm **Slice 19A · World library** in the footer. Desktop World should start disabled. **Saved worlds** should show your existing world with its chosen seed and **Desktop** badge. The seed is now fixed for that world. Click **Show desktop area** and check your saved circuit/repeater settings and original terrain patches. Enable the desktop and check it still shows your saved location and works with a harmless folder/empty output. Automatic Finder refresh should work as before. If you have a saved ON lever, enabling can activate its visible output once; turn it off if desired.
3. Disable Desktop World. Enter **42** in **New seed**, click **Preview**, set the new-world name to **Seed 42 tests**, then click **Create World**. The candidate and saved new world should have no original circuits or rectangular fixture patches. The selector should move to the new world while **Desktop:** still names your original world. New seed previews are separate candidates even when the seed matches the selected world's seed.
4. Place a few components on dry, undecorated terrain: choose Dust/Lever/Repeater and look for a **green** hover outline before clicking. Water, decorations and occupied tiles remain blocked. Pan to explore to the right if needed; Inspector shows hover coordinates. Configure a distinctive repeater direction/delay through Select if you place one. The new map has no guaranteed grass construction patch.
5. Create another world with seed **2026**, name it **Seed 2026 tests**, and place different components. Switch between these and your original through **Saved worlds**; each should show only its own build. A newly created 2026 world remains independent of your migrated 2026 world. Try **Rename** on the selected world; its components/seed should stay intact.
6. While a new world is selected, click **Enable Desktop World**. The real desktop should still run your original assigned world, not the editor's selected map. The world selector/edit controls should lock while running. **Use This Area** is unavailable for a new/inactive world. This is the deliberate Slice 19A limit; switching which world runs arrives in 19B.
7. Disable again, click **Show desktop area** to select the assigned world, and optionally pan then **Use This Area** to move its camera within its fixed seed. Seed entry/Preview no longer replaces that world's terrain. To return the assigned camera to origin zero, cancel any preview, **Show desktop area → Reset view → Use This Area**; do this only if you want to change your saved location.
8. Wait for **Saved.**, then quit/reopen. Desktop World should start disabled, your original assigned world/camera should be selected, and every newly created world, renamed label, component and repeater setting should still be available through Saved worlds. You can also make a small edit and quit immediately to verify quit-time flushing.

Owner-confirmed: the existing build/camera survived, worlds 42 and 2026 retained independent edits after restart, and selecting a world did not activate it. The corresponding SPEC.md manual checkboxes are complete.

### Save location and recovery for Slice 19A

The live save is now:

```text
~/Library/Application Support/RedstoneDesktop/library.json
```

The previous `world.json` stays untouched as a legacy backup. A present library takes precedence; the app does not import the backup again or fall back when the library is damaged. Normal edits save the entire library atomically after 0.75 seconds; **Save Now** retries failed writes. If saving fails, changes remain in memory, so resolve/retry before quitting if you want to keep those edits.

If loading fails, the footer explains the error and saving is disabled to preserve your files. Quit and use Finder **Go → Go to Folder…** to open the directory above. Copy the whole directory somewhere safe before attempting recovery. Moving a damaged library.json aside allows the preserved world.json to be imported again on the next launch, restoring only that older backup; newer worlds/edits remain in the moved library for repair. If no library exists and the error concerns world.json, preserve/move that legacy file instead. Do not delete either file to perform acceptance tests; corruption and migration failure have automated coverage.


## Named areas and desktop switching walkthrough — Slice 19B

This historical revision built and passed **205 automated tests**. Slice 19C rearranges its controls; use the current walkthrough below. The following four acceptance groups need your Mac report; automated fake Finder/display tests do not establish real desktop behavior. No new demo circuits were added.

1. **Launch the new build.** Quit the old app with **Command-Q**. In Terminal run:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

   Confirm **Slice 19B · Named areas** in the footer and Desktop World disabled. Saved areas should contain your migrated Desktop bookmark and each new world's Home bookmark. The menu groups areas by world and shows seeds; **Active** identifies the assigned desktop bookmark.
2. **Save and browse areas.** Select your original world's Desktop area. Give **New area name** a label such as **Original circuits**, then click **Save Area**. This selects the new bookmark without activating it. Pan a little to the right using Pan/drag left, name another view **Right workshop**, then Save Area again. Select either through Saved areas; the view returns to its saved origin, keeping your editor zoom. Components remain at the same coordinates, so overlapping views show the same build. Select a seed-42/2026 world, save **Experiments**, and confirm it shows that world's separate components. Try **Rename Area** and **Rename World**; names change without moving builds. Do not use a preview until you click Create World or Cancel Preview.
3. **Browse/edit while live.** Use Show desktop area, then Enable Desktop World. Select Experiments in another world. Place/erase a component or configure a repeater on dry, undecorated terrain, and save another bookmark. The actual desktop should continue showing/running its previous world and camera. The blue active outline should be absent in the inactive map, whose output occupancy is unavailable; orange still shows its proposed view. Select an area in the running active world: component tools and inspector edits should be locked, while Select/Pan/Zoom/Save Area remain available. Disable Desktop World to edit that world.
4. **Activate the saved target.** Select Experiments, pan away from its bookmarked origin, and read the **Target:** label. Click Activate on Desktop: it should use the saved origin shown there, rather than the new pan. Save Area first if you want the panned view instead. Switching while enabled keeps the new world running; switching while disabled prepares it without enabling. Choose Show desktop area to return to the active bookmark. Save Now, quit and reopen: the active world/area/camera and all bookmarks/builds should restore, with Desktop World disabled. A failure shows a status message; preflight/save failure preserves the previous live desktop. If rendering fails after a successful commit, the target stays saved but the desktop is disabled. Resolve the display/save issue, then retry.
5. **Check visible actions and cancellation.** Select your original world bookmark containing the demo circuit, activate it and enable. With an empty OUTPUT, press PRESS: the wire should light and nothing should open. Put only a harmless folder on the visible OUTPUT and move other Finder items away from PRESS; press again and check that folder opens once. Trigger a pulse and immediately activate an area in another world before the output fires: the previous pulse should stop and must not open a target after switching. Also try a bookmark in the original world with OUTPUT outside the visible desktop: its circuit still simulates, but no file should open from the hidden output. You may see a launch that already happened before a switch; it cannot be undone. Saved ON levers resume on enable/different-view activation and can create a new visible output activation; turn them off if you want quiet switching. Re-activating the same world/camera, including a duplicate bookmark, should not restart a held lever circuit or reopen its output.

Please report whether bookmark/build sharing, inactive editing/live isolation, saved-target activation/restart, and visible-output/cancellation behavior pass. Finder ghosts inside the editor remain Slice 20; current desktop markers continue as before. Save/recovery instructions above still apply to the complete library; failed activation never leaves a proposed active selection queued for a later Save Now.


## Clear library navigation walkthrough — Slice 19C

This revision builds and passes **213 automated tests**. Nine new cleanup tests cover deletion guards/failure/restoration, unchanged live runtime, camera-based previews and hosted editor/sheets. The obsolete developer-form hosting test was removed with that deleted window; placement/runtime tests remain. A native hosted UI capture was inspected for layout/previews; its bitmap capture omits the SpriteKit GPU canvas, so it is not proof of physical Mac rendering or clicks. App tests remain isolated from your real save files.

1. **Quit the old app with Command-Q**, then open this build from Terminal:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

   You should see Worlds on the left, your canvas in the center, Build/Inspector on the right, and the selected world's area previews below. The top labels **Editing:** and **Desktop:** should clearly distinguish browsing from the assigned desktop. Technical Details in the inspector identifies Slice 19C if needed.
2. **Browse existing builds.** Click a world in the sidebar, then one of its area previews below the canvas. Only areas belonging to that world should appear. Sidebar previews depict each world's first saved area; area cards depict their own saved cameras. These are small schematic previews, so tiny wires/decorations may be simplified. Selection should restore saved origins without copying builds or starting the desktop. Show Desktop Area returns to the assigned world/bookmark.
3. **Try the focused forms.** Click **+** beside Worlds: New World should appear in a sheet with name, seed, Preview and Random. Cancel a preview and confirm the normal canvas returns to your saved world. Create a disposable world named **Cleanup test**, seed 42 (it is intentionally independent even if you already have a 42 world). Place a component on valid terrain. Pan, then **Save Current View…** to name a second area; rename it by **right-clicking its card → Rename Area…**. Rename a world by **right-clicking its sidebar card → Rename World…**. Activation uses the selected saved camera shown below the cards; use Save Current View first to apply an unsaved pan.
4. **Check deletion using disposable records.** Select your extra Cleanup test bookmark and choose **right-click → Delete Bookmark…**. The dialog should explain that components remain on the map. Cancel once, then reopen and Delete; browse Home or pan back and verify your component remains. Attempting to delete Home as that world's final area should be disabled. Select the disposable world and use **right-click → Delete World…**: the dialog should explain that its builds and all areas will be removed. Confirm only for this disposable world. The sidebar should return to the assigned desktop world without changing what runs. Active desktop world/area deletion is disabled even while stopped; choose and activate another area first to make the old one eligible. Quit/reopen and confirm the deleted disposable records stay gone and other builds remain.
5. **Run the existing circuit.** Activate your original circuit area, Start Desktop, then minimize/move the editor to inspect it. Empty output should power without opening anything; a harmless folder on a visible output should open as before. Browse/edit an inactive world while it runs and confirm the desktop stays unchanged. Switch areas before a pending pulse reaches its output and verify it is canceled, then quit/reopen to confirm the active area restores stopped. Saved ON levers can cause a new visible output activation on start/different-view switching; identical world/camera activation does not restart a held circuit.
6. **Check recovery controls.** Advanced → Finder Diagnostics should still show permission/items/polling/errors and allow a manual refresh. Advanced → Desktop Details should show the assigned world/area, event rejection metadata, camera/pointer and last action. The Developer Placement window should be absent. Performance counters are collapsed under Technical Details instead of filling the normal footer. Report any clipping, missing previews or confusion in the new layout.

The three original Slice 19C MANUAL checkboxes remain pending until your specific Mac report; the Update Current Area/context-menu follow-up is accepted. The more specific 19B runtime checks also remain pending; this cleanup does not infer they passed. Resource packs and advanced redstone remain later slices; Slice 21 now implements display-change handling.


### Slice 19C follow-up — Update Current Area and right-click menus

The owner approved the layout with “looks great” and requested these two refinements before proceeding. Final Debug build and all **220 tests** pass. Seven new tests cover in-place update identity/count/circuit preservation, stopped-active prepared camera/restart, live-active refusal versus another same-world bookmark, failed update/pending-save retry, invalid camera/scale/preview refusal, clicked-ID renaming without changing browsing, and unavailable-display/damaged-store preservation. The native hosted layout capture was inspected again; the owner accepted the follow-up on 2026-10-07.

Quit the old app with Command-Q and launch using the command above. Then:

1. Select an area and **Pan** to a different location. **Update Current Area** should become available. Click it: the same card/name remains, its preview and saved origin change, and no new bookmark appears. Leave and reselect the area to confirm the updated origin restores. Components should remain at their original world coordinates. Editor zoom remains independent of desktop tile scale.
2. If this is the assigned desktop area, stop the desktop first; its update button is disabled while running. Updating it while stopped prepares its saved view for the next Start Desktop/restart. Updating another bookmark is allowed while the desktop runs and must leave its live camera/circuit unchanged. Save Current View still creates a separate bookmark whenever you want one.
3. **Right-click a world or area card**, including one that is not selected. Rename/Delete should apply to that clicked card without selecting/panning/activating it first. Deletion retains confirmation and active/final-record protection. Use only disposable inactive records when testing Delete; removing an extra bookmark preserves the world's components.
4. Quit/reopen and verify updated cameras and renamed labels persist; the desktop should start stopped. Advanced diagnostics remain available.

The management dropdowns are gone. Update failure keeps the previous saved view and never queues an implicit retry. The two follow-up MANUAL checks in SPEC.md are marked accepted following “Great. Lets do the next slice.” This is the historical follow-up walkthrough; Finder projection validation follows below.


## Finder projection walkthrough — Slice 20

1. Quit the old Redstone Desktop with **⌘Q**, then launch the rebuilt app:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Leave Desktop stopped. Below the canvas, choose **View → Show Finder Items**. Allow Finder Automation if macOS asks. Named teal circles should appear at projected icon centers. If permission is denied, use **Advanced → Finder Diagnostics → Read Finder Items** to retry after allowing access in System Settings → Privacy & Security → Automation, then switch Show Finder Items off/on. Tracking shares the existing 2 Hz poller; no repeated manual read is needed.
3. Move a harmless folder on your **real Finder desktop**, then return to the editor. Its marker should update within about half a second. If necessary move the editor window aside to reach the icon. Markers represent this world's **proposed view**; they are scaled for editor zoom, rather than matching physical desktop pixels. The caption says projection and the inspector says Projected Finder. A red circle means multiple centers share a tile; Outputs use EMPTY/ITEM/MANY/N/A badges.
4. Choose **Output**, then hover near a circle. The placement outline should snap to the tile containing its center even just across a tile edge (within 24 editor points). Click a green target: Output should appear on that tile, and nothing should open. Red targets remain blocked by terrain, decoration or an existing component. Move the folder again: its circle moves, but your placed Output stays on its original world tile. Use Erase if this was only a test.
5. Browse another world or pan to an unsaved view. The named projection should follow the selected world/proposed origin; the **Desktop:** assignment and running circuit must stay unchanged. Seed previews hide markers. Start/Stop Desktop should leave opted-in editor markers tracking; hiding them with View stops editor-only polling. Closing/reopening the app resets Show Finder Items to off. To try the real output, save/update the proposed view, explicitly activate that saved area, then Start Desktop and trigger its circuit normally.

Please report whether icon movement/alignment and snapping work on your Mac, including that browsing and placing Outputs leave the desktop assignment and Finder files alone. The owner subsequently accepted these checks on 2026-10-07 with “All looking good. Continue”. Slice 21 now handles live display reconfiguration; use the combined walkthrough below.


## Combined Mac validation — Slices 20 and 21

The owner authorized Slice 21 while away, then accepted the combined walkthrough with “All looking good. Continue” on 2026-10-07. Its five MANUAL checks are recorded as owner-reported acceptance. Final Debug build and **244 tests pass** (12 added display checks). The tests use fake displays, Finder providers, input and file openers; real display switching/Finder alignment still needs the following check.

1. **Launch the latest app.** Quit the old app with **⌘Q**. Open Terminal and run:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

   Desktop should start stopped and **Show Finder Items** should be off. Your existing worlds/areas/builds should remain. No Finder query is initiated until you explicitly start Desktop, enable editor tracking or request a diagnostic read.
2. **Track a real icon (Slice 20).** Leave Desktop stopped. Below the editor canvas, choose **View → Show Finder Items**. Allow Finder Automation if asked. Move a harmless folder on the **real Finder desktop**, moving the editor aside if needed. Its named teal marker should update automatically. The editor is scaled and may show another world/proposed camera, so the marker is a world projection rather than physical pixel-for-pixel placement. Red markers mean several icon centers share a tile.
3. **Check snapping (Slice 20).** Select **Output** and hover near a marker: the highlighted tile should be the tile under its center, even if the pointer is just across an edge (within 24 editor points). Click only a green outline; it should place an Output and open nothing. Red targets remain blocked by terrain/decoration/components. Move the folder: its marker moves but the placed Output stays. Erase the test Output if you do not want it saved. Browse another world or pan and confirm **Desktop:** assignment/circuit stays unchanged. Seed preview should hide markers.
4. **Prepare the actual desktop (Slice 21).** Choose **Show Desktop Area**, then **Start Desktop**. Use a harmless folder and keep it away from buttons/levers while checking input. Move/minimize the editor to see the desktop renderer: it should remain behind Finder icons and let Finder receive normal clicks/drags. Existing circuits should still work. An already-held powered output must not reopen merely because display geometry is rebuilt.
5. **Change scale/resolution (Slice 21).** Keep the app running. Open **System Settings → Displays**, note your current setting, then choose another scaling/resolution option. Wait about a second after it settles. The world should fill the primary display without a leftover old-size window, remain beneath icons and accept pointer/click mapping at the new positions. Finder markers/output occupancy should use the icons' current centers; refresh is automatic. Restore your original setting and repeat the alignment check. Finder may rearrange icons: an icon can land on a different tile. The saved world origin/tile size stays fixed while the visible extent changes.
6. **Unplug/replug if you have an external display (Slice 21).** Disconnect and reconnect it with the app running. The app should remain responsive and rebuild on the currently reported primary display. If you change which display is primary, the one desktop world should follow that primary; moving only the editor should not move it. If macOS temporarily exposes no usable display, Desktop stops and stays stopped when one returns; explicitly choose **Start Desktop**. This slice still renders only one display. If you have no external display, report this check as unavailable rather than passed.
7. **Check stopped-editor refresh/recovery.** Stop Desktop but leave **Show Finder Items** on; change scaling once more and verify editor markers return after settling. Turn Show Finder Items off to stop editor-only polling. If Automation is denied, **Advanced → Finder Diagnostics → Read Finder Items** can retry after System Settings → Privacy & Security → Automation allows access; toggle Show Finder Items off/on to resume. A denied permission should remain visible and not prompt repeatedly on display changes. Finally quit/reopen: stored areas/components remain, while Desktop and editor tracking start off.

Please report separately whether **Slice 20 icon movement/snapping** and **Slice 21 scaling/alignment/unplug-replug** pass. Both sets of MANUAL checkboxes are now recorded as owner-accepted from that report. The lower-left anchor and public notification policy are documented in SPEC.md Section 5.4. Finder icon-size synchronization, continuous multi-monitor maps and resource packs remain later work.


## Finder icon-size walkthrough — Slice 22

Debug build and **256 automated tests pass**. This slice reads the optional public Finder icon-size setting and rechecks centers after size changes. It preserves your world tile scale, saved camera, component coordinates and running circuit state. Diagnostics keep the first known stable size as a **session baseline** only; this does not change saved world/library data or enable synchronized zoom.

1. **Launch the new build.** Quit the old app with **⌘Q**, then run in Terminal:

   ```sh
   open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. **Enable tracking and check the setting.** Leave Desktop stopped and choose **View → Show Finder Items** below the editor canvas. Open **Advanced → Finder Diagnostics**. It should show **Finder icon size**, **Session baseline** and **independent world scale**. The baseline stays at the first reported stable size for this app session. If optional metadata is unavailable, the diagnostic says so and center-position polling still works; report that exact state.
3. **Resize the real desktop icons.** Note your current size so you can restore it. Right-click/Control-click a blank spot on your **real Finder desktop → Show View Options**, then drag **Icon size** to another value ([Apple's instructions](https://support.apple.com/guide/mac-help/mchlp2209/mac)). This must be the desktop's options, not a regular Finder folder's options. Wait roughly a second after releasing the slider. The diagnostic size should update, while its baseline and the world's tile scale stay unchanged. Tracking may briefly show settling/unavailable; it should recover automatically without pressing Read Finder Items. If you drag repeatedly, updates should settle on the final layout.
4. **Check centers after resizing.** Named editor markers should follow the icons' latest centers. Choose **Show Desktop Area → Start Desktop**, then move/minimize the editor to compare the real desktop's pink center crosshairs with a harmless folder. Resize smaller/larger again and verify alignment and normal Finder selection/dragging. Finder may move icons to different tiles; the app must follow those positions rather than keep their old targets. Already-placed circuit components stay at their world coordinates.
5. **Check the output target.** Wait for settling to finish, then place a harmless folder on a visible existing Output and trigger its button/lever normally. That current folder should open once. Move it off the Output and trigger again: nothing should open. Put a different harmless folder there and trigger a fresh pulse: the new folder should open. A click/output activation caught during detected resizing is intentionally skipped; wait and trigger again afterward. Holding an already-powered Output must not reopen it just because the icon size changes.
6. **Restore your original Finder icon size.** Confirm automatic alignment/occupancy recovers. Stop Desktop, leaving Show Finder Items on, and repeat a small resize once to verify the editor-only tracker also refreshes. Restore the setting again. Quit/reopen should retain builds/cameras and start integration off; the session baseline is captured anew after the next explicit successful tracking/read.

Please report whether the **size value updates**, **centers stay aligned**, and **the Output opens the current occupant after resizing**. All three Slice 22 MANUAL checks remain pending until your report. This slice does not adjust world zoom to icon size; that optional mode is Slice 23. It does not read undocumented Finder preference files, change Finder's settings, infer grid spacing or request extra permissions beyond existing Finder Automation.


## Optional synchronized scale — Slice 23

1. Quit the old app with **⌘Q**, then open the rebuilt app (command below). Start Desktop, wait for Finder to connect, and open **Advanced → Desktop Details**.
2. **Synchronize desktop scale to Finder icon size** starts off. Enable it to capture the current icon size as baseline. In Finder, click blank desktop and press **⌘J** for View Options. Change icon size: the desktop world should zoom while its center stays anchored. Scale is limited to 16–128 points/tile. The editor zoom/bookmarks do not change.
3. Finder may rearrange icons. Check the pink center markers follow their actual new positions and occupancy changes accordingly. Old activations are skipped; click the input again after settling. Only use a harmless folder/file on Output.
4. Switch synchronization off. The exact saved area's camera returns. Change icon size again: world scale should stay fixed. Leave this experiment off if you dislike it. To reset its baseline, turn it off/on.
5. The choice/baseline persist after quitting, but Desktop still starts stopped. Saved areas/circuits are unchanged. Report whether zoom, occupancy and independent mode pass.

```sh
open /Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug/RedstoneDesktop.app
```


## Sound effects — Slice 24

1. In **Advanced → Desktop Details → Sound effects**, keep volume low initially (default 35%). **Preview original sounds** lets you hear each named effect without running a circuit. Raise/lower Master volume; try **Mute** and **Enable sound effects**. Both must silence previews and circuit/editor events; unmuting must not replay queued sounds.
2. Stop Desktop, then place a component on valid ground, try placing another on that occupied tile, and erase the first. You should hear placement, refusal and removal respectively. Hovering and erasing empty ground should be silent.
3. Start Desktop and trigger an existing button: hear press, a brief Output activation and release after its pulse. Toggle a lever on/off for distinct effects. A repeater should tick on both powered/unpowered transitions, not continuously while held. An empty Output can still produce its activation sound.
4. Trigger nearby circuits quickly; short effects should overlap acceptably without long queued playback. Try mute while sounds occur. Stop Desktop: ongoing effects clear. Quit/reopen: settings persist, Desktop remains stopped and no startup circuit sounds play.

Report overlap/volume comfort and whether mute silences all effects. These checks remain pending.


## Stereo direction — Slice 25

1. Use stereo speakers/headphones, with system Mono Audio off if enabled. In **Advanced → Desktop Details → Sound effects → Stereo check**, press **Left**, **Center**, **Right**. The same sound should move between channels; mute/volume still apply. If your output is mono, direction cannot be assessed on it.
2. Stop Desktop. Place/erase components near the editor canvas's left/right edges on valid ground. The effects should follow the positions **within that canvas**, including after pan/zoom. Selecting a component, panning it offscreen and using **Erase selected component** should remove it silently.
3. Start Desktop and try visible buttons/levers toward its left/right sides. The input, release, repeater and Output effects should come from their own tile positions. Optional sync-to-Finder scale is not required; if enabled, sounds should follow the new positions after zoom. Offscreen circuit events are silent and must not replay when they come back into view.
4. Report whether direction feels sensible. No new demo circuits were inserted above your builds; add any test circuits to the right of existing ones.


## Finder scale follow-up — 2026-10-08

The original size query used a class reference that Finder rejected while ordinary item tracking continued. It now resolves `window of desktop` explicitly; a live read-only query returned icon size 64. No Finder setting was changed. Connected item tracking and available icon-size metadata are now distinguished in feedback, and ordinary background polling does not prevent opting in from a completed stable read.

Quit with ⌘Q, reopen the rebuilt app, Start Desktop, then check Advanced → Finder Diagnostics reports a numeric icon size. Enable synchronization in Desktop Details; change Finder's real desktop icon size in Show View Options and verify world zoom/center alignment and fresh Output targeting. Turn synchronization off to restore the saved camera. Leave it off if a stable circuit layout is preferable. Slices 24/25 are owner-accepted; corrected Slice 22/23 behavior remains pending.

Owner follow-up (2026-10-08): corrected Finder icon-size/marker and optional synchronization retest passed. The explicit real Output-after-resize check remains pending. Slices 26/27 are now implemented below; their manual validation remains pending.


## Resource packs — Slice 26

Advanced → **Appearance & Packs** lets you choose a pack folder/ZIP, reload it, inspect diagnostics or restore built-in assets. The complete format and contributor guide is [docs/RESOURCE_PACKS.md](docs/RESOURCE_PACKS.md).

Mac check: quit/reopen the new build, choose `examples/GrassOnly` or `examples/GrassOnly.zip` from this repository. Grass should become a purple/teal checker; stone/sand/water/circuits/sounds should retain built-in fallback. Both forms should match. Try Reload and Use Built-In; a running held circuit and world/camera should be preserved, without reopening Output from an appearance change. Quit/reopen should revalidate your choice with Desktop stopped. Both Slice 26 manual checks remain pending.


## Local Java textures — Slice 27; combined Mac walkthrough

No pack download is needed: this Mac already has installed Java versions. Read-only discovery found 29; a temporary import of **1.21.8** produced all 23 supported textures without warnings and left the source JAR unchanged. Your normal app selection has not been changed by that test.

1. Quit the running app with **⌘Q**. From this repository in Terminal, open the rebuilt app:

   ```sh
   open build/Build/Products/Debug/RedstoneDesktop.app
   ```

2. Open **Advanced → Appearance & Packs → Choose Pack Folder or ZIP…**. Choose `examples/GrassOnly`. Grass should become purple/teal checker art; other textures and sounds should keep original fallback. Repeat with `examples/GrassOnly.zip`; both forms should match. Try **Reload**, then **Use Built-In** to restore the original appearance. This checks Slice 26 without third-party assets.
3. Under **Local Minecraft Java textures**, choose **1.21.8** from **Installed version**, then **Import Selected**. Opening the window discovers versions; **Find Installed Versions** refreshes. Expected: **Imported 26 Java textures**, with no mapping warnings. If the list is empty, use **Choose Java JAR / Pack…**, press **⌘⇧G** and paste `~/Library/Application Support/minecraft/versions/1.21.8/`, then select `1.21.8.jar`.
4. Browse a generated world: grass/dirt/stone/sand, water and tree/flower/reed decorations should change where present. Water is a still first frame with fixed tint. Wire materials, button/lever/repeater art, coal/iron deposits and five flower varieties now change. Outputs use command-block art; all sounds remain original. Powered wire is bright red with strength-based dimming. Shelf thumbnails stay schematic. Start Desktop to inspect its assigned area. Change packs while a lever is held on: circuit state, world and camera should persist, with no new Output activation caused solely by the appearance change.
5. **Reveal Import Cache** should show a UUID folder under `~/Library/Application Support/RedstoneDesktop/ImportedTextures/`, containing semantic PNGs, `pack.json` and `import.json`. **Reload** rereads that cache; **Re-import** rebuilds it from the original JAR. The JAR should remain in its original Minecraft directory. Run `git status --short` from this repository: importing must not add copied game assets to the working tree.
6. With Java textures selected, quit/reopen: the cached appearance should restore, while Desktop starts stopped. Try **Use Built-In**: original art returns, and cache reveal/re-import remain available. Re-import, then **Remove Imported Assets**: built-in art returns and only the app-owned copy disappears; the original Java JAR remains. You can import it again later.

These steps cover both new slices; manual checkboxes remain pending until you report the results. Selection is global to appearance, independent of world/area selection. One pack is active at a time; missing IDs always resolve to original assets. See the guides for every supported ID, format/size limits, mapping/tint behavior, reload/removal semantics, source rights and contributor tests.


## Appearance follow-up — Slice 27A

Quit with **⌘Q**, reopen `build/Build/Products/Debug/RedstoneDesktop.app`, then open **Advanced → Appearance & Packs → Re-import**. This regenerates the old 11-mapping cache into the current **26-mapping** pack, including updated red wire art. **Reload** cannot update old imported images because it only reads that cache. If no prior import is available, select installed **1.21.8 → Import Selected**.

Inspect generated stone regions for coal/iron deposits and sand regions for cacti instead of loose rocks and grass/woodland regions for five flower varieties. These are selected from the world seed/coordinate, so revisit after panning/zooming/reopening: each location should keep its variety. Ore deposits still block placement; no mining or terrain-editing feature is added. Saved terrain/circuits/cameras are preserved.

Start Desktop and press a button/toggle a lever: dust should be thin, connected, dark red when off and bright red when powered. Java stone buttons depress, lever handles lean to opposite sides, and repeater top art rotates with direction while its label retains delay. Icons are larger with transparent backing. Editor browsing of an inactive world shows saved ON lever art as well as its label; it still does not simulate. Check a bend/junction and each repeater direction on an existing circuit or a disposable inactive world.

Try **Use Built-In** to confirm original ore/flower variety and red circuit appearance work without Java art. Switching appearance must leave world/camera/circuit and Finder action behavior intact, without a new Output activation caused solely by switching. These new visual checks await your confirmation. The documentation covers 27 semantic texture IDs, old-pack family fallback and the fixed Java 2D recipes; no downloaded/bundled game assets are needed.

## Desktop Build Mode — Slice 28 Mac walkthrough

1. Quit the previous app with **⌘Q** and reopen `build/Build/Products/Debug/RedstoneDesktop.app`. In Finder, **⌘⇧G** opens Go to Folder; paste `/Users/peterzielinski/git/redstone-desktop/build/Build/Products/Debug`, then double-click the app. Or run it from Xcode with **⌘R** after stopping its previous run.
2. Check the **Desktop:** name at the top. **Build on Desktop** edits that assigned world/area, even when the editor is browsing another world. Click it: the hotbar should clearly say **BUILD MODE**, name the assigned area and say **Circuit stopped**. The large editor should hide automatically; the hotbar remains visible. Look for a strong orange pulse around the screen edges. Finder icons should remain visible. Do not hide the whole app, since that deliberately exits Build Mode.
3. Choose **Dust**, **Button**, **Lever**, **Repeater** or **Output** in the hotbar and left-click an empty solid tile to place one. Use a disposable patch to the right of your existing circuits. Water, decorations and occupied tiles must reject placement and explain why in the hotbar. Clicking a placed button/lever while editing must not run the circuit or open a file. Right-click a placed component, or select **Erase** and left-click it, to remove only the component; terrain and Finder files stay intact.
4. Choose **Repeater** and place one. Move the pointer over it (no click needed), then press **R** to rotate it or **T** to cycle delay **1 → 2 → 3 → 4 → 1**. Its arrow/delay label and hotbar settings should update. Try two repeaters: the hovered one must change even when a different one was selected. Moving over empty terrain or a button/lever must not edit the old selection. Try again after clicking a hotbar control; moving back over the desktop restores canvas focus automatically. **D** remains a delay shortcut alias. The hotbar's **Rotate Selected** and **Delay** controls still edit the last selected repeater, or prepare the next placement when no repeater is selected. Number keys **1–6**, scrolling and **Escape** still work. Keyboard shortcuts are optional; hotbar controls work by mouse.
5. Repeat entering/exiting using **Exit Build Mode**, the hotbar's red close button, and the **hammer icon in the macOS menu bar → Exit Build Mode**. The app's **Window** menu also offers Exit. Try **⌘Tab** to Finder and **⌘H** while editing; both should automatically exit. After every exit, the border should disappear and the same editor window/view should return. Select/drag a Finder desktop icon and open a harmless folder normally. Switching to Finder must not pull keyboard focus back into the editor. Capture must never remain stuck. The menu-bar icon's **Open Editor** exits Build Mode and restores editor access. Windows already hidden/minimized before entry keep their previous state; unrelated settings/diagnostics windows are not hidden. If you already have another monitor, a display change during editing should also exit safely; no display change is required just to test editing.
6. Exit leaves the desktop **stopped**, so edits cannot trigger an Output automatically. Use the menu-bar icon → **Open Editor**, then **Start Desktop** to run the assigned circuit. The normal world must be fully click-through again: Finder selection/drag/open work, and existing button/lever circuits work as before. Stop, reopen the app and check your placed components, repeater settings and original world/area assignment survived. Browsing another world must not copy or move the edits.

Build Mode fixes its camera for one editing session, even if optional Finder scale synchronization receives new metadata. The next Start uses the latest prepared scale. It does not edit terrain, pan/zoom, paint while dragging or snap Outputs to Finder icons; those are outside this slice. No new Accessibility or keyboard permission is needed. For the border accessibility check, use **System Settings → Accessibility → Display → Reduce motion**: the pulse should become a steady strong border, and switching it off should resume the pulse. Quit during Build Mode should remove capture without flashing the editor back onscreen. The original two and three follow-up Slice 28 MANUAL checkboxes stay pending until you report actual Finder/input behavior; automated window configuration tests cannot prove physical WindowServer routing.


## Visual/navigation polish — Slice 28A Mac walkthrough

1. Quit the old app with **⌘Q**, then reopen `build/Build/Products/Debug/RedstoneDesktop.app` (or stop/run in Xcode with **⌘R**). Open **Advanced → Appearance & Packs → Re-import**. Expected: **26 Java textures** with local **1.21.8**. Reload alone reads your older cache, so it cannot add cactus/Output mappings. If no previous import is available, select **1.21.8 → Import Selected**.
2. Explore a generated grassy region: generated dirt patches now look like grass, using Java grass-block-top art. Sand decoration slots should show cacti, including sandy shores; coal/iron remain on other terrain. Outputs should show command-block art and their existing EMPTY/ITEM/MANY/N/A badges. Check **Use Built-In** too: original grass, cactus and terminal-block Output defaults must work. Re-import again to restore Java art. Saved terrain overrides, circuits and actions should stay intact.
3. Stop Desktop, then use **Build on Desktop** on a disposable patch to the **right** of existing circuits. The orange screen border should be much stronger. Place two or three adjacent repeaters pointing along the same path: larger plates should have visible redstone connections between them. Rotate one away to check incompatible ports disappear; dust beside a repeater's side must not connect there. Hover **R/T**, editor hiding/restoration and exits must still work. With **System Settings → Accessibility → Display → Reduce motion**, the border should be steady; every exit removes it.
4. Run a lever → long dust path → repeater → dust → Output circuit on the assigned desktop area. Dust should be thinner, bright red near power 15 and progressively dimmer farther along. A repeater restores outgoing power to 15 after its delay. Toggle off: dust returns dark red. Browse that active circuit in the editor while running to see the same strengths. A harmless folder over Output should still open as before; changing only appearance must not trigger it.
5. In the editor choose **Navigate**: click a component to inspect it, then drag to pan without editing/selecting. Pinch your trackpad to zoom, then try scrolling and the viewport **+ / −** buttons. Pinch/scroll should stay anchored under the pointer. The tools no longer have separate Select/Pan modes; component tools still place on a click.
6. Use the controls floating in the canvas's upper-right. **Home** (house) shows the **assigned desktop area**, switching the browsed world if needed. **View** (eye) → **Return to saved view** restores the **currently selected area's bookmark**, useful after panning around another area. They coincide when you're already browsing the active area, but differ when another area is selected. Neither activates an area or overwrites its saved view. View also contains **Show Finder Items** and **Reset to Origin**; Update Current Area/Activate remain explicit.

These four new MANUAL acceptance groups remain pending until you confirm them. The previous detailed Finder/exit/Reduce Motion checks are still pending where not explicitly reported. This is the requested polishing slice; **Slice 29 (script execution) has not been started**. See [resource packs](docs/RESOURCE_PACKS.md) for all 27 semantic IDs and [Java importing](docs/JAVA_TEXTURE_IMPORT.md) for all 26 mappings, cache lifecycle and sharing limits.


## Output presentation and editor stalls — Slice 28B Mac walkthrough

Quit the previous app with **⌘Q** and reopen `build/Build/Products/Debug/RedstoneDesktop.app`, or stop/run in Xcode with **⌘R**. Existing Java caches already have the command-block textures from 28A, so no new Re-import is needed if your last import reported 26 textures.

1. **Output appearance:** inspect an Output with Desktop started so Finder data is available. Command-block art should cover the full tile, with no OUTPUT/badge text or purple backing. Empty should glow gently red. Drag one harmless folder over its center: glow becomes green. Drag away: red returns. Ordinary Finder items elsewhere should no longer have green tile boxes. Several items on an Output should show amber and still refuse ambiguous opening; unreadable/not-yet-read occupancy is neutral gray, not falsely empty.
2. **Run regression:** press an existing input with the folder over Output. It should open once as before; the separate activation flash remains. Appearance and occupancy refreshes alone must not open it again. Inspector/Advanced diagnostics still provide occupancy details. Editor Output glow uses the optional projected Finder snapshot; enable **View → Show Finder Items** when you want it to reflect those icons.
3. **Pan/zoom:** with Java art active, use Navigate and drag across several chunk boundaries, then pinch/scroll in and out. The measured chunk-creation pauses were reduced from about 650 ms to 8 ms in the local Debug-like harness; check the actual interactive result on your Mac. Test both with Desktop stopped and with Desktop running/Show Finder Items enabled. Browse another world and return: desktop assignment and saved view must stay intact. Under Inspector → Technical Details, retained chunks/nodes should stay bounded while cumulative generation counts can increase.
4. **Pack replacement:** switch to Use Built-In, pan, then Re-import to restore Java art. Terrain should immediately use the selected appearance with no stale tiles. Existing circuit positions and saves should be unchanged.

These two new MANUAL groups await confirmation. If stalls remain, report whether they happen only while exploring new terrain or also over cached terrain/with Finder tracking enabled; the measured terrain-painting issue is fixed, but unrelated main-thread work is not assumed fixed.

**Later circuits:** torches were already planned in Slice 30; SPEC now explicitly includes placement, visuals, persistence and feedback tests. New **Slice 30A** plans `source → Output A → repeater → Output B`, with rear pickup, restored power and existing action protections. That logic is not active in this build: Outputs remain terminal sinks until its dedicated slice. Slice 29 remains next.

For contributors, `./scripts/pan-profile.sh` reproduces the unoptimized native pan path using the repository's original synthetic Java fixture. Optionally pass a readable local JAR/pack path as its first argument. It creates/removes a temporary import cache and uses an isolated in-memory library; it never starts desktop input/Finder polling, opens files or changes owner preferences/saves. Output reports initial and per-step milliseconds plus cumulative texture counts. Numbers depend on machine/load/source art; automated tests enforce finite provider work and cache correctness rather than fragile timing thresholds.


## Half-second Finder polling hitch — Slice 28C Mac walkthrough

The 2 Hz Finder poll was running a synchronous NSAppleScript call on the same main thread as pointer tracking and rendering. One live read took about 298 ms. The new runner uses macOS's public `osascript` tool asynchronously for the same fixed read-only AppleScript query, then decodes/looks up metadata off the UI thread. Finder reads still take time, but the app can keep processing pointer/rendering work while awaiting them. Polling remains serialized at 0.5-second intervals.

1. Quit the old app with **⌘Q**, then reopen `build/Build/Products/Debug/RedstoneDesktop.app`, or stop/run in Xcode with **⌘R**. No texture Re-import or save migration is needed.
2. Click **Start Desktop**. Move the pointer continuously over empty desktop for 15–20 seconds: the tile highlight should follow smoothly through the previous half-second pause. Check with Java and Built-In art if convenient. Open **Advanced → Finder Diagnostics**: reads should still succeed, item positions update and icon size stay available. Move a harmless desktop folder and confirm its marker/occupancy follows.
3. In the editor use Navigate and pan/pinch/scroll over both cached and newly explored terrain. Test while Desktop is running, then stopped with **View → Show Finder Items** enabled. Turning tracking off with Desktop stopped provides a comparison; the periodic difference should be gone.
4. With a harmless folder over an existing Output, press its circuit input: the current occupant should open once. Move it away: no target. Ambiguous targets must still be refused. A pending read/Stop/Start or quit/reopen must not publish an old target or replay an old activation. Desktop still starts stopped after reopening.
5. The app now invokes a system child tool for its fixed Finder query. If macOS presents Finder Automation consent, check the requesting app and allow it if you want tracking. If diagnostics instead report denial/failure, check **System Settings → Privacy & Security → Automation** and report the exact app/diagnostic message. Existing authorization may carry over, but the command-line comparison does not prove your launched app's permission attribution. Do not reset privacy settings or run shell workarounds just to bypass a failure.

Local native reads returned identical snapshots while 45–55 UI heartbeat updates ran during each pending query; all 338 tests pass. Your actual cursor/pan/Finder-permission checks remain MANUAL pending. Source files: `FinderScriptProcess.swift` owns asynchronous process/cancellation/pipe limits, `FinderScriptOutput.swift` strictly parses data, and `FinderScriptRunner.swift`/`FinderDesktopItemProvider.swift` preserve the adapter/snapshot contract. Resource packs and user filenames never provide executable source. If the hitch remains, report whether it also occurs with Desktop stopped and Show Finder Items off. Slice 29 remains next and untouched.


## Script execution Outputs — Slice 29

Implemented with Debug build/all **349 automated tests passing**. Existing/new Outputs keep **Open occupant** as their default. Stop the active desktop, use Navigate to select an Output, and choose **Output action → Execute script** in the Inspector. Supported local `.sh`/`.command` files run via sh, `.zsh` via zsh -f; no arbitrary interpreter or shell command string. First activation previews the resolved path and asks for approval. Always Allow is optional and tied to the exact file/contents; Desktop Details can forget approvals. Moving/changing the target during approval refuses execution. Results are in **Advanced → Desktop Details → Last script result**, including stdout/stderr, exit, duration and truncation. Execution is asynchronous and bounded; Stop/Quit cancels the child/prompt.

Read [docs/SCRIPT_OUTPUTS.md](docs/SCRIPT_OUTPUTS.md) for supported behavior, lifecycle limits, persistence and contributor guidance. The original MIT [hello.sh](examples/Scripts/hello.sh) fixture prints only a greeting and example stderr. Copy it to your Desktop for the walkthrough; no unfamiliar script is needed. Check first prompt/cancel/approval, repeater-before-prompt timing, held power, target movement, Stop while awaiting approval, optional remembering/revocation and mode save/reopen. Confirm ordinary folder opening still works after switching back to Open occupant. These new real-Mac checks remain MANUAL pending.

The owner accepted the remaining periodic responsiveness fix before this slice. Unreported detailed Finder Automation/ambiguity/restart checks remain pending. Pink desktop crosshairs are now absent; mapper-derived occupancy and opted-in editor rings/names/snapping remain. Slice 30 and powered-Output pickup remain future work.


## Execution settings and earlier Desktop access — Slice 29A

Open **Redstone Desktop → Settings… (⌘,)**, or **Advanced → Settings…**. Enable **Run supported scripts; open other items** to route Default Outputs automatically: regular `.sh`/`.command`/`.zsh` occupants go through script approval/execution; folders/documents/apps open normally. It is off by default and persists separately from worlds. Inspector labels show the current Default behavior; explicit Execute script and None retain their meaning. Settings changes do not activate held circuits.

Selecting Execute script or enabling this setting now checks Desktop-folder access immediately, before a circuit runs. macOS presents its Files & Folders permission only if needed; existing permission may mean no prompt. Settings offers status and **Check Desktop Access…** for retry. Startup never requests it automatically. This is separate from Finder Automation and the app's exact-script approval. **Always allow this exact file** now starts checked; click Run Script once to remember it, or uncheck to keep prompting. Settings → Forget Script Approvals revokes it.

Debug build/all **356 tests pass**. Follow the [new Mac walkthrough](docs/SCRIPT_OUTPUTS.md#slice-29a-settings-and-earlier-permission-walkthrough) to verify early access, automatic script/folder routing, checked remembering and restart. New MANUAL groups remain pending. First-launch wizard and confirmed, backed-up **Start Over → restart into setup** are documented future Slice 33 work, not current buttons. Start Over will reset app-owned data/preferences/approvals while preserving Desktop files/source packs and macOS privacy permissions. Slice 30 is still next.
