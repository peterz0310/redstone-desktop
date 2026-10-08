# Local Minecraft Java texture import

This optional importer reads a **local** Java Edition version JAR or Java texture-pack folder/ZIP and converts supported PNGs into a Redstone Desktop format-1 pack. Minecraft is not required to run the app. The app does not download assets, run Java, invoke a launcher, load mods, execute pack code or import Minecraft audio.

For packs made specifically for Redstone Desktop, use [RESOURCE_PACKS.md](RESOURCE_PACKS.md). A Java pack has `assets/minecraft/textures/...`; a Redstone Desktop pack has `pack.json` with semantic asset IDs. Use the corresponding picker in Appearance & Packs.

## Import an installed version

1. Open **Advanced → Appearance & Packs**.
2. Under **Local Minecraft Java textures**, choose an **Installed version**, then **Import Selected**. Opening the window attempts discovery; **Find Installed Versions** refreshes the list.
3. Wait for the imported texture count. Inspect **Pack diagnostics** for missing mappings. Browse the generated world in the editor, or Start Desktop to see the assigned area.

Discovery checks up to 512 version folders under:

```text
~/Library/Application Support/minecraft/versions/<version>/<version>.jar
```

It lists readable, regular, bounded-size JARs; discovery does not import or validate their contents. Version names sort numerically descending, with names starting `1.` first. The importer validates the selected archive when you press Import. Alternative launcher locations are supported through the manual picker.

For this development Mac, read-only discovery found 29 versions, and a temporary import of **1.21.8** successfully produced all 11 mappings with no warnings. Select that version for the first visual check. This observation is local validation, not a promise that every installed/version/modded JAR is supported. No game files are included with this repository.

## Import a JAR or Java pack manually

Choose **Choose Java JAR / Pack…**, then select a version `.jar`, Java pack `.zip`, or unpacked Java pack folder. If navigating to Library is awkward, press **⌘⇧G** in the picker and paste `~/Library/Application Support/minecraft/versions/`.

A folder must contain `assets/minecraft/textures/` directly. An archive may have those paths directly or under one unambiguous wrapper root. If matching textures occur under multiple roots, the archive is refused. `pack.mcmeta` is not interpreted: only the mappings below are used. Bedrock packs, launcher asset indexes, custom model definitions and mod-specific namespaces are not supported.

## Supported mappings

Modern paths below are relative to `assets/minecraft/textures/block/`. Legacy paths are relative to `assets/minecraft/textures/blocks/`. Modern paths are tried first, then the legacy alternative. Each semantic ID can independently fall back.

| Redstone Desktop ID | Modern PNG | Legacy PNG | Fixed RGB multiplier |
| --- | --- | --- | --- |
| `terrainGrass` | `grass_block_top.png` | `grass_top.png` | 108, 160, 62 |
| `terrainDirt` | `dirt.png` | `dirt.png` | None |
| `terrainStone` | `stone.png` | `stone.png` | None |
| `terrainSand` | `sand.png` | `sand.png` | None |
| `waterShallow` | `water_still.png` | `water_still.png` | 80, 180, 220 |
| `waterDeep` | `water_still.png` | `water_still.png` | 45, 95, 180 |
| `decorationTree` | `oak_leaves.png` | `leaves_oak.png` | 70, 145, 50 |
| `decorationFlower` | `poppy.png` | `flower_rose.png` | None |
| `decorationReed` | `sugar_cane.png` | `reeds.png` | None |
| `redstoneDustOff` | `redstone_dust_dot.png` | `redstone_dust_dot.png` | 170, 30, 30 |
| `redstoneDustOn` | `redstone_dust_dot.png` | `redstone_dust_dot.png` | 255, 190, 50 |

Tint multiplies each decoded RGB channel by the listed channel divided by 255, preserving alpha. This approximates readable grass/leaves/water and distinguishes powered dust; it does not reproduce Minecraft biome lighting or colormaps. Already-colored pack art receives the same tint.

