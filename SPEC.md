# Redstone Desktop — SPEC.md

> Working title: **Redstone Desktop**
>
> A native macOS experiment that turns the desktop into a persistent, seeded, top-down block world with redstone-inspired logic. Finder desktop items remain real Finder items, but their physical screen positions can participate in circuits. A button can power redstone, a repeater can delay it, and an output can open or explicitly execute the Finder item sitting over that output tile.

---

# 0. How to use this document

This file is the source of truth for the project.

The intended workflow is:

1. Start with an empty folder.
2. Give an AI coding agent this file.
3. Have the agent implement the roadmap in order.
4. Finish one small, testable slice at a time.
5. Run automated tests after every slice.
6. Perform the listed manual checks on the real Mac before marking integration work complete.
7. Commit after meaningful slices.
8. Update this spec when real macOS behavior contradicts an assumption.

The project is an experiment first and a polished application second.

Current implementation: Slices 0–19A have owner-confirmed acceptance. **Slices 19B–23 are implemented.** The 19C bookmark/context-menu follow-up is owner-accepted; Slices 20–21 now have owner-reported acceptance; earlier specific 19B/19C runtime/deletion checks remain pending. The owner requested 19C usability cleanup after tentative 19B feedback. Worlds now have a sidebar; area previews sit below the canvas; creation/rename/save/deletion use focused sheets. Atomic deletion protects active/final records and preserves configuration on failure. Library, fixed-seed world and explicit saved-area activation contracts remain intact. Slice 20 adds explicitly enabled Finder projections and Output snapping in the editor; Slice 21 adds primary-display change handling with preserved lower-left camera anchoring. Slice 22 adds read-only icon-size detection and settled center refresh; its Mac checks remain pending. Slice 23 adds optional, reversible Finder scale synchronization; Mac acceptance remains pending. Audio foundation is next in **Slice 24**. Historical entries record earlier behavior; Sections 3.8, 7.1, 25 and 29 define the current contract.

The most important early question is not whether attractive terrain or redstone can be made. Those are comparatively straightforward. The first major feasibility gate is:

> Can a native macOS app render a click-through block world visually beneath Finder desktop icons, track the real icon positions, observe a click on a world button without breaking Finder, propagate a signal, and activate the Finder item occupying an output tile?

Do not spend significant time on polish until that entire vertical slice works.

---

# 1. Product vision

The macOS desktop should feel as though a top-down block world exists underneath Finder.

Example:

```text
             real Finder item
                    ↓
                 build.sh
                    📄
                    │
🟩 🟩 🟥 🟥 🟥 🔁 🟥 ⬛ 🟩
          redstone       output
```

Pressing a world button can do this:

```text
[BUTTON] → dust → repeater → dust → output
```

When the signal reaches the output, the app checks which real Finder desktop item currently occupies that output tile.

If it is `build.sh`, the output may execute it when that output is explicitly configured for execution.

If the user drags `build.sh` away and moves a Safari alias over the same output, the circuit now targets Safari.

Finder remains the real desktop. The application does not replace Finder, clone its files, or draw fake functional icons.

The world should eventually support:

- deterministic seed-based terrain
- editor pan/zoom and seed exploration
- independent saved worlds with fixed seeds and their own circuits
- named saved areas within each world
- a chosen persistent desktop viewport, explicitly activated from the area list
- terrain that constrains circuit placement
- buttons
- levers
- redstone dust
- repeaters
- outputs
- later: a simplified torch/inverter
- Finder-item occupancy
- opening Finder occupants
- explicitly authorized script execution
- hover/block highlighting under the cursor
- sound effects and optional stereo panning
- original built-in assets
- custom resource packs
- optional local Minecraft Java asset importing
- display/Finder resizing resilience
- later: continuous multi-monitor world

---

# 2. Distribution assumptions

This is a personal/open-source hobby project.

Expected distribution:

- source on GitHub
- possibly prebuilt GitHub releases later
- no Mac App Store requirement
- no paid product requirement
- possible GitHub Sponsors/donation link later
- project must work without Minecraft installed
- project must work without copyrighted Minecraft assets

Do not make App Sandbox compatibility a design requirement.

Signing/notarization is desirable for public binaries later, but not needed for the first prototype.

---

# 3. Core design principles

## 3.1 Finder remains Finder

Do not replace the macOS desktop.

Do not fake Finder icons.

Do not move user files just to make the wallpaper work.

Do not capture normal desktop clicks unless the user has explicitly entered a build/edit mode that requires it.

The app observes Finder and renders beneath it.

## 3.2 World space and screen space are separate

The system has three important coordinate spaces:

```text
WORLD SPACE
persistent tile coordinate, e.g. (-142, 81)
        ↓ camera transform
SCREEN SPACE
macOS global logical points
        ↓ observation
FINDER ITEMS
real Finder icons at real screen positions
```

Every conversion must go through one tested coordinate service.

No subsystem may invent its own Y-axis flip, scale calculation, or Finder offset.

## 3.3 The world is deterministic

Given:

- generation version
- seed
- world coordinate

base terrain must be reproducible.

Do not persist generated terrain tile-by-tile.

Persist:

- seed
- generation version/settings
- camera
- circuit
- optional user terrain overrides later

## 3.4 Rendering is not simulation

The redstone simulation must work without SpriteKit.

Tests must be able to run circuits entirely in memory.

SpriteKit renders state; it does not define state.

## 3.5 Finder integration is an adapter

Use an abstraction such as:

```swift
protocol DesktopItemProviding {
    func currentDesktopItems() async throws -> [DesktopItem]
}
```

The circuit simulator must never know about AppleScript, Finder, Apple Events, or Accessibility APIs.

## 3.6 Actions are separate from simulation

The simulator emits an output activation event.

A separate action layer decides what to do.

The renderer must never directly launch files or scripts.

## 3.7 Prove risky integration first

Do not start by perfecting procedural terrain.

First prove:

- desktop window layering
- coordinate mapping
- cursor mapping
- click observation
- Finder positions
- Finder occupancy
- output action

Then build the game layer.

## 3.8 Worlds own components; areas bookmark views

A **world** has a stable UUID, name, fixed generation settings, terrain profile and one circuit dictionary keyed by world coordinates. Its lever positions are durable. The seed determines terrain; it is not world identity. Independently created worlds may share a seed without sharing components.

A **saved area** has its own UUID, name, world ID and desktop camera. It bookmarks a view into that world. It owns no components or cropped circuit snapshot. Overlapping areas in the same world see the same components; editing either view changes that world's circuit. Moving the camera never moves or duplicates components.

The **library** stores worlds, saved areas and one active area ID. Editor selection is independent of this active desktop selection. Browsing or editing an inactive world never activates it. **Activate on Desktop** explicitly selects which saved area is used by desktop rendering, input, simulation and actions. Enabling/disabling Desktop World controls whether that selection is running.

Fresh worlds begin with an empty circuit and procedural terrain. Preserve the prototype fixture only in the migrated world. Do not copy a user's existing components, fixture patches or lever positions into a new world.

---

# 4. Technology choices

## 4.1 Language

Use **Swift**.

Do not use Electron, React Native, Unity, Godot, a web server, or a JavaScript runtime.

## 4.2 App UI

Use:

- **SwiftUI** for editor/settings/inspectors
- **AppKit** for desktop windows, application integration, event monitoring, and other macOS-specific work

Do not force an AppKit requirement through awkward SwiftUI wrappers if AppKit is simpler.

## 4.3 World renderer

Use **SpriteKit** for V1.

Reasons:

- native macOS framework
- efficient 2D rendering
- sprites and tile-like visuals are easy
- nearest-neighbor pixel art is straightforward
- animation and particles are available
- significantly less complexity than Metal

Do not begin with Metal.

## 4.4 Audio

Use **AVFoundation**.

Start simple. Introduce an `AVAudioEngine`-based abstraction when stereo panning/mixing is implemented.

## 4.5 Persistence

Use Codable JSON.

Do not begin with Core Data or SwiftData.

## 4.6 Testing

Use XCTest.

At minimum, heavily test:

- coordinate mapping
- world generation
- placement rules
- circuit simulation
- occupancy mapping
- persistence
- resource-pack validation

## 4.7 Xcode project setup

Prefer a text-defined project suitable for AI editing.

Recommended:

- XcodeGen
- `project.yml`
- generated `.xcodeproj`

XcodeGen is only a development dependency.

If unavailable, a conventional Xcode project is acceptable, but project creation must still be deterministic and documented.

---

# 5. Current macOS API assumptions to validate

These are assumptions to spike, not guarantees to blindly rely upon.

## 5.1 Desktop-level rendering

Current macOS/SwiftUI exposes a desktop window level intended to appear just above wallpaper and behind other content.

Requirement:

> The world is visibly above wallpaper but below Finder desktop icons.

An AppKit `NSWindow` implementation is acceptable if it provides more control.

## 5.2 Mouse position

Use `NSEvent.mouseLocation` for global pointer position.

Hover must not require the renderer window to receive mouse events.

## 5.3 Global click monitoring

Use `NSEvent.addGlobalMonitorForEvents` for normal-mode observation where suitable.

A global monitor observes events delivered to other applications; it does not consume or modify them.

That is desirable because Finder should still receive clicks.

Do not make global keyboard shortcuts a V1 requirement. Key monitoring may involve Accessibility permissions.

## 5.4 Display changes

