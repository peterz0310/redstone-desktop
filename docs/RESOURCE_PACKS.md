# Redstone Desktop resource packs

Redstone Desktop packs are optional **data**: PNG images, short WAV effects and a JSON manifest. The app runs without a pack or Minecraft installation. Nothing in a pack is executed. World generation, terrain capabilities, component placement, simulation, Finder occupancy and action permissions are independent of appearance.

## Try the included original example

Open **Advanced → Appearance & Packs → Choose Pack Folder or ZIP…**. Select `examples/GrassOnly` or `examples/GrassOnly.zip` from this repository. Grass becomes a purple/teal checker; every other terrain, decoration, circuit and sound uses its built-in default. Both forms should look the same. Choose **Use Built-In** to restore the original appearance.

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

To ZIP on macOS, right-click the pack folder → **Compress**. A ZIP can have its manifest directly at root or below one wrapper folder. It must contain exactly one `pack.json`. Reload reads the originally selected folder/ZIP again; no automatic file watcher is installed.

## Texture IDs (case-sensitive)

All IDs below accept **PNG only**. These are the actual format-1 names; examples in older planning documents may differ.

| ID | Appearance |
| --- | --- |
| `terrainGrass` | Grass surface |
| `terrainDirt` | Dirt surface |
| `terrainStone` | Stone surface |
| `terrainSand` | Sand surface |
| `waterShallow` | Shallow-water surface |
| `waterDeep` | Deep-water surface |
| `decorationTree` | Tree overlay |
| `decorationFlower` | Flower overlay |
| `decorationRock` | Rock overlay |
| `decorationReed` | Reed overlay |
| `redstoneDustOff` | Unpowered wire material |
| `redstoneDustOn` | Powered wire material |
| `redstoneButtonUp` | Released button icon |
| `redstoneButtonDown` | Pressed button icon |
| `redstoneLeverOff` | Off lever icon |
| `redstoneLeverOn` | On lever icon |
| `redstoneRepeaterOff` | Unpowered repeater icon, pointing right/east |
| `redstoneRepeaterOn` | Powered repeater icon, pointing right/east |
| `redstoneOutputOff` | Unpowered output icon |
| `redstoneOutputOn` | Powered output icon |

PNG bounds: 1–1024 pixels in each dimension, at most 4 MiB encoded, one image frame. Square images are recommended; rectangular images stretch to the semantic surface. Transparent decorations overlay the terrain; alpha is decoded as premultiplied RGBA and composited. Texture sampling is nearest-neighbor. Circuit icons retain labels, rotation, power frames and occupancy badges; a pack does not replace interaction geometry. Dust remains a connected geometric path whose material is overridden, not a full-tile vanilla dust model. Highlight/selection/diagnostic overlays remain app UI.

Generated terrain is baked into bounded chunk sprites. Built-in terrain uses 8 pixels/tile. A terrain/decoration override uses 16 pixels/tile, sampled from the source PNG (higher-resolution files are reduced with nearest sampling). This keeps memory bounded and preserves standard 16-pixel Java texture detail. Circuit textures retain their source raster resolution. Shelf thumbnails remain schematic summaries rather than pack previews. Explicit non-generated diagnostic terrain uses provider textures; generated legacy overrides use the same terrain pack as their surroundings.

## Sound IDs (case-sensitive)

`buttonPress`, `buttonRelease`, `leverToggleOn`, `leverToggleOff`, `repeaterTick`, `placeCircuit`, `removeCircuit`, `invalidPlacement`, `outputActivate`.

Sounds require **little-endian RIFF WAV**, PCM 16-bit or IEEE float 32-bit, mono or stereo, 8–96 kHz, at most 2 seconds and 8 MiB encoded. Stereo is averaged to mono, linearly resampled to 44.1 kHz, and peaks above 0.11 are reduced to 0.11 to leave overlap headroom. The engine then applies master volume/mute and per-event stereo pan. NaN/infinite samples are refused. WAV extensible/compressed WAV, OGG, MP3, streaming audio, playlists and code are not supported in format 1.

Effects replace semantic events only: changing `buttonPress` does not change when a button accepts input. Eight simultaneous voices are retained; at saturation the oldest is recycled. Changing packs clears currently playing effects, preserves volume/mute, and does not replay held circuit events.

## Fallback and diagnostics

Resolution order is selected custom/imported pack → built-in original assets. Only **one** pack is active; imported Java textures use this same slot.

- An omitted ID uses built-in assets without warning.
- Unknown IDs are ignored with a warning (useful for spotting misspellings).
- Missing, oversized, unsupported or undecodable individual files warn and fall back **only that asset**.
- Bad manifests, escaping manifest paths, or unsafe/unsupported ZIP structures refuse the whole pack and activate built-in assets.
- Appearance & Packs shows active name, selected source, counts and expandable per-asset diagnostics.

The loader constructs a complete immutable snapshot before applying it. A newer selection or Use Built-In supersedes a pending load; a late load cannot switch the pack back. Snapshot/revision changes invalidate circuit/terrain appearance caches while retaining world data, simulator, camera, input monitors and Finder targets. Assets are decoded off the main thread; renderers never read paths from disk. Audio receives validated sample arrays, not pack code.

Selection is stored in app preferences, **not library.json**. Reopening revalidates the selected source, starts Desktop disabled, and falls back if the source was moved/damaged. A successful reload updates the snapshot. Use Built-In clears the remembered selection. Tests construct isolated preferences and temporary packs; the application test host does not restore the owner's selection.

## Archive contract and limits

The shared `SafeZIP` reader supports ordinary single-disk ZIP/JAR using stored or raw DEFLATE entries, UTF-8/ASCII names, and validates decompression output length and CRC-32. It does **not** invoke shell commands or unpack an archive into a folder. It inspects the central directory and only reads selected manifest/assets into memory.

Limits: archive ≤256 MiB; central directory ≤32 MiB; individual declared expanded entry ≤16 MiB; compressed entry ≤32 MiB; total declared expanded content ≤512 MiB; manifest/image/audio have the smaller limits above. Encrypted, multi-disk, ZIP64, unsupported compression, symbolic-link entries, unsafe names and duplicate/case-colliding normalized paths are refused. A ZIP64 export must be recreated as a normal ZIP. Metadata/source names must agree with local entry headers when read. Archive paths are never used as output paths.

Bounds are checked before raster decode using [ImageIO image properties](https://developer.apple.com/documentation/imageio/cgimagesourcecopypropertiesatindex(_:_:_:)). Archive parsing follows the [PKWARE ZIP specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT), and raw DEFLATE/CRC use the system zlib SDK. These are explicit narrow support boundaries; extend with tests rather than bypassing validation.

## Contributing

Relevant files: `Assets/AssetID.swift` defines the contract; `ResourcePack.swift` validates manifest/raster/WAV; `SafeZIP.swift` handles archives; `AssetProvider.swift` resolves overrides/fallback and manages revisions; `AssetSettingsView.swift` exposes controls. `TerrainChunkRenderer`, `CircuitTextures` and `AudioEngine` consume validated assets. Pure simulation/domain code has no asset or SpriteKit dependency.

When adding an ID, update enum, built-in fallback, renderer consumer, this table and tests. When changing accepted data, version/document the contract and add malformed/boundary cases. Never add third-party game art to examples, fixtures or the app bundle. Use original tiny test images, or load an owner's local game installation outside the repository for manual validation.
