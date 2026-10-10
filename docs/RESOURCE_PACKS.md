# Redstone Desktop resource packs

Redstone Desktop packs are optional **data**: PNG images, short WAV effects and a JSON manifest. The app runs without a pack or Minecraft installation. Nothing in a pack is executed. World generation, terrain capabilities, component placement, simulation, Finder occupancy and action permissions are independent of appearance.

To use an already-installed Minecraft Java version or native Java pack, see [Local Java texture import](JAVA_TEXTURE_IMPORT.md). That importer creates a local format-1 pack; it does not require you to write a manifest or add game assets to this repository.

## Try the included original example

Open **Advanced → Appearance & Packs → More options & custom packs → Choose Custom Pack Folder or ZIP…**. Select `examples/GrassOnly` or `examples/GrassOnly.zip` from this repository. Grass becomes a purple/teal checker; every other terrain, decoration, circuit and sound uses its built-in default. Both forms should look the same. Choose **Use Original Look** to restore the original appearance.

This example is original project art under the repository's MIT license, not Minecraft art. It is safe to commit/share. The ZIP includes one wrapper folder, as macOS Finder's Compress action normally does.

## Create a pack

Create a folder containing `pack.json`. Add your PNG/WAV files anywhere below that folder. Example:

```text
MyPack/
  pack.json
  textures/
    grass.png
    button-up.png
  sounds/
    press.wav
```

```json
{
  "formatVersion": 1,
  "name": "My Pack",
  "author": "Your name",
  "assets": {
    "terrainGrass": "textures/grass.png",
    "redstoneButtonUp": "textures/button-up.png",
    "buttonPress": "sounds/press.wav"
  }
}
```

`formatVersion`, `name` and `assets` are required. `author` is optional. Name must be nonblank and at most 128 characters; author at most 256; manifest at most 64 KiB; at most 64 asset entries. Version 1 is the only supported version. An empty asset map is valid and means all built-in defaults. Additional JSON metadata fields are currently ignored; do not rely on them for renderer behavior. Publish your artwork license/attribution separately in a README/LICENSE.