Slice 21 uses the primary display (`NSScreen.screens.first`), not focus-dependent `NSScreen.main`. Re-read descriptors on the public [screen-parameter notification](https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification); Apple documents the [primary versus focused screen distinction](https://developer.apple.com/documentation/AppKit/NSScreen/screens). V1 still renders one display; choosing arbitrary displays/continuous multi-monitor worlds remains later work.

Anchor policy: preserve the saved CameraState lower-left world origin and logical pointsPerTile exactly on resolution, scaling, origin, primary-display replacement or mirroring changes. Only the visible world extent changes; backing scale affects rendering density, not tile math. Saved area records and editor pan/zoom are unchanged. Finder may rearrange icons, so an icon is not guaranteed to stay on its previous tile.

Handle changed target/reference snapshots immediately: invalidate old Finder results and input/output session work, clear stale occupancy/highlights, recreate the click-through renderer and pointer/click monitors, and rebind the tick scheduler while retaining the current simulator (including pulse/repeater/lever state). Identical geometry notifications are no-ops. Simulation continues during settling, but input/output actions are suppressed and rising edges during that interval are dropped, never replayed. An existing held output is not retriggered by rebuilding the renderer.

Coalesce Finder refreshes for 500 ms after the last change. Preserve the shared read gate, discard earlier in-flight diagnostic/poll/input/output results using a geometry generation, and wait for old noncancelable reads to release it. Refresh only if Desktop is running or editor tracking is explicitly enabled, the display/reference exist, and access was not denied. Resume opted-in serialized polling after a successful refresh; read failures remain unavailable with diagnostics/retry. Display notifications alone never prompt/query Finder at disabled startup.

If no usable display is available, stop the renderer/input/ticks and leave Desktop disabled without changing saves. When a display returns, editor tracking may refresh if enabled, but Desktop requires explicit Start. Ordinary primary-display replacement falls back to the newly reported primary display with the same camera. Full shutdown cancels the delayed refresh/observer. Real resize/unplug/replug/layering/alignment remain owner checks.

Observe `NSApplication.didChangeScreenParametersNotification`.

Display changes trigger recalculation of:

- screen geometry
- renderer windows
- coordinate transforms
- Finder mappings

## 5.5 Opening files/apps

Use `NSWorkspace` for ordinary open/launch behavior.

Use `Process` only for explicit execution mode.

## 5.6 Finder automation

Initial provider: Apple Events / AppleScript querying Finder desktop items and `desktop position`.

The app must handle macOS Automation permission explicitly.

Do not assume access.

---

# 6. Suggested repository structure

```text
/
├── SPEC.md
├── README.md
├── CHANGELOG.md
├── LICENSE
├── .gitignore
├── project.yml
├── RedstoneDesktop/
│   ├── App/
│   │   ├── RedstoneDesktopApp.swift
│   │   ├── AppDelegate.swift
│   │   ├── AppState.swift
│   │   └── DependencyContainer.swift
│   ├── Desktop/
│   │   ├── DesktopWindowController.swift
│   │   ├── DesktopWindowCoordinator.swift
│   │   ├── DesktopScene.swift
│   │   ├── ScreenDescriptor.swift
│   │   ├── CoordinateMapper.swift
│   │   ├── PointerMonitor.swift
│   │   ├── DesktopClickMonitor.swift
│   │   └── DisplayChangeMonitor.swift
│   ├── FinderIntegration/
│   │   ├── DesktopItem.swift
│   │   ├── DesktopItemProviding.swift
│   │   ├── FinderDesktopItemProvider.swift
│   │   ├── FinderScriptRunner.swift
│   │   ├── FinderViewSettings.swift
│   │   └── DesktopItemTracker.swift
│   ├── World/
│   │   ├── World.swift
│   │   ├── WorldCoordinate.swift
│   │   ├── Tile.swift
│   │   ├── Terrain.swift
│   │   ├── Decoration.swift
│   │   ├── CameraState.swift
│   │   ├── WorldGenerator.swift
│   │   ├── Noise.swift
│   │   └── ChunkCache.swift
│   ├── Circuit/
│   │   ├── CircuitWorld.swift
│   │   ├── CircuitComponent.swift
│   │   ├── CircuitSimulator.swift
│   │   ├── PowerLevel.swift
│   │   ├── Direction.swift
│   │   ├── PlacementRules.swift
│   │   └── Components/
│   ├── Actions/
│   │   ├── OutputAction.swift
│   │   ├── ActionExecutor.swift
│   │   ├── DesktopOccupancyResolver.swift
│   │   ├── OpenItemAction.swift
│   │   ├── ExecuteScriptAction.swift
│   │   └── ActionAuthorizationStore.swift
│   ├── Rendering/
│   │   ├── WorldRenderer.swift
│   │   ├── TileRenderer.swift
│   │   ├── CircuitRenderer.swift
│   │   ├── HighlightRenderer.swift
│   │   └── RenderMetrics.swift
│   ├── Assets/
│   │   ├── AssetProvider.swift
│   │   ├── AssetID.swift
│   │   ├── BuiltInAssetProvider.swift
│   │   ├── ResourcePack.swift
│   │   ├── ResourcePackLoader.swift
│   │   └── MinecraftImport/
│   ├── Audio/
│   │   ├── AudioEngine.swift
│   │   ├── SoundID.swift
│   │   └── SoundEvent.swift
│   ├── Editor/
│   ├── BuildMode/
│   ├── Persistence/
│   │   ├── WorldDocument.swift
│   │   ├── WorldLibraryDocument.swift
│   │   ├── SavedArea.swift
│   │   ├── WorldLibraryStore.swift
│   │   └── WorldAutosaver.swift
│   ├── Diagnostics/
│   └── Resources/
└── RedstoneDesktopTests/
```

Exact filenames may evolve, but preserve subsystem boundaries.

---

# 7. Runtime architecture

```text
                         ┌────────────────────┐
                         │ Finder / macOS     │
                         └─────────┬──────────┘
                                   │
                          desktop item data
                                   ▼
                        DesktopItemTracker
                                   │
                                   ▼
┌───────────┐      ┌─────────────────────────┐
│ Pointer   │─────▶│ CoordinateMapper        │◀──── CameraState
└───────────┘      └────────────┬────────────┘
                               │
                         world coordinates
                               │
              ┌────────────────┼─────────────────┐
              ▼                ▼                 ▼
         World model      CircuitWorld   OccupancyResolver
              │                │                 │
              └────────┬───────┘                 │
                       ▼                         │
                CircuitSimulator                 │
                       │                         │
               output rising edge───────────────┘
                       │
                       ▼
                 ActionExecutor

World + circuit + highlight state
                       │
                       ▼
                 WorldRenderer
                       │
                       ▼
                 SpriteKit scene
```

---

## 7.1 Library, editor selection and desktop runtime

Library → editor-selected world + temporary editor camera → editor renderer.

Library → active saved area → its world + saved desktop camera → desktop renderer, input, simulator, occupancy and actions.

Keep these paths independent. Pure library/world/area values use Foundation/Swift only. Finder reads go through DesktopItemProviding and screen conversion through CoordinateMapper. SpriteKit receives snapshots, never storage ownership or action execution responsibilities.

While Desktop World runs, simulate the **entire finite circuit dictionary of the active world**, including offscreen components. Do not clip connected circuits to an area rectangle or invent per-area simulators. Inactive worlds have no running simulation. Render only the visible region. Dispatch desktop actions only for output tiles whose mapped centers lie within the active physical desktop canvas; offscreen events do not queue an action for a later visit. Crossing a viewport edge does not break a wire. Fixed-path actions added later obey the same visibility gate. Do not simulate generated terrain.

Each input/read/output operation is scoped to the active world ID and a runtime session token. Changing the active area, including a move within the same world, cancels pending work and creates a new session. Never apply an old completion to a new world with coincident tile coordinates. No catch-up simulation or replay of inactive-world events.

Activation preflights the target world, saved camera and available display, then successfully flushes pending library configuration with the new active area ID before stopping the old runtime. Validation/save failure leaves the old active selection/runtime intact and reports an actionable error. After a successful save, shut down old monitors/timers/actions, restore the target's durable lever positions into a fresh simulator, rebuild desktop mapping/rendering, clear transient highlights/pulses/history, and refresh Finder through the serialized tracker. If rendering cannot start after that commit, leave Desktop World disabled with an error and the saved target selected; never report a running desktop or silently resume the previous world.

Activation preserves the enabled/disabled state: switching while enabled runs the target, switching while disabled prepares it for the next explicit enable. Re-activating the exact same world/camera updates/saves the active area ID if selecting a different bookmark, but is a runtime no-op after pending edits are saved: it does not reset a held circuit or re-open an output. Enabling or switching to a different area can produce a new output rising edge from a saved ON lever, as in the current lifecycle; document this in the Mac walkthrough. Startup always restores selection with Desktop World disabled and no Finder query/action.

# 8. Coordinate system

## 8.1 Tile coordinates

```swift
struct WorldCoordinate: Hashable, Codable, Sendable {
    var x: Int
    var y: Int
}
```

World coordinates are conceptually unbounded.

## 8.2 Continuous world points

```swift
struct WorldPoint: Codable, Equatable {
    var x: Double
    var y: Double
}
```

One world unit equals one tile.

## 8.3 Camera

```swift
struct CameraState: Codable, Equatable {
    var worldOrigin: WorldPoint
    var pointsPerTile: Double
}
```

Define `worldOrigin` once and never ambiguously.

Recommended definition:

> The world coordinate corresponding to the lower-left corner of the virtual desktop canvas.

## 8.4 Use logical screen points

World mapping operates in macOS logical points, not backing pixels.

Retina backing scale must not alter which world tile an icon occupies.

## 8.5 Transform

Conceptually:

```text
worldX = originX + ((screenX - canvasMinX) / pointsPerTile)
worldY = originY + ((screenY - canvasMinY) / pointsPerTile)
```

Inverse:

```text
screenX = canvasMinX + ((worldX - originX) * pointsPerTile)
screenY = canvasMinY + ((worldY - originY) * pointsPerTile)
```

Any coordinate-system Y flip belongs inside `CoordinateMapper` only.

## 8.6 Tests

Required:

- world → screen → world round trip
- screen → world → screen round trip
- negative world coordinates
- negative global screen origins
- multiple scales
- exact tile boundaries
- points just to either side of boundaries
- changed display arrangement

---

# 9. Screens and virtual canvas

Never assume the main screen begins at `(0, 0)`.

macOS displays can have negative coordinates and arbitrary arrangements.

V1:

- fully support one active display
- architect for multiple displays

Later continuous multi-display mode:

- one shared world/camera/simulator
- one renderer window per physical screen
- each renderer draws the correct sub-viewport

Do not create one simulation per monitor.

---

# 10. Desktop renderer window

Requirements:

- borderless
- visually above wallpaper
- visually below Finder icons
- click-through in normal mode
- not a normal document window
- resizes with its screen
- easy to enable/disable during development

Prefer:

```swift
window.ignoresMouseEvents = true
```

or equivalent normal-mode behavior.

Finder usability always wins over world interaction.

Spaces, Mission Control, and Stage Manager behavior must be tested and documented rather than guessed.

Do not use private APIs merely to force perfect behavior.

---

# 11. Finder integration

## 11.1 Model

```swift
struct DesktopItem: Identifiable, Equatable, Sendable {
    var id: String
    var url: URL
    var displayName: String
    var position: CGPoint
    var estimatedIconSize: CGSize?
    var kind: DesktopItemKind
}
```

Prefer a file resource identifier for stable identity when available, with normalized URL/path fallback.

Never use display name alone as identity.

## 11.2 Finder coordinate calibration

Do not assume what Finder's `desktop position` means.

Create a diagnostic overlay showing:

- raw Finder coordinate
- transformed screen coordinate
- derived icon center
- derived world tile
- a visible marker behind the real icon

The human must confirm alignment.

## 11.3 Polling

Initial acceptable strategy: poll Finder.

Suggested rates:

- idle: 2–4 Hz
- while drag-like movement is detected: up to ~10 Hz if necessary

Never query Finder every render frame.

Never allow AppleScript requests to pile up concurrently.

If one query is still running, skip/defer the next.

## 11.4 Change detection

Publish meaningful differences only:

- added
- removed
- moved
- renamed/path changed

Do not rebuild the whole world because an identical Finder poll completed.

## 11.5 Occupancy rule

Default rule:

> A Finder item occupies the world tile containing the icon's visual center.

Pipeline:

```text
Finder item
→ screen center
→ CoordinateMapper
→ continuous world point
→ floor to tile coordinate
```

This remains the rule when Finder icon size changes.

## 11.6 Multiple icons on one tile

If several items map to the same output tile:

- mark output ambiguous
- do not execute a script
- inspector lists items
- future UI may let user choose explicitly

Never choose an executable target arbitrarily.

---

# 12. Finder icon size vs world zoom

These are separate values.

```text
WORLD TILE SIZE
CameraState.pointsPerTile

FINDER ICON SIZE
controlled by Finder

FINDER GRID SPACING
controlled by Finder
```

Never assume one Finder icon equals exactly one world tile.

When Finder icon size changes:

1. wait briefly for Finder to settle
2. refresh all item positions
3. recompute centers
4. recompute world occupancy
5. redraw output states

## 12.0 Slice 22 read-only settings and settled positions

Use Finder's installed public scripting dictionary: `icon size` on `icon view options` of `desktop window`. Capture the setting before/after item positions in the same query, through DesktopItemProviding/FinderScriptRunning. Accept only bounded positive integral settings; unsupported/missing optional values leave item tracking usable. No reading undocumented Finder preference files, private APIs, setting mutations, icon-size offsets or assumptions about grid spacing. `estimatedIconSize` stays nil: the raw setting is not a proven per-item visual/hit rectangle.

The diagnostic model compares successful known size samples. When they differ from the previous setting, or change inside one snapshot, invalidate published positions/occupancy, mark layout settling, and retain the shared read slot while waiting 500 ms and querying again. If size changes again, repeat the wait/read until a stable sample. Do not publish intermediate centers. Cancellation, display invalidation and read failure cannot publish the interrupted layout. Optional settings unavailable means ordinary 2 Hz position refresh continues, without claiming size-change detection.

Track a layout generation so an input/output operation begun before a detected resize cannot activate after that read, even when the final read succeeds. Drop queued/new output edges while settling; no held-output replay. Simulator, active world/area, all saved cameras and editor zoom remain unchanged. Fresh user input after settlement uses actual refreshed occupancy through the existing separate action executor.

Publish current optional view settings and retain the first successful stable setting as an optional **session-only baseline** for future synchronization. Baseline is not stored in world/area/library JSON and does not control zoom in Slice 22. Diagnostics show current setting/baseline, settling/unavailable status and independent world scale. Startup remains disabled/read-free; polling and permission recovery retain the shared adapter/tracker. Persistent synchronization settings and anchor calculations are Slice 23.

## 12.1 Optional synchronized scale mode

Implemented as an optional experiment in Advanced → Desktop Details, off by default:

- Independent world scale
- Sync world scale to Finder icon size

Synchronized concept:

```text
newPointsPerTile =
  baselinePointsPerTile *
  currentFinderIconSize / baselineFinderIconSize
```

Preserve the world point at the physical desktop center via CoordinateMapper. Derive each effective camera from the active saved area camera and the captured baseline, never cumulatively from the previous zoom. Clamp to 16–128 logical points/tile. Turning sync off restores the saved camera exactly. Editor zoom/proposed bookmarks remain independent; the blue active viewport shows the actual transformed camera.

Enabling requires a successful stable Finder read with known size and captures that size as the experiment baseline. Mode and baseline persist in app preferences, separate from world/library JSON; tests inject isolated preferences. Restoring preferences never starts Desktop or reads Finder. Unknown metadata leaves the last safe camera in place. Switching areas uses the new saved camera with the same baseline. Scale changes rebuild renderer/input with the existing simulator, cancel old input/output requests and remap fresh icon centers; they never replay held outputs or save camera changes. Re-enable the experiment to establish a new baseline.

Because Finder may itself rearrange icons when icon size/grid spacing changes, always re-read actual positions afterward.

Do not promise that the same icon remains on the same block if Finder chose to move it.

---

# 13. Cursor highlighting

Use `NSEvent.mouseLocation`.

Every reasonable render/update interval:

```text
mouse screen point
→ active screen
→ CoordinateMapper
→ world point
→ world tile
→ highlight renderer
```

Normal-mode highlight must:

- not capture mouse input
- not activate app
- hide outside active desktop area
- be subtle

Build/editor mode may show stronger outlines and metadata.

Potential metadata:

```text
Grass
World: (-142, 81)
Circuit: Dust
Power: 12
Desktop occupant: build.sh
```

---

# 14. Interaction modes

## 14.1 Normal mode

- renderer click-through
- Finder works normally
- cursor highlights world tile
- global click observer can notice button/lever clicks
- circuits simulate
- outputs work

If a clickable circuit component lies beneath a Finder icon, prioritize Finder and ignore the world click.

## 14.2 Build mode

Post-MVP direct desktop editing.

Must be entered explicitly.

Possible controls:

- left click: place
- right click: erase
- scroll: hotbar selection
- number keys: hotbar slot
- escape/menu item: exit

Because global keyboard observation can introduce Accessibility permission, never make keyboard the only exit mechanism.

A temporary interactive overlay window may be used in Build Mode only.

## 14.3 Editor mode

Normal SwiftUI window with:

- seed browser
- pan/zoom
- terrain preview
- desktop viewport rectangle
- ghosted real Finder icons
- component palette
- inspector
- placement feedback
- camera controls
- resource-pack controls
- diagnostics

Editor camera and desktop camera are separate.

Panning, choosing a world/area and seed exploration must not move the actual wallpaper. After Slice 19B, **Save Area** bookmarks the proposed view and **Activate on Desktop** explicitly activates a saved area. No automatic live-preview mode is required. The Slice 19 **Use This Area** workflow is the earlier prototype behavior and is superseded by these controls.

---

# 15. Seeded procedural world

## 15.1 Goals

The world generator is inspired by block-game terrain but does not reproduce Minecraft generation.

It must be:

- deterministic
- fast
- lazy
- chunkable
- stable by generation version
- valid for negative coordinates

## 15.2 Own deterministic noise/hash

Do not rely on undocumented OS-version behavior for deterministic generation.

Use a project-owned seeded hash/PRNG/noise implementation.

## 15.3 Settings

```swift
struct WorldGenerationSettings: Codable {
    var generationVersion = 1
    var seed: UInt64
}
```

Additional generation controls can be added in a later version; the current generator exposes only version and seed. The UI exposes unsigned decimal UInt64 seed entry and Random while exploring a possible new world. Generation settings are fixed after creation; previewing another seed does not change an existing world. Generation version 1 fixes the remaining scales/thresholds in code.

## 15.4 Suggested generation layers

1. elevation noise
2. moisture noise
3. temperature/variation noise
4. biome selection
5. terrain tile selection
6. shoreline/transition data
7. decoration placement

Initial terrain:

- grass
- dirt variant
- stone
- sand
- shallow water
- deep water

Initial decoration:

- tree
- flower
- rock
- reed

Circuit state is separate from terrain/decorations.

## 15.5 Chunks

Suggested chunk size:

```text
32 × 32 tiles
```

Use mathematical floor division for negative coordinates.

Test this explicitly.

Cache only visible chunks plus a margin.

---

# 16. Terrain capabilities and placement

Terrain is behavior plus appearance.

Example:

```swift
struct TerrainDefinition {
    var id: TerrainID
    var isLiquid: Bool
    var isSolidSurface: Bool
    var supportsCircuit: Bool
    var supportsHeavyComponent: Bool
}
```

Initial behavior:

| Terrain | Solid | Dust allowed | Components allowed |
|---|---:|---:|---:|
| Grass | Yes | Yes | Yes |
| Dirt | Yes | Yes | Yes |
| Stone | Yes | Yes | Yes |
| Sand | Yes | Yes | Yes |
| Shallow water | No | No | No |
| Deep water | No | No | No |

Decorations may further block placement.

Initial policy:

- tree blocks placement
- rock blocks placement
- flower blocks placement instead of silently disappearing

Later tools may support clearing decorations.

Centralize placement:

```swift
protocol PlacementRuleEvaluating {
    func canPlace(
        component: CircuitComponentKind,
        at coordinate: WorldCoordinate,
        in world: WorldSnapshot
    ) -> PlacementResult
}
```

Possible failures:

```swift
enum PlacementFailureReason {
    case liquid
    case noSolidSurface
    case blockedByDecoration
    case circuitOccupied
    case invalidOrientation
    case reserved
}
```

Editor and Build Mode must use the same evaluator.

---

# 17. Redstone-inspired circuit model

This is a deterministic **2D redstone-inspired** system, not complete Minecraft redstone parity.

Explicitly do not implement initially:

- vertical wiring
- pistons
- observers
- quasi-connectivity
- repeater locking
- every Java/Bedrock difference
- historical update-order quirks

## 17.1 Initial components

Required V1:

- empty
- dust
- button
- lever
- repeater
- output

Next:

- simplified torch/inverter

## 17.2 Direction

```swift
enum Direction: String, Codable, CaseIterable {
    case north, east, south, west
}
```

## 17.3 Power

Use integer power `0...15`.

```swift
struct PowerLevel: Equatable, Comparable, Codable {
    var rawValue: UInt8
}
```

Clamp values.

## 17.4 Dust

Rules:

- N/E/S/W only
- receives strongest valid incoming power
- outgoing dust strength decreases by 1 per dust tile
- no diagonal connection
- no vertical connection
- renderer shape depends on neighbor connectivity

## 17.5 Lever

- click toggles off/on
- on emits 15 continuously
- state persists with world unless later setting changes this

## 17.6 Button

- momentary pulse
- recommended default: 20 simulation ticks = 1 second at 20 Hz
- pressing while active restarts pulse timer

## 17.7 Repeater

- directional
- rear input only
- forward output only
- restores signal to 15
- delay: 1–4 redstone ticks
- one redstone tick = 100 ms
- simulation at 20 Hz therefore delays are 2/4/6/8 simulation ticks

## 17.8 Output

Output does not propagate power.

On:

```text
unpowered → powered
```

emit exactly one activation event.

Holding power must not repeatedly launch something.

## 17.9 Torch/inverter later

Simplified NOT behavior only.

No burnout behavior in first version.

---

# 18. Circuit simulator

Run at a fixed cadence:

```text
20 simulation ticks/sec
1 tick = 50 ms
```

Rendering runs independently.

Use two-phase updates:

1. read current state
2. compute next state/events
3. commit next state

Do not let dictionary iteration order change logic.

Circuits may contain loops. Never recursively propagate without a bound.

Use a bounded queue/iterative algorithm that cannot hang the app.

Simulator emits domain events, e.g.:

```swift
enum CircuitEvent {
    case outputActivated(WorldCoordinate)
    case componentChanged(WorldCoordinate)
    case soundRequested(SoundEvent)
}
```

Simulator never calls AppKit launch APIs.

---

# 19. Desktop occupancy resolver

Pure/testable component:

```swift
struct DesktopOccupancy {
    var coordinate: WorldCoordinate
    var items: [DesktopItem]
}
```

Input:

- camera
- screen geometry
- Finder items

Output:

- world-coordinate occupancy lookup

Output visual state:

- empty
- occupied(item)
- ambiguous(items)
- unavailable(error/permission)

---

# 20. Output action model

```swift
enum OutputActionMode: Codable {
    case openOccupant
    case executeOccupant
    case fixedOpen(URLReference)
    case fixedExecute(URLReference)
    case none
}
```

Initial vertical slice needs only `openOccupant`.

## 20.1 Open occupant

Use normal macOS open behavior.

Expected examples:

- folder → Finder opens it
- document → default application
- app/alias → application launches
- web location → default browser where macOS resolves it

## 20.2 Execute occupant

Explicitly powerful feature.

Initial supported types can include:

- `.sh`
- `.command`
- `.zsh`
- optional `.py` using an explicitly selected interpreter

Never do this:

```text
/bin/zsh -c "<concatenated user path>"
```

Use an executable plus argument array.

No sudo.

Capture:

- stdout
- stderr
- exit code
- duration

## 20.3 Authorization

Recommended default:

- first execution of an exact path requires confirmation
- show resolved path
- allow “always allow this exact file”
- provide developer setting to bypass confirmations if user deliberately wants it
- bypass default is OFF

If target identity/path is ambiguous, refuse instead of guessing.

---

# 21. Asset architecture

The renderer must never directly hard-code asset file paths.

Use semantic IDs.

Examples:

```swift
enum TextureAssetID: String, Codable {
    case terrainGrass
    case terrainDirt
    case terrainStone
    case terrainSand
    case waterShallow
    case waterDeep
    case decorationTree
    case decorationFlower
    case decorationRock
    case redstoneDustOff
    case redstoneDustOn
    case redstoneRepeater
    case redstoneButton
    case redstoneLeverOff
    case redstoneLeverOn
    case redstoneOutputEmpty
    case redstoneOutputOccupied
    case cursorHighlight
}
```

Actual dust rendering may later use a structured connection-state ID rather than one enum case per variant.

Provider:

```swift
protocol AssetProvider {
    func texture(for id: TextureAssetID) -> SKTexture?
    func soundURL(for id: SoundID) -> URL?
}
```

Resolution order:

```text
active custom/imported pack
    ↓ fallback
built-in original pack
```

The repository must include its own complete original/placeholder pack.

Use nearest-neighbor texture filtering.

Initial source art can be crude. Do not block engineering on art quality.

---

# 22. Resource packs

Support user-selected folder or ZIP packs.

A pack can override only some assets.

Suggested layout:

```text
MyPack/
├── pack.json
├── textures/
│   ├── terrain/
│   ├── circuit/
│   └── ui/
└── sounds/
```

Example manifest:

```json
{
  "formatVersion": 1,
  "name": "Example Pack",
  "author": "Example",
  "assets": {
    "terrainGrass": "textures/terrain/grass.png",
    "redstoneDustOff": "textures/circuit/dust_off.png",
    "buttonPress": "sounds/button_press.wav"
  }
}
```

Validation must reject or safely ignore:

- path traversal (`../`)
- invalid manifest schema
- unsupported asset type
- absurd image dimensions
- missing files

Pack failures fall back to built-in assets instead of crashing.

Resource packs are data only. Never execute code from a pack.

---

# 23. Optional Minecraft Java importer

This feature is separate from generic resource packs.

The app must never require it.

## 23.1 Distribution rule

Do not place Mojang/Microsoft textures or audio in GitHub source or release bundles.

Imported files stay local to the user's machine.

Do not embed imported assets into exported world files by default.

## 23.2 Java Edition first

Typical official Java launcher data may be under:

```text
~/Library/Application Support/minecraft/
```

but never require that exact path.

Provide:

- auto-detection attempt
- manual “Choose version JAR…”
- manual “Choose resource pack…”

## 23.3 JAR import

Java version JARs are ZIP-compatible.

Importer should:

1. inspect selected archive safely
2. find supported texture resources
3. map known source names to internal semantic IDs
4. extract only needed assets into local Application Support cache
5. write an import manifest

Do not make renderer depend on Mojang filenames.

## 23.4 Import cache

Provide:

- Re-import
- Remove Imported Assets
- Reveal Import Cache
- Switch to Built-In Pack

The repository working tree must never receive imported files.

## 23.5 Audio import

Do not implement Minecraft audio import in the first importer slice.

Java audio assets may involve hash-addressed launcher asset indexes and are a separate piece of work.

Texture import first.

---

# 24. Audio

Semantic sound IDs:

```swift
enum SoundID: String, Codable {
    case buttonPress
    case buttonRelease
    case leverToggleOn
    case leverToggleOff
    case repeaterTick
    case placeCircuit
    case removeCircuit
    case invalidPlacement
    case outputActivate
}
```

Requirements:

- master volume
- enable/disable effects
- resource-pack overrides
- multiple overlapping sounds
- one persistent audio engine rather than recreation per sound
- no microphone permission

Later positional pan:

```text
left edge   = -1.0
screen center = 0.0
right edge  = +1.0
```

Clamp values.

No need for full 3D positional audio.

---

# 25. Editor UX

Current layout after Slice 19C:

```text
Editing: world / area        Desktop: world / area     Start/Stop | Advanced
Worlds sidebar              World canvas              Build / Inspector
+ opens New World sheet     Pan / Zoom / Show Desktop
                            Areas in selected world: preview cards
                            Save Current View… / Update Current Area / Activate
Right-click world/area cards for Rename / Delete
```

Editor must support world creation/list/rename, area save/list/rename, pan, zoom, selection, placement/erase, component rotation, repeater delay, shared placement validation, viewport outlines and later Finder ghosts. World/area names must be nonempty after trimming; UUIDs identify records even when names coincide. Show each world's seed, its saved areas and the active desktop badge so the selected editor world cannot be mistaken for the live one. Slice 19C adds an explicit worlds sidebar, selected-world area previews below the canvas, creation/rename/save sheets and confirmed deletion. Circuit duplication, search and editor simulation remain deferred.

## 25.1 Browsing, saved areas and activation

- Selecting a world or saved area changes only editor selection and temporary browsing camera. Selecting a world starts at its first saved area (Home for a new world); every world must retain at least one area. Selecting an area browses to its saved origin; editor zoom remains independent of desktop points-per-tile.
- **Save Area…** names and saves a new bookmark in the selected world using the proposed lower-left origin and desktop tile scale. Saving does not activate or replace the existing active bookmark. **Update Current Area** replaces only the selected bookmark's camera, keeping its UUID/name/world and components. Save Current View still creates a separate bookmark. Renaming changes only its label.
- Each newly created world receives a default **Home** area at origin (0, 0), 64 logical points per tile. The migrated world's first area uses its existing saved camera, not this default.
- **Activate on Desktop** targets the selected saved area, using its saved camera, not an unsaved pan/zoom draft. If browsing has moved away, label the saved target clearly and offer Save Area. A seed preview must be created as a world before it can be edited, saved as an area or activated.
- Orange shows the proposed area in the selected world. Blue shows the active desktop viewport only when that viewport belongs to the selected world; an active area in another world is identified in text, never projected into the wrong map. All outlines use CoordinateMapper and the current display's logical dimensions; an area stores camera, not a frozen display size.
- Only the enabled active world's configuration is locked for editing. An inactive world can be edited while another world runs. Domain mutation methods enforce this by world ID, not only UI disabling. Disable Desktop World to edit the active world. Browsing and Select remain available at all times.
- Rendering inactive worlds shows their configuration/durable lever positions without attributing active-world power or occupancy to them. Until Slice 20 adds separately labeled Finder projections, inactive-world occupancy is unavailable rather than copied from the active world. No editor click executes an output or advances simulation.
- Temporary selection/pan/zoom is not persisted. Reopening selects the saved active area for editing, with Desktop World disabled. **Show Desktop Area** selects that world/area and browses to its origin; **Reset View** returns only editor browsing to origin zero.

## 25.2 Seeds belong to worlds

Generation settings are immutable for an existing world. **Preview** and **Random** explore terrain for a possible new world using an empty circuit and no prototype overrides. **Cancel Preview** returns to the previously selected world; **Create World…** saves a new UUID/name, chosen seed, empty circuit and Home area, then selects it in the editor without activating it.

Selecting a stored world restores its own components and lever positions. Entering the same seed again does not look up or merge worlds; use the world list to reopen an existing save. Creating another world with the same seed deliberately creates independent builds.

Remove the prototype's apply-new-seed-to-existing-circuit path when Slice 19A lands. There is no implicit reset, component transfer or terrain replacement for existing worlds. Import/export, explicit duplication and terrain regeneration/migration tools remain later work.

## 25.3 Library navigation and cleanup (Slice 19C)

Make the hierarchy visible: worlds in a sidebar; only the selected world's areas in a horizontal preview shelf below the canvas. World creation is a secondary New World sheet with name/seed/Preview/Random; normal editing has no persistent seed/creation/rename fields. Save Area and rename use focused sheets. Keep one compact desktop status/run control and a separately labeled saved-area activation action. Clearly distinguish browsing from the active desktop. Put debug metrics, Finder Diagnostics and desktop event details behind Advanced/Window menus, retaining permission/error recovery. Retire the developer placement window from app navigation; preserve fixtures needed by migration and automated tests, and never erase migrated user/demo circuits as cleanup.

World and area cards expose Rename/Delete through right-click context menus; remove Manage World and the area dropdown. Context-menu actions capture the clicked record UUID and do not select/pan/activate it. Sheets and domain rename/deletion methods must use that captured ID even if editor selection changes. After deletion, reset the editor camera only if its selected area was removed.

Update Current Area saves the proposed lower-left origin at that area's existing desktop scale into the same record, after complete-library validation and successful synchronous save. It never creates an area or moves circuit components. Failed/load-blocked updates preserve the previous bookmark/prepared desktop camera and are never queued for implicit retry. An inactive bookmark may be updated while the desktop runs another area, including another area of the same world. Refuse updating the active bookmark while running; stop the desktop first. When stopped, preflight the available display/mapper before updating the already-assigned bookmark; success also updates its prepared desktop camera for the next explicit Start Desktop/restart, without enabling or dispatching an action. Updating another bookmark never assigns it to the desktop. Preview candidates cannot update saved areas. Report success/failure in editor status; keep activation labels clear.

Previews are bounded, disposable schematic terrain/circuit images, not persisted assets or simulations. Use CoordinateMapper for their camera projection; regenerate only on world configuration, saved camera or display-size changes, not transient power ticks. No Finder reads/paths or actions in previews. Areas preview their saved viewport; sidebar worlds preview their first area.

Deletion is explicit and confirmed in UI, with stable target IDs enforced in domain methods. Deleting an area removes only its bookmark, never components. Deleting a world removes that world and all its areas/components/levers. Refuse deleting the active desktop area or world even while disabled: activate another saved area first. Refuse deleting the final world or a world's final area. No implicit desktop reassignment, runtime restart or automatic replacement bookmark. If editor selection is deleted, browse the first remaining area in that world or the active area after world deletion. Validate and synchronously save the complete proposed library before publishing deletion; load-blocked/save-failed deletion preserves in-memory records, selection and runtime and never queues a destructive retry. Other pending configuration still follows normal retry semantics. The legacy backup is untouched; deletion does not change Finder files.

## 25.4 Finder projections and Output snapping (Slice 20)

View → Show Finder Items is an explicit, session-only opt-in, initially off. It enables the existing serialized 2 Hz DesktopItemTracker while the editor is open, including when Desktop is stopped. Startup still performs no Finder query/action. The editor and desktop share one tracker/read slot; stopping Desktop retains opted-in editor tracking, hiding/closing the editor stops tracking only when the running desktop does not need it, and full shutdown stops both. Denied/error reads pause automatic polling; use Advanced → Finder Diagnostics to retry, then toggle Show Finder Items off/on to resume. No second Finder adapter is introduced.

Publish cached raw Finder read snapshots even when the desktop renderer is absent. Build a pure projection tagged with the selected world UUID and proposed desktop camera: convert Finder centers through CoordinateMapper using the current primary-display reference, filter to the physical target display, then convert projected world centers through the editor mapper. Backing scale does not multiply logical coordinates. Projection is ephemeral and never persists Finder paths/positions. Changing world, proposed origin, editor zoom or cached Finder data refreshes markers. Seed previews hide markers and disable snapping. Display-change observation and settled refresh are implemented in Slice 21.

Label markers and inspector/output occupancy as a projection of the selected world's proposed view, including inactive worlds and unsaved camera changes; never copy the live world's occupancy into another world. Actual desktop occupancy/action dispatch remains tied to its assigned camera/world. Render only centers inside the editor canvas, with names and center rings; red rings mean multiple items in one tile. Output badges show EMPTY/ITEM/MANY/N/A using projected occupancy. No editor interaction reads Finder directly, simulates an inactive circuit or launches a file.

Output snapping uses a 24-logical-point radius around visible ghost centers. Choose the nearest center's containing world tile (floor through CoordinateMapper); exact equal-distance ties across different tiles fall back to the ordinary clicked tile rather than guessing a target. Multiple items on one tile remain ambiguous and retain the existing action refusal. Recompute from the latest cached projection on click, rather than committing stale hover state. Snapping changes only the placement target; shared terrain/decoration/occupied-cell rules and preview/running-active editing guards still apply. Moving an icon never moves an already-placed component.

Interaction:

- select Output tool
- move near ghosted Finder item
- highlight tile under its center
- click to place output there

This should make precise setup easy without assuming Finder grid spacing.

---

# 26. Direct desktop Build Mode

Post-MVP feature.

Requirements:

- explicit enter/exit
- strong visual indication
- input overlay exists only while active
- visible status/menu exit always available

V1 Build Mode edits circuit only, not terrain.

Possible hotbar:

```text
[1 Dust] [2 Button] [3 Lever] [4 Repeater] [5 Output] [6 Erase]
```

---

# 27. Normal-mode component clicks

For a global click observation:

1. receive screen point
2. determine relevant display
3. map to world tile
4. check interactive circuit component
5. check Finder occupancy/overlap
6. if Finder icon owns the interaction, ignore circuit click
7. otherwise press button/toggle lever

A click on empty desktop may still deselect a Finder selection. That is acceptable.

Do not consume/modify Finder's event in normal mode.

---

# 28. Rendering architecture

Suggested SpriteKit hierarchy:

```text
worldRoot
├── terrainLayer
├── terrainEdgeLayer
├── decorationLayer
├── circuitLayer
├── circuitEffectLayer
├── occupancyIndicatorLayer
├── highlightLayer
└── diagnosticsLayer
```

Finder icons are not nodes in this scene. They appear above the scene due to macOS desktop layering.

## 28.1 Culling

Render only visible tiles plus a small margin.

Never instantiate the infinite world.

## 28.2 Circuit visuals

Need visual state for:

- powered/unpowered dust
- dust connection shape
- button pressed state
- lever state
- repeater orientation
- repeater delay
- repeater powered state
- output empty/occupied/ambiguous
- output trigger flash

## 28.3 Performance goals

On modern Apple Silicon:

- low idle CPU
- no terrain generation every frame
- no Finder query every frame
- state-driven sprite changes
- pause/reduce work when display sleeps if practical

Aim initially for comfortably under ~5% CPU while static, but profile rather than optimizing blindly.

---

# 29. Persistence

Slice 19A stores a single atomic **library.json** at `~/Library/Application Support/RedstoneDesktop/`. It migrates the earlier Slice 19 format-1/2 world.json without rewriting the source. One file holds world records, area records and active selection, avoiding a partially committed cross-file world/index update. Keep Codable JSON, Foundation storage, debounce autosave and explicit Save Now; no database or backend.

## 29.1 Target durable model

- `WorldLibraryDocument`, library format version 1: arrays of worlds and saved areas plus a nonoptional `activeAreaID`.
- `WorldDocument`, world format version 3: stable UUID/name, fixed generation settings, terrain profile (`procedural` or `legacyFixtureV1`), circuit configuration and ON lever coordinates. Move the old document camera into an area. Recreate legacy fixture overrides/unspecified cells by profile; procedural worlds have none. Future user terrain overrides require an explicit schema addition.
- `SavedArea`: stable UUID/name, `worldID` and CameraState. No components, Finder paths, simulation state or stored screen dimensions.
- Exclude editor selection/camera, enabled state, runtime power, button timers, repeater histories, pending actions, Finder items/permissions and generated terrain caches.

Validate unique world/area IDs, nonempty names, at least one world and at least one area per world, every area reference, active area reference, supported library/world/generator/profile versions, finite representable camera with 16…128 points-per-tile, component placement/configuration and lever membership. Validate cameras against the actual display again at activation. Retain the existing 2 MB encoded-document bound for the entire initial library; report a limit error without dropping worlds or overwriting the previous save. Raise limits only in an explicit later change with tests.

Store normal app data in Application Support and replace the complete library atomically. Autosave after 0.75 seconds of edit inactivity, coalescing pending writes into the latest **whole library snapshot**, including edits to multiple worlds. Flush on quit/disable and before activation. Failed saves retain the latest pending snapshot for retry and never claim Saved. Store-backed tests use isolated temporary files/fakes, never the owner's Application Support file.

Version library and world documents independently from generation and resource-pack manifest versions. This library change does not alter generation-version-1 terrain or introduce asset-pack persistence.

## 29.2 Migration and restoration

1. If library.json exists, load and validate it. It is authoritative even when world.json remains. Damaged/unsupported/oversized library data disables writes for the session; never fall back to the old save and overwrite the library.
2. If library.json is absent and world.json exists, decode its supported format 1 or 2. Preserve world UUID/name, current chosen seed/generator, components, lever positions and legacy terrain exactly. Format 1 retains the established seed-2026 migration. Create one **Desktop** area at the saved camera and select it as active.
3. Write/validate the migrated library atomically before reporting migration complete. Leave the source world.json byte-for-byte untouched as a backup. Repeat startup with a valid library must reuse its IDs and must not import the backup again. If migration fails, preserve both source and any previous destination, block writes for the session and report recovery guidance.
4. If neither file exists, create an initial library with one new procedural empty world and Home area. Prototype fixtures remain available to automated tests/explicit developer tools, not normal fresh worlds.
5. Restore the active area for editor browsing, but always start desktop integration disabled. Enabling uses that saved world's area, independent of later editor selection.

No saved data is deleted as part of migration. Distinguish missing from unreadable/corrupt data. Recovery instructions must distinguish current library.json from legacy world.json; moving the backup does not repair a damaged authoritative library.

## 29.3 Minimal scope

Slice 19A supplies models, migration, whole-library persistence, world creation/selection and immutable seeds. Saved-area domain records exist for migration/default areas, but the named-area browser/activation UX is Slice 19B. Until 19B, world switching/creation/editing can require Desktop World disabled and the live desktop remains assigned to the original active world; new-world activation is not implied by browsing. The interim Use This Area control may adjust only that active world's camera bookmark, never its seed or another world's active assignment. Document this temporary UI precisely.

Slice 19B adds named areas and independent editor/desktop selection, including inactive-world editing while another world runs. It replaces Use This Area with Save Area / Activate on Desktop and implements the runtime contract in Section 7.1. Existing saves and proven Finder/action/coordinate boundaries remain intact.

---

# 30. App lifecycle / menu bar

Eventually behave like a desktop utility.

Suggested status/menu commands:

- Open Editor
- Show Desktop Area
- Enable/Disable Desktop World
- Enter/Exit Build Mode
- Refresh Finder
- Diagnostics
- Quit

The editor window may close while desktop rendering continues.

Do not make the app invisible until there is an obvious way to reopen/quit it.

---

# 31. Permissions and degraded behavior

Create a `PermissionStatus` abstraction.

Track:

- Finder Automation status
- Accessibility trust if a later feature actually needs it

Do not repeatedly spam permission prompts.

If Finder access is denied:

- editor still opens
- terrain works
- circuit editing works
- simulation works
- Finder occupancy shows unavailable
- Finder-dependent output action is disabled

Permission denial must never crash app.

---

# 32. Diagnostics

A Diagnostics window is essential.

Show:

```text
app version
macOS version
active screens
editor-selected world/area IDs and names
active desktop world/area IDs and names
library/migration/save status
screen frames
backing scales
desktop window status
Finder automation status
Accessibility status
Finder poll status
Finder item count
last Finder error
current pointer screen coordinate
current pointer world tile
camera origin
points per tile
simulation tick rate
render FPS
loaded asset pack
last output activation
last action result
```

Debug toggles:

- draw tile coordinates
- draw raw Finder points
- draw mapped Finder centers
- draw output occupancy
- draw chunk boundaries
- freeze Finder polling
- pause simulation

This is not optional polish. It is part of making this unusual integration debuggable.

---

# 33. Logging

Use structured Apple logging (`Logger` / OSLog style).

Categories:

- app
- desktop-window
- finder
- coordinates
- world-generation
- circuit
- actions
- assets
- audio
- persistence

Do not log user file contents.

Do not spam logs every render frame or every unchanged Finder poll.

---

# 34. Safety rules

Even for a personal project:

1. Never execute scripts as root.
2. Never automatically use `sudo`.
3. Never concatenate an untrusted filename into a shell command string.
4. Resource packs are data only.
5. Never execute pack-provided code.
6. Validate ZIP extraction against path traversal.
7. Do not extract archive entries outside intended cache directory.
8. Script execution must be explicit and opt-in.
9. Normal outputs default to opening occupants, not executing them.
10. Ambiguous occupancy never auto-executes.

---

# 35. Asset/legal notes

The app must contain a complete original asset pack and must not require Minecraft.

For public GitHub distribution:

- do not commit Mojang/Microsoft textures
- do not commit Minecraft audio
- do not package extracted assets in releases
- do not imply Mojang/Microsoft endorsement
- consider branding that makes unofficial status obvious

The optional local importer operates on the user's local installation/files and stores imported data only in local Application Support cache.

Before public release, especially if using Minecraft naming or accepting donations, re-check the then-current terms:

- https://www.minecraft.net/en-us/eula
- https://www.minecraft.net/en-us/usage-guidelines

This section is engineering/product caution, not legal advice.

---

# 36. Tests

## 36.1 Unit tests

Must cover:

- coordinate round trips
- boundary mapping
- negative world coordinates
- negative chunk coordinates
- deterministic generator output
- placement rules
- dust attenuation
- button timing
- lever state
- repeater timing/direction
- output rising-edge behavior
- circuit loops do not hang
- occupancy ambiguity
- JSON round trips
- migrations preserving legacy identity/circuit/camera/lever data and source bytes
- independent worlds including duplicate seeds and coincident component coordinates
- overlapping area bookmarks sharing one circuit
- invalid/dangling library references and damaged-library preservation
- autosave coalescing edits across worlds
- inactive-world editing and browse/live isolation
- world/session-scoped cancellation across activation and failed activation
- entire active-world simulation with offscreen output action suppression
- resource-pack manifest validation

## 36.2 Integration tests with fakes

Use:

- fake `DesktopItemProvider`
- fake action executor
- fake screen geometry
- simulated display resize

## 36.3 Manual checks

Maintain explicit manual validation for things an automated agent cannot safely judge:

- desktop world really is below Finder icons
- Finder remains clickable
- icon drag works normally
- hover aligns with visible tiles
- mapped Finder marker aligns with visible icon
- output targets correct real item
- Finder resizing recalibrates
- display resolution changes survive
- permissions behave sensibly
- worlds and named areas restore independently after restart
- browsing/editing another world leaves the active desktop unchanged
- explicit area activation remaps real Finder targets and cancels old actions

The AI may mark a `MANUAL` checkbox complete only after the owner confirms the corresponding checks passed on their Mac. Record that confirmation as owner-reported validation, separate from automated test results. Never infer manual completion from a build or test run.

---

# 37. Rules for the AI coding agent

## 37.1 Work one slice at a time

Do not implement many milestones in one giant pass.

## 37.2 Keep project healthy

At the end of every slice:

- project builds
- tests pass
- app launches unless slice specifically concerns non-app tooling

## 37.3 Record owner-confirmed manual checks

Tell the human exactly what to look for. Mark MANUAL items complete only after the owner confirms the corresponding checks passed on their Mac.

## 37.4 Record discoveries

If actual macOS behavior differs from this spec:

- document it
- update Decision Log
- propose the smallest architecture/spec adjustment
- do not silently pile hacks on top

## 37.5 Avoid unnecessary dependencies

No backend.

No analytics.

No third-party game engine.

No custom rendering engine until profiling proves SpriteKit insufficient.

---

## 37.6 Owner workflow and demo layout

When the owner confirms a slice, record that report and implement the next roadmap slice in the same turn; do not require a separate confirmation-only turn. Keep the one-slice-at-a-time and feasibility-stop rules.

Keep existing desktop demo circuits in place. Extend any additional test circuits to their right (positive world X), rather than adding more rows above them. Preserve clear input/neighbor tiles for Finder interaction.

---

# 38. IMPLEMENTATION ROADMAP

The roadmap is deliberately granular. Adopted order after Slice 19 is **19A → 19B → 19C → 20**, then the existing numbered slices. Lettered additions preserve earlier slice numbers and validation history. Documentation planning is not implementation acceptance.

---

## Slice 0 — Repository bootstrap

### Goal

Create a reproducible native macOS app.

### Tasks

- [x] Initialize Git repository.
- [x] Add `.gitignore`.
- [x] Add `README.md` describing experimental status.
- [x] Add license chosen by owner.
- [x] Add XcodeGen `project.yml` if using XcodeGen.
- [x] Create macOS app target.
- [x] Create test target.
- [x] Add minimal SwiftUI editor placeholder.
- [x] Add one passing test.
- [x] Document project-generation command.
- [x] Document build command.
- [x] Document test command.

### Automated acceptance

- [x] `xcodebuild` Debug build succeeds.
- [x] test suite succeeds.

### Manual acceptance

- [x] MANUAL: app launches and shows editor placeholder.

---

## Slice 1 — Domain primitives

### Tasks

- [x] `WorldCoordinate`
- [x] `WorldPoint`
- [x] `CameraState`
- [x] `Direction`
- [x] `PowerLevel`
- [x] base circuit component types
- [x] Codable/equality tests

### Acceptance

- [x] pure domain layer does not depend on SpriteKit/AppKit.

---

## Slice 2 — Desktop renderer window spike

### Goal

Prove correct macOS window layering.

### Tasks

- [x] Add `DesktopWindowController`.
- [x] Add `DesktopScene`.
- [x] Create renderer on main display.
- [x] Render unmistakable checker/grid.
- [x] Make renderer click-through.
- [x] Add enable/disable command.

### Manual acceptance

- [x] MANUAL: checker appears above normal wallpaper.
- [x] MANUAL: Finder desktop icons appear above checker.
- [x] MANUAL: icons remain selectable.
- [x] MANUAL: icons can be dragged normally.
- [x] MANUAL: application windows appear above desktop world.

### Stop condition

If layering is wrong, investigate before proceeding.

---

## Slice 3 — Coordinate mapper

### Tasks

- [x] `ScreenDescriptor`
- [x] screen → world
- [x] world → screen
- [x] world point → tile
- [x] negative screen origins
- [x] unit tests
- [ ] optional debug coordinate labels

### Acceptance

- [x] round-trip tests pass.
- [x] boundary tests pass.

---

## Slice 4 — Cursor highlight

### Tasks

- [x] read global pointer
- [x] identify active screen
- [x] map to tile
- [x] draw highlight
- [x] hide outside active area
- [x] debug screen/world coordinate display

### Manual acceptance

- [x] MANUAL: highlight changes exactly at visible tile boundaries.
- [x] MANUAL: Finder remains fully interactive.

---

## Slice 5 — Global click observation

### Tasks

- [x] create `DesktopClickMonitor`
- [x] observe left mouse down
- [x] map click to tile
- [x] show short debug flash
- [x] remove monitor cleanly on shutdown
- [x] prevent duplicate monitors

### Manual acceptance

- [x] MANUAL: empty-desktop click flashes tile.
- [x] MANUAL: Finder still receives click.
- [x] MANUAL: clicking an icon still selects it normally.

---

## Slice 6 — Finder automation spike

### Tasks

- [x] add required Automation usage configuration
- [x] create `FinderScriptRunner`
- [x] query Finder desktop items
- [x] retrieve name
- [x] retrieve URL/path if possible
- [x] retrieve raw desktop position
- [x] distinguish permission denial from parse failure
- [x] diagnostics list

### Manual acceptance

- [x] MANUAL: macOS permission prompt appears when expected.
- [x] MANUAL: accepting returns desktop items.
- [x] MANUAL: moving item changes reported position.
- [x] MANUAL: denial does not crash app.

### Stop condition

Do not build fancy terrain if Finder positions are not viable.

---

## Slice 7 — Finder coordinate calibration

### Tasks

- [x] draw marker for every Finder position
- [x] implement provisional Finder→screen conversion
- [x] compare visually
- [x] document discovered semantics
- [x] add polling `DesktopItemTracker`
- [x] prevent concurrent poll pileup

### Manual acceptance

- [x] MANUAL: marker aligns with actual icon.
- [x] MANUAL: drag icon and marker follows.
- [x] MANUAL: test icons around all screen edges.
- [x] MANUAL: change Finder icon size and inspect again.

### FEASIBILITY GATE

This alignment must be trustworthy before further UI investment.

---

## Slice 8 — Desktop occupancy

### Tasks

- [x] implement pure `DesktopOccupancyResolver`
- [x] unit tests with fake items
- [x] visually mark occupied world tile
- [x] handle multiple-item ambiguity

### Manual acceptance

- [x] MANUAL: dragging icon across a tile boundary changes occupancy at expected point.

---

## Slice 9 — Minimal end-to-end circuit

### Goal

Prove the central concept before building the engine.

**Status: complete; feasibility Gate A passed on 2026-10-07.** The owner confirmed all five manual acceptance checks, including moving the occupant away and replacing it with a different item. Slice 10 is next.

### Tasks

- [x] create fixed test button
- [x] fixed visual dust path
- [x] fixed output
- [x] clicking button visually powers path
- [x] output emits rising activation
- [x] output reads current Finder occupant
- [x] output opens occupant via `NSWorkspace`
- [x] output visually flashes

### Manual acceptance

- [x] MANUAL: place harmless folder/file/app alias on output.
- [x] MANUAL: press button and see signal.
- [x] MANUAL: occupant opens.
- [x] MANUAL: move occupant away; no target remains.
- [x] MANUAL: move a different item onto output; new item becomes target.

### FEASIBILITY GATE A

Do not build the full editor until this works.

---

## Slice 10 — World model

- [x] `World`
- [x] `Tile`
- [x] `TerrainID`
- [x] `DecorationID`
- [x] `CircuitWorld`
- [x] circuit dictionary keyed by world coordinate
- [x] unit tests
- [x] renderer consumes model, not hardcoded test data

---

## Slice 11 — Circuit simulator core

- [x] fixed 20 Hz tick scheduler
- [x] power 0–15
- [x] dust propagation
- [x] attenuation
- [x] lever
- [x] button pulse
- [x] output rising edge
- [x] two-phase update
- [x] loop protection
- [x] comprehensive unit tests

**Status: complete; owner-confirmed regression on 2026-10-07.** Debug build and all 86 automated tests pass. The owner reported that this revision works as expected after the README.md Mac walkthrough. This slice has no roadmap MANUAL checkbox.

Required tests:

- [x] straight dust line power levels
- [x] signal eventually reaches 0
- [x] lever remains powered
- [x] button expires at exact tick
- [x] output triggers once per rising edge
- [x] held output does not retrigger
- [x] loop does not hang
- [x] insertion order does not change result

---

## Slice 12 — Repeater

- [x] orientation
- [x] rear input only
- [x] forward output only
- [x] power restoration to 15
- [x] 1–4 redstone-tick delays
- [x] exact timing tests
- [x] visual state

**Status: complete; owner-confirmed regression on 2026-10-07.** Debug application build and all 101 automated tests pass. The owner reported “It works!” after the README.md walkthrough. Slice 12 has no roadmap MANUAL checkbox.

---

## Slice 13 — Circuit renderer

- [x] dust shapes
- [x] powered/unpowered textures
- [x] button state
- [x] lever state
- [x] repeater orientation/delay
- [x] output occupancy
- [x] output trigger flash
- [x] renderer remains action-free

**Status: complete; owner-confirmed visual acceptance on 2026-10-07.** Debug build and all 107 automated tests pass. The owner reported “Looks good!” after the README.md visual walkthrough.

### Manual acceptance

- [x] MANUAL: visual state tracks simulation correctly.

---

## Slice 14 — Placement rules

- [x] terrain capability definitions
- [x] centralized evaluator
- [x] failure reasons
- [x] unit tests
- [x] developer placement UI

Acceptance:

- [x] dust cannot be placed on water.
- [x] blocked decoration rejects placement.
- [x] occupied circuit tile does not silently overwrite.

**Status: complete; owner-confirmed regression on 2026-10-07.** Debug application build and all 123 automated tests pass. The owner reported “Looks good! Continue.” after the developer placement walkthrough. This slice has no roadmap MANUAL checkbox.

---

## Slice 15 — Basic editor

- [x] editor layout
- [x] canvas
- [x] pan
- [x] zoom
- [x] selection
- [x] dust tool
- [x] button tool
- [x] lever tool
- [x] repeater tool
- [x] output tool
- [x] erase tool
- [x] inspector
- [x] placement preview
- [x] invalid placement feedback

### Manual acceptance

- [x] MANUAL: useful circuit can be authored without code changes.

**Status: complete; owner-confirmed manual acceptance on 2026-10-07.** The owner reported “It works! Thats neat.” after the circuit-authoring walkthrough. This records Mac validation separately from the 135 passing automated tests. Editing is available while Desktop World is disabled; editor browsing uses an independent camera. Persistence is implemented in Slice 16 below.

---

## Slice 16 — Persistence

- [x] versioned `WorldDocument`
- [x] `WorldStore`
- [x] atomic write
- [x] autosave debounce
- [x] restore last world
- [x] JSON tests
- [x] corrupted-document handling

### Manual acceptance

- [x] MANUAL: build, quit, reopen, state is restored.

**Status: complete; owner-confirmed restart validation on 2026-10-07.** The owner reported “Works!” after the quit/reopen walkthrough. This records Mac validation separately from the 148 automated tests. World configuration autosaves to Application Support after 0.75 seconds and flushes on quit. Damaged/unsupported documents are preserved with autosave disabled.

---

## Slice 17 — Deterministic terrain generator

- [x] deterministic seed/hash
- [x] 2D noise
- [x] elevation
- [x] moisture
- [x] terrain/biome selection
- [x] water
- [x] basic decorations
- [x] chunk generation
- [x] negative-coordinate correctness
- [x] generator snapshot/hash tests

Acceptance:

- [x] same seed and coordinate always gives same result for generation version.
- [x] different seeds differ visibly.
- [x] no chunk seams.

**Status: complete; generator implementation and automated acceptance.** Debug application build and all 157 tests pass. A standalone seed comparison was generated and inspected. Live app rendering remains the existing persisted fixture until Slice 18; the new generator does not mutate saved circuits. Slice 17 has no roadmap MANUAL checkbox.

---

## Slice 18 — Chunked terrain renderer

- [x] visible chunk calculation
- [x] `ChunkCache`
- [x] chunk SpriteKit nodes
- [x] add/remove as camera moves
- [x] nearest-neighbor rendering
- [x] original placeholder assets
- [x] render metrics

### Manual acceptance

- [x] MANUAL: long editor pan does not grow nodes indefinitely.
- [x] MANUAL: idle renderer does not regenerate terrain continuously.

**Status: complete; owner-confirmed renderer validation on 2026-10-07.** The owner reported “Great! it works” after the long-pan, idle, automatic Finder and persistence walkthrough. This records Mac validation separately from the 169 passing automated tests. The renderer retains visible chunks plus one margin, bakes original nearest-filtered textures into one sprite per chunk, and reports cache/node/generation/texture counts. Existing fixture terrain and saved circuits are preserved over generated surroundings. README.md gives the long-pan and idle checks.

---

## Slice 19 — Seed browser / choose desktop area

- [x] seed text entry
- [x] random seed
- [x] editor free pan
- [x] editor free zoom
- [x] physical desktop viewport rectangle
- [x] `Use This Area`
- [x] save desktop camera
- [x] browsing does not change live desktop prematurely

### Manual acceptance

- [x] MANUAL: explore seed, choose location, live desktop changes to selected area.

**Status: complete; owner-confirmed seed/area validation on 2026-10-07.** The owner reported “It works!” after the seed/location/restart walkthrough. This records owner-reported Mac validation separately from the last implementation build and 178 passing automated tests. Seed preview and editor navigation leave the live world unchanged until Use This Area. Invalidating seeds are refused; successful applies preserve circuits and save the seed/camera. README.md provides the Mac walkthrough.

---

## Slice 19A — Independent world library and migration

### Goal

Give each world its own permanent seed, coordinate-keyed circuit and save identity; preserve the owner's existing build before changing the UI's seed semantics.

### Tasks

- [x] Foundation-only library/world-format-3/saved-area models and reference validation.
- [x] Atomic library.json store, whole-library debounce/Save Now/quit flush and bounded damaged-data handling.
- [x] Idempotent format-1/2 world.json migration retaining original source bytes, identity, terrain profile, circuit, levers and camera in the first area.
- [x] Empty procedural fresh worlds and default Home areas; no inherited demo/user components.
- [x] SwiftUI world list, names/seed display, create/rename/select world while Desktop World disabled.
- [x] Preview/Random/Create World with an empty candidate; existing world seeds fixed; remove seed replacement of existing builds.
- [x] Route all editor/developer mutations and saves to the selected world; browsing never selects the active desktop world implicitly.
- [x] Interim desktop lifecycle continues using the saved active world/area; scope Use This Area to it and document the temporary restriction.
- [x] Update tests for world ownership, seed independence, migration/failure preservation, references and multi-world autosave; build and run the full suite.
- [x] Update README with exact current controls, new save/recovery path and Mac walkthrough.

### Automated acceptance

- [x] Seed-42 and seed-2026 worlds retain independent circuit edits at identical coordinates; duplicate-seed worlds remain independent too.
- [x] Legacy restoration/migration preserves every configuration value and source file, and a second launch does not duplicate records.
- [x] Corrupt/unsupported library or legacy input cannot be overwritten; failed saves retain pending edits for retry.
- [x] World creation/selection/seed preview causes no Finder read, simulation, desktop reassignment or action.
- [x] Edits in multiple worlds survive one coalesced whole-library save and restore.

### Manual acceptance

- [x] MANUAL: existing saved circuit, terrain, lever settings and desktop camera survive migration and restart.
- [x] MANUAL: create worlds with seeds 42 and 2026, author different components, switch and reopen; each restores its own build without copying.
- [x] MANUAL: selecting a world does not activate it; the original desktop selection still works after explicit enable.

**Status: complete; owner Mac validation confirmed.** Debug build and all 194 automated tests pass. Foundation-only World/Circuit/Persistence code also type-checks independently of AppKit/SpriteKit. The owner confirmed all three walkthrough checks on 2026-10-07 with “Yes it works!”; these MANUAL checkboxes are checked from that report. README.md has the current controls, save/recovery guidance and walkthrough. Named-area UI and new-world desktop activation remain Slice 19B.

---

## Slice 19B — Named areas and explicit desktop activation

### Goal

Browse a list of built areas across worlds and explicitly choose one for the desktop, without transferring components.

### Tasks

- [x] Saved-area list grouped by world, Save Area and rename with stable IDs; display seeds and active badge.
- [x] Save proposed camera as a new bookmark; selecting/browsing an area never changes its stored camera or desktop assignment.
- [x] Separate editor selection from activeAreaID; Show Desktop Area and startup selection restore.
- [x] Replace Use This Area with Save Area / Activate on Desktop; activate saved camera, never an unsaved browsing draft.
- [x] Allow inactive-world editing while live active-world configuration stays locked in both UI and domain mutation methods.
- [x] Scope editor power/occupancy and viewport outlines by world identity; no active overlay on an unrelated world.
- [x] Preflight and save-before-switch with clear failure status; invalidate old input/actions by world ID/session, rebuild mapping, reset transient state and refresh Finder.
- [x] One full active-world simulator, paused inactive worlds and visibility-gated output actions; no circuit clipping or deferred offscreen launches.
- [x] No-op activation of the same world/camera; enabled-state preservation and saved-lever resume semantics.
- [x] Tests for overlapping bookmarks, browsing/live isolation, inactive edits, activation failures/stale completions/offscreen outputs and restart selection; build/run full suite.
- [x] Update README with exact Mac checks and recovery/navigation instructions.

### Automated acceptance

- [x] Overlapping areas share a world circuit, while areas of another world never show/copy those components.
- [x] Browse/save/rename/edit inactive world while desktop runs changes no live mapper/simulator/action target.
- [x] Successful activation uses the selected saved world/camera; invalid/save-failed activation leaves the old runtime intact.
- [x] Late callbacks/actions from an old world/session never open a coincident-coordinate target after switching.
- [x] Offscreen circuit components continue transmitting, but offscreen outputs and inactive worlds dispatch no desktop action.
- [x] Active area ID and all worlds/areas survive restart; desktop starts disabled and no action occurs until explicit enable.

### Manual acceptance

- [ ] MANUAL: name two areas in one world and one in another; select/edit them and confirm builds stay at their map locations.
- [ ] MANUAL: browsing and editing an inactive world leaves the enabled desktop unchanged; active-world editing requires disabling it.
- [ ] MANUAL: Activate on Desktop switches terrain/circuit/camera to the saved area, and the selected active area survives quit/reopen.
- [ ] MANUAL: a harmless Finder occupant opens only from the active area's visible output; switching cancels the previous world's pending pulse/action.

**Status: implemented; owner Mac validation pending.** Debug build and all 205 automated tests pass; Foundation-only World/Circuit/Persistence type-check also passes. Its four MANUAL checkboxes remain unchecked. README.md contains the exact launch, bookmark, switching, cancellation and restart checks. Finder ghosts follow in Slice 20 after owner confirmation.

---

## Slice 19C — Clear library navigation and cleanup

Owner-requested usability detour before Finder ghosts; preserve Slice 19B runtime contracts.

- [x] Worlds sidebar with selected/desktop distinction; area preview shelf scoped to selected world.
- [x] Bounded camera-mapped terrain/circuit previews, refreshed on configuration rather than simulation ticks.
- [x] Secondary New World sheet; focused Save Area/rename/delete flows; compact editor/tool/inspector controls.
- [x] Confirmed stable-ID world/area deletion with active/final-record guards and save-before-publish failure preservation.
- [x] Remove developer placement window/navigation and demo-specific desktop diagnostic labels; retain test/migration fixtures and advanced recovery diagnostics.
- [x] Add deletion/preview/navigation regression tests, build app, run full suite and update README.

- [x] Update Current Area in place with save-failure/live-active guards and durable camera tests.
- [x] Right-click world/area rename/delete with captured target IDs; remove management dropdowns and preserve browsing for unselected targets.

### Manual acceptance

- [ ] MANUAL: sidebar worlds and area previews make browsing versus desktop activation clear; create/save/rename sheets work without copying builds.
- [ ] MANUAL: delete a disposable inactive world and an extra bookmark; builds survive bookmark deletion, active/final records stay protected, and deletion survives reopen.
- [ ] MANUAL: editing, desktop activation, Finder opening and Advanced diagnostic recovery still work after rearrangement.

- [x] MANUAL: Update Current Area keeps one bookmark/name and components, restores its new camera after reselection/restart, and respects running-active versus inactive behavior.
- [x] MANUAL: right-click rename/delete targets the clicked world/area, including unselected cards, without moving browsing; confirmation and deletion protections remain.

**Status: implemented; owner Mac checks pending.** Debug build and all 220 tests pass, plus Foundation-only type-check. The owner said “I think it works” for 19B and requested usability cleanup. Record this as tentative feedback; its four specific MANUAL checks remain pending rather than inferring all passed. The owner accepted the 19C follow-up with “Great. Lets do the next slice”; its two follow-up checks are recorded complete, while the earlier three cleanup checks remain pending. Slice 20 follows below.

---

## Slice 20 — Finder ghosts in editor

- [x] show real Finder items as ghosts/markers
- [x] update when tracker changes
- [x] map through the selected world's proposed/saved desktop camera, separately from live occupancy
- [x] scope ghosts/occupancy by selected world and label them as a projection when it is inactive
- [x] show occupancy state
- [x] snap output to tile under Finder icon center

### Manual acceptance

- [x] MANUAL: moving real icon updates editor ghost while opted-in editor tracking is on, including with Desktop stopped.
- [x] MANUAL: Output hover/click snaps to the tile under a ghost center, respects blocked placement, opens nothing, and icon movement does not move placed components.
- [x] MANUAL: inactive-world/unsaved-view projections leave desktop assignment/circuit unchanged; seed previews hide markers and tracking lifecycle/recovery works.

**Status: complete; owner-reported Mac acceptance on 2026-10-07.** The owner confirmed the combined Slice 20/21 walkthrough with “All looking good. Continue”. Debug build and all 232 tests passed at implementation. Pure World/Circuit/Persistence plus Finder projection type-check passes without AppKit/SpriteKit. README contains the View-menu opt-in and exact icon-movement, snapping, scoping and recovery checks. Slice 21 is implemented and owner-accepted below.

---

## Slice 21 — Display-change resilience

- [x] observe screen-parameter changes
- [x] rebuild screen descriptors
- [x] resize/recreate renderer windows
- [x] recalculate mapper
- [x] refresh Finder after settle delay
- [x] document camera-anchor policy
- [x] unit tests with fake screen changes

**Status: complete; owner-reported Mac acceptance on 2026-10-07.** The owner confirmed the combined walkthrough with “All looking good. Continue”. Debug build and all 244 tests passed at implementation, including 12 display-change checks. Section 5.4 documents primary-display/lower-left anchor behavior; README has a combined Slice 20/21 walkthrough. The owner authorized this slice while away, then reported acceptance after returning; manual completion comes from that report, not automated tests.

### Manual acceptance

- [x] MANUAL: display scaling/resolution change remains aligned.
- [x] MANUAL: external display unplug/replug does not crash.

---

## Slice 22 — Finder icon-size handling

- [x] read/detect relevant Finder view settings if practical
- [x] refresh icon layout after size change
- [x] keep occupancy center-based
- [x] store optional baseline values for future sync

**Status: implemented; owner Mac validation pending.** Debug build and all 256 tests pass, including 12 new icon-size checks. Pure domain/view-settings/Finder projection type-check without AppKit/SpriteKit. Baseline is optional and session-only; synchronization/persistent settings remain Slice 23. Unsupported optional settings retain normal position polling. README contains the desktop View Options, alignment and real-output-target walkthrough.

### Manual acceptance

- [ ] MANUAL: change desktop icon size.
- [ ] MANUAL: mapped markers realign after Finder settles.
- [ ] MANUAL: output target follows actual new item position.

---

## Slice 23 — Optional synchronized world scale

- [x] setting: independent vs sync-to-Finder
- [x] baseline Finder icon size
- [x] calculate world scale ratio
- [x] preserve camera anchor
- [x] refresh icons after Finder rearrangement
- [x] clamp minimum/maximum world scale

### Manual acceptance

- [ ] MANUAL: changing Finder icon size can zoom world in sync mode.
- [ ] MANUAL: occupancy is recalculated rather than assumed.
- [ ] MANUAL: independent mode leaves world scale alone.

Keep this optional if Finder behavior feels awkward.

---

## Slice 24 — Audio foundation

- [ ] `AudioEngine`
- [ ] semantic `SoundID`
- [ ] original built-in sounds
- [ ] button sounds
- [ ] lever sounds
- [ ] repeater tick
- [ ] placement/removal
- [ ] invalid placement
- [ ] output activation
- [ ] master volume
- [ ] mute toggle

### Manual acceptance

- [ ] MANUAL: overlapping events play acceptably.
- [ ] MANUAL: mute works.

---

## Slice 25 — Audio panning

- [ ] event world position → screen position
- [ ] horizontal position → -1...1 pan
- [ ] clamp
- [ ] off-screen event policy
- [ ] unit tests for panning math

### Manual acceptance

- [ ] MANUAL: left/right controls sound directionally sensible.

---

## Slice 26 — Resource packs

- [ ] `AssetProvider`
- [ ] built-in provider
- [ ] pack manifest
- [ ] validation
- [ ] partial override fallback
- [ ] folder/zip selection
- [ ] reload
- [ ] diagnostics
- [ ] unit tests

### Manual acceptance

- [ ] MANUAL: overriding only grass texture works.
- [ ] MANUAL: missing assets fall back to built-in.

---

## Slice 27 — Minecraft Java texture importer

- [ ] common-install detection
- [ ] manual JAR picker
- [ ] safe ZIP/JAR inspection
- [ ] selected semantic texture mappings
- [ ] local cache
- [ ] import manifest
- [ ] remove/reimport
- [ ] no imported files enter repository

### Manual acceptance

- [ ] MANUAL: selected local JAR imports supported textures.
- [ ] MANUAL: project Git working tree remains free of copied assets.
- [ ] MANUAL: switching back to built-in pack works.

Do not implement sound importing in this slice.

---

## Slice 28 — Desktop Build Mode

- [ ] build-mode controller
- [ ] visible mode indicator
- [ ] temporary interactive overlay
- [ ] hotbar
- [ ] place
- [ ] erase
- [ ] rotate
- [ ] repeater delay edit
- [ ] reliable menu/status exit

### Manual acceptance

- [ ] MANUAL: entering/exiting never leaves Finder unusable.
- [ ] MANUAL: normal mode afterward is fully click-through.

---

## Slice 29 — Script execution outputs

- [ ] `executeOccupant`
- [ ] supported type validation
- [ ] resolved-path preview
- [ ] first-run authorization
- [ ] `Process` execution
- [ ] stdout/stderr capture
- [ ] exit code
- [ ] diagnostics result
- [ ] harmless fixture tests

### Manual acceptance

- [ ] MANUAL: harmless `.sh` on output prompts for first execution.
- [ ] MANUAL: approval runs script.
- [ ] MANUAL: repeater delay causes expected execution timing.
- [ ] MANUAL: moving script away prevents it from being targeted.

---

## Slice 30 — Simplified torch/inverter

- [ ] define orientation/input semantics
- [ ] NOT behavior
- [ ] tests
- [ ] rendering
- [ ] optional sound

---

## Slice 31 — Diagnostics UI completion

- [ ] permissions
- [ ] editor-selected and active desktop world/area identity
- [ ] library/migration/save status
- [ ] screen geometry
- [ ] raw/mapped Finder positions
- [ ] item count
- [ ] pointer coordinates
- [ ] camera values
- [ ] FPS
- [ ] sim tick rate
- [ ] resource pack
- [ ] last output/action
- [ ] debug overlay toggles

Acceptance:

- [ ] “my icon is one tile off” can be investigated without editing source to add print statements.

---

## Slice 32 — Multi-display continuous world

- [ ] virtual screen union
- [ ] one renderer per screen
- [ ] shared world and simulation
- [ ] per-window viewport
- [ ] pointer screen selection
- [ ] Finder mapping across monitors where viable
- [ ] display add/remove handling

### Manual acceptance

- [ ] MANUAL: terrain/circuit remains one continuous logical world.
- [ ] MANUAL: different backing scales do not break world mapping.

If Finder coordinate behavior makes cross-display mapping unreliable, document the limitation instead of faking it.

---

## Slice 33 — Polish

- [ ] app icon
- [ ] onboarding
- [ ] permission explanations
- [ ] settings
- [ ] reset/export world
- [ ] animation polish
- [ ] audio polish
- [ ] energy profiling
- [ ] memory profiling
- [ ] README demo video/GIF
- [ ] known limitations
- [ ] shutdown/relaunch robustness

---

## Slice 34 — Release engineering

- [ ] fresh-clone build instructions
- [ ] required Xcode version
- [ ] deployment target
- [ ] permissions documentation
- [ ] asset licensing statement
- [ ] third-party notices if needed
- [ ] GitHub Actions build/test if practical
- [ ] optional signing/notarization
- [ ] optional DMG/release archive

---

# 39. MVP definition

Do not call the project MVP until these work:

- [ ] seeded top-down terrain
- [ ] independent saved worlds with fixed seeds and isolated circuits
- [ ] named areas and explicit desktop activation
- [ ] persistent chosen desktop area
- [ ] cursor block highlight
- [ ] Finder icons naturally appear above world
- [ ] Finder positions tracked
- [ ] editor-authored circuits
- [ ] dust
- [ ] button
- [ ] lever
- [ ] repeater
- [ ] output
- [ ] water rejects circuit placement
- [ ] output opens current Finder occupant
- [ ] output optionally executes approved script occupant
- [ ] moving Finder item changes output target
- [ ] saved world survives restart
- [ ] basic display changes do not catastrophically break alignment
- [ ] original built-in assets
- [ ] basic audio
- [ ] diagnostics

Resource packs and Minecraft importing are useful but are not necessary to prove the central concept.

---

# 40. Explicit non-goals before MVP

Do not let implementation expand into:

- exact Minecraft terrain generation
- exact Minecraft redstone parity
- 3D rendering
- first-person camera
- multiplayer
- cloud sync
- backend/server
- iOS
- Windows/Linux ports
- Mac App Store work
- arbitrary plugin code
- webhooks
- Home Assistant
- weather APIs
- pistons
- mobs
- pathfinding characters
- crafting/inventory
- full terrain sculpting
- elaborate water physics

---

# 41. Major risks

## Risk A — Finder coordinate semantics

Highest early risk.

Mitigation:

- slices 6–8 occur before major game work
- visible diagnostics
- centralized adapter
- human calibration

## Risk B — Desktop window layering

Must be proven in Slice 2.

## Risk C — Click semantics

Global event monitoring observes but does not consume Finder events.

Normal mode may cause harmless Finder side effects such as deselecting a file when pressing a circuit button on blank desktop.

Accept initially.

## Risk D — Finder icon resize/rearrangement

Finder may move icons when settings change.

Always re-read actual positions.

## Risk E — Multiple monitors

Do one display first.

## Risk F — TCC/privacy permissions during development

Changing bundle identity/signature/build path can make macOS permission behavior confusing.

Keep a stable bundle identifier and document reset/troubleshooting steps when discovered.

## Risk G — AI over-engineering

Countermeasures:

- roadmap order
- no Metal without profiling
- no backend
- no exact Minecraft clone
- no massive plugin architecture

---

# 42. First compelling demo

Keep the first shareable demo deliberately simple:

```text
┌───────────────────────────────────────────────┐
│                                               │
│      [BUTTON]━━dust━━[REPEATER]━━[OUTPUT]    │
│                                      📄       │
│                                   hello.sh    │
│                                               │
└───────────────────────────────────────────────┘
```

Expected sequence:

1. user clicks button
2. button changes state
3. sound plays
4. dust lights
5. repeater delays
6. output flashes
7. authorized `hello.sh` executes
8. result is visible in diagnostics/terminal/log

Then the user drags `hello.sh` away and puts a different Finder item over the output.

The same circuit now affects the new occupant.

That communicates the idea immediately.

---

# 43. Future ideas after MVP

Do not implement yet.

Potential input blocks:

- time of day
- battery level
- process running
- file changed
- Git repository state
- network state
- Shortcut trigger

Potential components:

- lamps
- pressure plates
- timers
- logic-gate helpers
- comparator-inspired component
- wireless transmitter/receiver
- fixed-action “command block”

Potential world features:

- day/night
- seasons
- weather
- animated water
- ambient biome audio
- bridges over water
- terrain editing

Potential Finder interactions:

- recent file glow
- file-size effects
- particles toward output
- hover action preview

---

# 44. What the human project owner needs to know

You do not need to know Swift to start this project.

You do need to validate macOS behavior the AI cannot reliably see.

Expect the agent to eventually ask you to run the app and report observations like:

```text
Is the debug grid below Finder icons?
Does the marker sit under the icon center?
Did macOS show the Finder Automation prompt?
Can you still drag desktop files normally?
Does changing Finder icon size break alignment?
```

A good rhythm is:

```text
AI implements one roadmap slice
        ↓
AI runs automated tests/build
        ↓
you launch it
        ↓
you perform MANUAL checks
        ↓
fix problems if any
        ↓
commit
        ↓
next slice
```

Good commits:

```text
feat: add desktop-level SpriteKit renderer
feat: map global pointer into world coordinates
feat: read Finder desktop item positions
feat: add desktop occupancy resolver
feat: prove button-to-output vertical slice
```

Avoid one enormous “initial implementation” commit.

---

# 45. Prompt to give an AI coding agent

```text
Read SPEC.md completely before changing anything.

You are implementing Redstone Desktop from an empty/new repository.

Follow the IMPLEMENTATION ROADMAP in order. Do not skip ahead to polished terrain, resource packs, or advanced redstone before the macOS feasibility slices are proven.

For each slice:
1. State which slice you are implementing.
2. Inspect existing files before editing.
3. Implement the smallest complete version satisfying that slice.
4. Add/update automated tests.
5. Build the application.
6. Run the test suite.
7. Fix build/test failures caused by your changes.
8. Update SPEC.md checkboxes only for work actually complete.
9. Tell me exactly what I need to verify on my Mac. Mark MANUAL checkboxes complete only after I confirm the corresponding checks passed; record them as owner-reported validation.
10. Summarize changed files and manual validation steps.

Architecture rules:
- Swift native macOS.
- SwiftUI for normal app UI.
- AppKit for macOS desktop integration where appropriate.
- SpriteKit for the 2D world.
- Pure simulation/domain code must not depend on SpriteKit.
- All world/screen conversion goes through CoordinateMapper.
- Finder access goes through DesktopItemProviding.
- Action execution is separate from simulation.
- Renderer never launches files directly.
- Do not bundle Minecraft assets.
- Do not execute resource-pack code.
- Do not introduce a backend.
- Do not use private macOS APIs without explicitly flagging and justifying it.
- Prefer documented public APIs.
- If real macOS behavior contradicts SPEC.md, stop that slice, document the observation, and propose the smallest spec/architecture adjustment instead of layering hacks over it.

Start at Slice 0 unless the repository clearly proves earlier slices are complete.
```

---

# 46. Decision log

Use this section as implementation discovers reality. Dated entries describe decisions/status at that time; later adopted decisions supersede conflicting earlier behavior. The current contract is in Sections 3.8, 7.1, 25 and 29, and the roadmap order in Section 38.

Format:

```text
YYYY-MM-DD — Decision title
Context:
Decision:
Reason:
Consequences:
```

Initial decisions:

## Native Swift

Context: project depends on macOS desktop, Finder, windows, events, files, and application launching.

Decision: Swift + SwiftUI/AppKit.

Reason: direct access to supported platform APIs with minimal integration layers.

## SpriteKit first

Context: top-down pixel-art world is 2D.

Decision: SpriteKit.

Reason: enough capability with much lower complexity than Metal.

## Finder is observed, not replaced

Context: real desktop files are core to the idea.

Decision: keep Finder and map icons into world space.

## Original built-in assets are mandatory

Context: optional imported assets may be useful, but the GitHub project must stand alone and avoid distributing copied game assets.

Decision: complete original pack + optional local import/custom packs.

## 2D redstone-inspired semantics

Context: exact Minecraft redstone contains many irrelevant 3D/edge-case behaviors.

Decision: deterministic familiar 2D system.

## 2026-10-07 — Provisional Finder calibration, pending visual evidence

Context: the owner confirmed Slice 6 can read Finder items and raw desktop positions. Finder's scripting dictionary describes `desktop position` but does not establish icon-center semantics or the coordinate origin.

Decision: Slice 7 tests the hypothesis that the raw point is an icon center in logical points from the primary display's upper-left. `CoordinateMapper` alone flips Y using the primary frame's `maxY`; no menu-bar or icon-size offset is applied. Diagnostics show raw position, mapped screen/assumed center, and world tile. Pink markers and explicit 2 Hz polling make the hypothesis reviewable.

Reason: establish the coordinate contract with visible evidence before implementing occupancy. The primary display reference comes from the documented first `NSScreen.screens` entry, independently of the active renderer screen.

Consequences at the time (superseded by the owner confirmation below): this was not a discovered/verified Finder semantic yet. “compare visually”, “document discovered semantics”, and all MANUAL checkboxes remain unchecked. A mismatch must stop this slice and be recorded here before proposing the smallest mapping adjustment. Polling is serialized with explicit reads, publishes meaningful item differences only, and pauses on errors; slow main-thread AppleScript behavior must also be reported.

---

## 2026-10-07 — Owner confirms Finder calibration; occupancy contract

Context: the owner reported “It all appears to work!” after the Slice 7 marker, dragging, screen-edge, and icon-size validation instructions. This records owner-reported evidence on their Mac; the agent did not independently verify those physical desktop checks.

Decision: use the tested center mapping for Slice 8: Finder desktop position is interpreted as an icon center in logical points from the primary display's upper-left. Flip Y using that display's frame maxY, with no menu-bar or icon-size adjustment. All conversion remains in CoordinateMapper. Recheck and stop if a later configuration contradicts this mapping.

Occupancy groups centers in the active display into floor-based world tiles. One center is occupied; multiple centers are ambiguous and retain every item in stable order. Outside-display centers are excluded. Unread or failed Finder data is unavailable, not empty. Green and red tile overlays expose this state without executing actions. Explicitly paused polling freezes the last snapshot.

Consequences at the time: the earlier provisional decision remains as history. Slice 7's comparison and semantics tasks were completed based on the owner's report. The original instruction kept MANUAL checkboxes unchecked until the later policy update below. Slice 8's boundary check was still pending at this point.

---

## 2026-10-07 — Record owner-confirmed manual acceptance

Context: the owner confirmed Slice 8 with “It works!” and explicitly requested checking off previous manual validations and future checks as they confirm them. Their earlier confirmations covered the manual acceptance instructions for Slices 0, 2, 4, 5, 6, and 7.

Decision: mark the 20 roadmap MANUAL checks through Slice 8 complete based on those owner reports. These are physical-Mac checks reported by the owner, not checks performed by the agent. The owner's instruction supersedes the original blanket prohibition against updating MANUAL checkboxes.

Consequences: Slices 0–8 have completed required acceptance checks. Future MANUAL items remain unchecked until the owner confirms the corresponding checks. Slice 9 is next and remains unimplemented. Build/test success alone never establishes manual completion.

---

## 2026-10-07 — Fixed button-to-output feasibility circuit

Context: Slice 8's occupancy boundary was confirmed by the owner. Slice 9 must prove the open-occupant path before the general world model or simulator.

Decision: use fixed world tiles (2, 3) for the button, (3...6, 3) for dust, and (7, 3) for output. The pure FixedTestCircuit emits one output activation on the rising edge of a 20-tick pulse; another press during power restarts the pulse without another activation. SpriteKit displays this state and a white output flash. The separate OpenItemAction sends the unique local Finder occupant to NSWorkspace for ordinary opening.

Each press requires a prior explicit successful Finder read and performs a fresh serialized read before activating. Busy reads request a retry, rather than using stale data or accumulating requests. Errors, ambiguity, and missing occupancy never choose a target. Session invalidation suppresses a cancelled read after disabling/re-enabling the desktop.

Finder interaction takes priority. Public on-screen window metadata excludes desktop elements and rejects clicks covered by ordinary windows; Finder must be frontmost. Window rectangle conversion stays in CoordinateMapper. A conservative one-tile margin around PRESS rejects nearby icon centers because exact Finder icon/label hit regions are not available from the center query. This intentionally favors Finder and is not claimed as exact hit testing. No private API, window capture, script executor, resource packs, or general simulation engine is introduced.

Consequences: implementation/build and 59 automated tests pass, including pure pulse/rising-edge tests, fake Finder/open integration, target movement, ambiguity, failure, cancellation, and window metadata checks. Real desktop activation and opening remain the five unchecked Slice 9 MANUAL checks. Stop and record any contradictory macOS behavior before advancing through Gate A.

---

## 2026-10-07 — Slice 9 stopped: window bounds are not click ownership

Observation: the owner reports that PRESS never activates the wire and provides no feedback, with or without an output item. A read-only query of CGWindowListCopyWindowInfo on this Mac returned a Dock-owned, layer-20, alpha-1 window with bounds (0, 0, 1728, 1117), covering the entire primary display. Its transformed bounds include the PRESS center (160, 224). The query was made while Brave was frontmost; it is not a captured Finder click or proof of which branch rejected the owner's exact click. It does establish a concrete false-positive mechanism in the current gate.

Contradicted assumption: every non-desktop, nonnegative-layer window rectangle containing a point owns that click. A large system window can have a full-display rectangle without visually covering or receiving clicks over the entire rectangle. The current gate also returned silently, hiding the rejection reason.

Decision: stop Slice 9 at Gate A. Restore the clicking-button task to unchecked; all five Slice 9 MANUAL checks remain unchecked. Add a PRESS observation counter and explicit rejection/read feedback, plus a fixture reproducing the actual Dock metadata. Keep the gate conservative while diagnosing; do not add Dock-name exceptions, layer-number exceptions, or remove ordinary-window protection.

Smallest proposed architecture adjustment: forward the captured mouse event's public recipient/window identity through DesktopClickMonitor. Determine whether Finder's desktop received that event, rather than treating every reported rectangle as a hit region. Public NSEvent windowNumber and CGEvent recipient/window fields are candidates; verify their real global-monitor values on this Mac before relying on them. Continue rejecting Finder folder-window and other application-window clicks. If that metadata is insufficient, document it and choose the smallest public-API alternative instead of adding owner-name heuristics.

Validation: the diagnostic revision builds and all 60 automated tests pass. These establish pulse/action behavior with fakes and rejection feedback, not a working physical desktop click. The next owner check should report the PRESS counter, last observed tile, and rejection result. No successful end-to-end action is claimed until Gate A is revalidated.

---

## 2026-10-07 — Replace bounds inference with captured recipient identity

Context: the owner confirmed PRESS was counted at (2, 3) and explicitly reported the Dock layer-20 rejection message. This confirms the gate failure; the amber click flash is diagnostic feedback, not a circuit pulse. Clicking the checkerboard is correct because it is click-through.

Decision: carry the captured mouse event's windowNumber, handling-window ID, and target-process ID through DesktopClickMonitor. Query metadata for only that recipient window. Accept Finder ownership at CGWindowLevelForKey(.desktopIconWindow); reject ordinary Finder/application windows and missing or conflicting identity. The public handling-window field is preferred when present; NSEvent.windowNumber is the fallback. A nonzero event target PID must agree with the window owner PID. There are no Dock-name or layer-20 exceptions. Remove the unused Quartz rectangle conversion added for the superseded gate.

Evidence and limits: a read-only live query found Finder desktop window 107 at layer -2147483603, equal to the SDK's public desktopIconWindow level. Two command-line listener attempts received no events even though the owner clicked; they do not verify the real global-monitor recipient fields. The new app captures them directly and explains missing recipient identity in its rejection result. If those fields are absent or contradict the model on a real click, stop and document that observation before another adjustment.

Validation: build succeeds and all 63 tests pass. Tests cover native event-field extraction from an unposted fixture, identity forwarding with mapped tiles, desktop acceptance, ordinary-window rejection, missing/conflicting identity, and existing circuit/action behavior. No new manual check is marked complete. The clicking-button task remains unchecked pending the owner's retest; Gate A and Slice 9 remain incomplete.

---

## 2026-10-07 — Captured target PID does not match window owner

Observation: the owner reports no circuit change and “Click recipient and target process disagree; nothing activated.” The event reaches PRESS, but the PID-equality requirement rejects it. This does not establish what either PID represents in that monitored copy, nor prove that the selected window is Finder's desktop.

Smallest proposed correction: use the documented NSEvent.windowNumber as the associated-window identity when available, with the public handling-window field only as fallback. Validate that selected window's owner and public desktop-icon level. Retain target PID as diagnostic data instead of equating it with window ownership. Show all selected/raw identity values and window metadata in the editor; keep ordinary Finder/application windows rejected. No process-name exceptions, event consumption, or private APIs are proposed.

Implemented adjustment: select the associated window first, query its owner/layer, and keep target PID out of the acceptance predicate. The editor shows the complete raw and selected-window metadata on every PRESS attempt. Regression tests accept a Finder desktop with a different target PID, still reject ordinary Finder/application windows, and verify window-number preference/fallback. Build succeeds and all 64 tests pass.

Slice 9 remains stopped at Gate A pending the owner's real-Mac retest. Its clicking-button task and five MANUAL checks remain unchecked. Do not advance to Slice 10 or describe the physical circuit as working based on automated fixtures.

---

## 2026-10-07 — Owner confirms circuit activation and occupant opening

Context: after the associated-window/PID correction, the owner reports “That worked! If I place something there, it opens it too.”

Decision: mark the clicking-button task and the first three Slice 9 MANUAL checks complete: place an item on output, press and see signal, and occupant opens. This is owner-reported real-Mac validation, distinct from the 64 passing automated tests.

Consequences: the previous click-gate blocker is resolved for the owner's tested configuration. Moving the occupant away and moving a different item onto output have not yet been confirmed in this report; those two MANUAL checks remain unchecked. Gate A remains open until they pass. No claims are added for window-overlap, repeat-press, or ambiguity manual checks not explicitly reported.

---

## 2026-10-07 — Owner confirms target removal and replacement; Gate A passes

Context: after the final two Slice 9 manual instructions, the owner reports “It passes those checks.” This confirms that moving the occupant away leaves no target and moving a different item onto output changes the target.

Decision: mark the remaining two Slice 9 MANUAL checks complete based on the owner's real-Mac report. All Slice 9 tasks and its five manual acceptance checks are now complete; feasibility Gate A passes for the tested configuration.

Consequences: Slice 10 (World model) is next and remains unchecked. The earlier gate failures and partial confirmations remain in the log as history. No new claims are made about other configurations or additional manual checks not reported by the owner. The last implementation revision built successfully and passed 64 automated tests; this update changes documentation only.

---

## 2026-10-07 — Explicit world and circuit model

Context: the owner confirmed every Slice 9 manual acceptance check, passing Gate A, and authorized Slice 10. The scene previously contained fixed test button/output coordinates and a single hardcoded wire.

Decision: add pure Codable/Equatable/Sendable World, Tile, TerrainID, DecorationID, and CircuitWorld types. World stores explicit tile data and a separate coordinate-keyed component dictionary. Missing terrain is unspecified; there is no generator or implied placement rule. Geometric cardinal adjacency is overflow-safe and is not a signal-propagation rule.

Keep the proven feasibility circuit as a model fixture created by FixedTestCircuit.makeWorld. Runtime power is separate from component identity. DesktopScene consumes the supplied World and a powered-coordinate set, draws only visible explicit tiles/components, and rebuilds that content on size changes. Output flashes use the event's output coordinate rather than a renderer constant. The checker remains a diagnostic background; six explicit grass tiles use plain placeholder fills. No general simulator, editor authoring, seeded terrain, persistence I/O, or resource packs are introduced.

Validation: Debug build and all 72 tests pass. The pure World/Circuit sources type-check independently of AppKit and SpriteKit. Tests cover value independence, negative-coordinate Codable round trips, all semantic IDs, cardinal/limit adjacency, the feasibility fixture, rendering an alternate model, clearing removed content, per-coordinate visual power, output geometry, and resize culling. Earlier fake Finder/open integration remains green. No new MANUAL item is inferred from those tests; a short owner regression check of the existing desktop demo is documented in README.

Consequences: all Slice 10 tasks are complete. Slice 11 (Circuit simulator core) is next and remains unchecked. The demo still uses the fixed feasibility pulse, rather than claiming the full engine exists.

---

## 2026-10-07 — Owner confirms Slice 10 regression

Context: the owner reports “I confirm it works basically the same as before except with green blocks under the circuit.”

Decision: record the model-rendering regression check as passed on the owner's Mac. The green blocks are the explicit grass tiles in the feasibility World fixture and are expected. This report confirms the existing demo behaves as before after moving rendering to model data.

Consequences: Slice 10 remains complete. It has no additional roadmap MANUAL checkbox, so none is invented or changed. Slice 11 remains next and unchecked. The last implementation build and all 72 automated tests passed; this update changes documentation only.

---

## 2026-10-07 — Owner confirms Slice 11 regression

Context: after receiving the Slice 11 Mac walkthrough, the owner reported: “It seems to work as expected!”

Decision: record the Slice 11 regression as passed based on the owner's Mac report. This is owner-reported validation, separate from the 86 passing automated tests; no additional agent-performed physical checks are claimed.

Consequences: Slice 11 is complete. It has no roadmap MANUAL checkbox, so none is invented or changed. Slice 12 (Repeater) is next and remains unchecked. The last application build and all 86 tests passed; this update changes documentation only.

---

## 2026-10-07 — Slice 12 directional delayed repeaters

Context: the owner confirmed the Slice 11 regression and authorized Slice 12. Repeaters previously had identity/orientation but no simulation semantics.

Decision: add RepeaterDelay configuration constrained to 1–4 redstone ticks, equivalent to 2/4/6/8 simulation ticks. Direction denotes the repeater's forward output; it reads only the opposite/rear tile. A positive valid rear signal becomes power 15 at the configured delay, regardless of its strength. Only the forward tile receives repeater power, including dust, an output, or the rear of a correctly aligned repeater. Side/front inputs and side/rear emission are rejected. Checked Direction adjacency remains domain geometry; all screen/world conversions still go through CoordinateMapper.

Timing contract: a rear input sample observed on simulation tick T appears at the repeater output on tick T + delay. Both on/off transitions are delayed equally using a fixed-length Boolean history of 2–8 samples per repeater. Short pulses are preserved even if input has turned off before their due tick. Aligned chain delays add. This is a transport delay contract, without Minecraft parity, pulse stretching, locking, or update-order quirks.

All repeater histories mature before dust is solved; rear input samples are collected from the completed power snapshot and committed together. Repeaters never read another repeater's partially updated history. The existing bounded dust queue remains, with at most one initial queue entry per powered source/repeater and 15 increases per dust tile. Delayed feedback can produce circuit feedback over later ticks, but never recursively propagates or performs unbounded work inside a tick. Histories contain at most eight samples per repeater. The immutable simulator world fixes delay configuration for its lifetime; future editor world changes must deliberately rebuild/reconcile runtime state.

Model Codable encoding includes repeaterDelay. Earlier components without this key decode to one redstone tick; invalid present values, including null, are rejected. No persistence I/O or document migration system is added. The placeholder renderer shows a direction arrow and delay (for example “→ 4t”), gray when off and orange when powered. It consumes model/power only and remains action-free.

Keep the original button and lever rows. Add a third demo row at y=7: button (2, 7), dust (3–4, 7), east-facing four-tick repeater (5, 7), dust (6, 7), output (7, 7). This demonstrates weaker rear dust at 14 restored to 15 after eight simulation ticks. Output events continue through the existing fresh-Finder-read and OpenItemAction path; disabling clears pending pulse histories and actions.

Validation: Debug build succeeds and all 101 automated tests pass. Pure World/Circuit files typecheck independently with Swift 6. New tests cover all delays on both edges, 20-snapshot button pulse duration, one-tick pulses, all orientations, forbidden input/emission directions, power restoration and downstream attenuation, aligned/reversed chains, output non-relay, delayed feedback loops, dictionary insertion order, integer limits, and delay Codable validation/defaulting. Renderer tests verify arrow/delay labels, power colors, geometry, and retained model after resize. Fake Finder integration verifies delayed opening uses the fresh occupant and disable/re-enable clears a pending repeater pulse.

Consequences: all seven Slice 12 implementation/test tasks are complete. Owner Mac regression confirmation is pending, and no MANUAL checkbox changes. Slice 13 and later remain unchecked. README.md provides the new-row check and regression instructions. No general editor, polished textures, terrain generation, resource packs, script execution, backend, or private macOS API is added.

---

## 2026-10-07 — Owner confirms Slice 12; continue with rightward demos

Context: after the repeater walkthrough, the owner reported “It works!” and requested documenting confirmation and implementing the next slice in a single step. They also requested that additional desktop test circuits go to the right rather than above existing rows.

Decision: record Slice 12 regression as passed on the owner's Mac, separately from its 101 automated tests. Preserve existing circuits and extend future demo fixtures rightward. Record confirmation and continue to Slice 13 in this same turn.

Consequences: Slice 12 is complete. It has no roadmap MANUAL checkbox, so none is invented. This confirmation does not imply Slice 13 visual acceptance.

---

## 2026-10-07 — Slice 13 snapshot-driven circuit renderer

Context: circuit rendering used generic blocks and geometric dust lines. The next slice needs distinct visual states and output occupancy without introducing actions into SpriteKit.

Decision: extract CircuitRenderer, consuming CircuitWorld, powered coordinates, occupancy snapshot, CoordinateMapper, and screen/viewport geometry. Use ten small original code-drawn placeholder textures under semantic CircuitTextureID values, cached per scene and rendered with nearest filtering. No texture files, Minecraft assets, pack loader, terrain generation, or general asset-import framework are added.

Dust halves meet at shared tile edges and connect to component frames. They reject diagonal/empty neighbors and repeater side ports; corners, tees, and crosses follow the supplied model. Dust is red when off and yellow when powered. Buttons use raised/depressed images and PRESS/DOWN labels; levers change handle/image and OFF/ON label. Repeaters rotate an arrow image and retain their orientation/delay label, with distinct off/on images. Outputs use a power image independently of occupancy: EMPTY/gray, ITEM/green, MANY/red, N/A/purple. Occupancy changes do not alter simulation power. Finder remains above the renderer, so icons may cover parts of a block or badge.

DesktopScene retains occupancy alongside world/power, so later power refreshes and viewport resizes preserve output state. Each output activation gets its own white 0.5-second fade/removal effect. Repeated activation of the same coordinate restarts that effect without accumulating nodes; different output coordinates can flash concurrently. Model removal clears obsolete output effects. Rendering receives snapshots only; it has no Finder provider or file-launch dependency. Existing OpenItemAction and simulation behavior are unchanged.

Validation: Debug build succeeds and all 107 automated tests pass. New checks cover isolated/corner/tee/cross dust geometry, repeater side-port exclusion, texture reuse/filtering and off/on bitmap differences, committed button/lever states, all four output occupancy states while held powered, occupancy retention on resize, independent bounded output flashes, and removal cleanup. Existing repeater tests now also verify arrow-image rotation and texture switching. Fake Finder/action integration continues to pass. A generated native art contact sheet was inspected; this is texture inspection, not physical desktop validation.

Consequences: all eight Slice 13 implementation tasks are complete. Its MANUAL visual-state checkbox remains unchecked until the owner confirms the current Mac walkthrough. Slice 14 and later remain unchecked. No new desktop test circuit is added; all three existing rows retain their positions, and future additions go to their right.

---

## 2026-10-07 — Owner confirms Slice 13 visual acceptance

Context: after the current circuit-renderer Mac walkthrough, the owner reported “Looks good!”

Decision: mark Slice 13's MANUAL visual-state checkbox complete based on this owner-reported Mac validation, separate from its 107 passing automated tests. Continue to the next slice in the same turn, as requested.

Consequences: Slice 13 is complete. This report does not imply validation of the new Slice 14 placement UI.

---

## 2026-10-07 — Slice 14 terrain capabilities and validated placement

Context: the renderer and simulation work, but no shared placement policy prevents components on water, decorations, or occupied cells. A small developer form is required before the general editor.

Decision: add pure TerrainDefinition capabilities, PlacementRuleEvaluating/PlacementRules, typed PlacementResult/failure reasons, and a CircuitPlacement transaction. All four dry terrain IDs support dust and heavy components; both water IDs support neither. Missing explicit terrain rejects placement rather than guessing generated terrain. All existing decorations, including reeds, block placement and remain unchanged; clearing requires a deliberate future tool. Reject empty-as-placement, reserved cells, and existing non-empty circuit components, even if the proposed component is identical. Repeater direction/delay are already constrained by typed configuration and validated Codable decoding.

Evaluate in deterministic order, then insert only when allowed. Rejected transactions preserve the complete World; successful transactions preserve terrain, decoration, and unrelated circuit data. Stored .empty identities are vacant. The centralized evaluator is reusable by the future editor/build tools; the developer UI's preview and actual placement use this same policy.

DeveloperPlacementFixture supplies an explicit patch to the right of the original circuits: x=10–15 at y=3 for grass, dirt, stone, sand, shallow/deep water; tree/flower/rock/reed at x=10–13, y=5; unspecified terrain at (14, 5). It leaves all original circuit and tile coordinates unchanged. No procedural generation or additional prebuilt circuit is added.

A separate scrollable SwiftUI Developer Placement window chooses a component and test tile, shows the policy result, and offers Place component / Reset test placements. Repeaters expose their typed orientation/delay configuration. Editing is locked while Desktop World is enabled, both in the UI and AppState methods, so active simulation and pending action reads cannot be changed by this form. With the world disabled, an accepted placement publishes the new world and creates a fresh unpowered simulator; enable/disable retains the placed configuration within this app session. Reset removes components only from test-patch coordinates. Nothing is saved to disk; persistence and the general canvas editor remain later slices.

Validation: Debug build succeeds; all 123 automated tests pass. Pure World/Circuit sources pass standalone Swift 6 typechecking. Tests cover the terrain capability table and every component on dry/water/decorated cells, negative/extreme coordinates, occupied-cell rejection, identical-placement rejection, complete-world preservation on failure, preserved repeater configuration/unrelated data on success, vacant .empty cells, reserved cells, deterministic reasons, and rightward fixture integrity. App integration tests verify no Finder/file actions for placement, locked live edits/reset without interrupting a held circuit, patch-only reset, new-world simulation, fresh occupant opening by a placed circuit, and retention across enable/disable. The SwiftUI form is hosted by an automated test; physical Mac interaction remains owner validation.

Consequences: all five Slice 14 tasks and three automated acceptance items are complete. Slice 14 has no roadmap MANUAL checkbox, so none is invented or inferred. README.md gives the exact developer-form regression checks; owner confirmation is pending. Slice 15 and later remain unchecked. No canvas editing, terrain generation, persistence I/O, resource packs, private APIs, or backend are added.

---

# 47. Public technical references

Re-check the current SDK documentation while implementing.

Apple desktop window level:

https://developer.apple.com/documentation/swiftui/windowlevel/desktop

Apple global event monitor:

https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)

