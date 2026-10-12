# Architecture and contributor contracts

Redstone Desktop is a native macOS application. SwiftUI owns ordinary UI, AppKit handles desktop windows and native integration, and SpriteKit draws the 2D world. There is no backend. Use documented public APIs; stop and document a real macOS contradiction before proposing the smallest contract change. Do not patch around mismatched desktop behavior with private APIs or unexplained offsets.

## Domain and simulation

Worlds own durable circuit components and seeds. Areas are named cameras into a world, sharing its components. Editor selection is independent of the active desktop assignment. Switching views must not copy circuits or start simulation. Simulation/domain code never imports SpriteKit. Renderers display state and feedback; they never launch files. Action execution, script approval and Finder refresh remain separate from the simulator. See [REDSTONE_RULES.md](REDSTONE_RULES.md) for the supported deterministic model.

All world/screen/scene conversion goes through `CoordinateMapper`. Tile sizes use logical points. The desktop is a virtual bounding canvas anchored at its lower-left; physical display gaps cannot dispatch actions. Finder’s public positions are mapped from the primary screen’s upper-left reference. Multi-display geometry and permission failures must invalidate stale mappings/actions. Build Mode currently edits the primary display only.

Editor test mode owns an independent simulator copy and scheduler; its Output events become local visual feedback and counters only. It never dispatches actions or saves test lever/power state. Group edits validate a complete working copy before publication; per-world, session-only undo uses bounded sparse component deltas. Reusable blueprints are a separately validated, atomic `blueprints.json` file; they are included in full Support reset backups, but excluded from world-library exports. See [EDITOR_TOOLS.md](EDITOR_TOOLS.md) for limits and UI contracts.

Default generation uses global integer climate/elevation/river fields with clustered scenery. Version-1 terrain locations are intentionally replaced by the current landscape; settings default to generation version 4, with backed-up upgrades preserving saved circuit footprints. New surfaces keep domain capabilities separate from art. See [WORLD_GENERATION.md](WORLD_GENERATION.md).

## Finder and actions

Finder access goes through `DesktopItemProviding`. Cached occupancy is presentation state; actions verify fresh occupancy before opening the current item. Mouse recipient metadata gates desktop circuit clicks so covered app windows do not activate hidden inputs. Stop, pause, area reassignment, target changes and Quit cancel stale action work.

Open-item actions use native workspace APIs. Script actions support only documented shell extensions, explicit opt-in and approvals bound to the exact file/content. Never execute pack code. Setup and permission checks must not run scripts. See [SCRIPT_OUTPUTS.md](SCRIPT_OUTPUTS.md).

Desktop pressure plates and file sensors consume mapped occupancy snapshots through `DesktopSensorInputs`; AppState rejects unavailable, frozen, settling or stale readings. The simulator accepts plain active-coordinate sets and never queries Finder. Inputs hold strength 15 while detection is true; only Outputs dispatch actions, including on startup/recovered occupancy. Configuration/filter validation applies to placement, worlds and blueprints. See [DESKTOP_SENSORS.md](DESKTOP_SENSORS.md).

## Persistence and UI

`WorldLibraryDocument` validates references, IDs, terrain and component configuration. Every proposed edit checks the whole library against the shared pretty-printed 2,000,000-byte encoding contract before model/history/runtime publication. Circuit placement, paste, desktop strokes, lever changes and world/area metadata use this boundary; rejection preserves the prior pending snapshot. `BoundedFileReader` checks an opened regular-file descriptor and caps chunk reads, including legacy saves, imports, blueprints and reset journal/preferences recovery. Desktop assignment, saved-view updates, deletion and import publish after durable commits. Creation, rename, lighting and circuit/terrain edits validate a complete candidate before publishing and coalesce autosaves. Import validates a bounded JSON file, copies IDs and appends worlds/areas transactionally; it never restores permissions, scripts or imported assets and never changes the current desktop assignment. Reset is backed up and staged, with failure/rollback handling; see [RECOVERY.md](RECOVERY.md).

`AppStartup.state` supplies the same isolated-or-production state to SwiftUI and `AppTerminationDelegate`. Public AppKit deferred termination handles failed saves before Quit; cancellation leaves pending data and the desktop runtime intact. Recovery snapshots are atomic and verified independently of the failing store. A successful reset discards its old writer, so deferred termination cannot resurrect old data. See [RECOVERY.md](RECOVERY.md).

Live pointer, rendering and power updates should not rebuild menu trees. `MenuPresentation` publishes only changes to its equatable menu snapshot. The root app owns the AppState reference without subscribing all scenes to every runtime update; each screen observes the state it needs. Selection loading does not write component settings; user picker changes save immediately.

Terrain editing uses pure bounded plans and transient stroke previews, publishing one sparse override/history operation on release. World format 5 stores terrain overrides and independent world lighting settings; format 3 decodes with no edits and formats 3/4 default to daytime lighting. Circuit support validation protects occupied cells, and terrain changes invalidate only affected render chunks. Edits are included in library export/import but not component blueprints. See [TERRAIN_EDITING.md](TERRAIN_EDITING.md) for limits and integration contracts.

Blueprint previews are cached, bounded AppKit images mapped through CoordinateMapper; they do not create per-card SpriteKit loops or query Finder. Native editor menus consume action options and revalidate the current world/locks before execution. Tool descriptions are shared across build modes. The switched clock is an example made from existing ports/delays, not a new simulator special case. See [BLUEPRINTS.md](BLUEPRINTS.md).

## Assets and verification

Original assets provide a complete fallback. Local Java/custom packs are bounded image/audio data, not executable content. Imported world assets remain outside the repository and app bundles. App/menu/Dust-tool identity comes from the owner-provided logo; other toolbar icons use native system symbols. No game-derived artwork is shipped. Logo provenance is in [artwork notices](../THIRD_PARTY_NOTICES.md). Keep all imported world textures, particles and audio local.

Audio configuration notifications are scheduled onto the main queue before entering an actor-isolated Combine sink. Engine teardown never runs synchronously on the engine notification queue. Scenes attach owned layers once after initialization; size/camera updates replace only checker geometry and preserve editor overlays. Failed custom-pack replacements retain the current pack, textures, sounds, source and saved preference.

Add meaningful automated coverage for behavior changes, build, and run the full suite. Keep physical validation separate in [TESTING.md](TESTING.md), including untested backup/reset, multi-display and distribution gates. Test hosts, reset harnesses and profiling must never use the owner’s production save/preferences. The retired implementation roadmap is available in Git history.

Per-world lighting is presentation only. A persisted phase/clock anchor drives a shared daylight uniform; lava and powered components supply bounded illumination masks. Masks reuse terrain sampling and remain separate from circuit simulation, Finder and actions. Cursor/editor overlays sit above night shading. See [WORLD_LIGHTING.md](WORLD_LIGHTING.md).
