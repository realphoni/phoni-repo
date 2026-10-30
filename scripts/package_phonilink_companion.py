"""Wrap the exact app from a PhoniLink .deb as an IPA for the user's signing tool."""
import argparse
import io
from pathlib import Path
import tarfile
import zipfile
from build_repo import read_control


def package(deb, output):
    fields = read_control(deb)
    if fields['Package'] != 'com.phoni.phonilink':
        raise ValueError('Expected a PhoniLink package')
    payload = None
    with deb.open('rb') as source:
        if source.read(8) != b'!<arch>\n':
            raise ValueError('Invalid .deb')
        while header := source.read(60):
            name, size = header[:16].decode().strip().rstrip('/'), int(header[48:58])
            if name.startswith('data.tar'):
                payload = source.read(size); break
            source.seek(size + size % 2, 1)
    if payload is None:
        raise ValueError('Missing app payload')
    entries = []
    prefix = 'Applications/PhoniLink.app/'
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r:*') as archive:
        for member in archive:
            if member.isdir():
                continue
            name = member.name.removeprefix('./')
            if not member.isfile() or not name.startswith(prefix) or '..' in name.split('/'):
                raise ValueError('Unexpected app payload: ' + name)
            info = zipfile.ZipInfo('Payload/PhoniLink.app/' + name.removeprefix(prefix), date_time=(2026, 10, 30, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (0o100755 if name == prefix + 'PhoniLink' else 0o100644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            entries.append((info, archive.extractfile(member).read()))
    if not entries:
        raise ValueError('Empty app')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w') as archive:
        for info, data in sorted(entries, key=lambda item: item[0].filename):
            archive.writestr(info, data)
    print('Companion IPA ready for re-signing: ' + str(output))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('deb', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    package(args.deb, args.output)