Apple mouse location:

https://developer.apple.com/documentation/appkit/nsevent/mouselocation

Apple screen-change notification:

https://developer.apple.com/documentation/appkit/nsapplication/didchangescreenparametersnotification

Apple NSWorkspace:

https://developer.apple.com/documentation/appkit/nsworkspace

Apple Apple Events automation entitlement:

https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events

Apple NSAppleScript:

https://developer.apple.com/documentation/foundation/nsapplescript

Apple Accessibility trust API if later needed:

https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions

Minecraft EULA:

https://www.minecraft.net/en-us/eula

Minecraft Usage Guidelines:

https://www.minecraft.net/en-us/usage-guidelines

---

# 48. Final priority order

When uncertain, prioritize in this exact order:

```text
1. Never break the user's normal desktop.
2. Correct screen/world coordinate mapping.
3. Reliable Finder item mapping.
4. Deterministic circuit logic.
5. Reliable output actions.
6. Persistence.
7. Editor usability.
8. Procedural-world quality.
9. Audio/animation polish.
10. Asset/import extras.
```

The project succeeds even if the first terrain is ugly.

It fails if the terrain is beautiful but the Finder icon is mapped to the wrong output tile.

The central magic is:

> A real desktop item can be physically moved onto a circuit endpoint in a persistent block world, changing what the circuit does.

