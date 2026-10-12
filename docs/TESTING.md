# Mac acceptance checklist

These are physical-Mac checks, separate from automated tests. Report which numbered groups you actually tried and what failed; untested groups remain unverified. Use harmless folders/text files first. Place new test circuits on clear ground **to the right** of your existing builds. Do not use scripts for display-calibration tests.


## Owner-provided logo — awaiting owner confirmation

- [ ] Quit the old app with ⌘Q and run the update with ⌘R in Xcode (or open the updated release). Check the new colored logo in Dock, Finder and ⌘Tab. macOS can cache old icons; quit/reopen the updated copy before judging a stale Dock image. No world reset is needed.
- [ ] Check the menu-bar silhouette in light and dark appearance. Its width should stay the same when stopped, running or in Build Mode.
- [ ] Check both build toolbars: Dust uses your logo silhouette; Button, Lever, Repeater, Output and R. Torch use native symbols. All tools should still place the same components. Optional locally imported Java world textures/audio should continue working.

Automated checks preserve the supplied PNG byte-for-byte, verify transparent-margin trimming/aspect and monochrome rendering, check native light/dark icon composition and menu resolution, resolve native tool symbols and reject retired game-derived catalogs in the source and compiled app. Release validation also inspects the compiled catalog inside the actual ZIP.

## Desktop Build palette sizing — awaiting owner confirmation

- [ ] Quit the old copy with ⌘Q, run the update with ⌘R in Xcode, then enter Build on Desktop. The palette should open compactly, with its header just below the title bar and no large blank area above the controls.
- [ ] Switch Dust → Terrain → Sensor → Dust and draw a dust path. The panel should fit the selected tool’s controls, keeping horizontal padding and readable descriptions, without jumping to a huge height. Exit and re-enter Build Mode to check its initial size again.

A native AppKit regression reproduces the oversized initial panel, then verifies the corrected panel fits its SwiftUI content through those tool/status changes.

## Dust dragging, brighter particles and Test Stop — awaiting owner confirmation

- [ ] Quit the old copy with ⌘Q and run the update with ⌘R in Xcode (or open the updated release). In Settings → Appearance, enable Show particles. Keep macOS Reduce Motion off while checking moving effects.
- [ ] Power a Dust path with a lever in Test Circuit. Red flecks should be clearly visible within a second, including weaker dust near the end. Try a short button pulse and a lit R. Torch. Turning power off stops particles. Check at night too: flecks should retain their brightness.
- [ ] Look at lava and a regular Torch for a few seconds. Pops, flames and smoke should be larger and more frequent. Test both original and your installed Java assets. Toggle Show particles off: all particles disappear while circuits, terrain animation and lighting continue.
- [ ] On clear ground to the right of existing builds, choose Dust and drag slowly, then quickly and diagonally. The preview should fill skipped tiles and connect diagonal steps with elbows. Release: it persists. Retrace a diagonal path: it should reuse the same elbows. Undo/redo should remove/restore the entire stroke in one step. Single clicks should still place one tile.
- [ ] Drag across an existing repeater and water: neither should be overwritten. The path skips blocked ground; you may need to route around obstacles to reconnect it. Press Escape during another drag, then release: none of that stroke should save.
- [ ] Repeat dust dragging in Desktop Build Mode, exit, and confirm the path appears in the editor and can be undone there. Changing tools during a stroke must not save it. Starting Desktop should run the saved circuit normally.
- [ ] Enter Test Circuit. **Stop** is on the left beside the playback controls and returns to editing. **Done Testing** still works on the right. Pause/Play, Step and Reset remain available. Stopping must not save test lever states or open desktop files.

Automated checks cover bounded/cardinal paths, retracing, obstacle protection, native editor and Desktop mouse dispatch, preview/release persistence, single undo/redo, cancellation and stale-session/world rejection, plus minimum particle visibility parameters. Final Mac appearance and toolbar placement still need the checks above.

## Visual preferences — awaiting owner confirmation

1. Quit the old copy with ⌘Q, then run the update with ⌘R in Xcode (or open the updated release). Open **Settings → Appearance → Animation & effects**. All three switches start enabled unless you have already changed them.
2. Find water/lava, some decorated grass and a regular torch; place any new examples to the right of existing circuits. Switch **Animate water and lava** off: liquid frames should become still, while particles and scenery shimmer can continue. Switch **Subtle scenery shimmer** off: tiny decoration glints should stop while liquids can continue. The shimmer is intentionally faint.
3. Switch **Show particles** off: torch flames/smoke, lava pops and powered redstone sparks should disappear immediately. Liquid animation, light from torches/lava and circuit operation should continue. Turn particles back on and allow a few seconds for the sparse particles to appear.
4. Repeat in the running Desktop and Desktop Build Mode. Change settings while each mode is open, and stop/start Desktop once: your choices should apply to new windows too. No circuit, area assignment or world lighting setting should change.
5. Leave a mix of switches on/off, quit and reopen, and confirm those choices persist. Switching texture packs must also preserve them.
6. With all three enabled, turn **System Settings → Accessibility → Display → Reduce Motion** on: all three effects should pause/hide. Turn it off: only effects enabled in the app should return. Restore your preferred Mac setting. A per-world day/night cycle should continue independently.

Automated coverage checks isolated preference persistence/defaults/corrupt-data recovery, independent liquid/scenery shader uniforms, particle hide/pause with retained nodes, unchanged terrain texture builds, editor/runtime propagation and new Desktop/Build session initialization. These do not replace the visual checks above.

## Fixed world time — awaiting owner confirmation

1. Quit with ⌘Q, then run the update with ⌘R in Xcode or open the updated release. World Settings → Lighting → Fixed Time. Choose Dawn or Dusk, adjust the slider to a nearby quarter-hour, and Save. Lighting should match that moment of the cycle and stay there for several minutes in both editor and Desktop.
2. Check lava and powered redstone still light nearby ground. Browse another area in the same world: it should share the fixed time. Other worlds should keep their own settings.
3. Quit/reopen and verify the chosen time persists. Try Cancel on a different time, then switch back to Day & Night and confirm time moves again. Existing Always Day and Always Night options should still work.

