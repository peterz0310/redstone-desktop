#!/usr/bin/env python3
"""Read-only Release checks; inspect catalog data in temporary storage and never launch the app."""
import plistlib
import json
import subprocess
import tempfile
from pathlib import Path, PurePosixPath
import struct
import sys
import zipfile


def validate(path):
    path = Path(path)
    if path.is_dir():
        names = [p.relative_to(path).as_posix() for p in path.rglob('*') if p.is_file()]
        read = lambda name: (path / name).read_bytes()
        archive = None
    else:
        archive = zipfile.ZipFile(path)
        for name in archive.namelist():
            parts = PurePosixPath(name)
            if parts.is_absolute() or '..' in parts.parts:
                raise ValueError('Archive has an unsafe path')
        prefix = 'RedstoneDesktop/RedstoneDesktop.app/'
        names = [name[len(prefix):] for name in archive.namelist() if name.startswith(prefix)]
        read = lambda name: archive.read(prefix + name)
        for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'README.md', 'docs/RELEASE.md', 'docs/RECOVERY.md', 'docs/TESTING.md', 'docs/KNOWN_LIMITATIONS.md']:
            if not archive.read('RedstoneDesktop/' + name):
                raise ValueError('Missing release guide/notice: ' + name)
    try:
        info = plistlib.loads(read('Contents/Info.plist'))
        assert info['CFBundleIdentifier'] == 'org.redstonedesktop.RedstoneDesktop', 'Bundle identity'
        assert info['LSMinimumSystemVersion'] == '14.0', 'Deployment target'
        assert info['CFBundleIconName'] == 'AppIcon', 'Native app icon'
        assert 'Finder' in info['NSAppleEventsUsageDescription'], 'Finder permission explanation'
        assert 'script' in info['NSDesktopFolderUsageDescription'].lower(), 'Script folder explanation'
        assert 'MIT License' in read('Contents/Resources/LICENSE').decode(), 'Embedded MIT license'
        assert 'No Minecraft artwork' in read('Contents/Resources/THIRD_PARTY_NOTICES.md').decode(), 'Embedded artwork notice'
        # Inspect the actual compiled catalog, including the one inside the review ZIP.
        with tempfile.TemporaryDirectory(prefix='redstone-release-assets-') as temporary:
            catalog = Path(temporary) / 'Assets.car'
            catalog.write_bytes(read('Contents/Resources/Assets.car'))
            entries = json.loads(subprocess.check_output(['xcrun', 'assetutil', '--info', str(catalog)]))
        asset_names = {entry.get('Name') for entry in entries}
        assert {'Logo', 'MenuLogo'}.issubset(asset_names), 'Owner logo identity missing'
        retired = {'RedstoneDust', 'MenuDust', 'ToolDust', 'ToolButton', 'ToolLever', 'ToolRepeater', 'ToolOutput', 'ToolTorch'}
        assert not retired.intersection(asset_names), 'Retired game-derived icons bundled'
        binary = read('Contents/MacOS/' + info['CFBundleExecutable'])
        magic, count = struct.unpack_from('>II', binary)
        assert magic == 0xCAFEBABE and 1 <= count <= 8, 'Universal Mach-O header'
        cpu_types = {struct.unpack_from('>I', binary, 8 + i * 20)[0] for i in range(count)}
        assert cpu_types == {0x0100000C, 0x01000007}, 'arm64 + x86_64 slices'
        for name in names:
            item = PurePosixPath(name)
            assert not {'ImportedTextures', 'node_modules', 'Minecraft'}.intersection(item.parts), 'Local/runtime data bundled: ' + name
            assert item.name not in {'library.json', 'blueprints.json', 'world.json', 'import.json', 'pack.json', 'preferences.plist'}, 'Saved/imported data bundled: ' + name
            assert item.suffix.lower() not in {'.jar', '.zip', '.sh', '.command', '.zsh', '.class', '.lua', '.py'}, 'Source pack/script bundled: ' + name
        print('Release verified: identity, macOS 14 target, permissions, icon, notices, universal binary, no saves/imports/scripts.' )
    finally:
        if archive:
            archive.close()


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: scripts/verify-release.py PATH.app|PATH.zip')
    try:
        validate(sys.argv[1])
    except (AssertionError, ValueError, KeyError, OSError, zipfile.BadZipFile, struct.error, subprocess.SubprocessError) as error:
        raise SystemExit('Release validation failed: ' + str(error)) from error
