import bz2
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from urllib.parse import unquote, urlsplit

SOURCE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_repo', SOURCE / 'scripts/build_repo.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def tar_bytes(filename, data, mode='w:gz'):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode=mode) as archive:
        member = tarfile.TarInfo(filename)
        member.size = len(data)
        archive.addfile(member, io.BytesIO(data))
    return buffer.getvalue()


def deb(path, *, version='1.0.0', arch='iphoneos-arm', package='com.phoni.fixture', custom='', compression='gz'):
    control = f'Package: {package}\nName: Fixture Tweak\nVersion: {version}\nArchitecture: {arch}\nMaintainer: Phoni\nDescription: A fixture, never published.\n More details.\n .\n Last paragraph.\nSection: Tweaks\nDepends: mobilesubstrate, firmware (>= 12.0), firmware (<< 13.0)\n{custom}'
    members = [('debian-binary', b'2.0\n'), ('control.tar.' + compression, tar_bytes('./control', control.encode(), 'w:' + compression)), ('data.tar.gz', tar_bytes('usr/share/doc/fixture', b'fixture only'))]
    with path.open('wb') as output:
        output.write(b'!<arch>\n')
        for name, data in members:
            output.write(f'{name + "/":<16}{0:<12}{0:<6}{0:<6}{"100644":<8}{len(data):<10}`\n'.encode())
            output.write(data)
            if len(data) % 2:
                output.write(b'\n')


class RepositoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=SOURCE, prefix='.test-')
        self.root = Path(self.temp.name) / 'repo'
        (self.root / 'site').mkdir(parents=True)
        (self.root / 'debs').mkdir()
        (self.root / 'site/index.html').write_text('<h1>Fixture</h1>')
        (self.root / 'repo.json').write_text(json.dumps({'name': 'Phoni Repo', 'description': 'Test', 'url': 'https://realphoni.github.io/phoni-repo/'}))
        self.out = Path(self.temp.name) / 'output'

    def tearDown(self):
        assert Path(self.temp.name).resolve().is_relative_to(SOURCE.resolve())
        self.temp.cleanup()

    def test_empty_repo_and_checksums(self):
        builder.build(self.root, self.out)
        self.assertEqual((self.out / 'Packages').read_bytes(), b'')
        self.assertEqual(gzip.decompress((self.out / 'Packages.gz').read_bytes()), b'')
        self.assertEqual(bz2.decompress((self.out / 'Packages.bz2').read_bytes()), b'')
        self.assertEqual(json.loads((self.out / 'packages.json').read_text()), [])
        release = (self.out / 'Release').read_text()
        for name in ['Packages', 'Packages.gz', 'Packages.bz2']:
            data = (self.out / name).read_bytes()
            self.assertIn(f'{hashlib.sha256(data).hexdigest()} {len(data)} {name}', release)

    def test_real_deb_indexes_downloads_and_versioned_depictions(self):
        deb(self.root / 'debs/tweak_1.9.deb', version='1.9', package='com.phoni.fixture+test')
        deb(self.root / 'debs/tweak_1.10.deb', version='1:1.10+build2', package='com.phoni.fixture+test', compression='xz')
        builder.build(self.root, self.out)
        catalog = json.loads((self.out / 'packages.json').read_text())
        self.assertEqual(len(catalog), 1)
        self.assertEqual(catalog[0]['version'], '1:1.10+build2')
        self.assertEqual(catalog[0]['description'], 'A fixture, never published.\nMore details.\n\nLast paragraph.')
        index = (self.out / 'Packages').read_text()
        for stanza in index.strip().split('\n\n'):
            fields = builder.parse_control(stanza)
            data = (self.out / unquote(fields['Filename'])).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), fields['SHA256'])
            path = unquote(urlsplit(fields['SileoDepiction']).path).removeprefix('/phoni-repo/')
            depiction = json.loads((self.out / path).read_text())
            self.assertEqual(depiction['tabs'][0]['views'][2]['text'], fields['Version'])
        self.assertEqual(len(list((self.out / 'depictions').glob('*.json'))), 2)
        self.assertEqual(gzip.decompress((self.out / 'Packages.gz').read_bytes()).decode(), index)

    def test_rootless_and_invalid_packages_block_publication(self):
        deb(self.root / 'debs/rootless.deb', arch='iphoneos-arm64')
        with self.assertRaisesRegex(ValueError, 'rootful'):
            builder.build(self.root, self.out)

    def test_duplicate_versions_block_publication(self):
        deb(self.root / 'debs/a.deb')
        deb(self.root / 'debs/b.deb')
        with self.assertRaisesRegex(ValueError, 'Duplicate package'):
            builder.build(self.root, self.out)

    def test_malformed_archive_is_rejected(self):
        (self.root / 'debs/bad.deb').write_bytes(b'not a package')
        with self.assertRaisesRegex(ValueError, 'Debian ar'):
            builder.build(self.root, self.out)

    def test_existing_output_is_preserved(self):
        self.out.mkdir()
        (self.out / 'keep').write_text('existing data')
        with self.assertRaisesRegex(ValueError, 'empty'):
            builder.build(self.root, self.out)
        self.assertEqual((self.out / 'keep').read_text(), 'existing data')

    def test_debian_version_ordering(self):
        versions = ['1.0~beta2', '1.0~beta10', '1.0', '1.0-1', '1.0-2', '1.0-10', '1.9', '1.10', '1:0.1']
        for earlier, later in zip(versions, versions[1:]):
            self.assertLess(builder.version_compare(earlier, later), 0)
            self.assertGreater(builder.version_compare(later, earlier), 0)
        self.assertEqual(builder.version_compare('1.0', '1.0-0'), 0)


if __name__ == '__main__':
    unittest.main()