Everything in the architecture should protect that interaction.


## 2026-10-07 — Slice 11 deterministic circuit simulator

Context: the owner confirmed Slice 10 behaves as before, including its grass tiles, and authorized the next slice. The fixed feasibility pulse could not simulate arbitrary component networks.

Decision: replace FixedTestCircuit with a pure CircuitSimulator and a model-only DemoCircuit fixture. The simulator accepts button presses and lever toggles, computes an entire next power snapshot from active sources, emits output rising edges, and commits the snapshot. Sources emit 15; the first adjacent dust receives 15 and subsequent dust-to-dust steps attenuate by one. Only cardinal dust connections transmit power. Outputs sense neighboring sources/dust but never relay power. Repeaters remain inert until Slice 12.

Within one simulation tick, an iterative queue settles the network to its strongest reachable power. Each queued dust update strictly increases a level bounded by 15; previous tick power never seeds the queue. This bounds work and prevents loops retaining power after a source turns off. Coordinates and output events are sorted by (y, x), independent of dictionary insertion order. A button powers exactly 20 tick snapshots, then turns off on tick 21; re-pressing restarts its remaining duration without retriggering a held output. Levers remain on until toggled off. Runtime state resets when the diagnostic desktop world is disabled; saving/restoring lever state with a persistent world remains for the persistence slice.

