# Terrain editing

Choose **Terrain** in the editor's Build tools. Pick a surface and brush size, then drag over the map. You see a preview while holding the mouse; releasing saves the whole stroke as one undo step. Escape cancels the unfinished stroke. A click paints one brush footprint. Fast drags interpolate between positions rather than leaving gaps.

## Brushes

- **Grass, Dirt, Stone, Sand, Dry grass, Snow, Gravel:** replace the surface and remove decorations. Use Grass to make a clear construction patch over trees or water. Dirt is an intentional exposed dirt surface; generated dirt retains the existing grassy appearance.
- **Shallow water / Deep water / Lava:** paint animated liquid onto clear tiles. Liquids reject component placement; see [Terrain animation](TERRAIN_ANIMATION.md).
- **Clear decorations:** removes trees, flowers, ores, cactuses or reeds while keeping the visible ground surface. It doesn't turn liquids into buildable land.
- **Restore original:** removes your terrain edits and restores the world's original generated terrain, including decorations. Older fixture-based worlds restore their original construction patch too.

Brushes are centered square footprints: **1×1**, **3×3**, or **5×5** tiles. The editor outlines their footprint; green is editable and orange protects a circuit tile. The status message reports changed and protected tiles.

## Existing circuits and undo

Painting preserves every component, its settings and saved lever position. Dry surfaces can be painted underneath a circuit. Liquid painting or restoration skips any tile that would leave its component on water, lava, decoration or missing ground; the rest of the stroke still applies. Explicitly erase the component first if you intend to change that ground.

Terrain and circuit edits share the right panel's Undo/Redo history, so a drag is one operation. Undo placement before undoing the terrain that made placement possible. History remains per world and session-only; the resulting terrain itself persists after quitting. Terrain edits don't move the camera, copy components between worlds, reassign Desktop, open files or change Finder icons.

Editing is disabled for a running world's circuit, in Test Circuit, during maintenance and in seed previews. Switching worlds, changing tools or closing the editor cancels its unfinished stroke. If another editor changes the source world before release, the draft is cancelled rather than overwriting that change. Releasing outside the canvas also cancels the stroke.

## Desktop Build Mode

Enter **Build on Desktop** and choose **0 Terrain** (existing shortcuts 1–9 retain their tools). Pick the same brush/size in the palette; drag to preview and release to save. It edits the assigned desktop world even if the editor is browsing another world. The circuit remains stopped. Escape cancels an active stroke; another Escape exits Build Mode. Right-click in Terrain cancels a stroke rather than erasing a circuit. Exit Build Mode normally when finished, then explicitly Start Desktop when ready.

Desktop Build Mode currently uses the primary display only. Its brush outline shows the footprint; the status reports protected circuit cells. Use the editor for per-cell protection colors and Undo/Redo after exiting Build Mode.

## Storage and limits

Edits belong to the world, so all its saved areas show the same terrain. They are included in Export Library, Import Library and existing recovery backups. Circuit blueprints and clipboard copies still contain only components, not terrain.

World format **5** stores a sparse `terrainOverrides` dictionary separately from generated terrain and circuit configuration. Format 3 worlds load with no edits; formats 3/4 default to daytime lighting, while format 5 also saves per-world lighting; legacy worlds retain their original terrain profile. Older apps cannot read format 5 saves. Keep an exported library before downgrading.

Each stroke is limited to 4096 addressed tiles and each world to 8192 saved edited tiles. The existing 2 MB whole-library limit also applies; terrain publication checks that budget before changing saved configuration. Restore Original removes overrides to free the terrain budget. Oversized strokes cancel without publishing partial edits. Ordinary autosave/recovery status still reports disk write failures.

## Contributor contracts

`TerrainEditing`, `TerrainStroke` and planning/validation are pure domain code, independent of SpriteKit, Finder and action execution. The plan validates support for existing components, skips protected cells and restores a validated WorldDocument before publication. Preview state belongs to the editor/build session; AppState publishes only on release. All pointer, brush and scene mapping uses CoordinateMapper.

Undo stores sparse terrain override deltas alongside component deltas, checks conflicts before applying and preserves unrelated lever state. Renderer invalidation targets changed chunks; seed/asset changes still invalidate all terrain textures. Painting uses existing terrain/decoration asset IDs and adds no bundled game art or backend.
