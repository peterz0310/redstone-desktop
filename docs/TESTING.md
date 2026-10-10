# Mac acceptance checklist

These are physical-Mac checks, separate from automated tests. Report which numbered groups you actually tried and what failed; untested groups remain unverified. Use harmless folders/text files first. Place new test circuits on clear ground **to the right** of your existing builds. Do not use scripts for display-calibration tests.


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
7. In Appearance, the installed-game choice and **Use Minecraft Textures** should be prominent. Choose a version, import and try **Use Original Look**. Expand More Options for custom packs and cache controls. Check monochrome icons in both toolbars with light/dark appearance.
8. Settings → Data: export a library outside app storage. Import it, review world/area counts, cancel once, then confirm **Add Worlds**. Original builds should stay intact; imported worlds should be separate copies with their own areas. Current desktop selection must not change. Invalid JSON should show an error without changing the library. Importing adds copies and cannot be undone with one click; delete the test copies in the world list when finished.

## Earlier integration checks

## 1. Build and launch the updated app

1. Quit the previous Redstone Desktop app using its dust menu → Quit. Keep your usual Finder desktop intact.
2. From the repo, run `xcodegen generate`, then open `RedstoneDesktop.xcodeproj`. Select **RedstoneDesktop → My Mac**, then **⌘R**. If Xcode asks about signing for local development, the unsigned Terminal build/run commands in README also work.
3. Confirm existing worlds/areas/circuits remain. New Setup should appear once after this update, without resetting them. Desktop must start stopped. Move/close windows and open the menu: status spacing should stay constant in Stopped, Running, Paused and Build Mode. Check the real dust icon in Dock/Finder/⌘Tab; restart after building if macOS cached the old icon.
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
