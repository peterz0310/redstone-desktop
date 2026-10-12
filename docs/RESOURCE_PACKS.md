# Redstone Desktop resource packs

Redstone Desktop packs are optional **data**: PNG images, short WAV effects and a JSON manifest. The app runs without a pack or Minecraft installation. Nothing in a pack is executed. World generation, terrain capabilities, component placement, simulation, Finder occupancy and action permissions are independent of appearance.

To use an already-installed Minecraft Java version or native Java pack, see [the user guide](USER_GUIDE.md#textures-and-sounds). That importer creates a local format-1 pack; it does not require you to write a manifest yourself.

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

`formatVersion`, `name` and `assets` are required. `author` and `animations` are optional. Name must be nonblank and at most 128 characters; author at most 256; manifest at most 64 KiB; at most 64 asset entries. Version 1 is the only supported version. An empty asset map is valid and means all built-in defaults. Additional JSON metadata fields are currently ignored; do not rely on them for renderer behavior. Publish your artwork license/attribution separately in a README/LICENSE.

Paths are relative to **the folder containing pack.json**, including inside ZIPs. Use `/`, not `\`. Absolute paths, drive prefixes/colons, control characters, empty path components, `.` and `..` are refused. Asset symlinks are ignored with diagnostics; assets may not escape the selected root. Do not use URLs, executable scripts or compiled plugins as asset paths.

To ZIP on macOS, right-click the pack folder → **Compress**. A ZIP can have its manifest directly at root or below one wrapper folder. It must contain exactly one `pack.json`. Reload Current Pack reads the originally selected folder/ZIP again; no automatic file watcher is installed.

## Texture IDs (case-sensitive)

All IDs below accept **PNG only**. IDs are case-sensitive.

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
| `particleFlame` / `particleSmoke` | Torch flame / smoke sprites |
| `particleLava` / `particleDust` | Lava pop / red-tinted powered dust sprites |
| `lavaStill` | Lava-pool surface |
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
| `decorationRock` | Family fallback for coal/iron deposits |
| `decorationReed` | Reed overlay |
| `redstoneDustOff` | Unpowered wire material |
| `redstoneDustOn` | Powered wire material |
| `redstoneButtonUp` | Released button icon |
| `redstoneButtonDown` | Pressed button icon |
| `redstoneLeverOff` | Off lever icon |
| `redstoneLeverOn` | On lever icon |
| `redstoneRepeaterOff` | Unpowered repeater icon, pointing right/east |
| `redstoneRepeaterOn` | Powered repeater icon, pointing right/east |
| `redstonePlateOff` / `redstonePlateOn` | Wooden pressure plate for Any item detection; raised/depressed states |
| `redstoneSensorOff` / `redstoneSensorOn` | Stone pressure plate for name/extension detection; raised/depressed states |
| `redstoneLampOff` / `redstoneLampOn` | Full-block unpowered / powered lamp face |
| `lightTorch` | Always-lit regular torch icon; no redstone power |
| `redstoneTorchOff` | Off torch icon |
| `redstoneTorchOn` | On torch icon |
| `redstoneOutputOff` | Unpowered output icon |
| `redstoneOutputOn` | Powered output icon |

PNG bounds: 1–1024 pixels in each dimension, at most 4 MiB encoded, one image frame. Square images are recommended; rectangular images stretch to the semantic surface. Transparent decorations overlay the terrain; alpha is decoded as premultiplied RGBA and composited. Texture sampling is nearest-neighbor. There are 49 texture IDs in format 1. Button/lever/repeater icons retain labels, rotation and power frames; full-tile Outputs retain soft occupancy glows; a pack does not replace interaction geometry. Dust uses filled square junctions and cardinal strips one fifth of a tile wide; its material is overridden, not a full-tile vanilla dust model. Built-in powered material is bright red, with dark red when off. Texture colors are displayed without multiplying by a yellow/orange UI tint. Positive power multiplies material RGB by a neutral brightness factor `0.45 + 0.55 × power/15`, preserving hue and alpha; zero uses the separate off material. Custom packs may deliberately choose other colors. Repeaters cover 86% of a tile, with short wire strips bridging compatible front/rear ports to adjacent repeaters and other connected components; side/head-to-head neighbors do not gain ports. Button/lever art has transparent backing; button/lever state labels and repeater rotation/delay remain. Outputs cover a full tile without app text or colored backing; their glow is green for one occupant, gently red for empty, amber for ambiguous and gray for unavailable. Highlight/selection/diagnostic overlays remain app UI.

Terrain and decoration overrides are sampled at 16 pixels per tile with nearest-neighbor filtering. Circuit textures retain their source resolution. Tree leaves overlay several tiles, with a log beneath the center. Transparent leaf pixels reveal the log or ground. An opaque leaf image hides the log.

Shallow water is darkened at display time (70% red/green, 88% blue), preserving alpha and animation timing. Water is composited over an opaque blue base so transparent water does not reveal the viewport backdrop. Source images remain unchanged.

## Sound IDs (case-sensitive)

`buttonPress`, `buttonRelease`, `leverToggleOn`, `leverToggleOff`, `repeaterTick`, `torchToggle`, `placeCircuit`, `removeCircuit`, `invalidPlacement`, `outputActivate`.

Sounds require **little-endian RIFF WAV**, PCM 16-bit or IEEE float 32-bit, mono or stereo, 8–96 kHz, at most 2 seconds and 8 MiB encoded. Stereo is averaged to mono, linearly resampled to 44.1 kHz, and peaks above 0.11 are reduced to 0.11 to leave overlap headroom. The engine then applies master volume/mute and per-event stereo pan. NaN/infinite samples are refused. WAV extensible/compressed WAV, OGG, MP3, streaming audio, playlists and code are not supported in format 1.

Effects replace semantic events only: changing `buttonPress` does not change when a button accepts input. Eight simultaneous voices are retained; at saturation the oldest is recycled. Changing packs clears currently playing effects, preserves volume/mute, and does not replay held circuit events.

## Fallback and diagnostics

Resolution order is selected custom/imported pack → built-in original assets. Only **one** pack is active; imported Java textures use this same slot.

- An omitted ID uses built-in assets without warning, except decoration variants first try their family override: flowers → `decorationFlower`; coal/iron → `decorationRock`. A specific variant override takes priority.
- Unknown IDs are ignored with a warning (useful for spotting misspellings).
- Missing, oversized, unsupported or undecodable individual files warn and fall back **only that asset**.
- Bad manifests, escaping manifest paths, or unsafe/unsupported ZIP structures refuse the replacement and preserve the current pack, sounds and saved choice. At startup, an unreadable remembered pack leaves the original fallback active.
- Appearance & Packs shows active name, selected source, counts and expandable per-asset diagnostics.

Selection is remembered separately from exported worlds. Reopening revalidates the source and falls back to the original look if it was moved or damaged. Reload Current Pack reads the selected source again. Use Original Look clears the selection.

## Archive contract and limits

Archives support ordinary single-disk ZIP/JAR using stored or raw DEFLATE entries, UTF-8/ASCII names, and validates decompression output length and CRC-32. It does **not** invoke shell commands or unpack an archive into a folder. It inspects the central directory and only reads selected manifest/assets into memory.

Limits: archive ≤256 MiB; central directory ≤32 MiB; individual declared expanded entry ≤16 MiB; compressed entry ≤32 MiB; total declared expanded content ≤512 MiB; manifest/image/audio have the smaller limits above. Encrypted, multi-disk, ZIP64, unsupported compression, symbolic-link entries, unsafe names and duplicate/case-colliding normalized paths are refused. A ZIP64 export must be recreated as a normal ZIP. Metadata/source names must agree with local entry headers when read. Archive paths are never used as output paths.

## Optional liquid animation (format 1)

Existing static packs need no changes. To animate `waterShallow`, `waterDeep` or `lavaStill`, supply a vertical strip of square PNG frames and an optional `animations` object alongside `assets`:

```json
"animations": {
  "waterShallow": {
    "frames": [0, 1, 2, 1],
    "durations": [0.1, 0.1, 0.2, 0.1],
    "interpolate": true
  }
}
```

Indices are zero-based, from the top of the PNG. Durations are seconds, one per sequence entry; `interpolate` defaults to false. Limits: 1–64 stored frames, 1–256 sequence steps, finite 0.05–10 second durations, at most the three liquid IDs. An animation ID must have a matching `assets` entry; other animation IDs refuse the pack. Invalid per-image animation data warns and uses original fallback for that image. PNG/manifest/archive bounds and safe-path rules remain unchanged. Custom packs without animation declarations remain static; Java imports convert `.png.mcmeta` into these declarations. No user-supplied shader code is accepted.

The editor and Desktop animate liquids; world and area cards use static previews. Reduce Motion and the app’s animation setting can pause effects. Particle PNGs supply images for the built-in effects. Packs cannot supply emitters, models or shader code. Java imports can convert supported local Ogg effects to the semantic WAV IDs; custom format-1 packs accept WAV only.
