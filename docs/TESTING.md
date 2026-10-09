# Mac acceptance checklist

These are physical-Mac checks, separate from automated tests. Report which numbered groups you actually tried and what failed; untested groups remain unverified. Use harmless folders/text files first. Place new test circuits on clear ground **to the right** of your existing builds. Do not use scripts for display-calibration tests.


## Latest polish checks — awaiting owner confirmation

Backup/reset testing remains deferred; the polish changes do not require Start Over.

1. Quit the old app and launch the updated build. Open Settings → General → Open Setup. Read each page, try Next/Back and confirm all text fits. Try the help buttons in Build and Appearance.
2. Start Desktop, open the dust menu and hover **Assign Desktop Area**, its world submenus and **Tools** for several seconds. Move the mouse between menu items; submenus should remain open without flicker while the circuit runs.
3. Check **Build on Desktop** at the viewport’s upper-left, **Advanced** then **Start Desktop** at the header’s right. Start/Stop should show play/stop icons. Enter desktop build mode: check horizontal padding, all tool icons and shortcuts. Exit normally.
4. Place dust, a repeater and an Output on coal/iron in stone. Trees and cactuses should still reject placement. Try the same in desktop build mode. Existing ore decorations should survive erasing and reopening.
5. Select a repeater and change Direction and Delay. The component should update immediately without Apply. Quit/reopen and check the saved values. Inspecting a component alone should not change it; running worlds remain locked for editing.
6. Create a new world, then save a new area after panning. The blue saved-area outline should be visible initially. Blue and orange rectangles should have small persistent labels; in an inactive world blue means **Saved area**, while the assigned world says **Desktop area**. Your actual desktop assignment should stay unchanged.
7. In Appearance, the installed-game choice and **Use Minecraft Textures** should be prominent. Choose a version, import and try **Use Original Look**. Expand More Options for custom packs and cache controls. Check monochrome icons in both toolbars with light/dark appearance.
8. Settings → Data: export a library outside app storage. Import it, review world/area counts, cancel once, then confirm **Add Worlds**. Original builds should stay intact; imported worlds should be separate copies with their own areas. Current desktop selection must not change. Invalid JSON should show an error without changing the library. Importing adds copies and cannot be undone with one click; delete the test copies in the world list when finished.

## Earlier integration checks

## 1. Build and launch the updated app

1. Quit the previous Redstone Desktop app using its dust menu → Quit. Keep your usual Finder desktop intact.
2. From the repo, run `xcodegen generate`, then open `RedstoneDesktop.xcodeproj`. Select **RedstoneDesktop → My Mac**, then **⌘R**. If Xcode asks about signing for local development, the unsigned Terminal build/run commands in README also work.
3. Confirm existing worlds/areas/circuits remain. New Setup should appear once after this update, without resetting them. Desktop must start stopped. Move/close windows and open the menu: status spacing should stay constant in Stopped, Running, Paused and Build Mode. Check the real dust icon in Dock/Finder/⌘Tab; restart after building if macOS cached the old icon.
4. In the dust menu, verify Start/Stop, assigned-world/area checkmarks, Open Editor, Show Assigned Area, Build Mode, Settings, Mute and Tools. Browsing an editor area should not change the desktop assignment. Choosing a menu area stops Desktop and requires explicit Start.

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
6. **Settings → Data → Reveal Backups Folder**. Find the timestamped directory: standalone library.json, preferences.plist, backup.json and original Support (including any old world.json/managed imports). Validate worlds/areas are present; keep the entire directory. If no backups exist yet, the reveal may simply fail to open a nonexistent directory—use Finder Go to Folder after the first successful backup.
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
