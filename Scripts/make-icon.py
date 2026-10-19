#!/usr/bin/env python3
"""Render the geometric QuotaBar icon without external dependencies."""
import json, math, pathlib, struct, zlib
root = pathlib.Path(__file__).resolve().parent.parent / 'Assets.xcassets'
(root / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
folder = root / 'AppIcon.appiconset'

def render(size):
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            dx, dy = (x + .5) / size - .5, (y + .5) / size - .5
            radius = math.hypot(dx, dy)
            angle = (math.atan2(dy, dx) + math.pi / 2) % (math.pi * 2)
            bg = (19 + int(9 * (1 - y / size)), 19 + int(8 * (1 - y / size)), 30 + int(15 * (1 - y / size)))
            ring = (129, 107, 249) if angle < math.pi * 1.47 else (48, 45, 67)
            coverage = max(0, min(1, (.039 - abs(radius - .285)) * size))
            color = tuple(int(a * (1 - coverage) + b * coverage) for a, b in zip(bg, ring))
            # Two bars: session and weekly quota.
            for bar_y, width in [(-.045, .19), (.045, .125)]:
                if abs(dy - bar_y) < .018 and -.095 < dx < width - .095:
                    color = (236, 231, 255)
            rows.extend((*color, 255))
    def chunk(tag, payload):
        return struct.pack('>I', len(payload)) + tag + payload + struct.pack('>I', zlib.crc32(tag + payload) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')

images = [{'filename': 'icon-1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}]
for points in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        size = points * scale
        filename = f'icon-{size}.png'
        images.append({'filename': filename, 'idiom': 'mac', 'size': f'{points}x{points}', 'scale': f'{scale}x'})
for size in {16, 32, 64, 128, 256, 512, 1024}:
    (folder / f'icon-{size}.png').write_bytes(render(size))
(folder / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2))
