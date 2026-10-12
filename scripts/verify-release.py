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
import stat
import re
import importlib.util
import os

_spec = importlib.util.spec_from_file_location("check_docs", Path(__file__).with_name("check-docs.py"))
_docs = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_docs)



def require(condition, message):
    if not condition: raise ValueError(message)


def check_archive_paths(archive):
    seen = set()
    for entry in archive.infolist():
        name = entry.filename
        parts = PurePosixPath(name)
        require(not parts.is_absolute() and '..' not in parts.parts and "\\" not in name, 'Archive has an unsafe path')
        require(parts.as_posix() == name.rstrip('/'), 'Archive has a noncanonical path')
        key = name.rstrip('/').casefold()
        require(key not in seen, 'Archive has duplicate or case-colliding entries')
        seen.add(key)
        if stat.S_ISLNK(entry.external_attr >> 16):
            require(name == 'RedstoneDesktop/Applications' and archive.read(entry) == b'/Applications', 'Archive has an unexpected symbolic link')
        require(name.startswith(('RedstoneDesktop/', '__MACOSX/')), 'Unexpected archive root')


def check_binary(binary):
    magic, count = struct.unpack_from('>II', binary)
    require(magic == 0xCAFEBABE and count == 2, 'Universal Mach-O header')
    cpu_types, spans = set(), []
    for index in range(count):
        cpu, _, offset, size, _ = struct.unpack_from('>IIIII', binary, 8 + index * 20)
        require(offset >= 8 + count * 20 and size >= 32 and offset + size <= len(binary), 'Invalid Mach-O slice bounds')
        thin_magic, thin_cpu = struct.unpack_from('<II', binary, offset)
        require(thin_magic == 0xFEEDFACF and thin_cpu == cpu, 'Invalid Mach-O slice identity')
        cpu_types.add(cpu); spans.append((offset, offset + size))
    require(cpu_types == {0x0100000C, 0x01000007}, 'arm64 + x86_64 slices')
    require(spans[0][1] <= spans[1][0] or spans[1][1] <= spans[0][0], 'Overlapping Mach-O slices')


def check_payload_names(names):
    for name in names:
        item = PurePosixPath(name)
        require(not {'ImportedTextures', 'node_modules', 'Minecraft'}.intersection(item.parts), 'Local/runtime data bundled: ' + name)
        require(item.name not in {'library.json', 'blueprints.json', 'world.json', 'import.json', 'pack.json', 'preferences.plist'}, 'Saved/imported data bundled: ' + name)
        require(item.suffix.lower() not in {'.jar', '.sh', '.command', '.zsh', '.class', '.lua', '.py', '.ogg', '.wav', '.zip'}, 'Source pack/script/audio bundled: ' + name)