Square PNGs are accepted. Vertical strips whose height is an integer multiple of their width contribute **only the first, top square frame**. Other nonsquare images are skipped. Animation metadata is ignored; there is no animated water. Source PNG dimensions must be 1–1024 on each axis and encoded size at most 4 MiB. Generated terrain is sampled at 16 pixels per tile, with nearest filtering.

Tree/flower/reed images are 2D decoration overlays, not 3D models. Dust uses the existing connected wire geometry with the imported material. Button, lever, repeater, Output, rock decoration, selection overlays and all sounds retain original built-in assets. Importing textures does not change terrain rules, circuits, Finder targets, world data or cameras.

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
| **Reload** | Re-read the currently selected pack. For a Java import, this reads the generated cache, not the original JAR. |
| **Re-import** | Read the last original JAR/folder/ZIP again and build a fresh cache. Requires that source to remain readable at its recorded path. |
| **Reveal Import Cache** | Show the last managed import directory in Finder. |
| **Use Built-In** | Restore original appearance and clear the active selection preference. Keep the last import cache available for re-import/reveal/removal. |
| **Remove Imported Assets** | Delete the last managed cache and clear its record. If active, restore built-in assets; if another custom pack is active, preserve it. Never delete or modify the original source. |

Selection and the last import UUID are app preferences, separate from `library.json`. Reopening validates the cached pack and starts Desktop stopped. Moving the original JAR does not break a valid cache, but prevents Re-import until you choose the source again. A missing/damaged active cache falls back to built-in assets. Import warnings are recorded in `import.json`; startup/Reload diagnostics describe the generated pack, while a fresh import displays mapping warnings.

## Failure and security boundaries

Missing or invalid individual mappings warn and use original fallback. At least one supported, valid PNG is required. A failed Java import preserves the previous active appearance and cache; generic pack-load failures instead activate built-in fallback, as documented in the format guide.

Archives use the same bounded [SafeZIP contract](RESOURCE_PACKS.md#archive-contract-and-limits): no shell extraction, unsafe paths, symlink entries, encryption, ZIP64, multi-disk or unsupported compression. Limits apply to the whole archive's declared metadata, including entries not selected for import. Some large/modded exports may therefore be refused even if a useful texture exists. Recreate a smaller ordinary Java texture pack rather than disabling validation.

Decode/validation happens before cache publication. Writes use fixed semantic filenames in an app-owned staging directory, validate the resulting pack, then rename the directory into place. Archive paths never become output filenames. Removal requires a direct UUID child of the configured cache root, no symlink redirection, and a matching format-1 import record. Unrecognized/tampered directories are refused rather than deleted. A newer selection or Use Built-In supersedes a pending import; late completion cannot reactivate it.

## Sharing the project and contributing

The source, original built-in assets and original examples use the repository license. That license does **not** grant rights to imported Minecraft or third-party pack art. Keep local imported assets out of commits, release bundles, shared screenshots/assets where rights do not permit use, and exported world data. Import paths are always Application Support, never the repository or app bundle. Do not add downloads or bundle game assets to make a demo work.

Code: `Assets/MinecraftImport/JavaTextureImporter.swift` owns discovery/mapping/cache records; `Assets/AssetProvider.swift` owns asynchronous selection and lifecycle; `Assets/AssetSettingsView.swift` exposes controls. Renderer consumers only see semantic validated assets; simulation never sees pack paths or depends on SpriteKit.

Tests in `JavaTextureImportTests.swift` use original synthetic PNGs in a real deflated ZIP, isolated preferences and temporary roots. They cover discovery, modern/legacy mappings, tint/first frame, ignored unrelated data, partial fallback, rejection/write failure, managed deletion, source preservation, reload/re-import/startup and inactive-cache removal. Extend mappings with original fixtures and explicit fallback expectations. A real local JAR can be validated in a temporary cache without committing its images or changing the owner's active selection.
