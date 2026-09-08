#!/usr/bin/env python3
"""Generates the tray icons (PNG for macOS/Linux, ICO for Windows) without
external dependencies. Output: apps/clipboard_sync/assets/icons/."""
import struct, zlib, os, sys

def png(size, pixels):
    raw = b''.join(b'\x00' + bytes(sum(pixels[y], ())) for y in range(size))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

def clipboard(size, rgb):
    """Clipboard glyph: board with a clip on top, drawn as alpha mask."""
    s = size; px = [[(0, 0, 0, 0)] * s for _ in range(s)]
    def fill(x0, y0, x1, y1, a=255):
        for y in range(int(y0 * s), int(y1 * s)):
            for x in range(int(x0 * s), int(x1 * s)):
                px[y][x] = (*rgb, a)
    fill(0.18, 0.15, 0.82, 0.95)           # board
    fill(0.26, 0.28, 0.74, 0.87, 0)        # hollow
    fill(0.36, 0.06, 0.64, 0.24)           # clip
    fill(0.32, 0.42, 0.68, 0.48)           # lines
    fill(0.32, 0.56, 0.68, 0.62)
    fill(0.32, 0.70, 0.56, 0.76)
    return px

def ico(png_bytes, size):
    header = struct.pack('<HHH', 0, 1, 1)
    entry = struct.pack('<BBBBHHII', size % 256, size % 256, 0, 0, 1, 32, len(png_bytes), 6 + 16)
    return header + entry + png_bytes

out = sys.argv[1] if len(sys.argv) > 1 else 'apps/clipboard_sync/assets/icons'
os.makedirs(out, exist_ok=True)
black = png(44, clipboard(44, (0, 0, 0)))          # macOS template (alpha only matters)
open(os.path.join(out, 'tray.png'), 'wb').write(black)
color = png(64, clipboard(64, (59, 110, 165)))
open(os.path.join(out, 'tray.ico'), 'wb').write(ico(color, 64))
open(os.path.join(out, 'app.png'), 'wb').write(png(256, clipboard(256, (59, 110, 165))))
print('icons written to', out)