A separate injectable CircuitTickScheduler registers a 50 ms timer in the main run loop's common modes. Rendering consumes simulator state and stays separate from actions. Main-thread delays, including the existing synchronous Finder scripting adapter, can lengthen visible wall-clock pulses; the scheduler does not issue catch-up bursts. Exact pulse duration is tested in simulation ticks, rather than claiming real-time timing on the owner's Mac.

AppState dispatches rising-edge events to a bounded queue of at most 32 pending output actions. It waits for existing Finder/input reads, refreshes occupancy through DesktopItemProviding before each action, and delegates opening to OpenItemAction. Read failures clear pending actions; disabling invalidates late results and clears power/actions. The renderer never launches files. The original button row remains at y=3; a separate lever row at y=5 permits held-power regression checks without adding editor authoring.

Validation: Debug application build succeeds; all 86 automated tests pass. Pure World/Circuit sources pass standalone Swift 6 typechecking. Tests cover attenuation to zero, exact button expiry/repress, held levers and output edges, loops including a 1,600-dust grid, insertion order, strongest sources, prohibited diagonal/output relay, deferred repeaters, coordinate overflow, scheduler registration/stop/restart, serialized fresh output reads, item replacement, and disable/re-enable invalidation. Existing mapping, Finder, occupancy, actions, and renderer integration tests also pass.

