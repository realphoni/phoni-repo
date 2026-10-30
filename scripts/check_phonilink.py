"""Check the Sileo app and resignable companion IPA contain the same signed arm64 app."""
import io
from pathlib import Path
import plistlib
import struct
import sys
import tarfile
import zipfile
from build_repo import read_control


def check_app(files):
    plist = plistlib.loads(files['Info.plist'])
    assert plist['CFBundleIdentifier'] == 'com.phoni.phonilink'
    assert plist['CFBundleExecutable'] == 'PhoniLink' and plist['MinimumOSVersion'] == '12.0'
    assert plist['NSMicrophoneUsageDescription'] and plist['NSLocalNetworkUsageDescription']
    assert plist['NSBonjourServices'] == ['_phonilink._tcp']
    assert not plist.get('UIBackgroundModes'), 'This beta deliberately stops when backgrounded'
    assert files['Icon.png'].startswith(b'\x89PNG\r\n\x1a\n')
    for scale in (2, 3):
        assert struct.unpack('!2I', files[f'Icon60@{scale}x.png'][16:24]) == (60 * scale, 60 * scale)
    assert 'Launch-667h@2x.png' in files
    binary = files['PhoniLink']
    magic, cpu, subtype, kind, ncmds, sizeofcmds, flags, reserved = struct.unpack_from('<8I', binary)
    assert magic == 0xfeedfacf and cpu == 0x0100000c and kind == 2
    offset, signed, minimum, cryptid = 32, False, None, 0
    frameworks = []
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
        elif command in (0xc, 0x80000018):
            start = struct.unpack_from('<I', binary, offset + 8)[0]
            frameworks.append(binary[offset + start:offset + size].split(b'\0')[0].decode())
        elif command == 0x2c:
            cryptid = struct.unpack_from('<I', binary, offset + 16)[0]
        offset += size
    assert signed and minimum == 0xc0000 and cryptid == 0
    assert any('/MultipeerConnectivity.framework/' in name for name in frameworks)
    assert not any('/PrivateFrameworks/' in name for name in frameworks)
    assert not any(name.endswith('.dylib') for name in files), 'Companion must not need jailbreak injection'
    assert 'embedded.mobileprovision' not in files, 'IPA is to be signed by its installer'


def check(deb, ipa):
    control = read_control(deb)
    assert control['Package'] == 'com.phoni.phonilink' and control['Architecture'] == 'iphoneos-arm'
    assert 'firmware (>= 12.0)' in control['Depends'] and 'firmware (<< 13.0)' in control['Depends']
    assert 'mobilesubstrate' not in control['Depends']
    with deb.open('rb') as source:
        assert source.read(8) == b'!<arch>\n'
        payload, metadata = None, None
        while header := source.read(60):
            size = int(header[48:58]); name = header[:16].decode().strip().rstrip('/')
            if name.startswith('data.tar'):
                payload = source.read(size); break
            if name.startswith('control.tar'):
                metadata = source.read(size); source.seek(size % 2, 1); continue
            source.seek(size + size % 2, 1)
    assert payload and metadata
    with tarfile.open(fileobj=io.BytesIO(metadata), mode='r:*') as archive:
        scripts = {item.name.removeprefix('./'): item for item in archive if item.isfile()}
        for name in ['postinst', 'postrm']:
            assert scripts[name].mode & 0o111, 'Home Screen refresh script must be executable'
            assert b'uicache' in archive.extractfile(scripts[name]).read()
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r:*') as archive:
        members = [item for item in archive if item.isfile()]
        assert next(item for item in members if item.name.removeprefix('./') == 'Applications/PhoniLink.app/PhoniLink').mode & 0o111
        all_files = {item.name.removeprefix('./'): archive.extractfile(item).read() for item in members}
    assert all(name.startswith('Applications/PhoniLink.app/') for name in all_files)
    app = {name.removeprefix('Applications/PhoniLink.app/'): data for name, data in all_files.items()}
    check_app(app)
    with zipfile.ZipFile(ipa) as archive:
        assert all(name.startswith('Payload/PhoniLink.app/') or name == 'Payload/' for name in archive.namelist())
        companion = {name.removeprefix('Payload/PhoniLink.app/'): archive.read(name) for name in archive.namelist() if not name.endswith('/')}
        assert archive.getinfo('Payload/PhoniLink.app/PhoniLink').external_attr >> 16 & 0o111
    check_app(companion)
    assert app == companion, 'Both installations must speak the same protocol and use the same binary'
    print('PhoniLink verified: matching signed arm64 app/IPA, public frameworks, iOS 12 minimum, microphone/local-network declarations')
    print('Companion IPA has no Apple provisioning profile: re-sign it with a sideloading tool before installing.')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('usage: check_phonilink.py PACKAGE.deb COMPANION.ipa')
    check(Path(sys.argv[1]), Path(sys.argv[2]))