Owner reports the day/night cycle looks smooth; the additional per-world, persistence and local-light checks below remain open where not explicitly confirmed.

## Per-world day/night and local lights — awaiting owner confirmation

1. Quit with ⌘Q, then run the update with ⌘R in Xcode or open the updated release. Existing worlds should retain their daytime appearance and saved circuits. Click the gear beside Worlds, or right-click a world card → World Settings….
2. Choose Always Night and Save. Terrain and inactive circuits should dim; cursor, tools, selection and area labels should remain clear. Find or paint a small lava pool to the right of your builds: it should brighten nearby tiles with soft edges. Switch the local-lights toggle off and confirm the light disappears.
3. Re-enable local lights. In Test Circuit, power a wire/torch/repeater circuit and check nearby ground brightens; switching it off should remove that light. Repeat on running Desktop. Changing lighting while Desktop runs should keep the circuit and assignment running, with no extra file actions.
4. Choose Day & Night, set Full day to 2 minutes, and Start at noon (12 PM). Watch the scene dim and brighten through a full cycle. Pan across chunk boundaries and zoom during night; lights should remain anchored without seams or recurring stalls. Check an adjacent saved area in the same world shares the time.
5. Set another world to Always Day: it should stay bright while the first keeps its own settings. Quit/reopen and check settings persist and the cycle resumes the current time. Cancel a settings change and confirm it does not apply. Export/import should preserve lighting settings too.

## Softer water and clustered forests — awaiting owner confirmation

1. Quit with ⌘Q, then run the update using ⌘R in Xcode or open the updated release app. Revisit that river: shallow water should be a darker blue with a gentler contrast against the deep channel, still visibly different and crisp. Check both Original Look and your existing imported textures; no reimport is needed. Waves should still animate and reeds should retain their colors.
2. Explore woodland and snowy forest in an existing or new world. Tree spacing should vary, with close trunks, overlapping canopies, dense patches and clearings. The center wood block should remain visible through leaf holes even where trees touch. Check across chunk boundaries and pan for a minute in both editor and Desktop.
3. Confirm your saved circuits, levers, areas and painted ground remain and work. Older generation settings upgrade with an exact backup; only new generated obstacles beneath saved circuits are cleared. Paint/clear/restore a tree patch to the right of your builds, try Undo/Redo, then quit/reopen to confirm persistence.

## Wider deep river channels — awaiting owner confirmation

1. Quit the running copy (⌘Q), then run the updated app with ⌘R in Xcode or open the newly built app. Revisit the river from your screenshot: most of its width should be dark deep water, with a light shallow strip only one or two tiles thick beside each bank. No new world or texture refresh is required.
2. Follow some bends and river/lake junctions in the editor and on Desktop. Look for continuous water across chunk boundaries, reeds only on shallow tiles, and responsive panning. Very narrow streams can be entirely shallow; lakes keep their existing depth rules.
3. Confirm your existing circuits and painted terrain remain in place. The river's outer outline and dry banks should stay unchanged; explicitly painted shallow/deep water should retain its chosen type after reopening.

## Terrain sharpness follow-up — awaiting owner confirmation

1. Quit the previous app copy and open the update. Zoom in on grass, stone, sand, leaves and flowers with both Original Look and imported Java textures. Their pixels should be crisp rather than smoothly blurred; water/lava should keep animating.
2. Pan and zoom across chunk boundaries in the editor, then check Desktop at its normal scale. Look for stable pixel edges and no water/glint bleeding onto adjacent ground. Component icons and labels should retain their usual appearance. Reduce Motion should still freeze the ambience.

The new rendered-pixel test reproduced the shader blur despite nearest texture flags. It now verifies exact pixel-center sampling, unchanged crisp colors and preserved node alpha. Real appearance remains pending owner confirmation.

## Terrain saving and desktop assignment recovery — awaiting owner confirmation

1. Quit the current copy, then open the update (or run with ⌘R in Xcode). Your saved worlds, areas and circuits should reappear; no reset is required. Settings → Data should show saving available. The older library receives an exact-byte backup beside `library.json` before upgrading.
2. Stop Desktop, choose Terrain and paint a few tiles to the right of existing builds. Release: the terrain should stay. Undo/Redo should work; quit/reopen and confirm the saved edits remain.
3. Select another saved area and choose Activate on Desktop. The desktop target should change. Start Desktop and check the assigned view; choose another area using the menu bar and check running Desktop switches and resumes.
4. Confirm your existing repeater and wires still exist and work. Only obstructing scenery underneath saved components should be cleared; other scenery and your painted ground should remain.

Owner reported that the animations look good. Terrain saving and assignment failed because older saved builds conflicted with expanded terrain/fixture decorations; the upgrade and these checks address that issue. Other animation checks below remain pending where not explicitly confirmed.

## Water, lava and scenery animation — awaiting owner confirmation

1. Quit the old copy and open the updated app. With **Use Original Look**, find water (seed **42** starts near a lake), zoom in and watch for gentle waves. Start Desktop and check it animates there too. Trees, flowers and reeds should have a slight glint, while ground, ores, circuits and Finder items stay steady.
2. In Appearance & Packs, use **More options & custom packs → Refresh Imported Minecraft Assets**, or import your installed Java version again. Old imports had their strips discarded, so Reload alone will not animate them. Check water now uses the game's animation. Switch Original/Java a few times; colors and animation should switch together without stale frames or a checkerboard showing through the water.
3. Stop Desktop, choose **Terrain → Lava**, and paint a small pool **to the right** of existing circuits. Lava should animate, reject component placement, and preserve any existing components painted across. Undo/Redo and quit/reopen should preserve the edited pool correctly. Explore desert/stone/savanna further out to find occasional small natural pools; they are deliberately rare.
4. Enable **System Settings → Accessibility → Display → Reduce motion** while the app is open. Water, lava and scenery glints should freeze in both views; turning it off should resume them. Restore your preferred setting afterward.
5. Pan and zoom around both views for a minute, including across chunk boundaries with Java textures. Look for smooth interaction, stable scenery, no flashing seams, missing frames or regular pauses. Try building and testing a small circuit afterward: animation must not affect its signals or file behavior.

