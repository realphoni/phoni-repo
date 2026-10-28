"""Validate DownShot's package, injection filter, signing, and arm64 target."""
import io
from pathlib import Path
import plistlib
import struct
import sys
import tarfile
from build_repo import read_control


def check(path):
    control = read_control(path)
    assert control['Package'] == 'com.phoni.downshot'
    assert control['Architecture'] == 'iphoneos-arm'
    assert 'firmware (>= 12.0)' in control['Depends'] and 'firmware (<< 13.0)' in control['Depends']
    with path.open('rb') as stream:
        assert stream.read(8) == b'!<arch>\n'
        payload = None
        while header := stream.read(60):
            name = header[:16].decode().strip().rstrip('/')
            size = int(header[48:58])
            if name.startswith('data.tar'):
                payload = stream.read(size)
                break
            stream.seek(size + size % 2, 1)
    assert payload is not None
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r:*') as archive:
        files = {m.name.removeprefix('./'): m for m in archive if m.isfile()}
        prefix = 'Library/MobileSubstrate/DynamicLibraries/DownShot'
        binary = archive.extractfile(files[prefix + '.dylib']).read()
        injection = plistlib.loads(archive.extractfile(files[prefix + '.plist']).read())
        assert injection == {'Filter': {'Bundles': ['com.apple.springboard']}}
        magic, cpu, subtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from('<8I', binary)
        assert magic == 0xfeedfacf and cpu == 0x0100000c and filetype == 6
        offset, signed, minimum = 32, False, None
        for _ in range(ncmds):
            command, size = struct.unpack_from('<II', binary, offset)
            assert size >= 8 and offset + size <= len(binary)
            if command == 0x1d:
                location, length = struct.unpack_from('<II', binary, offset + 8)
                signed = length > 0 and location + length <= len(binary)
            elif command == 0x25:
                minimum = struct.unpack_from('<I', binary, offset + 8)[0]
            elif command == 0x32:
                platform, minimum = struct.unpack_from('<II', binary, offset + 8)
                assert platform == 2
            offset += size
        assert signed and minimum is not None and minimum <= 0x000c0508
        assert not any(name.startswith('var/jb/') for name in files)
        assert 'Library/PreferenceBundles' not in ' '.join(files)
    print('DownShot package verified: signed arm64 dylib, iOS 12, SpringBoard-only injection')


if __name__ == '__main__':
    for filename in sys.argv[1:]:
        check(Path(filename))
