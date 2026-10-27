#!/usr/bin/env python3
"""从品牌母版导出各平台图标资源。

设计资产（提交在仓库里，改品牌时只需替换母版）：

  tool/brand/icon-1024.png   圆角图标母版 1024×1024 RGBA
  tool/brand/fox-mask.png    白狐剪影 alpha（留作自适应图标前景素材）

输出：

  assets/windows/app_icon.ico                     Runner.exe 图标 16/24/32/48/64/128/256
  assets/tray/tray_<state>.png                    托盘四态 64px
  assets/tray/tray_<state>.ico                    托盘四态 ICO 16/20/24/32/48
  assets/brand/icon.png                           界面品牌标记母版 1024（兜底）
  assets/brand/icon-<px>.png                      界面品牌标记预渲染档位 48/72/96/144/192
  android/app/src/main/res/mipmap-<dpi>/ic_launcher{,_round}.png   启动图标

注意：**界面内的品牌标记**（顶栏 / 启动页 / 欢迎页）由 `OlMark` 渲染
`assets/brand/icon-<px>.png`，按「逻辑尺寸 × DPR」挑最接近的一档 ——
用 1024 母版直接解码到 40~50px 会一步缩二十多倍，白狐边缘会出锯齿
（0.5.5 修的就是这个）。换品牌跑一遍本脚本即可，母版与档位一起刷新。

Windows 通知区域只认 ICO/BMP（Shell_NotifyIcon + LoadImage 不支持 PNG），
ICO 条目沿用 32 位 BMP(DIB) 而非 PNG 压缩，确保 rc.exe 与资源管理器都认。
托盘四态靠右下角状态点区分：idle 无点 / transferring 浅蓝 / error 红 / paused 灰。

依赖 Pillow：pip install pillow
"""
import struct
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "tool" / "brand"
MASTER = BRAND / "icon-1024.png"

# 托盘状态点用色（与品牌紫底保持足够对比）
STATE_COLORS = {
    "idle": None,
    "transferring": (0x7D, 0xD3, 0xFC),
    "error": (0xF4, 0x3F, 0x5E),
    "paused": (0x94, 0xA3, 0xB8),
}

# 状态点几何（相对图标边长的比例）。白狐右/下留白约 0.24，点必须落在留白里，
# 否则会盖住尾巴；半径也不能大，16px 托盘上 0.115×16≈1.8px 已是可辨下限。
BADGE_CX = 0.80
BADGE_R = 0.12
BADGE_RING = 0.032
BADGE_SS = 4  # 超采样倍数，消除 PIL 画圆的硬边


def load_master():
    if not MASTER.exists():
        raise SystemExit(f"缺少母版：{MASTER}")
    return Image.open(MASTER).convert("RGBA")


def rows_of(img, size):
    """RGBA 行列表，供 ICO 打包使用。"""
    im = img.resize((size, size), Image.LANCZOS)
    data = im.tobytes()
    step = size * 4
    return [data[y * step:(y + 1) * step] for y in range(size)]


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
    return header + bytes(body) + b"\x00" * (mask_row * size)


def build_ico(img, sizes):
    images = [(size, ico_entry(rows_of(img, size), size)) for size in sizes]
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


def with_badge(img, color):
    """右下角状态点 + 白色描边（图标圆角外也能看清边界）。"""
    size = img.size[0]
    big = size * BADGE_SS
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = cy = big * BADGE_CX
    r = big * BADGE_R
    ring = big * BADGE_RING
    d.ellipse([cx - r - ring, cy - r - ring, cx + r + ring, cy + r + ring], fill=(255, 255, 255, 240))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=tuple(color) + (255,))
    layer = layer.resize((size, size), Image.LANCZOS)
    out = img.copy()
    out.alpha_composite(layer)
    return out