Consequences: Slice 11 tasks and required automated-test checkboxes are complete. No MANUAL checkbox is changed or newly claimed. Owner regression confirmation is pending; README.md gives the exact Mac checks. Slice 12 and later slices remain unchecked. No persistence I/O, advanced component semantics, terrain generation, resource packs, private APIs, or backend are introduced.


## 2026-10-07 — Slice 14 owner confirmation and Slice 15 basic editor

Observation: the owner reported “Looks good! Continue.” after the Slice 14 placement walkthrough. Record that as owner-reported regression validation, separate from the 123 automated tests. Slice 14 has no MANUAL checkbox to add or change.

Decision: implement Slice 15 with a normal SwiftUI editor surrounding a local AppKit/SpriteKit canvas. Reuse the snapshot-only DesktopScene/CircuitRenderer. EditorSession owns an independent camera, tools, selection and hover; all canvas/world conversion, pan and anchored zoom go through CoordinateMapper. Native local mouse events keep upward Y coordinates; hover uses Apple's documented [NSTrackingArea](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/TrackingAreaObjects/TrackingAreaObjects.html) mouse-moved option. Source/output clicks in the editor select or place components; only real desktop input can activate the simulation/action adapter.

Placement uses the existing centralized evaluator. Erasing removes only circuit components, and the inspector changes typed repeater direction/delay. All world edits require Desktop World disabled, preserving the simulation's immutable configuration and cancellation boundary. The editor reads cached world occupancy, never queries Finder or opens files. Browsing does not move the desktop camera or remap physical targets. Existing controls remain available in a separate Desktop Controls window.

