"""Create plain launch backgrounds; retain the PNG app icon checked into source."""
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]


def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))


def prepare():
    resources = ROOT / 'tweaks/PhoniLink/Resources'
    resources.mkdir(parents=True, exist_ok=True)
    if not (resources / 'Icon.png').read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('The checked-in app icon must be PNG for iOS 12')
    for scale in (2, 3):
        icon = (resources / f'Icon60@{scale}x.png').read_bytes()
        if not icon.startswith(b'\x89PNG\r\n\x1a\n') or struct.unpack('!2I', icon[16:24]) != (60 * scale, 60 * scale):
            raise ValueError('Native icon variants must have standard iPhone dimensions')
    sizes = {'Launch-568h@2x': (640, 1136), 'Launch-667h@2x': (750, 1334),
             'Launch-736h@3x': (1242, 2208), 'Launch-812h@3x': (1125, 2436),
             'Launch-896h@2x': (828, 1792), 'Launch-896h@3x': (1242, 2688)}
    for name, (width, height) in sizes.items():
        rows = (b'\x00' + bytes((9, 17, 14)) * width) * height
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0))
        png += chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')
        (resources / (name + '.png')).write_bytes(png)
    print('PhoniLink icon and launch backgrounds ready')


if __name__ == '__main__':
    prepare()
