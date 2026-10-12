# 拾序 · Dayloom：设计与天气背景

## 设计

旧图标 `assets/branding/app_icon_legacy.png` 保留为来源。新图标 `assets/branding/dayloom_icon.png` 延续格线与叶形勾选，用森林绿、暖白和浅金色呼应应用的玻璃界面。`dayloom_icon_draft.png` 是生成过程中的中间稿。

Android 悬浮窗使用原生 Canvas 绘制圆形钟盘、刻度、剩余进度和数字时间，不加载背景图片。暂停冻结时间，专注与休息使用不同的进度色；点击返回，拖动调整位置。主设置提供统一入口。

## 天气行为

默认关闭。自动定位与手动城市可切换；定位为前台单次低精度获取，坐标四舍五入至小数点后两位，再用于请求天气。不开启天气时不请求定位或天气。常规刷新间隔为 30 分钟，缓存有效期 3 小时，过期回退原来的时段背景。

四个原始时段和自定义照片的索引保持不变。新增资源为 `assets/backgrounds/alpine_{rain|snow}_{noon|dusk|night|dawn}.png`，共八张 1536×1024 图片；与原始背景保持相同室内构图。自定义照片不随天气替换。

天气：[Open-Meteo](https://open-meteo.com/)，[接口文档](https://open-meteo.com/en/docs)。城市：[Open-Meteo Geocoding](https://open-meteo.com/en/docs/geocoding-api)，数据来自 [GeoNames](https://www.geonames.org/)。使用免费非商业接口；面向商业用途时应按服务商要求配置合适的接口方案。数据归属遵循服务商的 CC BY 4.0 条款。

## 图片生成记录

以上位图通过内置 imagegen 生成与编辑，没有使用外部 API 或用户密钥。代码原生钟盘没有使用图片生成。启动器工具将最终图标转换为 Android 各密度资源与 Windows ICO。

### 图标初稿

参考 `assets/branding/app_icon_legacy.png`，透明背景：

> Edit this legacy app icon for a calm modern productivity app named Dayloom, without any text. Preserve its recognizable overlapping task-grid and broad sweeping checkmark which also forms a leaf-like curved enclosure. Replace the pink lines with muted champagne gold and soft sage task lines; use deep forest teal for the checkmark, warm ivory for the rounded-square tile, an extremely subtle soft material highlight, restrained elegant contrast. Clean precise edges, strong readable silhouette at 32px, no extra symbols, no book or lamp, no letters, no border stroke around the tile, no exaggerated gloss or 3D perspective. The rounded-square icon tile fills about 90% of this 1024x1024 square canvas, with genuinely transparent outside corners/margins. Keep the composition frontal and centered. This is the single final app icon, not an icon sheet or mockup.

### 图标清理

参考 `assets/branding/dayloom_icon_draft.png`，透明背景：

> Clean up only the transparent perimeter of this app icon. Preserve the entire ivory rounded-square tile, its champagne gold task-grid, sage lines, teal sweeping check/leaf, exact colors, design and composition. Remove ALL detached stray pixels, white flecks, noise and specks outside the tile. Make the rounded-square edge perfectly smooth and crisp, with a clean antialiased outline and genuinely transparent empty margins. No added border, halo, glow or new detail. Production launcher icon, 1024x1024.

### 天气背景

每张参考对应原来的 `assets/backgrounds/alpine_{phase}.png`，不透明背景。下列模板各生成一次 rain/snow × noon/dusk/night/dawn 组合；花括号处按下方映射替换：

> Use case: lighting-weather edit. Final production app background, same 1536x1024 landscape aspect ratio. Change only the weather outdoors in this exact reference photograph to {weather}. Preserve exactly the room, window geometry, desk, books, cup, notebook, pen, plants, vase, view composition, perspective and all object locations. Preserve the existing {phase} and the warm indoor lighting. Photorealistic, refined quiet study atmosphere, subtle natural weather, keep the foreground desk crisp and dry. No people, text, logos, interface elements, dramatic lightning, impossible heavy storm or particles inside the room.

| 变量 | 替换文字 |
| --- | --- |
| rain | gentle steady rainfall with fine visible rain trails and a few realistic droplets on the window glass, moody low clouds, damp cool mountains and forest |
| snow | gentle snowfall with small naturally falling snowflakes outdoors, a softly snow-covered forest and hazy snowy mountains |
| noon | daytime light, replacing clear blue sky with soft bright overcast daylight |
| dusk | sunset time, muted warm peach amber sunset glow filtering through rainy or snowy clouds, not a clear sky |
| night | night time, cloudy dark blue sky WITHOUT stars and warm indoor light |
| dawn | early sunrise time, gentle pale peach dawn light through clouds |

## 版本验证

v1.0.10 完整 Flutter 回归测试 231 项通过；最后的名称同步另复测 AI 与天气资源 29 项通过。全项目静态检查无错误，保留 43 条既有提示与警告。Windows 与 Android 发布构建成功，APK 的三种架构内容与本地最终构建一致，签名与上一版一致。Windows 安装器保持原 AppId 与目录。

Android 16 模拟器验证最终 APK 覆盖安装、主设置入口、正计时暂停冻结、悬浮钟盘拖动及点击返回。截图保存在本地 build/pomodoro-qa/dayloom-*.png。定位权限被拒绝时展示手动城市入口；未采集或发送用户设备位置。自动定位使用单次定位流程与注入位置的服务测试覆盖，尚未覆盖各品牌真机与 Windows 定位硬件。