These Mac appearance/performance checks are pending. Automated checks include actual SpriteKit rendered pixels, frame metadata and looping, Reduce Motion freezing, cache/node stability, lava rarity/biome rules, placement, brush persistence and a real-JAR temporary-cache import. They do not replace owner acceptance.

## Tree canopy follow-up — awaiting owner confirmation

1. Quit the old copy and open the update. Explore snowy ground in seed **7**, then woodland in another area. Trees should be varied groups of five to ten leaf blocks, with a required cross, some corners filled, an occasional extra leaf making a tree wider or taller, and wood under the middle, rather than isolated leaf tiles. Check nearby trees have different corner shapes, which stay fixed after panning or reopening. Zoom in to see holes showing wood at the center and grass/snow on the outer blocks.
2. Check both original art and your current imported textures. Existing imports should use original log backing automatically. Import the Java version again for actual oak/spruce log tops. Opaque custom leaves can hide the log; that is expected from their alpha.
3. Try building on both the center and an outer leaf block: both should reject placement. Clear one leaf tile with Terrain: it should reveal its original ground and accept building without removing other leaves. A 3×3 Clear Decorations brush clears the core; use 5×5 centered on the trunk to clear extensions too; Undo/Redo should restore/remove it together.
4. Pan across several chunks and compare editor/Desktop: canopies should stay aligned and complete across chunk edges, with no leaves spilling into water. Check panning remains responsive. Tree positions have changed, while biome surfaces, rivers and saved painted ground remain the same.

## Improved default landscapes — awaiting owner confirmation

1. Quit the old copy and open the updated app. Create fresh worlds with seeds **2026**, **42** and optionally **7**. No new generation options should be required. Untouched terrain in older worlds can change; do not use those builds to judge the new generator. The app should not automatically delete worlds. Backup/reset testing remains deferred.
2. Pan and zoom out across a broad region. Look for larger distinct regions, winding inland rivers with banks, lakes, golden dry grass, snowy pine ground, meadows and clustered woodland. Seed 42's origin is near a lake; 2026's is desert; 7's is snowy. Explore beyond the starting view to find other regions. Check water and terrain join without visible chunk seams.
3. Select Terrain and try **Dry grass**, **Snow** and **Gravel**. Place a button/dust/repeater circuit on each clear surface, then Test Circuit. Clear a pine/shrub/mushroom or paint Grass over water to make room. Ore on stone should still allow building; untouched water/scenery should reject placement. Undo/Redo and Restore Original should work.
4. Save an area, quit/reopen, and check the same seed, new painted surfaces and circuit persist. Compare editor and desktop views of that area. Pan/zoom for a minute and report recurring pauses.
5. Check original artwork without a pack. If using installed Java textures, import that version again in Appearance to pick up snow, gravel, dry grass and new scenery. Existing cached packs should remain usable with original fallback where images are missing. No additional game assets should be shipped in the app.

## Sidebar and right-click follow-up — awaiting owner confirmation

1. Quit the old app and open the updated build. Check the wider panel has Build, Blueprints and Inspector tabs, with no Sidebar label or Technical Details. Build's first rows should be Move / Select, then Erase / Terrain, with components below.
2. Stop Desktop. Right-click a repeater on the editor map, then try Control-click. Both should show a menu even with Erase or Terrain selected, without erasing, painting or activating it. Choose Inspect: the Inspector tab should open. Rotate, change delay and Undo/Redo; settings should save immediately.
3. Opening Inspector should switch to Move automatically, so clicks inspect without placing or erasing. Click an Output or sensor: the selected item's appropriate settings should appear. Inspect empty terrain too. Return to Build and adjust repeater placement direction/delay: the previously selected repeater should stay unchanged; a newly placed repeater should use those defaults.
4. Right-click a selected group and try Copy, Move, Rotate, Delete and Save Selection as Blueprint. Save should open Blueprints. Check scrolling, card previews, tool descriptions and all three tabs fit at the smallest window size. While the world is running or Test Circuit is active, menus should still appear with editing actions disabled.

Native menu appearance and interaction remain physical checks; automated tests exercise dispatch and action behavior.

## Blueprint browser, tool help and editor context menus — awaiting owner confirmation

1. Quit the old copy and open the updated app. Stop Desktop. Check Build/Blueprints/Inspector tabs in the sidebar. Blueprints should show saved cards and eight examples with readable previews/names/descriptions; scroll to reach all cards. Hover tools in Build and Desktop Build Mode, and check the selected description stays visible below them.
2. Paint a clear Grass patch to the right of your existing builds, at least 9×5 tiles. Open Blueprints, choose Switched Pulse Generator, and click to place it. Test Circuit: wait about two seconds for startup to settle; Output should be off. Toggle the lever ON: the Output pulse count should keep increasing. OFF: after settling, pulses should stop and Output should be off. ON again should restart it. Reset may briefly pulse at startup; no files should open.
3. Try the other examples. Either Button should accept either input; Inverted Switch should invert its lever; the detector examples respond to clicks in Test Circuit. All example Outputs must remain Do Nothing. Placement preview rotation/cancel and existing saved blueprints should still work.
4. Select a group, switch to Blueprints and save it. Right-click its saved card, rename it, quit/reopen and confirm the new name/layout persists. Delete the shelf entry: placed copies must remain. Right-click a component on the map and choose Save Selection as Blueprint: it should open that tab's save dialog.
5. Right-click a repeater and try Rotate and Delay, then Undo/Redo. Right-click a torch: Rotate should be available. Dust/buttons shouldn't offer meaningless single-component rotation. Select several components and right-click one: Move, Rotate and Delete Selection should operate on the whole group; Undo should restore it in one step. Right-clicking by itself must not place/erase/activate anything.
6. Right-click scenery and remove it, then Undo. Right-click painted terrain and restore it; components must be preserved according to terrain protection rules. While Desktop runs or Test Circuit is active, delete/rotate/terrain actions should be disabled. The menu must never offer Finder file deletion.

These physical UI checks remain pending; automated tests do not establish Mac acceptance. Backup/reset checks remain deferred.

## Terrain editing — awaiting owner confirmation

