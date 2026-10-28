#!/usr/bin/env python3
"""Build a flat Sileo/APT repository and its website from debs/*.deb.

No tweak code is executed and no package payload is extracted.
Python's standard library handles the usual gzip/xz/bzip2 .deb controls.
For zstd controls, dpkg-deb is used when available (as on the CI runner).
"""
from __future__ import annotations

import argparse
import bz2
from datetime import datetime, timezone
from email.utils import format_datetime
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]


def parse_control(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    current = None
    for line in text.strip().splitlines():
        if line.startswith((' ', '\t')):
            if current is None:
                raise ValueError('Control continuation without a field')
            fields[current] += '\n' + line
        elif line:
            key, separator, value = line.partition(':')
            if not separator or not re.fullmatch(r'[A-Za-z][A-Za-z0-9-]*', key):
                raise ValueError('Malformed control field')
            if key.lower() in [field.lower() for field in fields]:
                raise ValueError('Duplicate control field: ' + key)
            fields[key] = value.strip()
            current = key
        else:
            raise ValueError('Unexpected second paragraph in control')
    # Debian field names are case-insensitive. Normalize fields consumed here.
    canonical = {key.lower(): key for key in ['Package', 'Name', 'Version', 'Architecture', 'Description', 'Maintainer', 'Author', 'Section', 'Depends', 'Icon', 'Depiction', 'SileoDepiction', 'Filename', 'Size', 'MD5sum', 'SHA1', 'SHA256']}
    return {canonical.get(key.lower(), key): value for key, value in fields.items()}


def read_control(path: Path) -> dict[str, str]:
    control_data, control_name, version, payloads = None, None, None, 0
    with path.open('rb') as source:
        if source.read(8) != b'!<arch>\n':
            raise ValueError('Not a Debian ar archive')
        while header := source.read(60):
            if len(header) != 60 or header[58:60] != b'`\n':
                raise ValueError('Invalid ar member header')
            name = header[:16].decode('ascii').strip().rstrip('/')
            size = int(header[48:58])
            if size < 0 or source.tell() + size > path.stat().st_size:
                raise ValueError('Truncated ar archive')
            if name == 'debian-binary':
                if version is not None or size > 32:
                    raise ValueError('Invalid Debian format marker')
                version = source.read(size)
                source.seek(size % 2, 1)
            elif name == 'control.tar' or name.startswith('control.tar.'):
                if control_data is not None:
                    raise ValueError('Duplicate control archive')
                if size > 16 * 1024 * 1024:
                    raise ValueError('Control archive exceeds 16 MiB')
                control_data, control_name = source.read(size), name
                source.seek(size % 2, 1)
            else:
                if name == 'data.tar' or name.startswith('data.tar.'):
                    payloads += 1
                source.seek(size + (size % 2), 1)
    if version != b'2.0\n' or payloads != 1 or control_data is None:
        raise ValueError('Missing Debian format marker, control archive, or unique payload')
    if control_name.endswith('.zst'):
        if not shutil.which('dpkg-deb'):
            raise ValueError('zstd control requires dpkg-deb; build on Linux or in GitHub Actions')
        result = subprocess.run(['dpkg-deb', '--field', str(path.resolve())], check=True, capture_output=True, text=True, timeout=30)
        return parse_control(result.stdout)
    with tarfile.open(fileobj=io.BytesIO(control_data), mode='r:*') as archive:
        for member in archive:
            if member.name in ('control', './control'):
                if not member.isfile() or member.size > 1024 * 1024:
                    raise ValueError('Invalid control file')
                stream = archive.extractfile(member)
                if stream is not None:
                    return parse_control(stream.read().decode('utf-8'))
        raise ValueError('Missing control file')


def version_compare(left: str, right: str) -> int:
    """Debian version ordering: epoch, upstream, revision; tilde sorts first."""
    def split(value):
        epoch, sep, tail = value.partition(':')
        if not sep:
            epoch, tail = '0', value
        upstream, sep, revision = tail.rpartition('-')
        return int(epoch), upstream if sep else tail, revision if sep else '0'

    def order(char):
        if char == '~':
            return -1
        if not char or char.isdigit():
            return 0
        return ord(char) if char.isalpha() else ord(char) + 256

    def part(a, b):
        while a or b:
            while (a and not a[0].isdigit()) or (b and not b[0].isdigit()):
                ac, bc = a[:1], b[:1]
                delta = order(ac) - order(bc)
                if delta:
                    return delta
                a, b = a[1:] if ac else '', b[1:] if bc else ''
            ad, bd = re.match(r'\d*', a)[0], re.match(r'\d*', b)[0]
            az, bz = ad.lstrip('0'), bd.lstrip('0')
            if len(az) != len(bz):
                return len(az) - len(bz)
            if az != bz:
                return 1 if az > bz else -1
            a, b = a[len(ad):], b[len(bd):]
        return 0

    ae, au, ar = split(left)
    be, bu, br = split(right)
    return (ae - be) or part(au, bu) or part(ar, br)


def validate(fields: dict[str, str], filename: str):
    for key in ['Package', 'Version', 'Architecture', 'Maintainer', 'Description']:
        if not fields.get(key):
            raise ValueError('Missing required field: ' + key)
    if not re.fullmatch(r'[a-z0-9][a-z0-9+.-]+', fields['Package']):
        raise ValueError('Invalid Package identifier')
    if not re.fullmatch(r'(?:[0-9]+:)?[0-9][0-9A-Za-z.+~\-]*', fields['Version']):
        raise ValueError('Invalid Version')
    if fields['Architecture'] not in ('iphoneos-arm', 'all'):
        raise ValueError('Use rootful iphoneos-arm (or all for architecture-independent content), not rootless iphoneos-arm64')
    if not re.fullmatch(r'[A-Za-z0-9_.+~\-]+\.deb', filename):
        raise ValueError('Use a .deb filename containing only letters, digits, dots, underscores, +, ~, or -')


def description(value: str) -> str:
    return '\n'.join('' if line.strip() == '.' else line.lstrip() for line in value.splitlines())


def depiction(pkg: dict) -> dict:
    return {'minVersion': '0.4', 'class': 'DepictionTabView', 'tintColor': '#25895f', 'tabs': [
        {'class': 'DepictionStackView', 'tabname': 'Details', 'views': [
            {'class': 'DepictionHeaderView', 'title': pkg['name']},
            {'class': 'DepictionMarkdownView', 'markdown': pkg['description'], 'useRawFormat': False},
            {'class': 'DepictionTableTextView', 'title': 'Version', 'text': pkg['version']},
            {'class': 'DepictionTableTextView', 'title': 'Architecture', 'text': pkg['architecture']},
            {'class': 'DepictionTableTextView', 'title': 'Developer', 'text': pkg['author']},
            {'class': 'DepictionTableTextView', 'title': 'Dependencies', 'text': pkg['depends'] or 'None declared'},
            {'class': 'DepictionMarkdownView', 'markdown': 'Check the declared dependencies and test this release on your device.'}
        ]}
    ]}


def build(root: Path, output: Path):
    root, output = root.resolve(), output.resolve()
    # Never allow a mistaken output path to replace source or package files.
    if output == root or output in root.parents or output.is_relative_to(root / 'site') or output.is_relative_to(root / 'debs'):
        raise ValueError('Output must be a separate build directory')
    if output.exists() and any(output.iterdir()):
        raise ValueError('Output must be empty; choose a new build directory')
    config = json.loads((root / 'repo.json').read_text(encoding='utf-8'))
    base = config['url'].rstrip('/') + '/'
    if not base.startswith('https://'):
        raise ValueError('The repository URL must use HTTPS')
    output.mkdir(parents=True, exist_ok=True)
    shutil.copytree(root / 'site', output, dirs_exist_ok=True)
    (output / 'debs').mkdir(exist_ok=True)
    (output / 'depictions').mkdir(exist_ok=True)
    stanzas, catalog, versions = [], {}, set()
    for path in sorted((root / 'debs').glob('*.deb')):
        if path.is_symlink() or not path.is_file():
            raise ValueError('Package must be a regular file: ' + path.name)
        try:
            fields = read_control(path)
            validate(fields, path.name)
        except Exception as error:
            raise ValueError(f'{path.name}: {error}') from error
        identity = fields['Package'], fields['Version'], fields['Architecture']
        if identity in versions:
            raise ValueError('Duplicate package/version/architecture: ' + str(identity))
        versions.add(identity)
        data = path.read_bytes()
        if len(data) >= 100 * 1024 * 1024:
            raise ValueError('Package exceeds the GitHub file size limit: ' + path.name)
        filename = 'debs/' + quote(path.name, safe='-._~')
        package_id = fields['Package']
        # Repository copy can be corrected without replacing an installed .deb.
        repo_description = config.get('package_descriptions', {}).get(package_id)
        if repo_description is not None:
            if not isinstance(repo_description, str) or not repo_description.strip():
                raise ValueError('Package description must be non-empty text: ' + package_id)
            lines = repo_description.strip().splitlines()
            fields['Description'] = lines[0] + ''.join('\n ' + (line if line.strip() else '.') for line in lines[1:])
        # Generate version-specific depictions so older versions retain their own metadata.
        version_key = hashlib.sha256((fields['Version'] + ':' + fields['Architecture']).encode()).hexdigest()[:16]
        depiction_path = 'depictions/' + package_id + '-' + version_key + '.json'
        fields.update({'Filename': filename, 'Size': str(len(data)),
                       'MD5sum': hashlib.md5(data).hexdigest(), 'SHA1': hashlib.sha1(data).hexdigest(), 'SHA256': hashlib.sha256(data).hexdigest()})
        fields.setdefault('Icon', base + 'CydiaIcon.png')
        fields.setdefault('Depiction', base + 'package.html?id=' + quote(package_id, safe=''))
        fields.setdefault('SileoDepiction', base + quote(depiction_path, safe='/'))
        stanzas.append('\n'.join(key + ': ' + value for key, value in fields.items()))
        pkg = {'id': package_id, 'name': fields.get('Name', package_id), 'version': fields['Version'],
               'architecture': fields['Architecture'], 'description': description(fields['Description']),
               'section': fields.get('Section', 'Tweaks'), 'author': fields.get('Author', fields['Maintainer']),
               'depends': fields.get('Depends', ''), 'filename': filename, 'size': len(data), 'sha256': fields['SHA256']}
        (output / depiction_path).write_text(json.dumps(depiction(pkg), indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        if package_id not in catalog or version_compare(pkg['version'], catalog[package_id]['version']) > 0:
            catalog[package_id] = pkg
        shutil.copyfile(path, output / 'debs' / path.name)
    index = ('\n\n'.join(stanzas) + '\n\n' if stanzas else '').encode('utf-8')
    (output / 'Packages').write_bytes(index)
    (output / 'Packages.gz').write_bytes(gzip.compress(index, mtime=0))
    (output / 'Packages.bz2').write_bytes(bz2.compress(index))
    release = [f"Origin: {config['name']}", f"Label: {config['name']}", 'Suite: stable', 'Version: 1.0',
               'Architectures: iphoneos-arm', 'Components: main', f"Description: {config['description']}",
               'Date: ' + format_datetime(datetime.now(timezone.utc), usegmt=True)]
    for label, algorithm in [('MD5Sum', 'md5'), ('SHA256', 'sha256')]:
        release.append(label + ':')
        for name in ['Packages', 'Packages.gz', 'Packages.bz2']:
            data = (output / name).read_bytes()
            release.append(f' {hashlib.new(algorithm, data).hexdigest()} {len(data)} {name}')
    (output / 'Release').write_text('\n'.join(release) + '\n', encoding='utf-8', newline='\n')
    (output / 'packages.json').write_text(json.dumps(sorted(catalog.values(), key=lambda p: p['name'].lower()), ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (output / '.nojekyll').touch()
    (output / 'sileo-featured.json').write_text('{"class":"FeaturedBannersView","banners":[]}\n', encoding='utf-8')
    print(f'Built {len(stanzas)} package versions ({len(catalog)} packages) in {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    build(args.root, args.output)
