#!/usr/bin/env python3
"""生成与 Android 启动图标一致的 Windows 图标资源。

Android 的自适应图标（android/app/src/main/res/drawable/ic_launcher_foreground.xml +
colors.xml）是：深蓝底 #0B2233 + 白/浅蓝/青三层「堆叠」图形（108 视口）。
这里用同一套几何数据渲染：

  assets/windows/app_icon.ico   → Runner.exe 图标（16/24/32/48/64/128/256）
  assets/tray/tray_*.png        → 托盘四态图标（64px，右下角状态点）

不依赖第三方库：PNG 用 zlib 手写，ICO 用 32 位 BMP（DIB）条目，兼容 rc.exe 与资源管理器。
"""
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BG = (0x0B, 0x22, 0x33)
WHITE = (255, 255, 255)
SKY = (0x7D, 0xD3, 0xFC)
TEAL = (0x5E, 0xEA, 0xD4)

# 108 视口下的三层轮廓（与 ic_launcher_foreground.xml 完全一致）
STROKE = 4.5
PATHS = [
    # 顶层菱形（白）
    (WHITE, [((54, 30), (80, 44)), ((80, 44), (54, 58)), ((54, 58), (28, 44)), ((28, 44), (54, 30))]),
    # 中层（浅蓝）
    (SKY, [((28, 54), (54, 68)), ((54, 68), (80, 54))]),
    # 底层（青）
    (TEAL, [((28, 66), (54, 80)), ((54, 80), (80, 66))]),
]


def seg_dist(px, py, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(px - x1, py - y1)
    t = max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))


def rounded_alpha(x, y, size, radius_ratio=0.22):
    r = size * radius_ratio
    cx = min(max(x, r), size - r)
    cy = min(max(y, r), size - r)
    d = math.hypot(x - cx, y - cy)
    return max(0.0, min(1.0, (r - d) + 0.5))


def shade(size, scale=108.0):
    """返回 size×size 的 RGBA 行列表（自上而下），内部 3×3 超采样抗锯齿。"""
    rows = []
    ss = 3
    k = size / scale
    for py in range(size):
        row = bytearray()
        for px in range(size):
            r = g = b = 0.0
            a = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    x = px + (sx + 0.5) / ss
                    y = py + (sy + 0.5) / ss
                    alpha = rounded_alpha(x, y, size)
                    if alpha <= 0:
                        continue
                    cr, cg, cb = BG
                    best = None
                    for color, segs in PATHS:
                        cov = 0.0
                        for (x1, y1), (x2, y2) in segs:
                            d = seg_dist(x / k, y / k, x1, y1, x2, y2)
                            cov = max(cov, max(0.0, min(1.0, (STROKE / 2 - d) * k + 0.5)))
                        if cov > 0:
                            if best is None or cov > best[0]:
                                best = (cov, color)
                    if best:
                        cov, color = best
                        cr = BG[0] + (color[0] - BG[0]) * cov
                        cg = BG[1] + (color[1] - BG[1]) * cov
                        cb = BG[2] + (color[2] - BG[2]) * cov
                    r += cr * alpha
                    g += cg * alpha
                    b += cb * alpha
                    a += alpha
            if a == 0:
                row += bytes((0, 0, 0, 0))
            else:
                n = ss * ss
                row += bytes((
                    int(min(255, r / a)),
                    int(min(255, g / a)),
                    int(min(255, b / a)),
                    int(min(255, a / n * 255)),
                ))
        rows.append(bytes(row))
    return rows


def png(rows, size):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(raw, 9))
    out += chunk(b"IEND", b"")
    return out


def ico_entry(rows, size):
    """32 位 BMP(DIB) 条目：BITMAPINFOHEADER + BGRA 自下而上 + AND 掩码。"""
    header = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, size * size * 4, 0, 0, 0, 0)
    body = bytearray()
    for y in range(size - 1, -1, -1):
        row = rows[y]
        for x in range(size):
            r, g, b, a = row[x * 4: x * 4 + 4]
            body += bytes((b, g, r, a))
    mask_row = ((size + 31) // 32) * 4
    mask = b"\x00" * (mask_row * size)
    return header + bytes(body) + mask


def build_ico(sizes, painter=None):
    painter = painter or shade
    images = []
    for size in sizes:
        images.append((size, ico_entry(painter(size), size)))
    offset = 6 + 16 * len(images)
    head = struct.pack("<HHH", 0, 1, len(images))
    entries = b""
    blob = b""
    for size, data in images:
        entries += struct.pack(
            "<BBBBHHII",
            0 if size >= 256 else size,
            0 if size >= 256 else size,
            0, 0, 1, 32, len(data), offset,
        )
        offset += len(data)
        blob += data
    return head + entries + blob


def badge(rows, size, color):
    """右下角状态点（托盘四态用）。"""
    cx, cy, r = size * 0.76, size * 0.76, size * 0.17
    out = []
    for y in range(size):
        row = bytearray(rows[y])
        for x in range(size):
            d = math.hypot(x - cx, y - cy)
            cov = max(0.0, min(1.0, (r - d) + 0.5))
            if cov <= 0:
                continue
            i = x * 4
            a0 = row[i + 3] / 255.0
            if a0 < 0.5:
                # 图标圆角外的区域也补上状态点，形成描边效果
                ring = max(0.0, min(1.0, (r + size * 0.045 - d) + 0.5))
                if ring > 0:
                    row[i:i + 4] = bytes((BG[2], BG[1], BG[0], 255))
                continue
            for c in range(3):
                row[i + c] = int(row[i + c] * (1 - cov) + color[c] * cov)
        out.append(bytes(row))
    return out


def main():
    win_dir = ROOT / "assets" / "windows"
    tray_dir = ROOT / "assets" / "tray"
    win_dir.mkdir(parents=True, exist_ok=True)
    tray_dir.mkdir(parents=True, exist_ok=True)

    ico = build_ico([16, 24, 32, 48, 64, 128, 256])
    (win_dir / "app_icon.ico").write_bytes(ico)
    print(f"assets/windows/app_icon.ico  {len(ico)} bytes")

    base = shade(64)
    states = {
        "idle": None,
        "transferring": SKY,
        "error": (0xF4, 0x3F, 0x5E),
        "paused": (0x94, 0xA3, 0xB8),
    }
    # Windows 通知区域只认 .ico（Shell_NotifyIcon + LoadImage 不支持 PNG），
    # 因此每种状态都产出多尺寸 ICO（16/20/24/32/48），覆盖 100%~200% DPI。
    tray_sizes = [16, 20, 24, 32, 48]
    for name, color in states.items():
        rows = badge(base, 64, color) if color else base
        data = png(rows, 64)
        (tray_dir / f"tray_{name}.png").write_bytes(data)

        def painter(size, _color=color):
            scaled = shade(size)
            return badge(scaled, size, _color) if _color else scaled

        ico = build_ico(tray_sizes, painter)
        (tray_dir / f"tray_{name}.ico").write_bytes(ico)
        print(f"assets/tray/tray_{name}.png  {len(data)} bytes / .ico {len(ico)} bytes")


if __name__ == "__main__":
    main()