1. Quit the old app and open the updated build. Stop Desktop, choose Terrain and Grass, then try 1×1, 3×3 and 5×5 brushes on terrain **to the right** of existing circuits. Drag quickly: the preview should be continuous, save on release and undo in one step. Start another stroke and press Escape while still dragging; releasing afterward must save nothing.
2. Paint over a tree/flower/cactus or water with Grass. Decorations should disappear and the ground should accept circuit placement. Try Stone, Sand and intentional Dirt. Clear Decorations should remove scenery while keeping the visible surface, including grassy generated dirt; clearing reeds must leave water as water.
3. Put a component on solid ground and paint water across it and adjacent empty tiles. The occupied tile should remain supported; orange marks it in the editor and the status reports it protected. The component's settings and saved lever state must stay intact. Restore Original should likewise skip a component whose original tile would be water or blocked scenery.
4. Restore Original on an edited empty patch: its original surface/decorations should return. Undo/Redo the restoration and a paint stroke. Quit/reopen, switch between areas of the same world, and inspect persistence. Another world's terrain should remain separate. Optional export/import should include terrain edits; no Start Over is needed.
5. Enter Desktop Build Mode, choose **0 Terrain**, and check palette fit, brush settings, preview and drag/release. Cancel with Escape or right-click. Exit and use editor Undo/Redo. If the editor was browsing another world, verify that Build Mode changed only the assigned desktop world. Start Desktop afterward to check ordinary circuits still run.
6. While Desktop is running or Test Circuit is active, terrain editing should be disabled for that world. Pan/zoom across edited chunk edges using built-in and imported textures; edits should appear without stale chunks or widespread redraw pauses. Report Mac/display/pack details for visible stalls.

These physical UI checks remain pending; automated tests do not mark them complete. Backup/reset testing remains deferred.

## Desktop pressure plates and file sensors — awaiting owner confirmation

1. Quit the old app and open the updated build. Stop Desktop and build `Plate → Dust → Output` on clear ground **to the right** of existing builds. Set the Output to Do nothing. Assign an area that includes it, Start Desktop, and drag a harmless file/folder so its icon center is over the Plate. After Finder refresh, the plate should say DOWN and the wire/Output power. Move it off: power should clear. Ordinary icon clicks must still work.
2. With no item on the Plate, Stop and change the Output to Open item. Place a different harmless folder on the Output. Start, then put an item on the Plate: the Output folder should open once. Leaving it there or replacing it without an observed empty interval must not reopen the folder. Move off, wait for power to clear, then move back: it should open again. Starting with an occupied Plate can activate immediately.
3. Stop and build `Sensor → Dust → Output` separately with Output Do nothing. Inspect Sensor, choose File extension, enter `pdf`, Start. A `.pdf` file should power it; `.txt` and folders should not. Stop, change to Item name and enter an actual full filename or folder name. Only that name should match; case differences should be accepted even if Finder hides extensions. Try Any item too. Do not rename real files just to test; use disposable copies.
4. Stop, edit the filter and Undo/Redo. Copy/save the sensor in a blueprint, place in another world, quit/reopen and inspect the stored filter. Enter Desktop Build Mode and try tools **8 Plate** and **9 Sensor**. Click a placed sensor and edit its palette filter. Check palette fit and existing tool shortcuts 1–7. Exit Build Mode; Desktop must remain stopped until Start.
5. Test Circuit: click both detector types to toggle simulated detection. Pause/Step, Reset and Done Testing should work without moving/opening files or querying Finder. Reset should clear detection and leaving the test must preserve saved configuration.
6. While Desktop runs, Pause, move the detected item away, wait for Finder to read, Resume: power should clear. With Outputs Do nothing, optionally freeze Finder polling in Diagnostics; detectors should turn off and recover after unfreezing/fresh reads. Stop should clear runtime power. If you have multiple displays, repeat with an area correctly mapped to a secondary display; report any mapping mismatch instead of compensating with offsets.

Backup/reset testing remains deferred. These physical checks are not marked accepted by automated test results.

## Editor test mode and reusable circuits — awaiting owner confirmation

Use the updated app after quitting the older copy. Existing saves should remain. None of these checks require Start Over. See [the editor guide](EDITOR_TOOLS.md) for shortcuts and storage scope.

1. Stop Desktop and open an existing circuit. Click **Test Circuit**, then its button/lever. Check bright powered paths, Output flashes, tick and Output pulse counters. Put a harmless folder under an Output if convenient: testing must not open it or show script approval. Done Testing should leave the saved circuit/lever positions unchanged.
2. Test again, Pause and wait: ticks and power should freeze. Click a button while paused, then Step repeatedly to see propagation and repeater delay. Reset should clear ticks/counts and restore the initial lever state, remaining paused. Play resumes; Done Testing exits. Switch worlds/areas during a test and confirm it ends. If Desktop was already running independently, exiting the test should leave it running.
3. With Desktop stopped, place a few components on clear ground to the right. Undo/Redo should reverse placement and inspector direction/delay changes. Choose Select and drag around the group; Shift-click should add/remove one. Move should still pan normally; Shift-drag in Move should select without panning.
4. Copy/Paste the group to clear ground. Check green preview, R rotation and one-click placement. Try a blocked location (an existing component or water): red preview and clicking must leave the entire circuit unchanged. Escape cancels. Move Selection should relocate the group only on a valid destination. Rotate and Erase Group should each undo in one step and preserve terrain. Switch worlds and confirm undo history is separate. Text-field Command-Z should still edit text.
5. Save the selection with a recognizable blueprint name. Open the Blueprints tab, place it in another world, then quit/reopen: it should remain in the shelf and preserve directions, delays and Output mode. Right-click/delete the shelf entry: already placed copies should remain. Copy/paste between editor windows should work too.
6. Place Delayed Button, Toggle Switch and Pulse Generator on clear ground. Test each: the first responds after its repeater delay, the second holds power until switched off, and the third pulses automatically. Their Outputs should say Do Nothing and never open files. Running/test worlds should reject building/moving/undo while locked.

## Latest polish checks — awaiting owner confirmation

