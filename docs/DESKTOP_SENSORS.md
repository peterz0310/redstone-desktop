# Desktop pressure plates and file sensors

These two inputs turn Finder item positions into circuit power. They do not move, read the contents of, open or execute the detected item. Connect them to dust, repeaters, torches and Outputs as usual.

## Pressure plates

Choose **Plate** in the editor or tool **8 Plate** in Desktop Build Mode. A plate supplies strength 15 on every side while at least one Finder item center occupies its tile. Files, folders, applications and aliases count. Multiple items on the same tile keep it powered. Removing the last item turns it off on the next simulation tick after Finder reports the change.

This is a desktop item pressure plate, not a mouse-hover or mouse-click detector. Finder still handles selecting and dragging the icon normally. Detection uses the icon's mapped center, not the entire icon/label rectangle or cursor position during an unfinished drag.

## File sensors

Choose **Sensor**, or tool **9 Sensor** in Desktop Build Mode. Sensors have three choices:

- **Any item:** behaves like a plate.
- **File extension:** for example `pdf` or `.pdf`. Matches ordinary files, ignoring case; folders, applications and aliases are excluded from extension matching.
- **Item name:** full filename including extension, for example `Notes.txt`, or a folder name like `Inbox`. Matching ignores case and uses the actual filename even when Finder hides its extension. It is an exact name, not a wildcard, regular expression or path.

Set the filter for a new sensor, or click an existing one with Move and edit its Inspector. In Desktop Build Mode, clicking an existing sensor selects it even if placement reports that the tile is occupied; edit the filter in the palette. Valid filter changes save immediately. An unfinished/empty name or extension stays a draft and leaves the stored filter unchanged. Values are limited to 255 UTF-8 bytes. Erase, undo/redo, copy, rotation, blueprints, world exports/imports and save/reopen preserve the configuration.

If multiple icons occupy a sensor tile, any matching item keeps it powered. Replacing one matching file with another while detection remains true does not create a new pulse. This is a held presence signal, not a file-arrival event counter. It does not monitor contents, modifications, downloads outside that tile or recursive folder contents.

## Timing and permissions

Start Desktop with the intended area assigned. Sensors use the existing `DesktopItemProviding` Finder reads and CoordinateMapper mapping. Production automatic polling requests a read about every 500 ms; a slow Finder read adds latency. Simulation applies the latest successful mapped snapshot at 20 Hz. No Apple Events or filesystem reads are added to the simulation tick.

Finder Automation permission is required, as for existing desktop actions. Unread, failed, frozen, unstable/display-settling or more-than-two-second-old snapshots make detector inputs OFF. Restoring a valid occupied snapshot can create a new rising edge. Pause freezes simulation; Resume uses the latest snapshot. Stop discards detector power, and editing a different world does not reassign Desktop. Multi-display sensors use the same documented occupancy mapper and ignore physical display gaps.

**Starting Desktop with an item already on a detector can immediately activate connected Outputs.** Recovery after unavailable reads can also activate them. First try with Outputs set to **Do nothing**, then use a harmless folder on an Output when ready to test opening. Execution remains exclusively in the existing Output adapter, with fresh target resolution and normal script approval. Detected files are never executed merely because they match a sensor.

## Try without moving real files

Click **Test Circuit**, then click a plate or sensor to toggle simulated occupancy ON/OFF. This deliberately bypasses the sensor filter to let you test the wiring; it does not query Finder. Pause/Step, power paths and Output pulse counts work normally. Reset clears simulated detection. Test detection is never saved, and editor test mode never runs desktop actions.

## Contributor contract and artwork

`FileSensorFilter` and `DesktopSensorInputs` operate on immutable metadata/mapped snapshots. `CircuitSimulator.setDesktopSensors` accepts only a set of component coordinates and filters out nonsensor tiles; the domain simulator has no Finder, AppKit, SpriteKit or executor dependency. Both detector types broadcast 15; dust attenuation, repeater delay, torch inversion and Output rising edges are unchanged. The runtime adapter checks availability/freshness before supplying inputs. No detector power is persisted.

The component decoder defaults older configurations to Any item. Invalid filter payloads fail validation before placement/publication, including world and blueprint loading. Old app versions cannot decode the new component kinds; retain a library backup when downgrading.

Four optional pack texture IDs are supported: `redstonePlateOff`, `redstonePlateOn`, `redstoneSensorOff`, `redstoneSensorOn`. Original code-drawn art is the default and fallback for existing packs/Java imports; no re-import is required. Toolbar icons use public SF Symbols. No new Minecraft artwork is bundled, and no pack code is executed.
