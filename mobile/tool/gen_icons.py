#!/usr/bin/env python3
"""Sinh bộ icon app 'App Vận Tải' (Cargo Radar) — mọi density + adaptive icon.

Thiết kế: nền gradient xanh (cargo/trust) + vành radar + xe tải trắng + điểm ping
vàng. Vẽ ở 1024px rồi downscale LANCZOS cho nét.

Chạy:  python3 mobile/tool/gen_icons.py
Output: mobile/android/app/src/main/res/mipmap-*/ic_launcher*.png,
        .../mipmap-anydpi-v26/ic_launcher.xml, docs/store/icon_512.png
"""
from PIL import Image, ImageDraw
import os

RES = os.path.join(os.path.dirname(__file__), "..", "android", "app", "src", "main", "res")
STORE = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "store")

BG_TOP = (16, 106, 255)
BG_BOTTOM = (6, 38, 105)
ADAPT_BG = "#0F55E6"
WHITE = (255, 255, 255, 255)
NAVY = (7, 34, 92, 255)
AMBER = (255, 197, 66, 255)

S = 4  # supersample factor (vẽ ở 1024*S rồi thu nhỏ)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_canvas(px):
    img = Image.new("RGBA", (px, px))
    d = ImageDraw.Draw(img)
    for y in range(px):
        d.line([(0, y), (px, y)], fill=lerp(BG_TOP, BG_BOTTOM, y / px) + (255,))
    return img, d


def draw_art(img, d, scale=1.0):
    """Vẽ vành radar + xe tải vào canvas px (tọa độ đã scale theo px/1024)."""
    k = img.width / 1024.0
    cx, cy = 512 * k, 470 * k

    # --- vành radar (3 vòng, mờ dần) ---
    for r, a in ((440, 48), (330, 64), (220, 84)):
        rr = r * k
        d.ellipse(
            [cx - rr, cy - rr, cx + rr, cy + rr],
            outline=(255, 255, 255, a),
            width=max(2, int(10 * k)),
        )

    # --- xe tải trắng ---
    y0 = 470 * k
    body = [round(v * k) for v in (0, 0, 0, 0)]
    # thùng hàng
    d.rounded_rectangle([300 * k, y0 - 90 * k, 655 * k, y0 + 110 * k], radius=22 * k, fill=WHITE)
    # đầu xe
    d.rounded_rectangle([655 * k, y0 - 25 * k, 795 * k, y0 + 110 * k], radius=18 * k, fill=WHITE)
    # kính lái (đục lỗ màu nền)
    d.rounded_rectangle(
        [682 * k, y0 - 2 * k, 762 * k, y0 + 48 * k], radius=10 * k, fill=lerp(BG_TOP, BG_BOTTOM, 0.45) + (255,)
    )
    # gầm
    d.rectangle([315 * k, y0 + 110 * k, 780 * k, y0 + 128 * k], fill=WHITE)
    # bánh xe
    for wx in (400, 700):
        d.ellipse(
            [(wx - 55) * k, y0 + 100 * k, (wx + 55) * k, y0 + 210 * k], fill=NAVY
        )
        d.ellipse(
            [(wx - 20) * k, y0 + 135 * k, (wx + 20) * k, y0 + 175 * k], fill=WHITE
        )
    # vạch chuyển động bên trái
    for i, (x1, x2, yy) in enumerate(((215, 285, y0 - 20), (185, 275, y0 + 30), (215, 265, y0 + 80))):
        d.rounded_rectangle(
            [x1 * k, yy, x2 * k, yy + 16 * k], radius=8 * k, fill=(255, 255, 255, 110)
        )

    # --- điểm radar ping ---
    px_, py_ = 745 * k, y0 - 130 * k
    d.ellipse([px_ - 30 * k, py_ - 30 * k, px_ + 30 * k, py_ + 30 * k], fill=AMBER)
    d.ellipse(
        [px_ - 52 * k, py_ - 52 * k, px_ + 52 * k, py_ + 52 * k],
        outline=(255, 197, 66, 150),
        width=max(2, int(9 * k)),
    )


def full_icon(px):
    img, d = make_canvas(px)
    draw_art(img, d)
    return img


def foreground_icon(px):
    """Adaptive foreground: art thu ~72% nằm giữa canvas trong suốt (safe zone)."""
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    art = full_icon(px)
    inner = int(px * 0.72)
    art = art.resize((inner, inner), Image.LANCZOS)
    off = (px - inner) // 2
    img.paste(art, (off, off), art)
    return img


DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
FG = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""


def main():
    for dens, size in DENSITIES.items():
        out = os.path.join(RES, f"mipmap-{dens}")
        os.makedirs(out, exist_ok=True)
        full_icon(size * S).resize((size, size), Image.LANCZOS).save(os.path.join(out, "ic_launcher.png"))
    for dens, size in FG.items():
        out = os.path.join(RES, f"mipmap-{dens}")
        foreground_icon(size * S).resize((size, size), Image.LANCZOS).save(
            os.path.join(out, "ic_launcher_foreground.png")
        )
    anydpi = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, name), "w") as f:
            f.write(ADAPTIVE_XML)
    colors = os.path.join(RES, "values", "colors.xml")
    with open(colors, "w") as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n')
        f.write(f'    <color name="ic_launcher_background">{ADAPT_BG}</color>\n')
        f.write("</resources>\n")
    # Icon store 512 (Google Play yêu cầu 512x512 PNG)
    os.makedirs(STORE, exist_ok=True)
    full_icon(512 * S).resize((512, 512), Image.LANCZOS).convert("RGB").save(
        os.path.join(STORE, "icon_512.png")
    )
    print("icons generated OK")


if __name__ == "__main__":
    main()
