#!/usr/bin/env python3
"""Record build identity and actual artifact hashes; signing is not notarization."""
import hashlib
import json
import plistlib
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''): digest.update(chunk)
    return digest.hexdigest()


def record(output, app, mode, artifacts):
    info = plistlib.loads((Path(app) / 'Contents/Info.plist').read_bytes())
    result = {
        'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
        'bundleIdentifier': info['CFBundleIdentifier'], 'minimumMacOS': info['LSMinimumSystemVersion'],
        'architectures': ['arm64', 'x86_64'], 'createdAt': datetime.now(timezone.utc).isoformat(),
        'sourceCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        'sourceDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip()),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
        'signing': mode, 'notarization': 'not-performed',
        'artifacts': [{'name': path.name, 'bytes': path.stat().st_size, 'sha256': sha256(path)} for path in map(Path, artifacts)]
    }
    Path(output).write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    record(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:])
