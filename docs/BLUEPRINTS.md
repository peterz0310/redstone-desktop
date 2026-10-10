# Blueprint browser and examples

The editor's right sidebar has **Build** and **Blueprints** tabs. Build contains tools and the component Inspector. Blueprints contains your saved circuits, layout previews, example circuits and the Save Selection action. Undo/Redo remain above both tabs.

## Save and reuse your circuits

In Build, choose Select and drag around the components you want. Switch to Blueprints and choose **Save Selection as Blueprint…**. Name it and Save. You can also right-click a selected component/group and choose that action; it opens the Blueprints tab and save dialog.

Click a preview card, move the pointer over clear ground, and click to place. **R** rotates the placement preview; **Escape** or Cancel Placement cancels. Green means the whole circuit fits. Painting a Grass patch with Terrain can make room for larger examples. Place new demonstration circuits to the right of your existing builds.

Right-click a saved preview to **Rename Blueprint…** or **Delete Blueprint**. Renaming keeps the template's identity/configuration, and deleting it doesn't remove already placed copies. Names and layouts persist across restarts. Placement is disabled while that world is running, in seed previews or in Test Circuit.

Previews are static layout diagrams using original artwork. They show positions and orientations, not simulated power or your imported texture pack. Blueprints copy components/settings and saved lever positions, not terrain, file contents, paths or approvals. Existing limits and separate shelf backup/export rules are in [EDITOR_TOOLS.md](EDITOR_TOOLS.md).

## Example circuits

Every example Output is set to **Do Nothing**. Test them with Test Circuit before deliberately configuring real desktop actions.

| Example | How to use it |
| --- | --- |
| Delayed Button | Press its button; a four-redstone-tick repeater delays the Output. |
| Toggle Switch | Its lever holds the Output on until switched off. |
| Pulse Generator | Runs continuously without a switch. |
| Switched Pulse Generator | Lever ON enables the clock; OFF disables it. Allow about two seconds for old delayed signals to settle. |
| Inverted Switch | The Output is on when the lever is off, and off when the lever is on. |
| Either Button | Either of its two buttons activates the shared Output. |
| PDF Detector | Detects a PDF file on the sensor tile; in Test Circuit click the sensor to toggle simulated detection. |
| Desktop Plate | An item on the plate powers the Output; in Test Circuit click the plate to toggle simulated detection. |

The switched clock uses a separate control torch, rear repeater and isolated return wire. Its lever enables oscillation without powering the Output continuously. It uses the existing documented port/timing model; no special clock simulation rule was added. Torches start ON, so it can produce a brief startup pulse even with its switch OFF; after settling it remains off until enabled. Reset in Test Circuit restarts that initialization. Output action None keeps examples action-free during desktop use too.

## Tool help and editor right-click menus

Hover any build tool to read its description. The selected tool's description stays below the tools in both the editor and Desktop Build Mode.

Right-clicking the editor map selects/inspects without placing, erasing or pressing an input. Menus include relevant actions:

- Component: Inspect, Copy, Save Selection as Blueprint, Move Selection and Delete.
- Repeater/torch: Rotate Clockwise; repeaters also offer all four delays.
- Selected group: Move, Rotate and Delete operate on the group. The delete label shows its component count.
- Decoration: Remove the named scenery, with terrain undo support.
- Painted terrain: Restore Original Terrain, preserving components that need the edited surface.
- Empty ground: Paste a copied circuit.

Delete removes app components/scenery; it never deletes or opens Finder files. Mutating actions are disabled during tests, seed previews or when the world is locked. Menu dispatch rechecks the selected world and action availability, so a stale menu cannot edit a different world. Inspector opens Build; saving opens Blueprints. Undo reverses group changes and terrain cleanup as usual.

## Contributor notes

Example templates use stable IDs and pure component configurations, validated and simulated in automated tests. Switched-clock tests prove OFF settles, ON pulses, OFF stops and ON restarts for all four rotations. Rename saves atomically before publishing and preserves the previous template on failure.

`BlueprintPreviewImage` draws bounded cached AppKit thumbnails through CoordinateMapper, with no Finder/executor dependency or SpriteKit render loop per card. Editor context action options are separate from the native menu adapter; commands revalidate before touching AppState. Right-click selection cancels unfinished placement/terrain previews rather than committing them.
