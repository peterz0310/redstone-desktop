# Local Minecraft Java texture import

This optional importer reads a **local** Java Edition version JAR or Java texture-pack folder/ZIP and converts supported PNGs into a Redstone Desktop format-1 pack. Minecraft is not required to run the app. The app does not download assets, run Java, invoke a launcher, load mods, execute pack code or import Minecraft audio.

For packs made specifically for Redstone Desktop, use [RESOURCE_PACKS.md](RESOURCE_PACKS.md). A Java pack has `assets/minecraft/textures/...`; a Redstone Desktop pack has `pack.json` with semantic asset IDs. Use the corresponding picker in Appearance & Packs.

## Import an installed version

1. Open **Settings → Appearance** (or Advanced → Appearance & Packs).
2. Under **Use your Minecraft textures**, choose a **Minecraft version**, then **Use Minecraft Textures**. The first discovered version is selected automatically. **More options & custom packs → Look for Installed Versions Again** refreshes the list.
3. Wait for the imported texture count. Inspect **Import details** for missing mappings. Browse the generated world in the editor, or Start Desktop to see the assigned area.

Discovery checks up to 512 version folders under:

```text
~/Library/Application Support/minecraft/versions/<version>/<version>.jar
```

It lists readable, regular, bounded-size JARs; discovery does not import or validate their contents. Version names sort numerically descending, with names starting `1.` first. The importer validates the selected archive when you press Import. Alternative launcher locations are supported through the manual picker.

For this development Mac, read-only discovery found 29 versions, and a temporary import of **1.21.8** successfully produced all 26 mappings with no warnings after the appearance follow-up. Select that version for the first visual check. This observation is local validation, not a promise that every installed/version/modded JAR is supported. The repository now includes owner-requested dust and derived toolbar-icon exceptions; see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). World-texture imports remain local and are not committed or shipped.

## Import a JAR or Java pack manually

Choose **Choose a Texture Pack…**, then select a version `.jar`, Java pack `.zip`, or unpacked Java pack folder. If navigating to Library is awkward, press **⌘⇧G** in the picker and paste `~/Library/Application Support/minecraft/versions/`.

A folder must contain `assets/minecraft/textures/` directly. An archive may have those paths directly or under one unambiguous wrapper root. If matching textures occur under multiple roots, the archive is refused. `pack.mcmeta` is not interpreted: only the mappings below are used. Bedrock packs, launcher asset indexes, custom model definitions and mod-specific namespaces are not supported.

## Supported mappings

There are 37 optional mappings, including landscape surface/scenery mappings and two log tops. Current automated imports use original synthetic assets. Reimport an installed version to add the new textures to an existing cache. Torch direction/NOT labels stay app UI; pack pixels never affect the documented [circuit rules](REDSTONE_RULES.md).

Modern paths below are relative to `assets/minecraft/textures/block/`. Legacy paths are relative to `assets/minecraft/textures/blocks/`. Modern paths are tried first, then the legacy alternative. Each semantic ID can independently fall back.

