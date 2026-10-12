# Desktop diagnostics

Open **Advanced → Desktop Details** for the overview and session controls. **Advanced → Finder Diagnostics** shows the item table, raw Finder positions, transformed screen centers and assigned-desktop tiles. Opening either window reads cached state; it never requests permission, queries Finder, saves a world, advances simulation or executes an action. Names/paths and script results are visible locally and are not uploaded or newly logged by this slice.

## What the panels show

- Editing world/area names and IDs separately from the assigned desktop world/area. Library path, legacy migration source/backup path, world/area counts, current persistence/status messages and pending-save state. **Save Now / Retry Save** explicitly flushes pending changes; merely inspecting status does not write.
- Finder Automation's last known status, current read/settling/poll state, item count, error, read attempts/duration and last successful read. A failed read does not claim a new success; the last-success time is historical evidence, not an assertion that current access is allowed.
- Desktop folder check status and separate exact-script approval. Accessibility is not used by the current app, so it does not claim an Accessibility grant or request one. OS privacy settings and app script approvals remain separate.
- App/macOS versions, current macOS display frames/backing scales, target/reference display, desktop window frame/visibility/level/click-through state, effective and saved assigned cameras, last editor canvas camera, pointer screen/world/tile coordinates and display identity.
- Measured simulation tick callbacks per second and desktop/editor SpriteKit scene-update callbacks per second (FPS). Targets are 20 ticks/s and 30 frames/s. Measurements use monotonic timestamps and constant-size counters; they are not GPU presentation counters. A sample needs about one second; values expire after two seconds without callbacks. Hidden/stopped scenes may report **no recent sample**. Readouts refresh once a second while visible; no new Finder/performance polling loop is added.
- Active pack name/source/loading state/status/warning count, desktop terrain cache/node/generation/texture-build counters, last Output rising-edge tile/strength/tick/world/area and last action/rejection/script result. A last Output event can remain visible after Stop for investigation; its captured IDs identify its source. Starting a new desktop session clears it. Signal activation and file-action success are distinct.

Finder positions are macOS logical points, measured from Finder's primary reference display using the previously owner-accepted center assumption. CoordinateMapper converts them to screen and world positions. Numeric diagnostic mappings can be inspected after a successful explicit read with Desktop stopped; this does not enable runtime occupancy or simulation.

## Diagnostic controls

All overlays and pause/freeze controls are session-only, start OFF on app launch and do not enter world/library saves. Normal Finder icons retain their uncluttered presentation.

| Control | Effect |
| --- | --- |
| Tile coordinates | Up to 128 visible tile labels in the desktop/last editor canvas |
| Raw Finder labels/dots | Up to 256 visible converted centers, with raw upper-left-reference coordinate labels |
| Mapped Finder center rings | Cyan rings around the same assumed centers, not exact icon hit bounds |
| Output occupancy | Labels for empty/single/ambiguous/unavailable Output occupancy; never selects an occupant |
| Chunk boundaries | Up to 64 visible/margin chunk outlines, using CoordinateMapper |
| Hide all diagnostic overlays | Removes all diagnostic artwork; circuit state is unchanged |
| Freeze automatic Finder polling | Stops automatic refresh; unfreezing resumes previously running polling when the current session/access permits |
| Pause simulation | Retains signal and delay history, cancels pending input/Output/script work, refuses new input and stops advancing ticks |

Raw dots and mapped rings deliberately share the same converted center: Finder provides one raw position, not an independent center/hit-region measurement. They help compare the mapping against the physical icon; they cannot establish exact icon/label extents. In the editor, enable **Show Finder Items** to supply projected markers, then opt into the diagnostic marker controls. Editor projections use the proposed area camera; the numeric Finder table uses the assigned desktop camera. Keep those roles separate when comparing.

Freeze does **not** freeze action targets. Explicit Read, button/lever validation and Output action refreshes remain enabled and serialized; the app will not open an obsolete cached target just because polling is frozen. To prevent actions while investigating, use Pause or Stop.

Pause leaves the desktop renderer and pointer sampling available, but invalidates pending action sessions and script approvals/process work. Resume continues retained signal/delay history; it does not replay an already-powered Output. A later genuine rising edge still acts normally. Stop resets runtime state and pause. Existing script cancellation limits remain as described in [SCRIPT_OUTPUTS.md](SCRIPT_OUTPUTS.md); earlier script side effects are not undone. Build Mode remains stopped editing and cannot run or pause simulation.

## Investigating “this icon is one tile off”

1. Confirm the **assigned** world/area names, IDs and saved/effective camera. Browsing or panning the editor does not change the desktop assignment. Optional Finder scale synchronization can change effective desktop tile size; its current status and both cameras are visible.
2. Check target and Finder-reference display frames/backing scales. Look for display/layout settling or unavailable mapping, and compare the click-through desktop window frame against its target. Desktop renders one continuous virtual canvas across reported displays; physical gaps cannot dispatch actions. Build Mode currently edits only the primary display.
3. Use **Finder Diagnostics → Read Finder Items** if no successful read is available. Inspect the icon's raw position, mapped screen center and world tile. Check read errors/permission status, age/duration and ambiguous occupants. The table stays read-only.
4. Start Desktop for physical alignment inspection, then Pause simulation. Enable mapped center rings and tile labels. Compare the ring against the real icon and the reported tile. If necessary freeze automatic polling while stationary; remember explicit reads/actions remain fresh.
5. Move the icon, unfreeze/read again and check the table/ring update. If geometry disagrees with actual macOS behavior, report the target/reference frames, camera values, raw/mapped row and settling/error state. Stop that behavior rather than adding manual offsets or source-level print statements.
6. Hide all overlays and Resume or Stop when finished. The normal desktop must again have no Finder crosshairs or diagnostic labels.

## Owner Mac acceptance

1. Run with **⌘R**. With Desktop stopped, open both Advanced diagnostic windows. Confirm they do not prompt for new permission or start a circuit. Browse another world and verify Editing changes while Desktop assignment stays fixed.
2. Start Desktop and reopen Desktop Details. After a second, inspect measured tick rate (near 20) and scene FPS (normally near 30 when drawing); actual rates can be lower. Inspect the last Output event/action after a harmless circuit activation and verify save/pack/pointer/display information is readable.
3. Pause a powered circuit: power should remain visible, new input should report paused and no new activation should occur. Resume: held Output must not open again. Pause during a pending script confirmation and verify a late approval cannot run/remember that old action.
4. Enable center rings/raw labels/tile coordinates, inspect one Finder row against the physical icon, then move the icon and verify updates. Try occupancy labels and chunk outlines, pan the editor, and Hide all overlays. Normal desktop presentation must return.
5. Freeze automatic polling. Move an Output occupant and explicitly Read or activate a harmless circuit; the current target must still be refreshed. Unfreeze previously active polling and confirm movement resumes updating.
6. Stop and quit/reopen: session diagnostics return to defaults. Existing circuit/action behavior and world persistence remain intact. If a pending save fails in normal use, its status should remain visible and Save Now should retry; do not deliberately damage your library to test this.

Automated tests use fake Finder/action providers, isolated stores and native hosting/scene fixtures. They establish command/state/mapping and lifecycle behavior; physical icon alignment and actual FPS/menu/window interaction remain owner checks.