Label/water follow-up: both zone labels should sit the same distance above their own top edge; coincident labels appear side by side. With imported Java textures, shallow/deep water should show no checker backdrop. No re-import is needed.

Settings → Data → Reveal Backups Folder should open Finder even before the first backup; an empty folder is expected then. This button does not reset the app.

Backup/reset testing remains deferred; the polish changes do not require Start Over. Owner feedback on 2026-10-09 confirms the tool icons look good and menus work better. The latest follow-up changes still need these checks: pan zone labels offscreen and back, check their position above the top lines, and switch menu areas with Desktop both running and stopped.

1. Quit the old app and launch the updated build. Open Settings → General → Open Setup. Read each page, try Next/Back and confirm all text fits. Try the help buttons in Build and Appearance.
2. Start Desktop, open the dust menu and hover **Assign Desktop Area**, its world submenus and **Tools** for several seconds. Move the mouse between menu items; submenus should remain open without flicker while the circuit runs.
3. Check **Build on Desktop** at the viewport’s upper-left, **Advanced** then **Start Desktop** at the header’s right. Start/Stop should show play/stop icons. Enter desktop build mode: check horizontal padding, all tool icons and shortcuts. Exit normally.
4. Place dust, a repeater and an Output on coal/iron in stone. Trees and cactuses should still reject placement. Try the same in desktop build mode. Existing ore decorations should survive erasing and reopening.
5. Select a repeater and change Direction and Delay. The component should update immediately without Apply. Quit/reopen and check the saved values. Inspecting a component alone should not change it; running worlds remain locked for editing.
6. Create a new world, then save a new area after panning. The blue saved-area outline should be visible initially. Blue and orange rectangles should have labels above their top edges, following the outlines offscreen as you pan; in an inactive world blue means **Saved area**, while the assigned world says **Desktop area**. Your actual desktop assignment should stay unchanged.
7. In Appearance, the installed-game choice and **Use Minecraft Assets** should be prominent. Choose a version, import and try **Use Original Look**. Expand More Options for custom packs and cache controls. Check monochrome icons in both toolbars with light/dark appearance.
8. Settings → Data: export a library outside app storage. Import it, review world/area counts, cancel once, then confirm **Add Worlds**. Original builds should stay intact; imported worlds should be separate copies with their own areas. Current desktop selection must not change. Invalid JSON should show an error without changing the library. Importing adds copies and cannot be undone with one click; delete the test copies in the world list when finished.

## Earlier integration checks

## 1. Build and launch the updated app

1. Quit the previous Redstone Desktop app using its dust menu → Quit. Keep your usual Finder desktop intact.
2. From the repo, run `xcodegen generate`, then open `RedstoneDesktop.xcodeproj`. Select **RedstoneDesktop → My Mac**, then **⌘R**. If Xcode asks about signing for local development, the unsigned Terminal build/run commands in README also work.
3. Confirm existing worlds/areas/circuits remain. New Setup should appear once after this update, without resetting them. Desktop must start stopped. Move/close windows and open the menu: status spacing should stay constant in Stopped, Running, Paused and Build Mode. Check the owner-provided logo in Dock/Finder/⌘Tab; restart after building if macOS cached the old icon.
4. In the dust menu, verify Start/Stop, assigned-world/area checkmarks, Open Editor, Show Assigned Area, Build Mode, Settings, Mute and Tools. Browsing an editor area should not change the desktop assignment. Choosing a menu area automatically resumes Desktop if it was running; a stopped desktop stays stopped.

## 2. Setup and Settings (Slice 33)

1. In Setup, move Next/Back through all four pages. Text/buttons should fit without truncation. Close or **Skip Setup**: no circuit should run and no script should execute. Quit/reopen: skipped/completed Setup should not appear automatically again.
2. Open **Settings → General → Open Setup…**. It should reopen even after Skip/Finish. Completing it should preserve all builds and keep Desktop stopped.
3. Only choose **Connect to Finder…** when you want tracking. If permission was already allowed, no new prompt is expected. If denied, the app should explain the refusal and keep the editor usable. To retry, enable Redstone Desktop under **System Settings → Privacy & Security → Automation → Finder**, then explicitly retry the read. Do not reset system privacy settings just to repeat this test.
4. On the script page, **Allow Access to Desktop Scripts…** checks the separate folder access. It must not execute a file or enable automatic routing. Inspect **Settings → Outputs**: automatic script/open routing should remain your existing preference, off on fresh setup.
5. Open each Settings tab: **General, Sound, Appearance, Outputs, Data**. Check fit, scrolling, native tab switching and Settings keyboard shortcut **⌘,**. General scale controls should match their existing behavior. Appearance/Packs and Tools windows should still work.
6. In Sound, lower volume, try Left/Center/Right previews and an effect. Mute should stop current sound; further previews/inputs should be silent. Restore low volume and unmute. After a few quiet seconds, a new effect should still play. Quit/reopen and check volume/mute persist. No microphone permission should appear.
7. Enable **System Settings → Accessibility → Display → Reduce Motion**. In Desktop Build Mode the border should stay steady; click/Output feedback should appear briefly without fading. Turn Reduce Motion off and check the ordinary border/feedback returns. This should not alter circuit timing or files.

## 3. Multiple displays (Slice 32; skip if you have one display)