| Redstone Desktop ID | Modern PNG | Legacy PNG | Tint or 2D recipe |
| --- | --- | --- | --- |
| `terrainGrass` | `grass_block_top.png` | `grass_top.png` | 108, 160, 62 |
| `terrainDryGrass` | `grass_block_top.png` | `grass_top.png` | 181, 168, 69 |
| `terrainSnow` | `snow.png` | `snow.png` | None |
| `terrainGravel` | `gravel.png` | `gravel.png` | None |
| `decorationOakLog` | `oak_log_top.png` | `log_oak_top.png` | Solid backing beneath central oak leaves |
| `decorationSpruceLog` | `spruce_log_top.png` | `log_spruce_top.png` | Solid backing beneath central pine leaves |
| `decorationPine` | `spruce_leaves.png` | `leaves_spruce.png` | 55, 100, 75 |
| `decorationShrub` | `acacia_leaves.png` | `leaves_acacia.png` | 140, 145, 55 |
| `decorationMushroom` | `red_mushroom.png` | `mushroom_red.png` | None |
| `terrainDirt` | `dirt.png` | `dirt.png` | None |
| `terrainStone` | `stone.png` | `stone.png` | None |
| `terrainSand` | `sand.png` | `sand.png` | None |
| `waterShallow` | `water_still.png` | `water_still.png` | 80, 180, 220 |
| `waterDeep` | `water_still.png` | `water_still.png` | 45, 95, 180 |
| `lavaStill` | `lava_still.png` | `lava_still.png` | none |
| `decorationTree` | `oak_leaves.png` | `leaves_oak.png` | 70, 145, 50 |
| `decorationFlower` | `poppy.png` | `flower_rose.png` | None |
| `decorationReed` | `sugar_cane.png` | `reeds.png` | None |
| `decorationDandelion` | `dandelion.png` | `flower_dandelion.png` | None |
| `decorationBlueOrchid` | `blue_orchid.png` | `flower_blue_orchid.png` | None |
| `decorationAllium` | `allium.png` | `flower_allium.png` | None |
| `decorationOxeyeDaisy` | `oxeye_daisy.png` | `flower_oxeye_daisy.png` | None |
| `decorationCoal` | `coal_ore.png` | `coal_ore.png` | None |
| `decorationIron` | `iron_ore.png` | `iron_ore.png` | None |
| `decorationCactus` | `cactus_top.png` | `cactus_top.png` | Transparent top-view recipe |
| `redstoneButtonUp` | `stone.png` | `stone.png` | Raised 2D stone-button recipe |
| `redstoneButtonDown` | `stone.png` | `stone.png` | Depressed 2D stone-button recipe |
| `redstoneLeverOff` | `lever.png` | `lever.png` | Off handle recipe |
| `redstoneLeverOn` | `lever.png` | `lever.png` | On handle recipe |
| `redstoneRepeaterOff` | `repeater.png` | `repeater_off.png` | East-facing top/indicator recipe |
| `redstoneRepeaterOn` | `repeater_on.png` | `repeater_on.png` | East-facing top/indicator recipe |
| `redstonePlateOff` / `redstonePlateOn` | `oak_planks.png` | `planks_oak.png` | Wooden raised/depressed pressure-plate recipe for Any item |
| `redstoneSensorOff` / `redstoneSensorOn` | `stone.png` | `stone.png` | Stone raised/depressed pressure-plate recipe for name/extension filters |
| `redstoneLampOff` | `redstone_lamp.png` | `redstone_lamp_off.png` | Full square lamp face |
| `redstoneLampOn` | `redstone_lamp_on.png` | `redstone_lamp_on.png` | Full square lit lamp face |
| `lightTorch` | `torch.png` | `torch_on.png` | Regular torch; unchanged pixels |
| `redstoneTorchOff` | `redstone_torch_off.png` | `redstone_torch_off.png` | First square frame, unchanged pixels |
| `redstoneTorchOn` | `redstone_torch.png` | `redstone_torch_on.png` | First square frame, unchanged pixels |
| `redstoneDustOff` | `redstone_dust_dot.png` | `redstone_dust_dot.png` | Dark red material recipe |
| `redstoneDustOn` | `redstone_dust_dot.png` | `redstone_dust_dot.png` | Bright red material recipe |
| `redstoneOutputOff` | `command_block_front.png` | `command_block_front.png` | Command-block face |
| `redstoneOutputOn` | `command_block_front.png` | `command_block_front.png` | Face with original red powered indicator |

For rows with numeric tint, each decoded RGB channel is multiplied by the listed channel divided by 255, preserving alpha. This approximates readable grass/leaves/water; it does not reproduce Minecraft biome lighting or colormaps. Already-colored pack art receives the same tint. These are cache colors: the renderer further darkens shallow-water RGB by 70% red/green and 88% blue, including existing imports, so a white water source appears as 56, 126, 193 before alpha backing. Source/cache pixels and animation metadata are unchanged; no reimport is needed for this display adjustment.

