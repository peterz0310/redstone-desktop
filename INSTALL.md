# Install Redstone Desktop

This is an early preview for macOS 14 or newer. Local review packages are unsigned and not notarized; they are not yet the public download. Check the release's signing/notarization status before sharing it. Do not disable Gatekeeper to install a review build.

For a signed public release:

1. Open the DMG and drag **RedstoneDesktop.app** onto **Applications**.
2. Eject the disk image, then open Redstone Desktop from Applications. Xcode is not needed.
3. Follow the optional setup steps. Keep the original look or import graphics and sounds from your own Minecraft Java installation.
4. Try **Test Circuit** before starting your real Desktop. **Help → Redstone Desktop Help** explains controls, saving and permissions.

The ZIP is an alternative: extract it, then move its app into Applications. Quit older running copies before replacing or opening another copy. Your worlds and settings live separately from the app and are kept when updating. Desktop always starts stopped.

Finder access may ask for permission in **System Settings → Privacy & Security → Automation → Finder**. Script execution is optional and has separate Desktop-folder access and exact-file approval. No account, backend or Minecraft installation is required.

For builds from source, signing and local verification, see [the release guide](docs/RELEASE.md). For backups or restoring worlds, see [recovery](docs/RECOVERY.md). Start Over resets app data; it does not delete desktop files or uninstall the app.
