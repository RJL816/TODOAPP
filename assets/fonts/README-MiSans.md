# MiSans 字体

本项目界面字体使用 [MiSans](https://hyperos.mi.com/font)（小米 × 汉仪字库出品），
依据官方授权免费用于个人与商业项目，无需另行授权。

目录内文件为按本项目字符集（GB2312 全量 + ASCII + 常用中西文标点，约 7600 字符）
子集化后的 4 个静态字重，由 `scripts/subset_misans.py` 生成：

| 文件 | 字重 |
|---|---|
| MiSans-Regular-subset.ttf | w400 |
| MiSans-Medium-subset.ttf | w500 |
| MiSans-Semibold-subset.ttf | w600 |
| MiSans-Bold-subset.ttf | w700 |

子集未覆盖的生僻字在运行时回退到系统字体显示。
排版特性（含等宽数字 tnum）已完整保留。

Noto Serif SC（衬线，仅用于问候语等固定文案的子集）仍按 OFL 授权随包分发，
见 `OFL-NotoSerifSC.txt`。