Square PNGs are accepted. Water and lava retain vertical square-frame strips with up to 64 frames. Their adjacent `.png.mcmeta` files contribute frame order, integer frame times (1–200 ticks, 20 ticks/second), and optional interpolation. Missing metadata uses sequential 1-tick frames; malformed metadata warns and uses that default. Unreadable/oversized metadata uses the missing-metadata default. Only bounded JSON data is read; pack shaders, models and code are never executed. Other animated textures still contribute only the first, top square frame. Other nonsquare images are skipped. Source PNG dimensions remain 1–1024 on each axis and encoded size at most 4 MiB. All terrain is sampled at 16 pixels per tile, with nearest filtering. See [terrain animation](TERRAIN_ANIMATION.md) for rendering, limits and Reduce Motion.

Tree/flower/reed images are 2D decoration overlays, not 3D models. Dust uses the existing connected wire geometry with the imported material. Selection overlays and all sounds retain original built-in assets. Outputs use the command-block face with a small original red indicator when powered; soft occupancy glow remains app UI; Output art covers a full tile with no text or colored backing. Cacti crop the central top face into a transparent 16×16 overlay. Missing individual mappings also use original fallback. Importing textures does not change terrain rules, circuits, Finder targets, world data or cameras.

### Circuit and decoration appearance

Java stone buttons use the validated stone texture cropped into a raised/depressed 16×16 transparent icon with different face shading. Levers use the known handle UV region `[7,6]–[9,16]` scaled from the source raster onto an original gray base; opposite slopes distinguish on/off. Repeaters rotate the top image from north to the semantic east-facing orientation and add two original red/dark indicator marks. Scene rotation then handles all four directions. These fixed 2D recipes do not read/execute Java models or reproduce 3D geometry; labels still show direction and actual configured delay.

Dust converts source-dot luminance into an **opaque** textured material, dark red when off and bright red when on (base RGB 106/12/18 and 255/24/32, luminance strength 184–255/255). Transparent source corners become continuous material so they cannot cut holes in connected traces. The renderer supplies one-fifth-tile-wide cardinal strips and square junctions, without an orange tint. Positive power applies neutral brightness `0.45 + 0.55 × power/15`, so weak signals fade while strength 15 retains full bright red. Adjacent aligned repeaters have short visible end traces; larger repeater art retains labels and directional port rules. Generic Redstone Desktop packs can still override semantic wire materials directly.

The existing generator's flower and legacy rock positions are preserved. Stable seed/coordinate selection chooses poppy/dandelion/blue orchid/allium/oxeye daisy, with cactus on sand (including sandy shores) and coal/iron elsewhere. Generated dirt is presented with the imported grass-block top; explicit saved dirt overrides remain dirt. Ore art replaces loose rock art; deposits remain placement-blocking decorations, not mineable resources. This is appearance variety, not a generation/save migration.

**After upgrading an existing import, use More options & custom packs → Refresh Imported Minecraft Textures once.** Reload only reads the generated cache; it cannot recover discarded animation frames or add new mappings. Reimport reads the original local source and creates the current 37-mapping pack, including water/lava strips and log tops. No automatic rewrite of user caches occurs.

## Cache, reload and removal

An import creates one managed directory:

```text
~/Library/Application Support/RedstoneDesktop/ImportedTextures/<UUID>/
  pack.json
  import.json
  terrainGrass.png
  ...only successfully mapped semantic PNGs...
```

`pack.json` is an ordinary format-1 manifest consumed by the shared resource-pack loader. `import.json` records format version 1, cache UUID, absolute source path, import date, successful semantic-to-source-path mappings and missing-mapping warnings. No source archive, executable, audio or unrelated asset is copied. Imported PNGs are decoded, optionally cropped/tinted, then re-encoded; they are not byte-identical copies of source PNGs.

There is **one active pack**, shared by editor and desktop. Importing Java textures replaces the current custom pack; unspecified assets resolve to built-in defaults rather than stacking packs. The app retains one last managed import for the controls below. Successful re-import/replacement publishes a new UUID directory, then removes the previous managed import. If old-cache removal fails, a warning reports the retained directory.

| Control | Behavior |
| --- | --- |
| **Reload Current Pack** | Re-read the currently selected pack. For a Java import, this reads the generated cache, not the original JAR. |
| **Refresh Imported Minecraft Textures** | Read the last original JAR/folder/ZIP again and build a fresh cache. Requires that source to remain readable at its recorded path. |
| **Show Imported Textures in Finder** | Show the last managed import directory in Finder. |
| **Use Original Look** | Restore original appearance and clear the active selection preference. Keep the last import cache available for re-import/reveal/removal. |
| **Remove Imported Textures** | Delete the last managed cache and clear its record. If active, restore built-in assets; if another custom pack is active, preserve it. Never delete or modify the original source. |