1. Start Desktop with two displays. Both should show the same continuous world, beneath Finder icons, with only one cursor highlight at the pointer. Move across the boundary and compare to the editor's blue desktop outline. Check desktop icons still select, drag, rename, marquee and double-click normally.
2. In **System Settings → Displays → Arrange**, try the second screen to the right, left and below, including an offset arrangement. Stop/start after changing if needed. Negative origins are supported; adding a display left/below can shift the primary view because the virtual lower-left is the anchor. This must not copy/move saved components.
3. With mixed Retina/non-Retina screens, a tile is measured in logical points. Cursor/Finder mapping must agree with the visible tile on each screen, without a factor-of-two or one-tile offset. Open Finder Diagnostics and compare raw positions, mapped centers, display frames and hovered tiles. If wrong, stop testing Outputs on that screen and report screen arrangement, scaling, raw/mapped row and screenshot. Do not compensate with guesses.
4. Create harmless empty folders on each desktop. Read Finder successfully. Put an Output under a folder only after checking center mapping. A button/dust circuit must open that current folder on a new rising edge. Move/replace the folder: the next activation should resolve the current occupant. Empty/ambiguous Outputs should not open anything.
5. Build a connected wire/repeater circuit crossing a screen boundary. It should simulate as one circuit, without double ticks or duplicate actions. Physical display gaps must not dispatch invisible Outputs.
6. Move an ordinary app window over the button: clicking the covered app must not activate the circuit. Repeat on both screens. Hover/click after a display change must not act using old coordinates.
7. Disconnect/reconnect the second screen while Desktop runs. Windows should rebuild, stale action work should be cancelled and the saved world/area/camera should remain. Try mirroring: no doubled world/input/action. If all displays disappear, return should require explicit Start.
8. Enter Build Mode. It currently edits **the primary screen only**, using the shared world mapper. Primary-screen hotbar/R/T, stronger border and hidden-editor restoration should work. Other displays must not become unexpected build surfaces. Exit normally, through Open Editor and through Quit.

## 4. Responsiveness and real energy/memory

1. Start Desktop and pan/zoom around the editor for at least two minutes. Cross many terrain chunks and try scroll/pinch. Cursor highlight, UI controls and panning should remain responsive during Finder polling; report recurring pauses with approximate frequency.
2. Open **Activity Monitor**, select Redstone Desktop and observe CPU, Memory and Energy Impact when stopped, running idle, panning, and after a minute idle again. Record Mac model, macOS, display count/scales and pack. A single RSS increase is not itself a leak; sustained growth across repeated identical workloads deserves investigation.
3. Repeat briefly with built-in art and a locally imported Java pack. Missing textures should use original fallback. Local profiling is a synthetic CPU/peak-RSS measurement, not a battery-power guarantee; these live checks matter.
4. Sleep/wake, switch Spaces, enter/exit Mission Control and, if you use it, Stage Manager. Check layering, input exclusion, highlight and clean Stop/Quit. These older detailed physical gates are still open.

## 5. Export, cancellation and backed-up Start Over

**Do this only when you intend to replace the current app library. Export first and keep the backup. Your Desktop files are not reset.** To test without touching your real builds, use a separate macOS account or the developer isolated harness described in RECOVERY.md. Normal Start Over resets the currently installed app's library.

1. Stop Desktop. **Settings → Data → Export Library…**; save outside Application Support. Cancel one export too. Open the JSON in a text editor: named worlds/areas, seeds, components and lever positions should be present. Finder files, script source, approvals and texture contents should be absent. Keep this export.
2. Open **Start Over…**, read the exact scope, then Cancel. Confirm builds/settings/assignment stay the same and no relaunch occurs.
3. For an intentional reset, note a harmless Desktop folder and your source JAR/pack path. Confirm **Back Up, Reset and Restart**. The app should stop all integration, create a backup, close the old instance and open Setup automatically. If relaunch fails, read the message, Quit and reopen manually; do not repeat reset blindly.
4. Fresh instance: one empty procedural world and Home area, no copied demo/old components, Desktop stopped, default sound/scale/appearance, routing off and no remembered script approvals. Quit/reopen once more: no old library/legacy migration should reappear. Setup Skip/Finish should persist again.
5. Check the original Desktop folder and source pack/JAR still exist with unchanged contents. macOS Automation/Files & Folders decisions should remain; new system prompts are not guaranteed. Built-in appearance should be selected even if a previous import was active.
6. **Settings → Data → Reveal Backups Folder**. Find the timestamped directory: standalone library.json, preferences.plist, backup.json and original Support (including any old world.json/managed imports). Validate worlds/areas are present; keep the entire directory. Before the first backup, Reveal Backups Folder should open an empty folder. Saved blueprints, when present, should be included as Support/blueprints.json.
7. Follow [RECOVERY.md](RECOVERY.md) with the app quit to restore the exported or backed-up library, preserving the fresh file first. Reopen: builds/assignment should return **stopped**. Full preference/cache restoration is optional and also described there. Do not force corruption/rename failures in your real store; automated tests cover injected failures and interrupted recovery.

## 6. Action cancellation regression

1. With an empty Output, verify dust/repeater/torch visuals and powered-Output rear pickup still work without Finder files. Use the documented [2D rules](REDSTONE_RULES.md), not full Minecraft behavior. Torches start ON unless inhibited; start with empty Outputs.
2. Use harmless folders to test replacing the occupant just before pressing. One valid press during a short Finder refresh should wait/read freshly rather than require multiple attempts. Repeated presses while a button stays powered need not create repeated actions.
3. Only if you want to test scripts, use your own harmless supported script. Explicit Execute or opt-in routing should ask for exact-file approval. Cancel must run nothing. Remembered approval should apply only to the same unchanged target; changed contents should ask again. Uncheck remembering to ask every time.
4. While approval is open, Stop/Pause, switch assigned areas, change routing or Quit; finishing stale approval must not execute or remember it. Resume/restart should not replay cancelled work. See [SCRIPT_OUTPUTS.md](SCRIPT_OUTPUTS.md) for timeout/output/revocation checks. Do not approve unknown scripts merely for testing.

## 7. Release engineering (Slice 34)

1. Follow [RELEASE.md](RELEASE.md)'s clean-checkout build instructions. XcodeGen generates the untracked Xcode project. Build and test without relying on owner-specific paths, game installs or preferences.
2. Run the unsigned release script and inspect its ZIP: app, license, third-party notices and release/limitations documentation should be present; no imported Java world assets, saves or scripts should be included.
3. Extract to a separate folder and launch that app after quitting the development copy. It uses the same production library unless you use a separate account. Check icon/menu/setup/settings, explicit Start/Stop and Quit/reopen. Unsigned download Gatekeeper behavior, Developer ID/notarized distribution and older macOS/Intel require separate validation.
4. Inspect the GitHub Actions run after pushing: build, tests and Release archive must actually pass there. A local successful build is not a hosted-CI result. Signing/notarization remains optional and requires your credentials/asset distribution decision.

Please report acceptance by group/substep, e.g. “1, 2, 4 passed; 3 skipped (one screen); 5 not attempted.” That keeps the testing record accurate without claiming untested destructive, permission or multi-display behavior.

