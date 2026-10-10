# Testing and reusing circuits

## Test a circuit without opening files

Click **Test Circuit** above the editor viewport. The editor runs a temporary copy of the selected world's circuit. Click its buttons and levers to watch power travel. Click plates and file sensors to toggle simulated detection; their filters are bypassed in test mode and no Finder read occurs. Outputs flash and the toolbar counts Output pulses, but test mode never opens a Finder item, requests script approval or executes a script. Your running desktop remains independent.

**Pause** freezes the test. **Step** advances one simulation tick (50 milliseconds of circuit time); a repeater's redstone tick is two simulation ticks. Inputs clicked while paused take effect as you step. **Play** resumes at 20 simulation ticks per second. **Reset** returns to the saved component configuration and saved lever positions, clears pulse counts and keeps your play/pause choice. **Done Testing** returns to building without saving test power or lever changes.

Building and inspector changes are disabled during testing. Switching worlds/areas, previewing another seed or closing the editor ends the test. External changes to the source circuit also invalidate it. Testing does not start or stop Desktop.

## Select, copy, move and rotate

**Move** still pans when you drag and inspects a component when you click. Use **Select** to drag a rectangle around components. Shift-click adds/removes individual components; Shift-drag also selects while using Move. The right panel reports the number selected. Empty ground and terrain decorations aren't copied.

Choose **Copy**, then **Paste**. Move the pointer over a destination: a green preview means the whole group fits; red means something blocks it. Click to place, press **R** to rotate the preview clockwise, or **Escape** to cancel. The destination tile is the lower-left of the group's bounding rectangle. A failed placement changes nothing, so you can try another location. Existing components aren't overwritten; water, trees and other placement restrictions still apply.

**Move Selection** uses the same preview but removes the originals only after the entire destination is valid. **Rotate** turns a selected group in place around its lower-left bounding corner; if it won't fit, nothing changes. Directions, repeater delays, Output modes and saved ON lever positions travel with the group. **Erase Group** removes components while preserving terrain. **Clear** removes the selection.

Click the canvas before using keyboard shortcuts:

| Shortcut | Action |
| --- | --- |
| Command-A | Select all components (up to 4096) |
| Command-C / Command-V | Copy / paste circuit components |
| Command-Z / Command-Shift-Z | Undo / redo |
| R | Rotate selection or placement preview |
| Delete | Erase selected components |
| Escape | Clear selection and cancel placement |

Circuit copies use a private macOS clipboard type. They contain configuration, not Finder paths, script contents, permissions, textures or runtime power. Copy in one editor, select another world and paste there. Text fields retain ordinary text shortcuts.

## Undo and redo

The right panel's **Undo** and **Redo** buttons reverse terrain strokes, component placement, erasure, inspector configuration and group operations. A terrain stroke, group move, paste, rotation or deletion is one undo step. History belongs to each world and lasts for the current app session. It holds up to 100 operations, additionally bounded by 50,000 changed cells across multiple operations. A new edit clears redo.

Undo doesn't reverse camera movement, world/area creation or deletion, blueprint shelf deletion, permissions, or desktop runtime inputs. It is disabled for a running world's circuit, seed previews and test mode. Successful edits and undo/redo use normal autosaving; quitting clears history but preserves the resulting circuit.

## Blueprints and examples

Select a circuit and choose **Save Selection as Blueprint…**, give it a name and Save. Open the **Blueprints** tab to place it in any world. Right-click a saved blueprint to delete it; placed circuit copies are unaffected. Blueprints persist after quitting.

Eight examples are included, including **Switched Pulse Generator**, whose lever enables and disables its clock. See [BLUEPRINTS.md](BLUEPRINTS.md) for the browser, all examples and editor context menus. Place them on clear ground to the right of your existing builds, then use Test Circuit. Press button examples, toggle lever examples, or click a detector to simulate occupancy. Example Outputs use **Do Nothing**. You can deliberately change a placed Output's mode later to connect real desktop actions.

Blueprints are limited to 4096 components in a 256 by 256 tile bounding rectangle. Up to 128 can be saved, with a 2 MB library limit. Storage is `~/Library/Application Support/RedstoneDesktop/blueprints.json`, written atomically and validated before loading. An unreadable file is preserved and shelf writes are blocked rather than replacing it.

**Export Library** exports placed circuits in worlds, but not the separate blueprint shelf. Keep `blueprints.json` with your own backups if you want to preserve the shelf. Start Over's recovery backup includes this file in its full Support folder backup, and resetting clears it. See [RECOVERY.md](RECOVERY.md); owner acceptance of backup/reset remains pending.

## Contributor boundaries

`EditorCircuitTest` owns a simulator copy and exposes power/pulse counters only; it has no executor or Finder dependency. The editor session owns its independent scheduler, stops it on exit and invalidates a test when its source changes. Renderer feedback consumes those events without executing actions.

`CircuitBlueprint`, `BlueprintPlacement` and `CircuitEditHistory` are pure Foundation domain code. Group placement validates a working copy before publication. History stores sparse before/after component deltas and touched lever states, checks for conflicting component changes and preserves unrelated state. AppState performs validated publication/autosaving. AppKit's `EditorCircuitClipboard` is the only clipboard adapter. All selection, marquee and preview coordinate conversion uses CoordinateMapper.
