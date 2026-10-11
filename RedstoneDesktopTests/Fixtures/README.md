# Original test fixtures

`SyntheticJava.zip` is a tiny, original ZIP fixture under the repository's MIT license. It contains programmatically generated white/color PNGs covering 37 earlier Java image mappings at Java-style texture paths, including original white/teal two-frame water/lava strips and small `.png.mcmeta` JSON files for timing/interpolation tests. Snow, gravel, spruce/acacia leaves and red mushroom and oak/spruce log-top entries reuse the original white synthetic PNG for mapping tests. It contains no Mojang/Microsoft art.

Unrelated `.class` and `.ogg` entries contain inert test bytes, not executable Java or actual audio. Tests assert that supported image mappings and generated manifest/import JSON for this image-only fixture enter the managed cache; source `.mcmeta` contributes bounded data rather than being copied. The archive exercises real DEFLATE handling without requiring a Minecraft installation or touching user preferences.


`SyntheticTone.ogg` and `SyntheticLongTone.ogg` contain original sine waves (550 Hz for 0.15 seconds, and 250 Hz at 8 kHz for 2.1 seconds). They test actual native Ogg decoding, PCM caching and the two-second import limit. No game audio is included. They were generated with FFmpeg’s `sine` source and `libvorbis`; FFmpeg is a fixture-authoring tool only, never a runtime or test-suite dependency:

```sh
ffmpeg -f lavfi -i 'sine=frequency=550:duration=0.15' -c:a libvorbis SyntheticTone.ogg
ffmpeg -f lavfi -i 'sine=frequency=250:duration=2.1:sample_rate=8000' -c:a libvorbis SyntheticLongTone.ogg
```

`SyntheticEffectsJava.zip` is an original wrapped Java-style pack. Its four particle entries reuse the project's original GrassOnly PNG solely as arbitrary mapping data; seven supported sound paths reuse SyntheticTone.ogg. An unrelated `.class` entry contains inert text. Tests exercise ZIP particle/audio mapping and normalized WAV-only cache publication without reading an owner's game assets. All these original fixtures are covered by this repository's MIT license and are excluded from app/release resources.