## Lamps and regular torches — Mac validation pending

- [ ] Quit the previous app with ⌘Q, then run the updated app from Xcode with ⌘R.
- [ ] Stop Desktop, open the selected world's gear and choose Always Night. Leave “Light nearby ground with torches, lava and redstone” enabled.
- [ ] In Build, place a Torch on clear ground to the right of your existing circuits. Its surroundings brighten immediately, without Test Circuit. Place dust/Output next to it: it must not power them or open anything.
- [ ] Place Lever → Dust → Lamp, start Test Circuit and click the lever. Lamp becomes a full lit block and brightens its surroundings; switching off darkens both. Lamp does not pass power into another dust wire or repeater behind it.
- [ ] Turn local lights off in World Settings: night stays dark around Torch and powered Lamp. Turn them back on; illumination returns. Day and Fixed Time still behave normally.
- [ ] Save/reopen and check that both components remain. Copy them into a blueprint and stamp it elsewhere; undo/redo and erase work normally.
- [ ] Reimport your Minecraft textures (older caches do not acquire new mappings automatically); lamps and regular torches use their Java artwork. Built-In still provides distinct original art for each.
- [ ] In Desktop Build Mode, use the third palette row to place Lamp and Torch. Exit Build Mode, start Desktop and test the lever/lamp circuit. Existing number shortcuts and all palette tools still work.
- [ ] Try exposed Desktop button and lever clicks during Day and Night. Record Last action in Advanced → Desktop Details if an input does not respond. Confirm no file opens merely from a torch/lamp placement.

Desktop click investigation remains open: the owner reports missed clicks on the running Desktop. Inputs blocked during Finder/display settling now report the reason and count the received press; this is diagnostic feedback, not a verified fix for the reported missed clicks. Capture Last action and event metadata from Desktop Details when reproducing. Automated input gates, queued reads, fresh-output routing and polling tests continue to pass.

## Sensor pressure-plate appearance and source shortcuts — Mac validation pending

- [ ] Quit the app with ⌘Q, then run the updated app from Xcode with ⌘R. Stop Desktop before editing.
- [ ] Place Plate and Sensor with Any item selected: both look wooden. Select a Sensor, choose File extension and enter `pdf`: it becomes a stone plate. Item name filters also use stone. Switching back to Any item restores wood.
- [ ] Right-click either plate in the editor. Detect: Any item saves immediately. Detect: File extension… / Item name… opens the Inspector with the right entry field. Empty drafts must leave the original saved configuration unchanged; typing a valid value saves immediately. Undo/redo restores both filter and appearance.
- [ ] In Desktop Build Mode, right-click a plate and use the same shortcuts. The palette opens its field; changing the source leaves the plate on the same tile. Delete Component still works in the sensor menu; right-click nonsensor components still erases them.
- [ ] Use Test Circuit and click each plate to toggle simulated occupancy. Both wood and stone have distinct raised/depressed appearances; Test Circuit bypasses matching only for its simulated input. It never opens files. Stop testing before changing filters.
- [ ] Refresh Imported Minecraft Assets in Appearance settings. Any item plates use oak plank material; filtered plates use stone. Built-In still supplies clear wood/stone art without an import.
- [ ] Copy a filtered plate into a blueprint and check its preview is stone. Stamp it elsewhere, save/reopen, and confirm the filter remains. With Desktop running, Any item accepts a file or folder; a `pdf` filter accepts a PDF and turns off for a TXT/folder replacement after Finder refresh. Use Outputs set to Do nothing for this check.

## Particles and imported Java sounds — Mac validation pending

- [ ] Quit the app with ⌘Q, then run the updated app from Xcode with ⌘R. Under Settings → Appearance, select an installed version and choose Use Minecraft Assets, or refresh your previous import with More options & custom packs → Refresh Imported Minecraft Assets. Check the status shows an image count and sound count. The development Mac’s 1.21.11 installation supplies all ten mapped effects.
- [ ] Place a regular Torch on clear ground to the right of existing circuits. Watch for a few seconds for flames and faint rising smoke. Nearby lava pools produce occasional small pops across the pool, rather than particles on every tile.
- [ ] In Test Circuit, power a short Dust path. It should emit occasional red flecks; switching off removes them. Longer/weaker powered wire runs should be quieter. A lit R. Torch emits red sparks and stops when inhibited. Particles must appear in both day and night; existing night illumination remains intact.
- [ ] Start Desktop and confirm the same effects. Finder icons remain usable; particles must not intercept button/lever or normal desktop clicks. Desktop Build Mode shows regular torch/lava particles while its simulation is stopped.
- [ ] Pan, zoom and return to your area repeatedly. Old trails should clear as the camera moves, emitters should follow tiles, and the map should stay responsive. A dense group of torches must remain bounded rather than filling the screen.
- [ ] Toggle macOS System Settings → Accessibility → Display → Reduce Motion. Particles disappear and pause; turning it off restores them. Existing water/scenery animation and desktop build border still obey their documented Reduce Motion behavior.
- [ ] Under Settings → Sound, enable sound effects at low volume and unmute. In Test Circuit or on a harmless Desktop circuit, press/release Button, toggle Lever and use placement/erase. Hear imported clicks/block sounds. Existing volume, mute and stereo panning should work. No particles produce continuous ambient sound.
- [ ] Choose Use Original Look: visuals and audio return to originals together. Re-select your import and restart the app: the cache reload should restore both, without rereading/downloading game assets.
- [ ] Import a Java pack missing sounds or particles: originals fill the gaps. A missing launcher sound cache must not break an otherwise valid texture import. No imported images/audio should appear in exported world data or the release app bundle.

## Setup import, appearance icons and public README (2026-10-11)

