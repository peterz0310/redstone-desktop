#!/usr/bin/env python3
"""Check local Markdown links, anchors and README images without network access."""
import posixpath
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


def headings(text):
    result, seen = set(), {}
    for heading in re.findall(r'^#{1,6}\s+(.+?)\s*#*$', text, re.MULTILINE):
        slug = re.sub(r'[^\w\- ]', '', heading.lower()).replace(' ', '-')
        count = seen.get(slug, 0); seen[slug] = count + 1
        result.add(slug + (f'-{count}' if count else ''))
    return result


def validate_files(names, read):
    names = set(names)
    for name in sorted(names):
        if not name.endswith('.md'):
            continue
        text = read(name).decode('utf-8')
        text = re.sub(r'^```[^\n]*\n.*?^```\s*$', '', text, flags=re.MULTILINE | re.DOTALL)
        targets = re.findall(r'!?\[[^\]]*\]\(([^)]+)\)', text)
        targets += re.findall(r'\b(?:src|srcset)="([^"]+)"', text)
        for target in targets:
            target = target.strip().strip('<>').split(' "', 1)[0]
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc: continue
            path = posixpath.normpath(posixpath.join(posixpath.dirname(name), unquote(parsed.path))) if parsed.path else name
            if path.startswith('../') or path.startswith('/'):
                raise ValueError(f'{name}: link escapes documentation root: {target}')
            if path not in names and not any(n.startswith(path.rstrip('/') + '/') for n in names):
                raise ValueError(f'{name}: missing local link/image: {target}')
            if parsed.fragment and path.endswith('.md') and parsed.fragment not in headings(read(path).decode('utf-8')):
                raise ValueError(f'{name}: missing heading: {target}')



def validate_pack_contract(asset_source, sound_source, guide):
    def cases(source, name):
        body = re.search(r'enum\s+' + name + r'[^\{]*\{([\s\S]*?)^\}', source, re.MULTILINE)
        if not body: raise ValueError('Could not read ' + name + ' contract')
        result = set()
        for line in re.findall(r'^\s*case\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*$', body.group(1), re.MULTILINE):
            result.update(part.strip() for part in line.split(','))
        if not result: raise ValueError('Empty ' + name + ' contract')
        return result
    table = guide.split('## Texture IDs', 1)[1].split('## Sound IDs', 1)[0]
    textures = set()
    for line in table.splitlines():
        if line.startswith('| `'): textures.update(re.findall(r'`([A-Za-z_]\w*)`', line.split('|')[1]))
    sounds = set(re.findall(r'`([A-Za-z_]\w*)`', guide.split('## Sound IDs', 1)[1].split('Sounds require', 1)[0]))
    if textures != cases(asset_source, 'TextureAssetID'): raise ValueError('Resource-pack texture table differs from the actual asset IDs')
    if sounds != cases(sound_source, 'SoundID'): raise ValueError('Resource-pack sound list differs from the actual sound IDs')
    count = re.search(r'There are (\d+) texture IDs', table)
    if count and int(count.group(1)) != len(textures): raise ValueError('Incorrect resource-pack texture count')

def validate(root):
    root = Path(root).resolve()
    names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '--cached', '--others', '--exclude-standard'], text=True).splitlines()
    validate_files(names, lambda name: (root / name).read_bytes())
    validate_pack_contract((root / "RedstoneDesktop/Assets/AssetID.swift").read_text(),
        (root / "RedstoneDesktop/Audio/SoundID.swift").read_text(), (root / "docs/RESOURCE_PACKS.md").read_text())
    print('Documentation verified: local links, heading anchors, README images and texture/sound documentation.')


if __name__ == '__main__':
    try: validate(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(f'Documentation validation failed: {error}') from error