Add an explicit 80-tile grass construction area at x=10–25, y=7–11, to the right of the three original circuits. Preserve the developer terrain patch and all earlier component positions. This is a finite fixture, not terrain generation. Developer patch reset leaves the construction area intact. Changes survive desktop enable/disable within this app session; no persistence is claimed.

Validation: Debug application build and all 135 tests pass. Twelve new tests cover mapper pan/anchor zoom, independent bounded navigation, every placement tool, invalid/occupied rejection, terrain-preserving erase, repeater inspection/configuration, live-edit locks, out-of-canvas input, bounded preview/selection nodes, cached occupancy without Finder reads, native local mouse click/pan coordinates, hosting without permissions, and an authored button/dust/repeater/dust/output circuit with a fresh occupant opened once after its configured delay. Pure World/Circuit sources also type-check independently of AppKit and SpriteKit. A temporary test window's teardown ownership was corrected in the test harness; it is not evidence of an application-window failure.

Consequences: all fourteen Slice 15 implementation tasks are complete. The MANUAL useful-circuit authoring checkbox remains unchecked until the owner validates the current Mac walkthrough. Automated hosting and synthetic mouse events do not establish visible/native-interaction acceptance. Slice 16 and later remain unchecked. No persistence, procedural terrain, Finder ghosts, resource packs, private APIs, or backend are added.


## 2026-10-07 — Owner confirms Slice 15; Slice 16 persistence

Context: the owner reported “It works! Thats neat.” after the basic editor's circuit-authoring/run walkthrough. Mark Slice 15's MANUAL acceptance complete based on that owner-reported Mac validation, separate from its 135 automated tests. Continue directly to Slice 16.

Decision: introduce Foundation-only WorldDocument, WorldStore and a main-actor WorldAutosaver adapter. Format version 1 includes stable world identity/name, terrain fixture version 1, desktop camera, circuit configuration and ON lever coordinates. Recreate the explicit fixture tiles by version instead of persisting terrain tile-by-tile. Generator settings are deliberately deferred until Slice 17; a future schema/version adjustment will distinguish generated worlds from this prototype fixture. Editor camera remains temporary exploration state.

Store the last world at ~/Library/Application Support/RedstoneDesktop/world.json. Use Apple's documented [Application Support location](https://developer.apple.com/documentation/foundation/url/applicationsupportdirectory) and [atomic Data write](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic). Autosave after 0.75 seconds of no further configuration edits, retaining only the newest snapshot. Save Now retries a failed write. Disable/quit synchronously flushes pending changes before clearing runtime power, tasks and monitors. Tests inject stores; normal AppState test construction has persistence disabled and never reads/writes the owner's actual file.

Restore configuration before desktop integration starts. Startup always leaves Desktop World disabled and does not query Finder or open files. Saved ON lever positions resume after explicit enable; outputs can activate at that point if Finder has been explicitly read. Disable clears runtime power/pulses/history while preserving durable lever positions. Buttons, runtime power, repeater history, pending actions, Finder data/paths, permissions and enabled state are not saved. Edits/reset prune removed lever coordinates and share the existing placement policy.

Validation rejects unsupported document/fixture versions, invalid cameras, invalid component configuration/placement, lever coordinates that are not levers, malformed/truncated JSON and documents over 2 MB. Missing files start a new fixture. Other load failures display an actionable status and disable all writes for that session, preserving the original file even after subsequent edits/quit. Failed saves retain the newest pending snapshot for retry; no silent success or destructive reset is claimed.

Validation: Debug application build and all 148 automated tests pass. Thirteen persistence tests cover JSON/value round trips, terrain reconstruction without stored tiles, stable identity and camera, version/configuration validation, nested Application Support-style directory creation, full-file replacement, invalid-save and filesystem-failure preservation, damaged/oversized documents, debounce coalescing and flush cancellation, failed-save retry, AppState edit/erase/repeater restoration on shutdown/reopen, corrupt-load write blocking, developer patch reset, rejected-edit no-save, and saved lever resume with explicit enable/Finder access. Existing 135 tests remain green.

Consequences: all seven Slice 16 implementation tasks are complete. Its MANUAL restart checkbox awaits the owner's Mac test; automated lifecycle calls do not prove Command-Q/relaunch behavior. Slice 17 and later remain unchecked. No terrain generator, seed UI, general import/export, resource-pack code, backend or private API is introduced.


## 2026-10-07 — Owner confirms Slice 16; Slice 17 deterministic generation

Context: the owner reported “Works!” after the persistence quit/reopen walkthrough. Mark Slice 16's MANUAL checkbox complete based on that owner-reported Mac validation, separate from its 148 automated tests. Implement only the next slice's generator; chunk rendering/cache and seed browsing remain Slices 18–19.

Decision: add a stateless pure Swift WorldGenerator with Codable WorldGenerationSettings (generationVersion and full UInt64 seed), project-owned SeededNoise, ChunkCoordinate and TerrainChunk. Generation version 1 fixes all scales, thresholds and densities. Reject unknown generation versions instead of silently changing their terrain. No Swift Hasher, system random generator, OS noise API, trigonometry or floating-point sampling is used.

Hash global lattice coordinates and independent field channels using fixed UInt64 avalanche constants and wrapping arithmetic. Integer Q16 smooth interpolation yields elevation, moisture and temperature in 0…65535. Elevation blends 64- and 32-tile fields; biome/moisture/temperature use 128-tile fields. Classify wetland, plains, woodland, desert and rocky areas; generate grass, dirt, stone, sand, shallow/deep water. Shore heights select sand/shallow-water transitions. An independent coordinate roll places trees/flowers/rocks/reeds only on their designated terrain. Terrain sampling is independent of circuits and placement remains governed by the existing shared capabilities.

Chunks are fixed 32×32 snapshots sampled at global coordinates, not independently seeded images. Mathematical floor division gives negative chunk addresses without negating Int.min or multiplying intermediate negative origins. Checked chunk-origin multiplication rejects unrepresentable requests; valid chunks containing Int.min/Int.max still produce all 1,024 tiles without overflow. Sampling is exact even at those integer limits and does not convert large coordinates to Double. The generator owns no cache, unbounded world collection or renderer.

Validation: Debug build and all 157 tests pass; pure World/Circuit files also type-check independently of AppKit/SpriteKit. Nine new tests cover negative chunk boundaries, full integer limits, overflow refusal, noise range/lattice values/continuity, request-order independence, full chunk-to-global sample equality across negative/positive axes, smooth boundary fields, fixed version-1 semantic field/terrain/decoration fingerprints for seeds 42 and 2026, different-seed terrain differences, all six terrain/four decoration/five biome types, decoration constraints, settings Codable/full UInt64 seed and unsupported-version rejection, and reuse of placement capabilities without changing the original circuit fixture.

Generate a standalone developer comparison with scripts/terrain-preview.sh. It compiles only the pure domain/generator plus an artifact writer and writes build/terrain-preview.svg: 128×128 samples per seed at coordinates −64…63, 32-tile chunk lines and decoration dots. The generated image was inspected and the two seeds visibly differ without artificial chunk borders. This is a data preview, not verification of a live desktop terrain renderer. Snapshot fingerprints were recorded after inspection; changing version-1 output requires an explicit version/migration decision.

Consequences: all ten Slice 17 tasks and three acceptance items are complete. This slice has no roadmap MANUAL checkbox; no new one is invented. The application footer identifies Slice 17, while existing fixture rendering, saved JSON, desktop camera and circuit behavior remain intact. Generated-world persistence/migration will be added when generated worlds enter the application; current format-1 fixture documents are not rewritten or reinterpreted. Slice 18 and later remain unchecked. No chunk cache/render nodes, seed UI, procedural live terrain replacement, resource packs, private APIs or backend are introduced.


## 2026-10-07 — Owner confirms Slice 17; automatic Finder refresh and Slice 18

Context: the owner confirmed the Slice 17 regression behaves and looks basically identical, and requested removing the repeated need to press Read Finder Items. Record that as owner-reported Mac validation, separate from the 157 automated tests. Slice 17 has no MANUAL checkbox. Continue to Slice 18 and make the requested Finder workflow change.

Decision: the normal app enables automatic Finder refresh when Desktop World is enabled, using the existing serialized DesktopItemTracker at 2 Hz, including its immediate initial read. Startup with Desktop World disabled still does not query Finder. Disable/quit stops polling and cancels pending reads; late cancelled results remain ignored. A read error pauses polling, and a known denied permission is not automatically retried on each enable in that app session. Finder Diagnostics retains explicit read/retry controls. Main editor reports Finder errors. Input/output actions continue to use fresh serialized reads and never choose stale or ambiguous targets. The dependency flag is explicit in app startup so isolated tests can continue without real Finder access.

Add pure ChunkCache and mapper-owned bounded visible-chunk/geometry calculation. Cache only the requested visible chunks plus one chunk margin; checked arithmetic, invalid origins and an allocation bound of 256 chunks protect degenerate viewports. TerrainChunkRenderer retains one SKSpriteNode and one 256×256 texture per chunk, rather than 1,024 child sprites per chunk. It bakes project-owned 8×8 semantic terrain/decorative placeholder pixels, using Apple's public [bitmap representation](https://developer.apple.com/documentation/appkit/nsbitmapimagerep) and [nearest texture filtering](https://developer.apple.com/documentation/spritekit/sktexturefilteringmode). No assets are loaded from another game or pack.

Retain chunk data/textures across editor scene/camera recreation, reposition through CoordinateMapper, reuse overlapping chunks and remove evicted nodes/textures. Camera/viewport changes alone do not rebuild retained textures. Circuit, power, occupancy and hover changes do not regenerate terrain. Expose current retained chunks/chunk nodes plus cumulative generated-chunk/texture-build counts in the editor footer. The cumulative counts increase while exploring; only retained counts should stay bounded. No per-frame terrain generation is installed.

World now resolves explicit terrain overrides before an optional generator. The existing fixture and grass construction area remain exact overrides, preserving circuits and all earlier terrain. Preserve the developer form's intentionally unspecified tile (14, 5) through a generic unspecified-tile set. Placement and Inspector use the same World.tile lookup, so generated water/decorations constrain edits and generated dry cells can be authored/saved. Renderer combines the same overrides with cached base chunks; no generated tile dictionary accumulates in World.

Persistence format 2 adds generation settings (generation version 1, default seed 2026). Decode format-1 fixture saves into format 2 in memory, preserving ID/name, camera, circuit, lever positions and fixture version; add generated surroundings without changing the original override tiles. No load-time rewrite is performed. Next accepted edit/save writes format 2 atomically. Generated terrain and the override fixture are recreated, not stored tile-by-tile. Unsupported/malformed documents still block writes and preserve the original file.

Validation: Debug build, standalone pure World/Circuit typecheck and all 169 tests pass. Seven renderer/cache tests cover negative mapper chunk boundaries/margins, bounded cache eviction/seed invalidation, one nearest sprite per chunk, idle/power/occupancy texture reuse, long pan node bounds, camera-scene recreation reuse, explicit/unspecified override pixels and placement consistency, and distinct original semantic placeholder art. Two persistence tests cover format-1 migration preserving configuration and generated-cell placement/restoration without serialized tiles. Three automatic-Finder tests cover initial enable/read, stop on disable, denied-read pause/no repeated request, and a fresh occupant opening without any explicit diagnostic read. Existing cancellation/serialization/Finder and circuit tests remain green. A new test listener initially fulfilled its initial-read expectation on subsequent successful reads; it was corrected to observe only the first matching publication. No application or API behavior contradiction is inferred from that test-harness failure.

Consequences: all seven Slice 18 implementation tasks are complete. Its two MANUAL checkboxes remain pending the owner's visible long-pan/idle validation. README.md also requests checking automatic refresh and preserved circuits after migration. Slice 19 and later remain unchecked. No seed browser, Use This Area, Finder ghosts, resource packs, private macOS API or backend is added. Future examples continue to the right of existing circuits.


## 2026-10-07 — Owner confirms Slice 18; Slice 19 seed browser and desktop area

Context: the owner reported “Great! it works” after the chunk renderer's long-pan/idle/automatic Finder/persistence walkthrough. Mark the two Slice 18 MANUAL items complete as owner-reported Mac validation, separate from its 169 automated tests. Continue to Slice 19.

Decision: add unsigned decimal seed entry, Preview, Random, Cancel Preview and Use This Area in normal SwiftUI. Random selection is a UI convenience; the pure generator remains deterministic from the chosen stored seed. Parse the full UInt64 range, rejecting signs, fractional text and overflow. Use This Area validates the current text even when Preview was not clicked. Preview generation lives in EditorSession; its browsing World is a value copy retaining the current circuit and explicit terrain overrides. Preview/pan/zoom never modify the live world, query Finder or write persistence.

Pause editor circuit edits while a different seed is previewed. Preview existing circuit validity and refuse applying any seed that would put an existing component on water, decoration or unspecified terrain. This implements the specification's detect/warn requirement conservatively without silently invalidating/removing a circuit or adding Reset World. Cancel returns to current terrain; the user can revise the existing circuit deliberately before trying a conflicting seed.

The orange physical-desktop rectangle uses the editor view's lower-left world origin as the proposed desktop origin. Blue shows the current desktop camera area. Display size is in logical points; rectangle projection goes through CoordinateMapper. Desktop points-per-tile remains unchanged while editor zoom is browsing state. Zoom out to see the full outline. Show desktop area browses to the current desktop origin; Reset view browses to world origin zero. Neither changes the wallpaper.

Use This Area first validates the display, representable/bounded camera, generation version and complete circuit. Rejection leaves the world, camera and running desktop untouched. On success, publish the selected generation/camera and autosave them in the existing format-2 document, preserving circuit identity/configuration, fixture overrides and durable lever positions. If desktop rendering is enabled, use its established shutdown/re-enable path to cancel old tasks/actions, clear transient power/pulses, recreate renderer/input/pointer mappers, recompute occupancy and resume automatic Finder refresh. Old mouse callbacks are ignored by the stopped monitor. Camera relocation changes which world tiles real Finder items occupy; those mappings are recalculated rather than carried forward. Desktop remains disabled if it was disabled before applying.

Validation: Debug build and all 178 tests pass. Nine new tests cover full-range seed parsing and invalid drafts/random selection, preview/pan/zoom/cancel isolation without saves, paused preview editing, successful seed/camera save and restart with preserved circuit, atomic refusal of a seed invalidating a generated component, applying while enabled with replaced monitor and stale-callback rejection, real item snapshot remapping to the new camera's tile, negative-origin physical viewport projection and bounded overlays, and missing-display/invalid-camera/version refusal. Existing renderer root-count expectation includes the new bounded viewport overlay. A test-store actor annotation was corrected to match the synchronous storage protocol, and a pointer assertion was corrected to account for the monitor's immediate sample; all tests are green after those corrections.

Consequences: all eight Slice 19 implementation tasks are complete. Its MANUAL seed/location/live-desktop checkbox remains pending the owner's Mac check. Existing fixture positions are preserved globally; moving the desktop camera may put those circuits outside the current display, rather than deleting/moving them. README.md includes recovery to origin zero and checking camera/seed persistence. Slice 20 and later remain unchecked. No Finder ghosts/snapping, resource packs, backend or private API is added.


## 2026-10-07 — Owner confirms Slice 19; proposal for independent worlds and saved areas

Historical proposal: adopted by the following decision and the 19A/19B roadmap. Its pending language records the earlier discussion, not the current plan.

Context: the owner reports “It works!” for Slice 19 and asks whether circuits can belong to their seeded map, with a list of built areas to browse/edit and one explicitly active desktop area. Mark Slice 19's MANUAL checkbox complete based on that owner report. This turn discusses a product/model adjustment rather than implementing Slice 20.

Current behavior: there is one WorldDocument and one circuit dictionary. Camera movement within the same seed leaves components at their original world coordinates. Applying a different seed changes generation settings in that same document, retaining the existing circuit; it does not load a separate saved map. Seed previews also retain that circuit for validation.

Proposed design, pending adoption: a library of independently identified world documents, each with fixed generation settings, its own coordinate-keyed circuit, durable lever positions and terrain overrides. A seed defines terrain, not save identity: two independent documents may intentionally use the same seed. Named saved areas reference a world ID and a desktop camera; they are bookmarks into that world and never copy or own circuit components. Overlapping areas share the same world-coordinate components. Browsing a world or saved area affects only editor selection; explicit Activate on Desktop chooses the live world/area. Inactive worlds do not simulate or execute actions. Define the treatment of offscreen components in the active world before implementation; area bookmarks must not silently clip connected circuits.

Architecture assessment: this fits existing pure World/Circuit models, CoordinateMapper, Finder provider and separate action executor. Changes concentrate in document/library persistence, editor selection and AppState lifecycle; the generator, simulator and renderer can be reused. Switching active world/area must invalidate old input/action work, clear transient simulation state, rebuild mapping and refresh Finder occupancy. Finder items remain physical desktop items and are not stored or moved with areas.

Recommended implementation sequence if adopted: add a small world-library/persistence migration slice, then a named-area list and explicit activation slice before Finder ghosts. Preserve the current document as the first world, including identity, chosen seed, camera, circuit and levers; preserve the source save during migration and retain fail-closed damaged-document handling. Fresh worlds should not receive the old world's user components or automatically inherit prototype demo fixtures. Test independent edits across seeds, shared coordinates for overlapping areas, browse/live isolation, cancelled stale actions, atomic persistence and restart restoration.

