# Todo App

一个功能丰富的待办事项管理应用，使用 Flutter 开发，支持 Windows 和 Android 平台。

## 使用方法
- Windows：拉取代码后，todo_app_v5为最新版本的已经打包好的文件夹，直接放在本地，点击文件夹中的.exe文件即可在本地运行。
- Android：下载其中的app.apk文件，无视风险安装即可，app的使用教程见视频：https://www.bilibili.com/video/BV1p99yBYEcP?vd_source=391ef5a06586cdb72b7afc9fdad35b3b  
（该视频录制时还不包含备忘录功能）

## 功能特性

### 核心功能
- **任务管理** - 创建和管理一次性任务和每日打卡习惯
- **任务类型区分**
  - 一次性任务 (One-Time)：完成后第二天不再显示
  - 每日重复任务 (Recurring)：每天自动重置，持续显示
- **课程表导入** - 支持从 Excel 文件导入课程安排
- **备忘录** - 快速记录笔记和想法
- **数据持久化** - 使用 Isar 数据库本地存储

### 游戏化元素
- **连续打卡统计** - 显示连续完成任务的天数
- **热力图** - 可视化展示每日完成情况
- **完成动画** - 完成所有任务时播放庆祝动画
- **音效反馈** - 点击完成时播放提示音

### 平台支持
- Windows 桌面应用
- Android 移动应用（支持桌面小组件）

## 技术栈

- **框架**: Flutter 3.x
- **语言**: Dart
- **数据库**: Isar (高性能 Flutter 数据库)
- **主要依赖**:
  - `window_manager` - 窗口管理
  - `shared_preferences` - 轻量级存储
  - `flutter_heatmap_calendar` - 热力图日历
  - `confetti` - 庆祝动画
  - `audioplayers` - 音效播放
  - `excel_wps` - Excel 文件解析
  - `file_picker` - 文件选择器
  - `home_widget` - Android 桌面小组件
  - `flutter_markdown` - Markdown 渲染

## 开始使用

### 环境要求

- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Windows 10/11 或 Android 5.0+

### 安装步骤

1. 克隆仓库
```bash
git clone https://github.com/your-username/todo_app.git
cd todo_app
```

2. 安装依赖
```bash
flutter pub get
```

3. 生成代码 (Isar 数据库模型)
```bash
flutter pub run build_runner build
```

4. 运行应用
```bash
# Windows
flutter run -d windows

# Android
flutter run -d android
```

### 构建 Release 版本

```bash
# Windows
flutter build windows --release

# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release
```

## 项目结构

```
lib/
├── main.dart                      # 应用入口
├── models/                        # 数据模型
│   ├── course.dart               # 课程模型
│   ├── daily_completion.dart     # 每日完成记录
│   ├── memo.dart                 # 备忘录模型
│   └── todo_item.dart            # 待办事项模型
├── pages/                         # 页面
│   ├── memo_page.dart            # 备忘录页面
│   ├── schedule_page.dart        # 课程表页面
│   └── statistics_page.dart      # 统计页面
└── services/                      # 服务层
    ├── autostart_service.dart    # 自动启动服务
    ├── course_import_service.dart # 课程导入
    ├── course_service.dart       # 课程管理
    ├── excel_preprocessor.dart   # Excel 预处理
    ├── gamification_service.dart # 游戏化服务
    ├── isar_service.dart         # 数据库服务
    ├── memo_service.dart         # 备忘录服务
    └── widget_service.dart       # 小组件服务
```

## 使用说明

### 添加任务
1. 点击添加按钮创建新任务
2. 选择任务类型（一次性/每日重复）
3. 设置任务描述和可选时间
4. 保存任务

### 导入课程表
1. 进入课程表页面
2. 点击导入按钮
3. 选择 Excel 文件 (.xlsx)
4. 系统自动解析并导入课程

### 查看统计
- 热力图显示每日完成情况
- 连续打卡天数统计
- 任务完成率分析

## 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 致谢

- [Flutter](https://flutter.dev/) - UI 框架
- [Isar](https://isar.dev/) - 数据库
- 所有依赖库的作者

---

如有问题或建议，请提交 [Issue](https://github.com/your-username/todo_app/issues)
