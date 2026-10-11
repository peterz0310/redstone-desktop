# Default landscapes

New worlds automatically use the improved landscape; there are no extra generation controls. A seed still identifies one continuous map, and areas are views into that map rather than separate terrain copies.

Climate regions are broader than before. Eight biomes mix large recognizable areas with smaller ground details:

| Biome | Ground and scenery |
| --- | --- |
| Plains | Open grass, scattered flowers and occasional small groves |
| Woodland | Clusters of trees, flower clearings and mushrooms |
| Meadow | Grass with denser patches of mixed flowers |
| Savanna | Golden dry grass with sparse shrubs and rare lava pools |
| Desert | Sand, scattered cacti and rare lava pools |
| Rocky | Stone, gravel patches, coal/iron deposits and rare lava pools |
| Alpine | Snow, exposed stone and evergreen pines |
| Wetland | Lakes, winding rivers, shallow-water reeds and gravel or sandy banks |

Rivers follow continuous winding contours independently of lake elevation, so they cross inland ground and can connect to lakes. This is a 2D landscape, not a water-flow or erosion simulation. River depth and bank width vary with the local contour slope. Biomes have distinct climate/height thresholds; riverbanks and exposed stone can interrupt a region without becoming separate worlds.

Trees now occupy a 3×3 canopy with five required blocks (center plus four neighbors) and independently optional corners, plus an occasional leaf extending one arm, with a full wood block beneath the center leaves. Transparent outer leaves reveal the ground; transparent center leaves reveal the log. Planting cells keep canopies spaced apart, and banks clip foliage rather than placing it on water. About one quarter of trees get one extra leaf, chosen independently of their corners and attached to a required arm. The maximum footprint fits a 5×5 clearing brush. Both the central block and surrounding leaves block construction until cleared.

Dry grass, snow and gravel support every circuit component. Water and lava do not. Trees, flowers, pines, shrubs, mushrooms, reeds and cacti must be cleared or painted over to build; ore deposits on stone remain buildable. The new surfaces are available in both Terrain brush menus. Restore Original restores this generator's terrain, not a historical map.

## Existing worlds

Generation settings now default to version 3. Versions 1 and 2 still use the current landscape, so historical untouched terrain positions are not preserved. On library load, those older settings are upgraded once: any generated scenery or liquid that now conflicts with a saved component is replaced by an explicit support tile beneath that component (same dry surface with decorations cleared, or grass for a liquid). Later leaf/lava additions in the old feasibility fixture are reconciled too. Circuits, lever states, worlds, areas and assignments are preserved; existing painted terrain is never repaired or overwritten automatically.

Before writing the upgraded library, the app validates every world and retains the exact original bytes as `library-before-terrain-upgrade-<UUID>.json` beside `library.json` in Application Support. If validation, backup or saving fails, the source library remains preserved and saving/editing stays blocked with an explanation. Already-upgraded version-3 libraries are validated strictly; malformed components, unsupported versions, original fixture obstacles and invalid painted terrain are not silently accepted. Fresh worlds remain useful for exploring changed terrain, but deleting old builds is unnecessary.

## Artwork and packs

Every new surface and decoration has project-owned fallback pixels, so no Minecraft install or pack is required. Optional Java imports map dry grass to a golden-tinted grass top, snow/gravel to their block textures, pines/shrubs to spruce/acacia leaves, tree centers to oak/spruce log tops and mushrooms to red mushroom art. Existing cached imports do not gain new images automatically: import your installed version again to obtain those textures. An older pack continues to work and uses original art for missing IDs. No new game art is bundled and no pack code runs. See [resource-pack IDs](RESOURCE_PACKS.md) and [Java import mappings](JAVA_TEXTURE_IMPORT.md).

## Contributor contract

`WorldGenerator` remains pure and stateless. All sampling uses integer noise at global coordinates; requests, chunk order and camera motion cannot affect the result. Elevation uses 128/48-tile fields, moisture 224, temperature 256, river contours 160 with 48-tile bends, and scenery clusters 40 with 24-tile ground detail. Trees are centered deterministically inside six-tile cells and occupy five to ten tiles. Corner and extension choices use separate seed/center hashes; sampling derives each canopy directly, including at chunk edges. No neighboring chunk lookup, per-world random state, background terrain task or Finder dependency is introduced.

Automated tests cover fixed seed fingerprints, all biomes/surfaces/scenery, integer limits, chunk seams, inland rivers and banks, broad region continuity, dry-ground coverage, varied tree footprints with all sixteen corner combinations, occasional connected extensions in every direction, cross-chunk canopies, transparent leaf/log compositing, new brush persistence, placement and complete built-in/Java texture support. Golden fingerprints represent the current generator, not historical version-1 terrain. Native appearance, imported pack fit and real panning remain [Mac checks](TESTING.md).

Run `scripts/terrain-preview.sh` to write `build/terrain-preview.png`: seeds 42, 2026 and 7 show wide landscape overviews and close-ups using the actual original fallback pixels. This developer tool compiles only generation/domain types and pixel art; it never launches the app or reads its library. The overview samples every four tiles, so narrow features can appear broken there even when the full-resolution map is continuous.

Rare lava pools use deterministic 64-tile cells: one in six cells proposes a jagged radius-2–4 pool, clipped to desert, rocky or savanna terrain. The sampled seed-42 region is tested to keep lava below 0.5% of tiles. Pools have no scenery overlays and never replace lakes, rivers or their banks. They are visual liquids, without spreading, damage, heat, ignition or Finder actions. Lava is also available as a Terrain brush, with ordinary circuit protection, persistence and Undo/Redo. [Animation](TERRAIN_ANIMATION.md) is a renderer concern; the generator has no clock, asset or SpriteKit dependency.

When changing generated surfaces/scenery or expanding legacy fixture tiles, bump the generation revision and define how existing circuit footprints are preserved. Never rely on owner deletion or disable library validation to ship a terrain change. The version-3 upgrade is bounded by the existing tile/library limits and tested for exact backups, idempotence, strict rejection and editor/activation recovery.
