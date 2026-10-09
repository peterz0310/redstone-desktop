# Architecture and contributor contracts

Redstone Desktop is a native macOS application. SwiftUI owns ordinary UI, AppKit handles desktop windows and native integration, and SpriteKit draws the 2D world. There is no backend. Use documented public APIs; stop and document a real macOS contradiction before proposing the smallest contract change. Do not patch around mismatched desktop behavior with private APIs or unexplained offsets.

## Domain and simulation

Worlds own durable circuit components and seeds. Areas are named cameras into a world, sharing its components. Editor selection is independent of the active desktop assignment. Switching views must not copy circuits or start simulation. Simulation/domain code never imports SpriteKit. Renderers display state and feedback; they never launch files. Action execution, script approval and Finder refresh remain separate from the simulator. See [REDSTONE_RULES.md](REDSTONE_RULES.md) for the supported deterministic model.

All world/screen/scene conversion goes through `CoordinateMapper`. Tile sizes use logical points. The desktop is a virtual bounding canvas anchored at its lower-left; physical display gaps cannot dispatch actions. Finder’s public positions are mapped from the primary screen’s upper-left reference. Multi-display geometry and permission failures must invalidate stale mappings/actions. Build Mode currently edits the primary display only.

## Finder and actions

Finder access goes through `DesktopItemProviding`. Cached occupancy is presentation state; actions verify fresh occupancy before opening the current item. Mouse recipient metadata gates desktop circuit clicks so covered app windows do not activate hidden inputs. Stop, pause, area reassignment, target changes and Quit cancel stale action work.

Open-item actions use native workspace APIs. Script actions support only documented shell extensions, explicit opt-in and approvals bound to the exact file/content. Never execute pack code. Setup and permission checks must not run scripts. See [SCRIPT_OUTPUTS.md](SCRIPT_OUTPUTS.md).

## Persistence and UI

`WorldLibraryDocument` validates references, IDs, terrain and component configuration. Publication follows successful durable commits for library management operations. Import validates a bounded JSON file, copies IDs and appends worlds/areas transactionally; it never restores permissions, scripts or imported assets and never changes the current desktop assignment. Reset is backed up and staged, with failure/rollback handling; see [RECOVERY.md](RECOVERY.md).

Live pointer, rendering and power updates should not rebuild menu trees. `MenuPresentation` publishes only changes to its equatable menu snapshot. The root app owns the AppState reference without subscribing all scenes to every runtime update; each screen observes the state it needs. Selection loading does not write component settings; user picker changes save immediately.

## Assets and verification

Original assets provide a complete fallback. Local Java/custom packs are bounded image/audio data, not executable content. Imported world assets remain outside the repository and app bundles. Only explicitly owner-authorized icon artwork is shipped; provenance and MIT exclusions are in [third-party notices](../THIRD_PARTY_NOTICES.md). Do not extend that exception to general world textures or game audio.

Add meaningful automated coverage for behavior changes, build, and run the full suite. Keep physical validation separate in [TESTING.md](TESTING.md), including untested backup/reset, multi-display and distribution gates. Test hosts, reset harnesses and profiling must never use the owner’s production save/preferences. The retired implementation roadmap is available in Git history.