Selection and the last import UUID are app preferences, separate from `library.json`. Reopening validates the cached pack and starts Desktop stopped. Moving the original JAR does not break a valid cache, but prevents Re-import until you choose the source again. A missing/damaged active cache falls back to built-in assets. Import warnings are recorded in `import.json`; startup/Reload diagnostics describe the generated pack, while a fresh import displays mapping warnings.

## Failure and security boundaries

Missing or invalid individual mappings warn and use original fallback. At least one supported, valid PNG is required. A failed Java import preserves the previous active appearance and cache; generic pack-load failures instead activate built-in fallback, as documented in the format guide.

Archives use the same bounded [SafeZIP contract](RESOURCE_PACKS.md#archive-contract-and-limits): no shell extraction, unsafe paths, symlink entries, encryption, ZIP64, multi-disk or unsupported compression. Limits apply to the whole archive's declared metadata, including entries not selected for import. Some large/modded exports may therefore be refused even if a useful texture exists. Recreate a smaller ordinary Java texture pack rather than disabling validation.

Decode/validation happens before cache publication. Writes use fixed semantic filenames in an app-owned staging directory, validate the resulting pack, then rename the directory into place. Archive paths never become output filenames. Removal requires a direct UUID child of the configured cache root, no symlink redirection, and a matching format-1 import record. Unrecognized/tampered directories are refused rather than deleted. A newer selection or Use Built-In supersedes a pending import; late completion cannot reactivate it.

## Sharing the project and contributing

The source, original built-in assets and original examples use the repository license. That license does **not** grant rights to imported Minecraft or third-party pack art. Keep local imported assets out of commits, release bundles, shared screenshots/assets where rights do not permit use, and exported world data. Import paths are always Application Support, never the repository or app bundle. Do not add downloads or bundle world assets to make a demo work. The separately owner-authorized app/menu/tool icon artwork is documented in THIRD_PARTY_NOTICES.md; it does not extend to world textures.

Code: `Assets/MinecraftImport/JavaTextureImporter.swift` owns discovery/mapping/cache records; `JavaCircuitArt.swift` owns fixed raster recipes and `World/DecorationAppearance.swift` chooses stable variants; `Assets/AssetProvider.swift` owns asynchronous selection and lifecycle; `Assets/AssetSettingsView.swift` exposes controls. Renderer consumers only see semantic validated assets; simulation never sees pack paths or depends on SpriteKit.

Tests in `JavaTextureImportTests.swift` use original synthetic PNGs in a real deflated ZIP, isolated preferences and temporary roots. They cover discovery, modern/legacy mappings, tint, liquid frames/timing/cache round trips, static first-frame fallback, ignored unrelated data, partial fallback, rejection/write failure, managed deletion, source preservation, reload/re-import/startup and inactive-cache removal. Extend mappings with original fixtures and explicit fallback expectations. A real local JAR can be validated in a temporary cache without committing its images or changing the owner's active selection.

The animation follow-up was also checked against the locally installed **1.21.8 JAR** in a temporary cache: 37 textures, no import warnings; water has 32 frames at 0.1 seconds each, and lava has 20 frames in a 38-step forward/backward sequence at 0.1 seconds each. Cache reload preserved the sequences. This read did not change the owner’s active pack, save data or source JAR, and its temporary imported images were removed. Other Java versions/packs still need their own validation.

Lamps and regular torches use original art when missing from a pack. Existing imported caches keep their original mappings; choose **Refresh Imported Minecraft Textures** for the Minecraft JAR or Java pack to pick up the three new mappings. They are image data only, never code, models or scripts.

Pressure-plate recipes sample the material into a transparent 16×16 plate, with a shaded rim and a depressed powered variant. An Any item Sensor uses the wooden plate IDs just like a Plate; filtered Sensors use the stone IDs. No nonexistent standalone Java pressure-plate PNG or model execution is required. Refresh an existing Minecraft import to acquire the new mappings.
