# Third-party artwork

The project's MIT license applies to its own code and original artwork. It does **not** license the Minecraft artwork below or the portions of generated icons containing that artwork.

## Minecraft redstone dust item

- Owner: Mojang/Microsoft; original source rights apply.
- Source: the owner's local Minecraft Java Edition **1.21.11** installation, version JAR `1.21.11.jar`.
- Archive entry: `assets/minecraft/textures/item/redstone.png`.
- Committed file: `RedstoneDesktop/Resources/Assets.xcassets/RedstoneDust.imageset/redstone.png`.
- Original PNG: 16 × 16 pixels, 179 bytes, copied unchanged.
- SHA-256: `6d0e6a1fd54142cd3de649e1100c428733512b322a0b0a530f62eae9f86881ec`.
- Derived files: the PNGs in `AppIcon.appiconset` and `MenuDust.imageset`. The generator scales the item with nearest-neighbor interpolation, adds an original app-icon background, and renders the item's alpha silhouette in monochrome for the template menu icon.

The repository owner explicitly requested committing and shipping this one graphic on 2026-10-08. That request is a narrow exception to the project's previous no-bundled-game-assets rule, not a license grant from the artwork's owner or a conclusion that distribution is permitted. No other game texture, audio, model or executable is included through this exception. Optional world-texture imports still stay local and outside Git/release bundles.

Regeneration instructions are in README.md. Replacing the source PNG and regenerating the catalogs replaces this icon artwork; update this notice and its provenance test at the same time.