- [ ] MANUAL: Rebuild/launch the updated app, open Settings → General → setup, and reach **Choose your look**. Installed Java versions should appear. Choose one and click **Use Minecraft Assets**; wait for completion, finish setup, and check the editor uses that look. Quit/reopen and verify it remains selected. Existing worlds/circuits must be unchanged.
- [ ] MANUAL: Reopen setup and try **Choose a Texture Pack or JAR…** with a local Java pack/JAR. Cancel once, then import a valid source. The app should remain usable in both cases. Next/Skip must work without Minecraft or an import. The window must fit and the import help button must read clearly.
- [ ] MANUAL: Check the setup logo in light and dark system appearance. Check menu-bar/Dust-tool visibility in both. On macOS 26+, check the app icon using the system’s light/dark icon styles in System Settings → Appearance (including Automatic if available); both should show the same centered red logo. Quit/reopen or inspect a freshly copied build if macOS is showing a cached icon. On older macOS, check the static fallback in Finder/Dock.
- [ ] MANUAL: Open README on GitHub and in the extracted review ZIP. Verify its adaptive logo, circuit animation, world examples, day/night image and guide links load, and the first-circuit instructions are understandable. The DMG section must say it is coming, with no pretend download link.

Automated validation: Debug build and all 582 XCTest tests passed. The universal arm64/x86_64 Release app and actual review ZIP passed the release verifier, including compiled light/dark icon appearances and bundled README media. Every README image/relative guide link was checked in source and ZIP. Light/dark variants were previewed in native Icon Composer; the generated static fallback was inspected separately. These checks do not replace the pending Mac acceptance items above.

## Long days and local system time (2026-10-11)

- [ ] MANUAL: Open World Settings → Day & Night. Drag the Full day slider from 2 minutes to 24 hours; check the duration label and the 20 minutes / 1 hour / 24 hours presets. Save a 24-hour cycle, reopen settings, and verify it is retained. Cancel a subsequent change and verify the saved setting stays unchanged.
- [ ] MANUAL: Choose Match System Time. Duration/start-time controls should disappear. Save and compare the world lighting with the current local time (noon is bright, midnight is dark, dawn/dusk around 6 AM/PM). Quit/reopen or sleep/wake: it should follow the current time without resetting the world clock. Other worlds keep their own settings; circuits continue normally.
- [x] MANUAL: Owner confirmed the Dock icon looks good after the dark icon-style check. Read-only diagnosis found Dark window appearance with Default icon style; Dark icon style selects the compiled dark background. Normal Debug builds contain both variants; Release is not required.
- [ ] MANUAL: Check Icon & widget style → Dark → Auto across both Light and Dark window appearance, and verify the Dock icon follows both transitions. Switching only window appearance while icon style is Default is not a dark-icon test.

Read-only diagnosis found Dark window appearance with Default icon style on the owner’s Mac. Both compiled app-icon variants have distinct compositions and the intended light/dark background layers. The owner confirmed the dark-icon appearance looks good; both automatic transitions remain a separate check.

Automated clock validation: Debug build and all 587 XCTest tests passed, including the five new duration/local-time/persistence/sheet checks. An initial run exited before finishing an unrelated Java-import test; that test passed in isolation and the complete rerun passed. No additional code changes were needed for that interruption.

## Particle shading with local lighting disabled (2026-10-11)

- [ ] MANUAL: Rebuild/launch the update, enable Show particles with Reduce Motion off, then set a world to Always Night. Look at lava, a regular Torch and powered dust/R. Torch. Uncheck **Light nearby ground with torches, lava and redstone**, then Save: their particles and existing trails should darken with the surrounding scene. Try original artwork and your current Java import.
- [ ] MANUAL: Re-enable local lighting: particles should glow again. Switch to Always Day with local lighting disabled: particles should retain daytime brightness. Check both editor/Test Circuit and running Desktop; panning and Show particles should still behave normally.

Automated particle validation: Debug build and all 589 XCTest tests passed. Native rendered-pixel comparisons cover lava, regular/redstone torches and powered dust across night/local-light toggling and daylight; clock and viewport checks preserve emitters and lighting-mask reuse. Component labels are hidden only in the pixel fixture to isolate particle brightness. Manual editor/Desktop and imported-pack checks above remain pending.

## Stability fixes (2026-10-12)

Use one updated app instance. Quit the previous build, open `RedstoneDesktop.xcodeproj`, select the **RedstoneDesktop** scheme and **My Mac**, then click **▶ Run** (or **⌘R**). You can also open the rebuilt `.app` directly; Xcode is useful for logs but is not required for ordinary use. These checks do not require resetting your worlds or filling your disk.

- [ ] MANUAL: In Settings → Sound, unmute effects and play a preview. Change the Mac’s output device (for example speakers ↔ headphones/Bluetooth, or connect/disconnect a USB device), then play another effect. The app should stay open and sound should resume when an output is available. Repeat after sleep/wake. Skip device types you do not own.
- [ ] MANUAL: Make a small edit, quit with **⌘Q**, reopen and confirm it persisted. Repeat using **Quit Redstone Desktop** in the menu bar. Desktop should reopen stopped, as before. Injected write-failure/Cancel/Retry/copy-failure branches are covered by tests; do not deliberately fill or damage your disk to test them. If a real write error occurs, **Stay Open** should preserve the session, and **Save Copy and Quit…** should exit only after a successful copy.
- [ ] MANUAL: Copy/paste a small blueprint several times, draw dust/terrain, change a repeater and use Undo/Redo. Save and reopen: accepted edits should remain. If you eventually hit the 2 MB limit, the refused operation should leave no partial placement or extra undo step; removing unused content should allow editing again.
- [ ] MANUAL: With your working Java/custom textures active, open Settings → Appearance → **More options & custom packs** → **Choose Custom Pack Folder or ZIP…** and choose a folder/ZIP without `pack.json` (or a malformed custom manifest). The refusal message should appear while the previous look and sounds stay active. Quit/reopen: the previous choice should still load.
- [ ] MANUAL: Pan, zoom and resize the editor; close/reopen it; start/stop Desktop, reassign areas and enter/exit Build Mode repeatedly. Keep particles, animated liquids and nighttime lighting enabled for 20–30 minutes, including a sleep/wake cycle. Existing circuits should still react; no app crash or growing stack of overlay windows should appear. If available, repeat with another display/Spaces arrangement.

Automated results and remaining crash-history boundaries are recorded in [STABILITY.md](STABILITY.md). No manual checkbox above is marked complete by automated tests.