def validate_package(root):
    root = Path(root)
    link = root / 'Applications'
    require(link.is_symlink() and link.readlink() == Path('/Applications'), 'Installer Applications shortcut')
    names = []
    for path in root.rglob('*'):
        if path == link: continue
        require(not path.is_symlink(), 'Unexpected installer symlink')
        if path.is_file(): names.append(path.relative_to(root).as_posix())
    check_payload_names(names)
    for name in ['README.md', 'INSTALL.md', 'CHANGELOG.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'docs/RELEASE.md', 'docs/RELEASE_CHECKLIST.md', 'docs/RECOVERY.md', 'docs/TESTING.md', 'docs/KNOWN_LIMITATIONS.md']:
        require((root / name).is_file() and (root / name).stat().st_size > 0, 'Missing release guide: ' + name)
    _docs.validate_files(names, lambda name: (root / name).read_bytes())
    validate(root / 'RedstoneDesktop.app')


def validate_dmg(path):
    subprocess.run(['hdiutil', 'verify', str(path)], check=True, stdout=subprocess.DEVNULL)
    with tempfile.TemporaryDirectory(prefix='redstone-dmg-check-') as temporary:
        mount = Path(temporary) / 'mount'; mount.mkdir()
        attached = False
        try:
            subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen', '-mountpoint', str(mount), str(path)], check=True, stdout=subprocess.DEVNULL)
            attached = True
            validate_package(mount)
        finally:
            if attached or os.path.ismount(mount): subprocess.run(['hdiutil', 'detach', str(mount)], check=True, stdout=subprocess.DEVNULL)
    print('DMG verified: read-only installer, Applications shortcut, documentation and app.')

def validate(path):
    path = Path(path)
    if path.suffix.lower() == ".dmg":
        return validate_dmg(path)
    if path.is_dir():
        require(not any(p.is_symlink() for p in path.rglob("*")), "Unexpected app symlink")
        names = [p.relative_to(path).as_posix() for p in path.rglob('*') if p.is_file()]
        read = lambda name: (path / name).read_bytes()
        archive = None
    else:
        archive = zipfile.ZipFile(path)
        check_archive_paths(archive)
        prefix = 'RedstoneDesktop/RedstoneDesktop.app/'
        names = [name[len(prefix):] for name in archive.namelist() if name.startswith(prefix)]
        read = lambda name: archive.read(prefix + name)
        for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'README.md', 'INSTALL.md', 'CHANGELOG.md', 'docs/RELEASE_CHECKLIST.md', 'docs/RELEASE.md', 'docs/RECOVERY.md', 'docs/TESTING.md', 'docs/KNOWN_LIMITATIONS.md', 'docs/media/icon-light.png', 'docs/media/icon-dark.png', 'docs/media/circuit-demo.gif', 'docs/media/worlds.png', 'docs/media/lighting.png']:
            if not archive.read('RedstoneDesktop/' + name):
                raise ValueError('Missing release guide/notice: ' + name)
        package_names = [name[len('RedstoneDesktop/'):] for name in archive.namelist() if name.startswith('RedstoneDesktop/') and not name.endswith('/')]
        check_payload_names(package_names)
        _docs.validate_files(package_names, lambda name: archive.read('RedstoneDesktop/' + name))
    try:
        info = plistlib.loads(read('Contents/Info.plist'))
        require(info['CFBundleIdentifier'] == 'org.redstonedesktop.RedstoneDesktop', 'Bundle identity')
        require(info['LSMinimumSystemVersion'] == '14.0', 'Deployment target')
        require(re.fullmatch(r'\d+\.\d+\.\d+', info['CFBundleShortVersionString']) is not None, 'Marketing version')
        require(re.fullmatch(r'\d+(?:\.\d+){0,2}', info['CFBundleVersion']) is not None, 'Build version')
        require(info['CFBundleExecutable'] == 'RedstoneDesktop', 'Executable identity')
        require('MIT' in info.get('NSHumanReadableCopyright', ''), 'Copyright/license metadata')
        require(info['CFBundleIconName'] == 'AppIcon', 'Native app icon')
        require('Finder' in info['NSAppleEventsUsageDescription'], 'Finder permission explanation')
        require('script' in info['NSDesktopFolderUsageDescription'].lower(), 'Script folder explanation')
        require('MIT License' in read('Contents/Resources/LICENSE').decode(), 'Embedded MIT license')
        require('No Minecraft artwork' in read('Contents/Resources/THIRD_PARTY_NOTICES.md').decode(), 'Embedded artwork notice')
        # Inspect the actual compiled catalog, including the one inside the review ZIP.
        with tempfile.TemporaryDirectory(prefix='redstone-release-assets-') as temporary:
            catalog = Path(temporary) / 'Assets.car'
            catalog.write_bytes(read('Contents/Resources/Assets.car'))
            entries = json.loads(subprocess.check_output(['xcrun', 'assetutil', '--info', str(catalog)]))
        asset_names = {entry.get('Name') for entry in entries}
        require({'Logo', 'MenuLogo', 'AppLogo'}.issubset(asset_names), 'Owner logo identity missing')
        icon_stacks = [entry for entry in entries if entry.get('Name') == 'AppIcon' and entry.get('AssetType') == 'IconImageStack']
        appearances = {entry.get('Appearance') for entry in icon_stacks}
        require({'NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua'}.issubset(appearances), 'Native light/dark icon variants missing')
        stacks_by_appearance = {entry.get('Appearance'): entry for entry in icon_stacks}
        light = stacks_by_appearance['NSAppearanceNameAqua']
        dark = stacks_by_appearance['NSAppearanceNameDarkAqua']
        require(light.get('SHA1Digest') != dark.get('SHA1Digest'), 'Light/dark icon compositions are identical')
        require(light['Layers'][0]['Name'].endswith('/system-light'), 'Light icon background mismatch')
        require(dark['Layers'][0]['Name'].endswith('/system-dark'), 'Dark icon background mismatch')
        logo_appearances = {entry.get('Appearance') for entry in entries if entry.get('Name') == 'AppLogo'}
        require('NSAppearanceNameDarkAqua' in logo_appearances, 'In-app dark logo missing')
        retired = {'RedstoneDust', 'MenuDust', 'ToolDust', 'ToolButton', 'ToolLever', 'ToolRepeater', 'ToolOutput', 'ToolTorch'}
        require(not retired.intersection(asset_names), 'Retired game-derived icons bundled')
        binary = read('Contents/MacOS/' + info['CFBundleExecutable'])
        check_binary(binary)
        check_payload_names(names)
        require(not any(PurePosixPath(n).suffix.lower() == ".zip" for n in names), "Nested archive in app")
        print('Release verified: identity, macOS 14 target, permissions, icon, notices, universal binary, no saves/imports/scripts.' )
    finally:
        if archive:
            archive.close()


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: scripts/verify-release.py PATH.app|PATH.zip|PATH.dmg')
    try:
        validate(sys.argv[1])
    except (AssertionError, ValueError, KeyError, OSError, zipfile.BadZipFile, struct.error, subprocess.SubprocessError) as error:
        raise SystemExit('Release validation failed: ' + str(error)) from error
