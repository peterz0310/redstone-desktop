# Original test fixtures

`SyntheticJava.zip` is a tiny, original ZIP fixture under the repository's MIT license. It contains programmatically generated white PNGs at Java-style texture paths, including a two-frame vertical strip for cropping tests. It contains no Mojang/Microsoft art.

Unrelated `.class` and `.ogg` entries contain inert test bytes, not executable Java or actual audio. Tests assert that only supported PNG mappings enter the managed cache. The archive exercises real DEFLATE handling without requiring a Minecraft installation or touching user preferences.
