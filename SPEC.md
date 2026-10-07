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
- a chosen persistent desktop viewport
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

## 12.1 Optional synchronized scale mode

Later provide:

- Independent world scale
- Sync world scale to Finder icon size

Synchronized concept:

```text
newPointsPerTile =
  baselinePointsPerTile *
  currentFinderIconSize / baselineFinderIconSize
```

Preserve a documented camera anchor, probably desktop center.

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

Panning around the editor must not move the actual wallpaper until the user clicks **Use This Area** or enables an explicit live-preview mode.

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
    var generationVersion: Int
    var seed: UInt64
    var biomeScale: Double
    var terrainScale: Double
    var decorationDensity: Double
    var waterThreshold: Double
}
```

The UI may initially expose only seed.

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

Suggested layout:

```text
┌────────────────────────────────────────────────────────────────┐
│ World: My Desktop       Seed: 8483920291       [Use This Area] │
├──────────────┬──────────────────────────────────┬──────────────┤
│ Tools        │                                  │ Inspector    │
│              │          world canvas            │              │
│ Select       │                                  │ Tile         │
│ Dust         │    terrain + circuit             │ Component    │
│ Button       │    + Finder ghost icons          │ Power        │
│ Lever        │                                  │ Output mode  │
│ Repeater     │                                  │              │
│ Output       │                                  │              │
│ Erase        │                                  │              │
├──────────────┴──────────────────────────────────┴──────────────┤
│ Finder connected · 17 items · 48 pt/tile · Sim 20 Hz          │
└────────────────────────────────────────────────────────────────┘
```

Editor must support:

- pan
- zoom
- select
- place
- erase
- component rotate where relevant
- repeater delay edit
- placement validation
- seed entry
- random seed
- desktop viewport rectangle
- Finder ghost overlay

## 25.1 Editor camera vs desktop camera

The editor has temporary exploration state.

The desktop has persisted camera state.

Browsing must not alter desktop until **Use This Area** is invoked.

## 25.2 Seed changes after circuit exists

Do not silently invalidate a circuit.

At minimum:

- detect components that become invalid under new terrain
- warn before applying

Simpler V1 policy is acceptable:

> Once circuit editing begins, changing seed requires Reset World.

## 25.3 Output snapping

Eventually support:

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

Start with one Codable JSON world document.

Example:

```json
{
  "formatVersion": 1,
  "id": "uuid",
  "name": "My Desktop",
  "generation": {
    "generationVersion": 1,
    "seed": 8483920291
  },
  "camera": {
    "worldOrigin": { "x": -142.25, "y": 80.0 },
    "pointsPerTile": 48.0
  },
  "circuit": {
    "components": []
  },
  "terrainOverrides": [],
  "resourcePack": {
    "kind": "builtin"
  }
}
```

Version at minimum:

- world format
- generator
- resource-pack manifest

Store normal app data in Application Support.

Use atomic writes.

Autosave with a short debounce, e.g. 0.5–1 second after edit activity stops.

---

# 30. App lifecycle / menu bar

Eventually behave like a desktop utility.

Suggested status/menu commands:

- Open Editor
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
- migrations
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

# 38. IMPLEMENTATION ROADMAP

The roadmap is deliberately granular.

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

- [ ] orientation
- [ ] rear input only
- [ ] forward output only
- [ ] power restoration to 15
- [ ] 1–4 redstone-tick delays
- [ ] exact timing tests
- [ ] visual state

---

## Slice 13 — Circuit renderer

- [ ] dust shapes
- [ ] powered/unpowered textures
- [ ] button state
- [ ] lever state
- [ ] repeater orientation/delay
- [ ] output occupancy
- [ ] output trigger flash
- [ ] renderer remains action-free

### Manual acceptance

- [ ] MANUAL: visual state tracks simulation correctly.

---

## Slice 14 — Placement rules

- [ ] terrain capability definitions
- [ ] centralized evaluator
- [ ] failure reasons
- [ ] unit tests
- [ ] developer placement UI

Acceptance:

- [ ] dust cannot be placed on water.
- [ ] blocked decoration rejects placement.
- [ ] occupied circuit tile does not silently overwrite.

---

## Slice 15 — Basic editor

- [ ] editor layout
- [ ] canvas
- [ ] pan
- [ ] zoom
- [ ] selection
- [ ] dust tool
- [ ] button tool
- [ ] lever tool
- [ ] repeater tool
- [ ] output tool
- [ ] erase tool
- [ ] inspector
- [ ] placement preview
- [ ] invalid placement feedback

### Manual acceptance

- [ ] MANUAL: useful circuit can be authored without code changes.

---

## Slice 16 — Persistence

- [ ] versioned `WorldDocument`
- [ ] `WorldStore`
- [ ] atomic write
- [ ] autosave debounce
- [ ] restore last world
- [ ] JSON tests
- [ ] corrupted-document handling

### Manual acceptance

- [ ] MANUAL: build, quit, reopen, state is restored.

---

## Slice 17 — Deterministic terrain generator

- [ ] deterministic seed/hash
- [ ] 2D noise
- [ ] elevation
- [ ] moisture
- [ ] terrain/biome selection
- [ ] water
- [ ] basic decorations
- [ ] chunk generation
- [ ] negative-coordinate correctness
- [ ] generator snapshot/hash tests

Acceptance:

- [ ] same seed and coordinate always gives same result for generation version.
- [ ] different seeds differ visibly.
- [ ] no chunk seams.

---

## Slice 18 — Chunked terrain renderer

- [ ] visible chunk calculation
- [ ] `ChunkCache`
- [ ] chunk SpriteKit nodes
- [ ] add/remove as camera moves
- [ ] nearest-neighbor rendering
- [ ] original placeholder assets
- [ ] render metrics

### Manual acceptance

- [ ] MANUAL: long editor pan does not grow nodes indefinitely.
- [ ] MANUAL: idle renderer does not regenerate terrain continuously.

---

## Slice 19 — Seed browser / choose desktop area

- [ ] seed text entry
- [ ] random seed
- [ ] editor free pan
- [ ] editor free zoom
- [ ] physical desktop viewport rectangle
- [ ] `Use This Area`
- [ ] save desktop camera
- [ ] browsing does not change live desktop prematurely

### Manual acceptance

- [ ] MANUAL: explore seed, choose location, live desktop changes to selected area.

---

## Slice 20 — Finder ghosts in editor

- [ ] show real Finder items as ghosts/markers
- [ ] update when tracker changes
- [ ] map through proposed desktop camera
- [ ] show occupancy state
- [ ] snap output to tile under Finder icon center

### Manual acceptance

- [ ] MANUAL: moving real icon updates editor ghost.

---

## Slice 21 — Display-change resilience

- [ ] observe screen-parameter changes
- [ ] rebuild screen descriptors
- [ ] resize/recreate renderer windows
- [ ] recalculate mapper
- [ ] refresh Finder after settle delay
- [ ] document camera-anchor policy
- [ ] unit tests with fake screen changes

### Manual acceptance

- [ ] MANUAL: display scaling/resolution change remains aligned.
- [ ] MANUAL: external display unplug/replug does not crash.

---

## Slice 22 — Finder icon-size handling

- [ ] read/detect relevant Finder view settings if practical
- [ ] refresh icon layout after size change
- [ ] keep occupancy center-based
- [ ] store optional baseline values for future sync

### Manual acceptance

- [ ] MANUAL: change desktop icon size.
- [ ] MANUAL: mapped markers realign after Finder settles.
- [ ] MANUAL: output target follows actual new item position.

---

## Slice 23 — Optional synchronized world scale

- [ ] setting: independent vs sync-to-Finder
- [ ] baseline Finder icon size
- [ ] calculate world scale ratio
- [ ] preserve camera anchor
- [ ] refresh icons after Finder rearrangement
- [ ] clamp minimum/maximum world scale

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

Use this section as implementation discovers reality.

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
