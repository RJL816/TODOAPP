# -*- coding: utf-8 -*-
"""从 promo_screens 生成 README 用图：压缩单图 + 场景/手机拼图。"""
from PIL import Image
import os

SRC = "promo_screens"
DST = "images"
os.makedirs(DST, exist_ok=True)

JPEG_Q = 87
WIDE_W = 1600  # 宽屏图统一宽度


def save_jpeg(img: Image.Image, path: str, q: int = JPEG_Q) -> None:
    img.convert("RGB").save(path, "JPEG", quality=q, optimize=True)
    print(f"{path}: {os.path.getsize(path) / 1024:.0f} KB ({img.width}x{img.height})")


def shrink(path: str, width: int) -> Image.Image:
    img = Image.open(os.path.join(SRC, path))
    h = round(img.height * width / img.width)
    return img.resize((width, h), Image.LANCZOS)


# 1) 单图压缩
singles = {
    "12_focus_immersive_wide.png": "hero-immersive.jpg",
    "01_home_night_wide.png": "home-night.jpg",
    "03_full_timetable_wide.png": "timetable.jpg",
    "09_weekly_review_wide.png": "weekly-review.jpg",
    "10_monthly_summary_wide.png": "monthly.jpg",
    "14_ai_panel_wide.png": "ai-advice.jpg",
    "06_fitness_wide.png": "fitness.jpg",
    "07_diet_wide.png": "diet.jpg",
}
for src, dst in singles.items():
    save_jpeg(shrink(src, WIDE_W), os.path.join(DST, dst))

# 2) 四场景 2x2 拼图（午后 / 晚霞 / 夜色 / 日出），每格下缘留场景名条
cell_w = 950
cells = [shrink(p, cell_w) for p in (
    "16_home_noon_wide.png", "17_home_dusk_wide.png",
    "01_home_night_wide.png", "18_home_dawn_wide.png")]
cell_h = cells[0].height
label_h = 56
grid = Image.new("RGB", (cell_w * 2 + 12, (cell_h + label_h) * 2 + 12), (17, 27, 32))
from PIL import ImageDraw
from PIL import ImageFont
font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 30)
draw = ImageDraw.Draw(grid)
names = ["山间午后 09-17", "山间晚霞 17-20", "山间夜色 20-05", "山间日出 05-09"]
for i, (cell, name) in enumerate(zip(cells, names)):
    x = 6 + (i % 2) * (cell_w + 6)
    y = 6 + (i // 2) * (cell_h + label_h + 6)
    grid.paste(cell, (x, y))
    draw.text((x + 14, y + cell_h + 10), name, fill=(235, 240, 238), font=font)
save_jpeg(grid, os.path.join(DST, "scenes.jpg"))

# 3) 手机三屏并排（首页 / 专注 / 备忘录）
phones = [shrink(p, 460) for p in (
    "22_home_narrow.png", "24_pomodoro_narrow.png", "26_memo_narrow.png")]
ph = phones[0].height
gap = 10
row = Image.new("RGB", (460 * 3 + gap * 4, ph + gap * 2), (17, 27, 32))
for i, p in enumerate(phones):
    row.paste(p, (gap + i * (460 + gap), gap))
save_jpeg(row, os.path.join(DST, "mobile.jpg"))

print("done")