Paths are relative to **the folder containing pack.json**, including inside ZIPs. Use `/`, not `\`. Absolute paths, drive prefixes/colons, control characters, empty path components, `.` and `..` are refused. Asset symlinks are ignored with diagnostics; assets may not escape the selected root. Do not use URLs, executable scripts or compiled plugins as asset paths.

To ZIP on macOS, right-click the pack folder → **Compress**. A ZIP can have its manifest directly at root or below one wrapper folder. It must contain exactly one `pack.json`. Reload Current Pack reads the originally selected folder/ZIP again; no automatic file watcher is installed.

## Texture IDs (case-sensitive)

All IDs below accept **PNG only**. These are the actual format-1 names; examples in older planning documents may differ.

| ID | Appearance |
| --- | --- |
| `terrainGrass` | Grass surface |
| `terrainDirt` | Dirt surface |
| `terrainStone` | Stone surface |
| `terrainSand` | Sand surface |
| `terrainDryGrass` | Golden savanna grass surface |
| `terrainSnow` | Snowy highland surface |
| `terrainGravel` | Gravel riverbank / rocky surface |
| `waterShallow` | Shallow-water surface |
| `waterDeep` | Deep-water surface |
| `decorationTree` | Oak leaf-block overlay, reused across the canopy |
| `decorationOakLog` | Solid log top beneath central oak leaves |
| `decorationSpruceLog` | Solid log top beneath central pine leaves |
| `decorationPine` | Evergreen leaf-block overlay, reused across the canopy |
| `decorationShrub` | Dry shrub overlay |
| `decorationMushroom` | Woodland mushroom overlay |
| `decorationFlower` | Poppy; also family fallback for other flower variants |
| `decorationDandelion` | Yellow dandelion overlay |
| `decorationBlueOrchid` | Blue orchid overlay |
| `decorationAllium` | Purple allium overlay |
| `decorationOxeyeDaisy` | White oxeye daisy overlay |
| `decorationCoal` | Coal deposit surface |
| `decorationIron` | Iron deposit surface |
| `decorationCactus` | Cactus top on sand; original fallback, never ore-family fallback |
| `decorationRock` | Legacy family fallback for coal/iron deposits; retained for older packs |
| `decorationReed` | Reed overlay |
| `redstoneDustOff` | Unpowered wire material |
| `redstoneDustOn` | Powered wire material |
| `redstoneButtonUp` | Released button icon |
| `redstoneButtonDown` | Pressed button icon |
| `redstoneLeverOff` | Off lever icon |
| `redstoneLeverOn` | On lever icon |
| `redstoneRepeaterOff` | Unpowered repeater icon, pointing right/east |
| `redstoneRepeaterOn` | Powered repeater icon, pointing right/east |
| `redstonePlateOff` / `redstonePlateOn` | Desktop pressure plate; original-art fallback in older packs/Java imports |
| `redstoneSensorOff` / `redstoneSensorOn` | File sensor; original-art fallback in older packs/Java imports |
| `redstoneTorchOff` | Off torch icon |
| `redstoneTorchOn` | On torch icon |
| `redstoneOutputOff` | Unpowered output icon |
| `redstoneOutputOn` | Powered output icon |

PNG bounds: 1–1024 pixels in each dimension, at most 4 MiB encoded, one image frame. Square images are recommended; rectangular images stretch to the semantic surface. Transparent decorations overlay the terrain; alpha is decoded as premultiplied RGBA and composited. Texture sampling is nearest-neighbor. There are 41 texture IDs in format 1; the two tree log IDs, three new landscape surface IDs and three scenery IDs, the seven decoration variant IDs, two torch IDs and four desktop detector IDs are additive, so earlier manifests remain valid. Button/lever/repeater icons retain labels, rotation and power frames; full-tile Outputs retain soft occupancy glows; a pack does not replace interaction geometry. Dust uses filled square junctions and cardinal strips one fifth of a tile wide; its material is overridden, not a full-tile vanilla dust model. Built-in powered material is bright red, with dark red when off. Texture colors are displayed without multiplying by a yellow/orange UI tint. Positive power multiplies material RGB by a neutral brightness factor `0.45 + 0.55 × power/15`, preserving hue and alpha; zero uses the separate off material. Custom packs may deliberately choose other colors. Repeaters cover 86% of a tile, with short wire strips bridging compatible front/rear ports to adjacent repeaters and other connected components; side/head-to-head neighbors do not gain ports. Button/lever art has transparent backing; button/lever state labels and repeater rotation/delay remain. Outputs cover a full tile without app text or colored backing; their glow is green for one occupant, gently red for empty, amber for ambiguous and gray for unavailable. Highlight/selection/diagnostic overlays remain app UI.

Generated terrain is baked into bounded chunk sprites. Generated dirt uses `terrainGrass` (Java grass-block top); explicit saved dirt overrides still use `terrainDirt`. Legacy rock slots on sand, including sandy shores, use `decorationCactus`; other rock slots choose coal/iron. These are appearance choices independent of generation and placement rules. Default terrain generation has changed; see [World generation](WORLD_GENERATION.md). Outputs use original terminal-block defaults or optional command-block Java art; occupancy glow, inspector details and actions remain separate. Built-in terrain uses 8 pixels/tile. A terrain/decoration override uses 16 pixels/tile, sampled from the source PNG (higher-resolution files are reduced with nearest sampling). This keeps memory bounded and preserves standard 16-pixel Java texture detail. Circuit textures retain their source raster resolution. Shelf thumbnails remain schematic summaries rather than pack previews. Explicit non-generated diagnostic terrain uses provider textures; generated legacy overrides use the same terrain pack as their surroundings.

Tree canopies span five to nine world tiles in a 3×3 footprint; the cross is always present and each corner may be missing. `decorationTree` / `decorationPine` provide the leaves on every canopy tile; the renderer puts `decorationOakLog` / `decorationSpruceLog` beneath the center only. Transparent center pixels reveal wood, while outer leaf holes reveal terrain. Missing log textures use original opaque wood, so older imported packs immediately gain proper trunks. Reimport a Java version to use its log textures. A custom leaf image should keep its transparency; an entirely opaque image will naturally hide the log.

## Sound IDs (case-sensitive)

`buttonPress`, `buttonRelease`, `leverToggleOn`, `leverToggleOff`, `repeaterTick`, `torchToggle`, `placeCircuit`, `removeCircuit`, `invalidPlacement`, `outputActivate`.

Sounds require **little-endian RIFF WAV**, PCM 16-bit or IEEE float 32-bit, mono or stereo, 8–96 kHz, at most 2 seconds and 8 MiB encoded. Stereo is averaged to mono, linearly resampled to 44.1 kHz, and peaks above 0.11 are reduced to 0.11 to leave overlap headroom. The engine then applies master volume/mute and per-event stereo pan. NaN/infinite samples are refused. WAV extensible/compressed WAV, OGG, MP3, streaming audio, playlists and code are not supported in format 1.

Decoration type/positions come from the current generator or explicit saved terrain. A separate stable seed/coordinate hash chooses five flower appearances and coal/iron at legacy rock positions. These choices never depend on load order, camera or system randomness; changing art does not invalidate saved builds. The inspector names the visible variant. Built-in art supplies every variant without requiring a pack.

Effects replace semantic events only: changing `buttonPress` does not change when a button accepts input. Eight simultaneous voices are retained; at saturation the oldest is recycled. Changing packs clears currently playing effects, preserves volume/mute, and does not replay held circuit events.

## Fallback and diagnostics

Resolution order is selected custom/imported pack → built-in original assets. Only **one** pack is active; imported Java textures use this same slot.

- An omitted ID uses built-in assets without warning, except decoration variants first try their family override: flowers → `decorationFlower`; coal/iron → legacy `decorationRock`. A specific variant override takes priority.
- Unknown IDs are ignored with a warning (useful for spotting misspellings).
- Missing, oversized, unsupported or undecodable individual files warn and fall back **only that asset**.
- Bad manifests, escaping manifest paths, or unsafe/unsupported ZIP structures refuse the whole pack and activate built-in assets.
- Appearance & Packs shows active name, selected source, counts and expandable per-asset diagnostics.

The loader constructs a complete immutable snapshot before applying it. A newer selection or Use Original Look supersedes a pending load; a late load cannot switch the pack back. Snapshot/revision changes invalidate circuit/terrain appearance caches while retaining world data, simulator, camera, input monitors and Finder targets. Assets are decoded off the main thread; renderers never read paths from disk. Audio receives validated sample arrays, not pack code.

Selection is stored in app preferences, **not library.json**. Reopening revalidates the selected source, starts Desktop disabled, and falls back if the source was moved/damaged. A successful reload updates the snapshot. Use Original Look clears the remembered selection. Tests construct isolated preferences and temporary packs; the application test host does not restore the owner's selection.

## Archive contract and limits

The shared `SafeZIP` reader supports ordinary single-disk ZIP/JAR using stored or raw DEFLATE entries, UTF-8/ASCII names, and validates decompression output length and CRC-32. It does **not** invoke shell commands or unpack an archive into a folder. It inspects the central directory and only reads selected manifest/assets into memory.

Limits: archive ≤256 MiB; central directory ≤32 MiB; individual declared expanded entry ≤16 MiB; compressed entry ≤32 MiB; total declared expanded content ≤512 MiB; manifest/image/audio have the smaller limits above. Encrypted, multi-disk, ZIP64, unsupported compression, symbolic-link entries, unsafe names and duplicate/case-colliding normalized paths are refused. A ZIP64 export must be recreated as a normal ZIP. Metadata/source names must agree with local entry headers when read. Archive paths are never used as output paths.

Bounds are checked before raster decode using [ImageIO image properties](https://developer.apple.com/documentation/imageio/cgimagesourcecopypropertiesatindex(_:_:_:)). Archive parsing follows the [PKWARE ZIP specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT), and raw DEFLATE/CRC use the system zlib SDK. These are explicit narrow support boundaries; extend with tests rather than bypassing validation.

## Contributing

Relevant files: `Assets/AssetID.swift` defines the contract; `ResourcePack.swift` validates manifest/raster/WAV; `SafeZIP.swift` handles archives; `AssetProvider.swift` resolves overrides/fallback and manages revisions; `AssetSettingsView.swift` exposes controls. `TerrainChunkRenderer`, `CircuitTextures` and `AudioEngine` consume validated assets. Pure simulation/domain code has no asset or SpriteKit dependency.

When adding an ID, update enum, built-in fallback, renderer consumer, this table and tests. When changing accepted data, version/document the contract and add malformed/boundary cases. Never add third-party game art to examples, fixtures or the app bundle. Use original tiny test images, or load an owner's local game installation outside the repository for manual validation.

Water textures are composited over an opaque blue base for their depth, so translucent Java/custom water does not expose the checker backdrop. Decoration transparency is preserved. Imported/cache PNGs are unchanged; this is a rendering rule and requires no re-import.
