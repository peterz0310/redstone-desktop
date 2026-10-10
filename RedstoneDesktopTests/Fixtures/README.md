# Original test fixtures

`SyntheticJava.zip` is a tiny, original ZIP fixture under the repository's MIT license. It contains programmatically generated white/color PNGs covering all 37 current Java import mappings at Java-style texture paths, including original white/teal two-frame water/lava strips and small `.png.mcmeta` JSON files for timing/interpolation tests. Snow, gravel, spruce/acacia leaves and red mushroom and oak/spruce log-top entries reuse the original white synthetic PNG for mapping tests. It contains no Mojang/Microsoft art.

Unrelated `.class` and `.ogg` entries contain inert test bytes, not executable Java or actual audio. Tests assert that only supported PNG mappings and generated manifest/import JSON enter the managed cache; source `.mcmeta` contributes bounded data rather than being copied. The archive exercises real DEFLATE handling without requiring a Minecraft installation or touching user preferences.
