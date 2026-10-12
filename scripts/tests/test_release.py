import importlib.util
import io
import stat
import struct
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    result = importlib.util.module_from_spec(spec); spec.loader.exec_module(result)
    return result


release = module('release', 'verify-release.py')
docs = module('docs', 'check-docs.py')
manifest = module('manifest', 'release-manifest.py')


class ReleaseTests(unittest.TestCase):
    def archive(self, entries):
        data = io.BytesIO()
        with zipfile.ZipFile(data, 'w') as archive:
            for name, content in entries: archive.writestr(name, content)
        data.seek(0)
        return zipfile.ZipFile(data)

    def test_archive_refuses_absolute_parent_backslash_and_foreign_root(self):
        for name in ['/tmp/file', '../outside', 'RedstoneDesktop/../file', 'RedstoneDesktop\\file', 'Unexpected/file', 'RedstoneDesktop/./file', 'RedstoneDesktop//file']:
            with self.archive([(name, b'bad')]) as archive:
                with self.assertRaises(ValueError): release.check_archive_paths(archive)

    def test_archive_refuses_duplicates(self):
        import warnings
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with self.archive([('RedstoneDesktop/README.md', b'one'), ('RedstoneDesktop/README.md', b'two')]) as archive:
                with self.assertRaises(ValueError): release.check_archive_paths(archive)

    def test_archive_refuses_case_collisions(self):
        with self.archive([('RedstoneDesktop/README.md', b'one'), ('RedstoneDesktop/readme.md', b'two')]) as archive:
            with self.assertRaises(ValueError): release.check_archive_paths(archive)

    def test_archive_allows_only_exact_applications_shortcut(self):
        for name, destination, allowed in [('RedstoneDesktop/Applications', b'/Applications', True), ('RedstoneDesktop/Applications', b'/tmp', False), ('RedstoneDesktop/app', b'/Applications', False)]:
            info = zipfile.ZipInfo(name); info.create_system = 3
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            with self.archive([(info, destination)]) as archive:
                if allowed: release.check_archive_paths(archive)
                else:
                    with self.assertRaises(ValueError): release.check_archive_paths(archive)

    def test_payload_refuses_owner_data_and_executable_imports_anywhere(self):
        for name in ['docs/library.json', 'Contents/Resources/ImportedTextures/a.png', 'docs/local.jar', 'Contents/Resources/a.ogg', 'Contents/Resources/a.wav', 'docs/hello.sh', 'docs/pack.json', 'docs/local-pack.zip']:
            with self.assertRaises(ValueError): release.check_payload_names([name])
        release.check_payload_names(['docs/media/lighting.png', 'Contents/Resources/Assets.car'])

    def binary(self):
        cpus = [0x0100000C, 0x01000007]
        headers = [struct.pack('>IIIII', cpu, 0, 48 + i * 32, 32, 0) for i, cpu in enumerate(cpus)]
        slices = [struct.pack('<II', 0xFEEDFACF, cpu) + bytes(24) for cpu in cpus]
        return struct.pack('>II', 0xCAFEBABE, 2) + b''.join(headers + slices)

    def test_binary_checks_real_slice_identity_bounds_and_overlap(self):
        binary = self.binary(); release.check_binary(binary)
        for offset, value in [(16, 500), (20, 500), (36, 48), (52, 0)]:
            altered = bytearray(binary); struct.pack_into('>I', altered, offset, value)
            with self.assertRaises(ValueError): release.check_binary(altered)
        with self.assertRaises(struct.error): release.check_binary(b'bad')

    def test_documentation_checks_images_and_heading_anchors(self):
        files = {'README.md': b'[Guide](docs/guide.md#first-step)\n<img src="docs/media/icon.png">', 'docs/guide.md': b'# First step\n[Home](../README.md)', 'docs/media/icon.png': b'png'}
        docs.validate_files(files, files.__getitem__)
        for target in ['docs/missing.md', 'docs/guide.md#missing', '../outside.md']:
            changed = dict(files); changed['README.md'] = f'[Bad]({target})'.encode()
            with self.assertRaises(ValueError): docs.validate_files(changed, changed.__getitem__)
        del files['docs/media/icon.png']
        with self.assertRaises(ValueError): docs.validate_files(files, files.__getitem__)

    def test_resource_pack_guide_matches_exported_texture_and_sound_contracts(self):
        assets = 'enum TextureAssetID: String {\n    case terrainGrass, terrainStone\n}\n'
        sounds = 'enum SoundID: String {\n    case buttonPress\n}\n'
        guide = '## Texture IDs\n| `terrainGrass` | Grass |\n| `terrainStone` | Stone |\nThere are 2 texture IDs.\n## Sound IDs\n`buttonPress`\nSounds require WAV.'
        docs.validate_pack_contract(assets, sounds, guide)
        for altered in [guide.replace('terrainStone', 'unknown'), guide.replace('buttonPress', 'unknown'), guide.replace('2 texture', '3 texture')]:
            with self.assertRaises(ValueError): docs.validate_pack_contract(assets, sounds, altered)

    def test_documentation_ignores_external_urls_and_fenced_examples(self):
        files = {'README.md': b'[Apple](https://apple.com/path)\n```md\n[Example](missing.md)\n```\n'}
        docs.validate_files(files, files.__getitem__)

    def test_manifest_hashes_actual_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'artifact'; path.write_bytes(b'abc')
            self.assertEqual(manifest.sha256(path), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')

    def test_distribution_cli_refuses_development_identity_before_building(self):
        result = subprocess.run([str(SCRIPTS / 'release.sh'), '--sign', 'Apple Development: Fixture'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('Developer ID Application', result.stderr)

    def test_installer_requires_exact_applications_link(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(ValueError): release.validate_package(root)
            (root / 'Applications').symlink_to('/tmp')
            with self.assertRaises(ValueError): release.validate_package(root)


if __name__ == '__main__': unittest.main()
