"""Verify compiled PhoniLock package structure and Mach-O arm64 binaries."""
import io
from pathlib import Path
import plistlib
import struct
import sys
import tarfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_repo import read_control


def check(path):
    fields = read_control(path)
    assert fields['Package'] == 'com.phoni.phonilock'
    assert fields['Architecture'] == 'iphoneos-arm'
    assert 'firmware (>= 12.0)' in fields['Depends'] and 'firmware (<< 13.0)' in fields['Depends']
    with path.open('rb') as source:
        assert source.read(8) == b'!<arch>\n'
        payload = None
        while header := source.read(60):
            name = header[:16].decode().strip().rstrip('/')
            size = int(header[48:58])
            if name.startswith('data.tar'):
                payload = source.read(size)
                break
            source.seek(size + size % 2, 1)
    assert payload is not None, 'No package payload'
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r:*') as archive:
        files = {member.name.removeprefix('./'): member for member in archive if member.isfile()}
        required = [
            'Library/MobileSubstrate/DynamicLibraries/PhoniLock.dylib',
            'Library/MobileSubstrate/DynamicLibraries/PhoniLock.plist',
            'Library/PreferenceBundles/PhoniLockPrefs.bundle/PhoniLockPrefs',
            'Library/PreferenceBundles/PhoniLockPrefs.bundle/Info.plist',
            'Library/PreferenceBundles/PhoniLockPrefs.bundle/Root.plist',
            'Library/PreferenceLoader/Preferences/PhoniLock.plist',
        ]
        for name in required:
            assert name in files, 'Missing ' + name
        for name in (required[0], required[2]):
            data = archive.extractfile(files[name]).read()
            magic, cpu, subtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from('<8I', data)
            assert magic == 0xfeedfacf and cpu == 0x0100000c, 'Not a thin arm64 Mach-O: ' + name
            assert filetype in (6, 8), 'Not a dylib/bundle: ' + name
            offset, signed, min_version = 32, False, None
            for _ in range(ncmds):
                command, size = struct.unpack_from('<II', data, offset)
                assert size >= 8 and offset + size <= len(data)
                if command == 0x1d:
                    signature_offset, signature_size = struct.unpack_from('<II', data, offset + 8)
                    signed = signature_size > 0 and signature_offset + signature_size <= len(data)
                elif command == 0x25:
                    min_version = struct.unpack_from('<I', data, offset + 8)[0]
                elif command == 0x32:
                    platform, min_version = struct.unpack_from('<II', data, offset + 8)
                    assert platform == 2, 'Binary targets a non-iOS platform'
                offset += size
            assert signed, 'Missing ad-hoc code signature: ' + name
            assert min_version is not None and min_version <= 0x000c0508, 'Deployment target is newer than iOS 12.5.8'
            print('arm64, signed, iOS 12 deployment:', name)
        for name, member in files.items():
            assert not name.startswith('var/jb/'), 'Unexpected rootless file'
            if name.endswith('.plist'):
                plistlib.loads(archive.extractfile(member).read())
        injection = plistlib.loads(archive.extractfile(files[required[1]]).read())
        assert injection == {'Filter': {'Bundles': ['com.apple.springboard']}}
    print('Package structure verified:', path.name)


if __name__ == '__main__':
    for filename in sys.argv[1:]:
        check(Path(filename))
