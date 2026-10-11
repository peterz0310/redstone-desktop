# Artwork and third-party notices

No Minecraft artwork, audio, game code or game-derived toolbar icons are shipped in this repository’s current app or release bundle.

## Owner-provided identity

The repository owner supplied `logo.png` on 2026-10-11 to replace the previously bundled game artwork. The source is preserved unchanged at `RedstoneDesktop/Resources/Assets.xcassets/Logo.imageset/logo.png`.

- Source PNG: 1254 × 1254 pixels, RGBA.
- SHA-256: `2e2cc646437e3d992546e5b32df44ac12d1908875c1d10a15e847febf321f533`.
- Derived assets: `AppIcon.icon`, light/dark `AppLogo.imageset` and `MenuLogo.imageset`; README icon previews reuse those generated PNGs.
- Generation: trim transparent margins only in the generated images, preserve proportions, render a colored foreground for the native Mac app icon with system light/dark backgrounds, generate matching light/dark in-app logo previews, and render a monochrome alpha silhouette for the menu bar and Dust tool. The source PNG is never modified.

Project code and project artwork use the repository’s MIT license. Other toolbar icons use native SF Symbols from the system; they are not extracted from Minecraft. SwiftUI, AppKit, SpriteKit and AVFoundation are system frameworks. No third-party runtime packages or backend are bundled.

## Optional local imports

Users may import supported textures, particle sprites and short audio from their own Minecraft installation or resource packs. Those files remain in the user’s Application Support cache and are excluded from Git, app bundles, release archives and exported world data. Import support grants no rights to that material; original source rights apply. No resource-pack or game code is executed. See `docs/JAVA_TEXTURE_IMPORT.md` and `docs/RESOURCE_PACKS.md`.

Regeneration instructions for the owner-provided identity are in docs/RELEASE.md. The previous game-derived identity/tool sources and their generation manifest have been removed from the current tree.