def main():
    master = load_master()
    print(f"母版 {MASTER.relative_to(ROOT)}  {master.size[0]}×{master.size[1]}")

    # ---- Windows 程序图标 ----
    win_dir = ROOT / "assets" / "windows"
    win_dir.mkdir(parents=True, exist_ok=True)
    ico = build_ico(master, [16, 24, 32, 48, 64, 128, 256])
    (win_dir / "app_icon.ico").write_bytes(ico)
    print(f"assets/windows/app_icon.ico  {len(ico)} bytes")

    # ---- 托盘四态 ----
    tray_dir = ROOT / "assets" / "tray"
    tray_dir.mkdir(parents=True, exist_ok=True)
    for name, color in STATE_COLORS.items():
        img = with_badge(master, color) if color else master

        png_path = tray_dir / f"tray_{name}.png"
        img.resize((64, 64), Image.LANCZOS).save(png_path, "PNG", optimize=True)

        tray_ico = build_ico(img, [16, 20, 24, 32, 48])
        (tray_dir / f"tray_{name}.ico").write_bytes(tray_ico)
        print(f"assets/tray/tray_{name}.png {png_path.stat().st_size} bytes / "
              f".ico {len(tray_ico)} bytes")

    # ---- Android 启动图标 ----
    # 两套并存：
    #   1) adaptive icon（API 26+ 生效）—— 满幅绘制，启动器不会再套白框缩小
    #   2) 传统 mipmap PNG —— 兜底，同时供 roundIcon 引用
    # 只用传统 PNG 时，Android 8+ 会对其做 legacy 处理（加白底框、缩到约 2/3），
    # 这正是「装好之后图标很小」的根因。
    res = ROOT / "android" / "app" / "src" / "main" / "res"

    for dpi, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                    ("xxhdpi", 144), ("xxxhdpi", 192)):
        out_dir = res / f"mipmap-{dpi}"
        out_dir.mkdir(parents=True, exist_ok=True)
        icon = master.resize((px, px), Image.LANCZOS)
        for fname in ("ic_launcher.png", "ic_launcher_round.png"):
            icon.save(out_dir / fname, "PNG", optimize=True)
        print(f"mipmap-{dpi}/ic_launcher{{,_round}}.png  {px}×{px}")

    # 界面内的品牌标记（顶栏 / 启动页 / 欢迎页）也按档位预渲染。
    # 直接用 1024 母版解码到 46px 会一步缩 22 倍，白狐边缘出锯齿；
    # 预渲染后 OlMark 按「逻辑尺寸 × DPR」挑最接近的一档。
    brand_dir = ROOT / "assets" / "brand"
    brand_dir.mkdir(parents=True, exist_ok=True)
    master.save(brand_dir / "icon.png", "PNG", optimize=True)
    print("assets/brand/icon.png  1024×1024（母版）")
    for px in (48, 72, 96, 144, 192):
        master.resize((px, px), Image.LANCZOS).save(
            brand_dir / f"icon-{px}.png", "PNG", optimize=True)
        print(f"assets/brand/icon-{px}.png  {px}×{px}")

    # 前景：白狐剪影铺在 108dp 画布上（母版留白 25%，正好落在 66dp 安全区内）
    mask = Image.open(BRAND / "fox-mask.png").convert("L")
    fox = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    fox.putalpha(mask)
    for dpi, px in (("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                    ("xxhdpi", 324), ("xxxhdpi", 432)):
        out_dir = res / f"drawable-{dpi}"
        out_dir.mkdir(parents=True, exist_ok=True)
        fox.resize((px, px), Image.LANCZOS).save(
            out_dir / "ic_launcher_foreground.png", "PNG", optimize=True)
        print(f"drawable-{dpi}/ic_launcher_foreground.png  {px}×{px}")

    # 背景：品牌渐变（左上深蓝 → 右下浅紫），XML 比位图省空间且任意分辨率不失真
    (res / "drawable").mkdir(parents=True, exist_ok=True)
    (res / "drawable" / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:shape="rectangle">\n'
        '    <gradient\n'
        '        android:angle="315"\n'
        '        android:startColor="#3936C1"\n'
        '        android:centerColor="#6F4ACF"\n'
        '        android:endColor="#A66DE3"\n'
        '        android:type="linear" />\n'
        '</shape>\n',
        encoding="utf-8",
    )
    print("drawable/ic_launcher_background.xml  渐变")

    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n'
    )
    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    for fname in ("ic_launcher.xml", "ic_launcher_round.xml"):
        (anydpi / fname).write_text(adaptive, encoding="utf-8")
    print("mipmap-anydpi-v26/ic_launcher{,_round}.xml  adaptive")


if __name__ == "__main__":
    main()