Consequences: this is a recorded proposal, not an implemented feature or a change to the ordered roadmap. Slice 20 and later remain unchecked. Only SPEC.md and README.md are changed this turn; no new application build/test results or manual acceptance beyond Slice 19 are claimed.


## 2026-10-07 — Adopt independent worlds and named areas; documentation first

Context: the owner approved the independent-worlds/saved-areas proposal and requested bringing all documentation up to date before resuming implementation slice by slice.

Decision: adopt the contracts in Sections 3.8, 7.1, 25 and 29. Insert Slice 19A (library/migration/world selection) and Slice 19B (named areas/explicit activation) between completed Slice 19 and untouched Slice 20, preserving existing numbered milestones and manual validation history. Supersede the proposal's pending-adoption status and the prototype's seed-replacement workflow for future implementation; current code remains Slice 19 until these slices land.

Worlds own circuits and immutable generation settings; seeds are not save identity. Areas are named camera bookmarks sharing their world's components. A single atomic library.json stores world/area records and active selection. Migration preserves the old world.json source and configuration, retaining prototype terrain only in the migrated world. New worlds are procedural and empty. Browse/Save Area do not activate; explicit Activate on Desktop targets a saved area. Inactive worlds are paused, with inactive-world editing allowed in 19B while enabled active-world edits remain locked.

Resolve the earlier offscreen question by simulating the full active-world circuit without clipping wires, but dispatching actions only from outputs whose mapped centers are inside the active desktop canvas. Switching saves/preflights first, invalidates old world/session work, resets transient state and refreshes Finder. Same-world/same-camera activation is a no-op; enabled state is preserved on other successful switches. Saved ON levers can cause a fresh rising edge on explicit enable/different-area activation. Restoration never enables the desktop automatically.

Consequences: this turn changes SPEC.md and README.md only. New roadmap tasks and MANUAL checks remain unchecked. No source code, owner data, generation fingerprints, APIs or assets change. The next implementation is Slice 19A; no new application build/test or physical Mac result is claimed for this documentation update.


## 2026-10-07 — Slice 19A independent world library and migration

Context: the owner approved the documentation plan and requested continuing. Implement only Slice 19A; no Slice 19B named-area UI or new-world desktop reassignment is added.

Decision: add Foundation-only format-3 WorldDocument with immutable generation/profile, SavedArea and format-1 WorldLibraryDocument. Worlds own coordinate-keyed circuits/ON lever positions; areas hold camera bookmarks. Validate unique IDs, every world/area/active reference, at least one area per world, trimmed nonempty names, camera bounds, generator/profile versions and component placement/lever membership. New worlds use procedural terrain, empty circuits and Home areas. Preserve legacy fixture overrides/unspecified tiles only in migrated worlds.

WorldLibraryStore reads/writes the complete atomic library.json with the existing 2 MB bound. A present library is authoritative, including on parse/read/version/size errors; never fall back to or overwrite a backup. Missing library migrates supported format-1/2 world.json, preserving UUID/name, generation, every component, durable lever position and camera in its first Desktop area. Save migration before returning success; never change the source bytes. A second launch reuses the stored library/IDs. Missing both files saves a new empty procedural library. Errors block autosave for the session; failed later writes retain the newest complete snapshot for retry. Autosave coalesces edits across worlds and flushes on Save Now/disable/quit.

AppState keeps selected editorWorld/selectedWorldID separate from desktopWorld/active area. Create/rename/select and all component/developer mutations require Desktop World disabled for this interim slice. Edits update only the selected document; active configuration/simulator synchronize only when that selected world is the assigned world. Enabling always runs the assigned world, regardless of editor selection. Inactive-world rendering receives no active-world power/occupancy or blue viewport outline. Procedural-world developer reset is refused rather than deleting arbitrary coordinate-matching user builds.

SwiftUI provides Saved worlds (names, fixed seeds and Desktop badge), Rename, new seed Preview/Random/Cancel, new-world name and Create World. Seed previews use empty procedural World copies, including when the seed equals the existing map. Canvas edits pause for any preview; Create World reparses the current draft and selects a new independent UUID/Home area. Existing seeds cannot be replaced. Session world selection clears tile/hover state and browses to the selected default area's origin. Use This Area remains only for the assigned world's camera, using its fixed seed; it refuses previews/other worlds. Show desktop area selects the assigned world while disabled; no new activation behavior is implied.

Validation: final Debug build and all 194 tests pass, plus standalone Swift-6 typechecking of World/Circuit/Persistence. Sixteen new library tests cover empty procedural/format-3 round trips, both legacy migrations/source preservation/idempotence, authoritative-library precedence, migration write failure at the size bound, invalid IDs/references/names/versions/cameras/profiles/levers, oversized read/write preservation, empty fresh installation without Finder, independent seed-42/2026 and duplicate-seed edits at coincident coordinates with whole-library autosave/restart, rename/erase/repeater/developer routing, live mutation/switch locks and original runtime selection, empty same-seed preview/fixed-seed refusal, selection/outline/occupancy isolation and SwiftUI hosting, damaged-library write blocking, failed multi-world retry and isolated test-host startup. Existing persistence/cache/seed tests are updated for the adopted model; other regression checks remain green.

Implementation observations: an early compile exposed Swift's initialization-order rule; initial identity/world values now use local constants before property access. The first application-hosted test run initialized normal app startup and created the owner's migrated library.json. That was a test-isolation issue, not evidence of a macOS API contradiction or manual UI acceptance. The legacy world.json was not rewritten; a read-only semantic comparison verified identity, seed, all components/levers and camera preservation despite dictionary JSON ordering differences. AppStartup now detects XCTest/injection and constructs an isolated no-store fixture with automatic Finder disabled. A dedicated test verifies that behavior; SHA-256 comparisons verified both owner save files remained byte-for-byte unchanged during the final build/test run.

Consequences: all Slice 19A implementation/automated tasks are complete; its three MANUAL items remain pending the owner's Mac walkthrough. Slice 19B and later remain unchecked. Original terrain generation fingerprints, Finder/API mapping, simulation/action boundaries, assets and backend scope are unchanged. Normal app startup uses the library adapter; LegacyWorldDocument/WorldStore remain isolated migration/fixture adapters, never the normal save path. README.md distinguishes current versus planned controls and retains dated validation history.


## 2026-10-07 — Slice 19A owner confirmation and Slice 19B saved areas

Context: the owner reported “Yes it works!” after the Slice 19A migration/world-library walkthrough. Record its three MANUAL checks as owner-confirmed and proceed directly to the next roadmap slice, per the owner's requested workflow.

Decision: implement Slice 19B with saved area selection grouped by world, seed/active labels, stable-ID rename and Save Area / Activate on Desktop. Bookmarks hold cameras only; shared world components stay at their coordinates. Editor selection, pan and zoom remain temporary. Show Desktop Area selects the actual active bookmark. Existing seeds remain fixed and fresh worlds remain empty. Inactive-world edits are allowed while running; the enabled active world's mutation methods and UI controls remain locked.

Activation preflights restored configuration, camera and physical display, flushes pending configuration and commits the proposed active ID atomically before stopping the old runtime. Failed proposed selections are never retained for later autosave. Matching world/camera activation saves the bookmark ID without resetting the runtime. A different view cancels old input/actions, releases the task slot immediately, starts a new world/session identity and rebuilds the mapper/simulator with durable levers. Old task cleanup cannot clear the new session's task slot. A post-commit rendering/display failure leaves the new saved selection disabled with an error. Production activation restarts the serialized automatic Finder tracker.

The active world's complete finite circuit continues simulating offscreen; output actions are gated by mapped center inside the physical canvas at enqueue and execution. Offscreen rising edges are dropped. Inactive worlds show stored lever labels without active power/occupancy. Renderer receives snapshots only and executes no actions.

Evidence: Debug build and all 205 tests pass. SavedAreaTests adds 11 checks covering shared bookmarks, saved-camera versus pan, restart-disabled selection, held live isolation under inactive editing, pending/selection write failure, same-view runtime no-op, old-world input and old-view output completion cancellation, offscreen wire transmission/output suppression, inactive lever labels and display failure before/after commit. Earlier seed browser/library tests now exercise the replacement controls. Foundation-only domain/persistence type-check and git diff --check pass. Owner save-file hashes remained unchanged across the final automated build/test runs; app test startup remains isolated from production persistence/Finder.

Consequences: Slice 19B implementation/automated tasks are complete; its four MANUAL checks remain pending. No new demo circuits, Finder ghosts, resource packs, private APIs, backend, generated-terrain changes or deletion/copying workflows were introduced. README.md distinguishes historical Slice 19A restrictions from current behavior and provides the exact Mac walkthrough.


## 2026-10-07 — Owner requests library UX cleanup before Finder ghosts

Context: the owner finds the top controls overwhelming and world creation too prominent. They like areas belonging to worlds and request previews, deletion, clearer layout and removal of obsolete test controls. “I think it works” is tentative 19B feedback, not a specific confirmation of all four Mac checks.

Decision: insert Slice 19C before 20 and adopt Section 25.3. Worlds sidebar, selected-world preview shelf and focused sheets replace permanent top-bar forms. Advanced diagnostics remain useful for Automation/alignment/event rejection failures; move them away from the normal task flow. Remove developer placement navigation and fixed-demo-only diagnostic presentation while retaining automated tests and migration fixtures. Do not automatically clear stored circuits. Add explicit deletion of inactive/nonfinal records, confirmation text distinguishing bookmark versus world removal, and atomic save-before-publish failure behavior. No Finder files are deleted.

Consequences: implement only this owner-requested UX slice, no Finder ghosts/resource packs/advanced redstone. Slice 19B's manual items remain pending. New manual checks require owner validation.


## 2026-10-07 — Slice 19C implementation and automated validation

Decision: implement Worlds sidebar with first-area schematic previews, selected-world area shelf with saved-camera previews, focused New World/Save Current View/rename/deletion sheets, compact desktop/browsing labels and right-hand Build/Inspector. New World is secondary; entering or canceling a seed preview never transfers components. Move Finder Diagnostics/Desktop Details/Save Now into Advanced; collapse terrain metrics. Remove DeveloperPlacementView/window and rename EditorPlaceholderView to DesktopDetailsView with world-independent action/event information. Keep legacy data/test fixtures and every existing saved circuit.

Deletion restrictions live in Foundation-only WorldLibraryDocument; AppState validates and saves the complete candidate before publishing. Active desktop/final records are protected. Area deletion retains shared circuits. World deletion removes its areas/configuration, falls back editor browsing to the active bookmark, and leaves active mapping/simulation/session untouched. Write/load failure preserves the old library/selection/runtime and does not retain deletion as an autosave retry. No schema change or Finder file mutation.

Previews sample a fixed 48×30 grid, use CoordinateMapper for saved viewport/world projection, preserve display aspect within 144×88 points, draw terrain/decorations and visible component marks once into a disposable bitmap, and refresh on configuration/camera/display size rather than transient power. They do not query Finder or simulate. SpriteKit remains the actual interactive world renderer. Preview bitmaps are not saved, exported assets or ghost projections.

Evidence: Debug build and all 213 tests pass; nine new cleanup tests cover pure guards/unknown IDs, bookmark-only removal/build preservation/restart, inactive world deletion without live restart, failed proposed deletion and failed pending-save retry, unselected deletion/stopped-active guards, damaged-store preservation, bounded aspect/camera/component previews, and native editor/sheet hosting. Bootstrap now hosts the actual editor; the obsolete developer-form hosting test was removed along with its view, while placement/runtime regression tests remain. Native hosted layout/preview capture was inspected in light appearance; NSView bitmap capture omits the SpriteKit GPU canvas and does not establish physical Finder/desktop behavior. Pure domain/persistence type-check and diff checks pass; owner save hashes stayed unchanged during final automated runs.

Consequences: all 19C implementation tasks complete; its three manual checks and 19B's specific runtime checks remain pending owner confirmation. README describes current controls, disposable deletion checks and recovery. No Finder ghosts, resource packs, advanced circuits, private API or backend added.


## 2026-10-07 — Slice 19C follow-up: update bookmarks and contextual management

Context: the owner says Save Current View is useful, requests updating the current bookmark without creating another, and prefers right-click Rename/Delete on world and area cards. They report the layout otherwise “looks great” and want these changes before resuming slices.

Decision: extend 19C with explicit Update Current Area and captured-ID context menus as defined in Section 25.3. Supersede the fixed-camera-only restriction. Same-world circuits remain shared; no implicit activation or component movement. A running active bookmark is protected from camera replacement; stopping allows its prepared camera to update. Inactive bookmarks remain independently editable. Record visual approval without inferring deletion/recovery/runtime checks passed. Do not start Slice 20 in this turn.


Validation of the 19C follow-up: final Debug build and all 220 tests pass, plus pure World/Circuit/Persistence type-check and diff checks. Seven AreaUpdateTests cover in-place camera replacement/ID/name/count/world/circuit preservation, persisted inactive cameras, stopped-assigned camera preparation/restart/explicit start, held live circuit preservation while updating another bookmark of the same world, running-active refusal, failed proposed update and pending-config flush retry, invalid camera/scale/preview refusal, captured-ID rename without changing selection/camera and active-world rename locks, unavailable-display and damaged-library write preservation. The initial sheet initializer referenced a stored ID inside a closure before State initialization; local target IDs now avoid that Swift initialization-order error. No macOS API contradiction is inferred. Context sheets capture UUIDs; successful deletion resets the editor only when its selected area changes. Native hosted layout capture was inspected; physical context menus remain owner checks. Save Current View remains the create-new-bookmark action, and Update Current Area retains the existing desktop tile scale. No schema, generation, Finder adapter or simulator change. Follow-up implementation tasks are checked, their two MANUAL items remain pending; prior “looks great” records visual approval only, not unreported runtime/deletion checks.


## 2026-10-07 — Slice 20 implementation

Context: the owner accepted the 19C Update Current Area/context-menu follow-up and requested the next slice. Record its two manual follow-up checks as accepted; leave unreported earlier 19B/19C runtime/deletion groups pending.

Decision: implement Finder ghosts and Output snapping under Section 25.4. Use one shared tracker with explicit editor opt-in, preserving disabled startup and desktop action ownership. Cached read snapshots publish independently of desktop renderer lifetime. A Foundation/CoreGraphics-only projection resolves selected-world proposed-camera occupancy; SpriteKit draws action-free center rings/names, and editor clicks re-evaluate snapped targets through normal placement transactions. No stored schema, circuit generation, simulation or file-opener behavior changes. No extra demonstration circuits, private APIs, resource packs or backend.

Validation: Debug application build and all 232 automated tests pass (12 new Finder projection tests; prior editor occupancy test now checks that hidden projections do not borrow live occupancy). Pure World/Circuit/Persistence and new projection type-check without AppKit/SpriteKit; diff checks pass. Coverage includes fractional/negative display/world origins and logical Retina geometry, center mapping/world identity, off-display exclusion, ambiguity/unavailable states, near-center/tie snapping, tracker ownership on stop/shutdown, disabled startup, stopped-desktop movement publication, denied-read pause, inactive/proposed-camera isolation, preview/terrain/live editing guards, fresh-click versus stale hover, projected output badges versus actual desktop occupancy, bounded marker replacement and no editor actions. Two initial test expectations were corrected: equal-distance fixtures now lie in different tiles, and a post-movement ordinary click correctly places on its valid unsnapped tile while preserving the existing Output. These were fixture errors, not macOS behavior contradictions.

Real icon alignment/movement, menu interaction and the projection-versus-assigned-desktop walkthrough require the owner's Mac report; all three Slice 20 MANUAL checks remain unchecked. Slice 21 is untouched.


## 2026-10-07 — Slice 21 display-change resilience

Context: the owner is away and explicitly requested the next slice before manually validating Slice 20, with a combined walkthrough afterward. This authorizes proceeding to Slice 21 without treating Slice 20 as owner-accepted; both slices' MANUAL checks remain pending.

Decision: adopt Section 5.4's primary-display/lower-left anchor policy. Use the public AppKit notification through an injectable DisplayChangeMonitor. Re-read target and primary-reference descriptors, publish geometry to the editor, recreate renderer/input on actual change, preserve simulator/configuration, and invalidate all old-session I/O. FinderDiagnosticsModel rejects reads begun under an older geometry generation, including noncancelable manual reads. A generation-scoped delayed refresh coalesces notifications and waits for the shared read slot. No-display/invalid geometry stops safely without an implicit restart; stopped startup remains read-free. Display handling uses no private API, backend or asset pack.

Validation: final Debug application build and all 244 automated tests pass. Twelve DisplayChangeTests cover the public notification adapter lifecycle, negative-origin/logical Retina resize geometry, renderer/window/input recreation and stale callbacks, camera/library/pulse preservation, identical notifications, coalesced refresh and backing-scale-only changes, unavailable/invalid display stop and explicit restart, read-free disabled startup versus opted-in stopped editor, canceled input/output completions, generation rejection of noncancelable diagnostic reads, stop-during-settle tracker ownership, denied-access/error preservation without re-prompting, and full-shutdown cancellation. The additional held-output test initially expected an unrelated exact power strength; it now asserts the property under test (Output remains powered without reopening), while circuit-strength coverage remains in simulator tests. This is a test expectation correction, not a macOS API contradiction. Pure domain/Finder projection type-check and diff checks pass.

Physical resolution/scaling, unplug/replug, primary fallback, click-through window layering and real Finder position settling require the owner's Mac checks; no real display settings or connections were changed during automation. README provides the combined Slice 20/21 walkthrough. Both slices' MANUAL checks remain unchecked; Slice 22 is untouched.


## 2026-10-07 — Owner confirms Slices 20/21; Slice 22 Finder icon size

Context: the owner reports “All looking good. Continue” after the combined Finder-projection/display-change walkthrough. Mark the corresponding five MANUAL checks owner-accepted, separately from automated evidence; earlier unreported 19B/19C check groups remain pending. Proceed with Slice 22 only.

Decision: implement Section 12.0. Inspect Finder's installed scripting dictionary and use its public icon-view size property in a structured before/after-size/item snapshot. Optional metadata is read through DesktopItemProviding, with backward-compatible defaults for providers/runners that only supply items. Keep center mapping and world scale unchanged. A single serialized diagnostic read waits/rechecks changing layouts and publishes only stable positions. Layout generations skip old input/output activations; transient circuit state and saved configuration remain intact. Keep an optional session baseline for future Slice 23; no save schema or undocumented preferences access. Diagnostics and the editor's transient caption expose state without adding normal top-bar controls.

Validation: final Debug build and all 256 automated tests pass (12 new icon-size tests), plus Foundation-only domain/view-settings/Finder projection type-check and diff checks. Tests validate bounded settings, structured before/after parsing and unchanged raw centers, optional unsupported/malformed metadata and empty desktop, native snapshot-script compilation without querying Finder plus harmless descriptor execution, changed/mid-query/continuous sizes with stable-only publication, unchanged/no-settings reads without delay, retained optional session baseline, settle failure/recovery, cancellation/display invalidation, old input refusal with successful fresh retry, and old output refusal with a later fresh pulse opening the current fixture occupant. Existing polling, permission, library, coordinate, display and action regression tests remain green. No actual Finder setting was changed in automation; compilation is syntax evidence, not physical icon alignment or setting-availability proof.

Actual setting availability, resizing/alignment and fresh real output targeting require the owner's Mac check. All three Slice 22 MANUAL checkboxes remain unchecked. No schema, terrain, asset, simulator, private API or backend change; Slice 23 remains untouched.


## Slice 23 implementation evidence

Optional FinderScale camera transform and settings implemented. Unit/integration tests cover independent defaults, missing metadata, ratio/clamps, negative-display center anchoring, drift-free return, live center remapping, unchanged library and isolated persisted settings. No Finder preference mutation or new API permission. Debug build and all 262 tests pass. Mac acceptance remains pending.
