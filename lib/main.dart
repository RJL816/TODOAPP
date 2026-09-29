import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'services/isar_service.dart';
import 'services/backup_service.dart';
import 'services/gamification_service.dart';
import 'services/autostart_service.dart';
import 'services/course_service.dart';
import 'services/widget_service.dart';
import 'services/memo_service.dart';
import 'services/reminder_service.dart';
import 'services/pomodoro_service.dart';
import 'services/focus_analytics_service.dart';
import 'services/training_service.dart';
import 'services/diet_service.dart';
import 'services/ai_service.dart';
import 'services/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'ui/ai_assistant.dart';
import 'services/expense_service.dart';
import 'models/class_time_config.dart';
import 'models/course.dart';
import 'models/diet_log.dart';
import 'models/expense.dart';
import 'models/pomodoro_session.dart';
import 'models/todo_item.dart';
import 'models/training.dart';
import 'pages/statistics_page.dart';
import 'pages/plan_page.dart';
import 'pages/memo_page.dart';
import 'pages/pomodoro_page.dart';
import 'pages/focus_insights_page.dart';
import 'pages/fitness_page.dart';
import 'pages/diet_page.dart';
import 'pages/expense_page.dart';
import 'pages/more_page.dart';
import 'pages/record_hub_page.dart';
import 'ui/app_theme.dart';
import 'ui/ambient_backdrop.dart';
import 'ui/ambient_palette.dart';
import 'ui/ambient_reading_theme.dart';
import 'ui/window_class.dart';
import 'ui/glass_panel.dart';
import 'ui/page_frame.dart';

// ==================== Windows 窗口状态持久化 ====================

const String _kWindowWidth = 'window_width';
const String _kWindowHeight = 'window_height';
const String _kWindowX = 'window_x';
const String _kWindowY = 'window_y';
const String _kWindowMaximized = 'window_maximized';
const String _kAlwaysOnTopKey = 'window_always_on_top';
const String _kWindowSizeLayoutVersion = 'window_size_layout_version';
const Size _kWindowMinSize = Size(420, 560);
const Size _kLegacyWindowDefaultSize = Size(960, 720);

Size _recommendedWindowSize(Size available) {
  final width = (available.width * .76).clamp(760.0, 1280.0);
  final height = (available.height * .86).clamp(640.0, 880.0);
  final maxWidth = available.width >= _kWindowMinSize.width + 32
      ? available.width - 32
      : _kWindowMinSize.width;
  final maxHeight = available.height >= _kWindowMinSize.height + 32
      ? available.height - 32
      : _kWindowMinSize.height;
  return Size(
    width.clamp(_kWindowMinSize.width, maxWidth).toDouble(),
    height.clamp(_kWindowMinSize.height, maxHeight).toDouble(),
  );
}

/// 恢复上次的窗口大小/位置并显示。
/// 注意：不调用 setAsFrameless——它会连原生可调边框一起去掉，导致窗口无法缩放；
/// TitleBarStyle.hidden 只隐藏系统标题栏，保留拖拽边缘调整大小的能力。
Future<void> _restoreAndShowWindow() async {
  final prefs = await SharedPreferences.getInstance();
  final w = prefs.getDouble(_kWindowWidth);
  final h = prefs.getDouble(_kWindowHeight);
  final x = prefs.getDouble(_kWindowX);
  final y = prefs.getDouble(_kWindowY);
  final maximized = prefs.getBool(_kWindowMaximized) ?? false;
  Size available;
  try {
    final display = await ScreenRetriever.instance.getPrimaryDisplay();
    available = display.visibleSize ?? display.size;
  } catch (_) {
    available = const Size(1440, 900);
  }
  final recommendedSize = _recommendedWindowSize(available);

  final hasSize = w != null &&
      h != null &&
      w >= _kWindowMinSize.width &&
      h >= _kWindowMinSize.height;
  final legacyDefault = prefs.getInt(_kWindowSizeLayoutVersion) == null &&
      w == _kLegacyWindowDefaultSize.width &&
      h == _kLegacyWindowDefaultSize.height;
  // 记忆的尺寸可能来自分辨率更高的显示器，恢复时收敛到当前屏幕范围，避免越界
  final remembered = hasSize && !legacyDefault ? Size(w, h) : recommendedSize;
  final size = Size(
    remembered.width.clamp(_kWindowMinSize.width, recommendedSize.width),
    remembered.height.clamp(_kWindowMinSize.height, recommendedSize.height),
  );
  if (legacyDefault) {
    await prefs.setInt(_kWindowSizeLayoutVersion, 1);
  }

  final windowOptions = WindowOptions(
    size: size,
    minimumSize: _kWindowMinSize,
    center: x == null || y == null || legacyDefault,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (x != null && y != null && !legacyDefault) {
      await windowManager
          .setPosition(await _clampToVisibleScreen(Offset(x, y)));
    }
    if (maximized) {
      await windowManager.maximize();
    }
    await windowManager.show();
    await windowManager.focus();
  });
}

/// 把恢复的窗口位置夹取到可见屏幕范围内：
/// 至少保证标题栏区域（左上角 120×40）落在某块屏幕内，否则退回主屏幕。
Future<Offset> _clampToVisibleScreen(Offset pos) async {
  try {
    final retriever = ScreenRetriever.instance;
    final displays = await retriever.getAllDisplays();
    final visible = displays.any((d) {
      final left = d.visiblePosition?.dx ?? 0;
      final top = d.visiblePosition?.dy ?? 0;
      final size = d.visibleSize ?? d.size;
      return pos.dx + 120 > left &&
          pos.dx < left + size.width &&
          pos.dy + 40 > top &&
          pos.dy < top + size.height;
    });
    if (visible) return pos;

    final primary = await retriever.getPrimaryDisplay();
    final left = primary.visiblePosition?.dx ?? 0;
    final top = primary.visiblePosition?.dy ?? 0;
    return Offset(left + 40, top + 40);
  } catch (_) {
    return pos; // 屏幕信息获取失败时保守使用原位置
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 只在 Windows 平台初始化窗口管理器
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await _restoreAndShowWindow();
  }

  // 初始化中文日期格式
  await initializeDateFormatting('zh_CN');

  // 在 Isar.open（自动迁移 schema）之前，先完成旧库的备份（详见 BackupService）
  final autoBackup = await BackupService.instance.ensureBackupBeforeOpen();

  // 初始化数据库
  await IsarService.instance.init();

  // 迁移后验证：真实库条数应与备份时统计一致；不一致时备份已保留可回退
  if (autoBackup != null) {
    final verified = await BackupService.instance
        .verifyAfterOpen(IsarService.instance.isar, autoBackup);
    debugPrint(
      '自动备份${autoBackup.success ? '完成（${autoBackup.path}）' : '失败：${autoBackup.failedReason}'}，'
      '迁移后验证${verified ? '通过' : '未通过'}',
    );
  }

  // 初始化课程服务
  await CourseService.instance.init(IsarService.instance.isar);

  // 初始化备忘录服务
  MemoService.instance.init(IsarService.instance.isar);

  // 初始化游戏化服务
  await GamificationService.instance.init();

  // 初始化开机自启动服务（内部已有平台判断）
  await AutoStartService.instance.init();

  // 初始化桌面小部件服务（Android）
  await WidgetService.instance.initialize();
  // 同步考试数据到小部件
  if (Platform.isAndroid) {
    final exams = await CourseService.instance.getAllExams();
    await WidgetService.instance.syncExams(exams);
  }

  // 初始化提醒服务并全量重排（Android 用系统排程；Windows 依赖托盘驻留）
  await ReminderService.instance.init();
  await ReminderService.instance.rescheduleAll();

  // 初始化番茄钟（持久化目标结束时刻，恢复进行中的计时）
  await PomodoroService.instance.init();

  // 初始化健身服务（注册训练提醒排程）
  await TrainingService.instance.init();

  // Windows：拦截关闭按钮（驻留托盘 or 真退出由设置决定）
  if (Platform.isWindows) {
    await windowManager.setPreventClose(true);
  }

  runApp(const TodoApp());
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '学习桌',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // 中文本地化：日期/时间选择器等 Material 组件随系统语言显示
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      locale: const Locale('zh', 'CN'),
      home: const TodoHomePage(),
    );
  }
}

class TodoHomePage extends StatefulWidget {
  const TodoHomePage({super.key});

  @override
  State<TodoHomePage> createState() => _TodoHomePageState();
}

class _TodoHomePageState extends State<TodoHomePage>
    with WindowListener, TrayListener {
  final IsarService _db = IsarService.instance;
  int _currentIndex = 0; // 底部导航栏当前索引
  int _statisticsVersion = 0;
  int _planVersion = 0;
  int _moreVersion = 0;
  List<TodoItem> _todos = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _quickInputFocus = FocusNode();
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;

  // 任务分类选择：默认为生活
  TaskCategory _selectedCategory = TaskCategory.life;

  /// 快速添加的任务类型：一次性 / 长久习惯 / DDL
  String _quickKind = 'oneTime';

  /// 快速添加里暂存的截止时间（DDL 模式；添加任务时带入并自动到点提醒）
  DateTime? _quickDeadline;

  String get _quickKindLabel {
    switch (_quickKind) {
      case 'recurring':
        return '长久习惯';
      case 'ddl':
        return _quickDeadline == null
            ? 'DDL · 选择截止时间'
            : 'DDL · 截止 $_quickDeadlineLabel';
      default:
        return '一次性';
    }
  }

  bool _showCompleted = false;
  bool _windowMaximized = false;
  bool _focusImmersive = false;
  bool _navExpanded = false;
  bool _showAmbientBackground = true;
  static const String _kAmbientBackgroundKey = 'show_ambient_background';
  static const String _kFontColorModeKey = 'ambient_font_color_mode';
  static const String _kFontColorValueKey = 'ambient_font_color';
  static const String _kAmbientSceneKey = 'ambient_scene_index';
  static const String _kAmbientSceneAutoKey = 'ambient_scene_auto';
  static const String _kAmbientSceneCatalogVersionKey =
      'ambient_scene_catalog_version';
  static const String _kAmbientCustomPathKey = 'ambient_custom_path';
  static const String _kAmbientShadeKey = 'ambient_shade';
  static const String _kGlassClarityKey = 'glass_clarity';
  static const String _kAmbientCustomPortraitXKey = 'ambient_custom_portrait_x';
  int _ambientSceneIndex = 0;
  bool _ambientSceneAuto = true;
  int _ambientSceneRequest = 0;
  int _lastAutoSceneIndex = AmbientBackdrop.sceneForHour(DateTime.now().hour);
  Timer? _ambientClockTimer;
  String? _ambientCustomPath;
  double _ambientShade = .10;

  // 用户自定义字体颜色（配自定义背景用）：auto 跟随场景；white/black/custom 为覆盖
  String _fontColorMode = 'auto';
  int? _fontColorValue;
  AiConfig _aiConfig = const AiConfig();
  bool _alwaysOnTop = false;
  String _appVersion = '';
  ReleaseInfo? _newRelease;

  Timer? _updateCheckTimer;

  /// 启动静默检查更新：发现新版时提示一次（忽略后同版本不再打扰）
  Future<void> _silentCheckForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final release = await UpdateService.instance.fetchLatestRelease();
      if (release == null || !mounted) return;
      final dismissed =
          (await SharedPreferences.getInstance()).getString('update_dismissed_version');
      if (UpdateService.isNewerVersion(release.version, info.version) &&
          dismissed != release.version) {
        await (await SharedPreferences.getInstance())
            .setString('update_dismissed_version', release.version);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('发现新版本 v${release.version}，可前往设置-关于与更新下载'),
          action: SnackBarAction(
              label: '前往下载',
              onPressed: () => launchUrl(Uri.parse(release.pageUrl),
                  mode: LaunchMode.externalApplication),
            ),
        ));
      }
    } catch (_) {
      // 静默检查失败不打扰用户
    }
  }

  Future<void> _setAlwaysOnTop(bool value) async {
    await windowManager.setAlwaysOnTop(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAlwaysOnTopKey, value);
    if (mounted) setState(() => _alwaysOnTop = value);
  }

  double _glassClarity = GlassTuning.defaultClarity;
  double _ambientCustomPortraitX = 0;

  // 今天概览：下一节课 / 生活数据 / 今日轨迹（Day Arc）
  _TodayBrief? _brief;
  Future<List<_RecentActivity>>? _recentFuture;

  // 任务分类筛选：null表示显示全部（选择会记忆，下次启动恢复）
  TaskCategory? _selectedCategoryFilter;
  static const String _kCategoryFilterKey = 'todo_category_filter';

  // 游戏化相关状态
  int _currentStreak = 0;
  bool _shouldPlayConfetti = false;

  // 开机自启动状态
  bool _autoStartEnabled = false;

  // Windows 托盘驻留：关闭按钮 = 隐藏到托盘（提醒继续可用），托盘菜单可真退出
  static const String _kTrayResidentKey = 'tray_resident';
  bool _trayResident = true;
  bool _forceExit = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    if (Platform.isWindows) _syncWindowMaximized();
    _loadTodos();
    _loadStreak();
    _loadAutoStartState();
    _loadCategoryFilter();
    _loadAmbientBackground();
    _updateCheckTimer = Timer(const Duration(seconds: 8), _silentCheckForUpdate);
    // 窗口置顶状态恢复（Windows）
    if (Platform.isWindows) {
      SharedPreferences.getInstance()
          .then((prefs) => prefs.getBool(_kAlwaysOnTopKey) ?? false)
          .then((onTop) async {
        if (onTop) await windowManager.setAlwaysOnTop(true);
        if (mounted) setState(() => _alwaysOnTop = onTop);
      });
    }
    _loadAiConfig();
    _ambientClockTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!_ambientSceneAuto || !mounted) return;
      final scene = AmbientBackdrop.sceneForHour(DateTime.now().hour);
      if (scene != _lastAutoSceneIndex) {
        await _precacheAmbientScene(scene);
        if (mounted && _ambientSceneAuto) {
          setState(() => _lastAutoSceneIndex = scene);
        }
      }
    });
    _initTrayAndNavigation();
  }

  Future<void> _loadAiConfig() async {
    final config = await AiService.instance.loadConfig();
    if (mounted) setState(() => _aiConfig = config);
  }

  Future<void> _loadAmbientBackground() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      _fontColorMode = prefs.getString(_kFontColorModeKey) ?? 'auto';
      _fontColorValue = prefs.getInt(_kFontColorValueKey);
      final customPath = prefs.getString(_kAmbientCustomPathKey);
      final validCustom = customPath != null && File(customPath).existsSync();
      final selected = prefs.getInt(_kAmbientSceneKey) ?? 0;
      final oldCatalog = prefs.getInt(_kAmbientSceneCatalogVersionKey) == null;
      // In the three-scene catalog, index 3 meant a personal photo.
      final restoredIndex = AmbientBackdrop.restoreSceneIndex(selected,
          oldCatalog: oldCatalog, hasCustom: validCustom);
      setState(() {
        _showAmbientBackground = prefs.getBool(_kAmbientBackgroundKey) ?? true;
        _ambientSceneAuto = prefs.getBool(_kAmbientSceneAutoKey) ??
            !prefs.containsKey(_kAmbientSceneKey);
        _lastAutoSceneIndex = AmbientBackdrop.sceneForHour(DateTime.now().hour);
        _ambientCustomPath = validCustom ? customPath : null;
        _ambientSceneIndex = restoredIndex;
        _ambientShade =
            (prefs.getDouble(_kAmbientShadeKey) ?? .10).clamp(.04, .24);
        _glassClarity =
            (prefs.getDouble(_kGlassClarityKey) ?? GlassTuning.defaultClarity)
                .clamp(0.0, 1.0);
        _ambientCustomPortraitX =
            (prefs.getDouble(_kAmbientCustomPortraitXKey) ?? 0)
                .clamp(-1.0, 1.0);
      });
      GlassTuning.clarity.value = _glassClarity;
      if (oldCatalog) {
        if (restoredIndex != selected) {
          await prefs.setInt(_kAmbientSceneKey, restoredIndex);
        }
        await prefs.setInt(_kAmbientSceneCatalogVersionKey, 1);
      }
    }
  }

  Future<void> _setAmbientBackground(bool value) async {
    setState(() => _showAmbientBackground = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAmbientBackgroundKey, value);
  }

  Future<void> _setAmbientScene(int index) async {
    final request = ++_ambientSceneRequest;
    await _precacheAmbientScene(index);
    if (!mounted || request != _ambientSceneRequest) return;
    setState(() {
      _ambientSceneIndex = index;
      _ambientSceneAuto = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAmbientSceneKey, index);
    await prefs.setInt(_kAmbientSceneCatalogVersionKey, 1);
    await prefs.setBool(_kAmbientSceneAutoKey, false);
  }

  Future<void> _setAmbientSceneAuto(bool value) async {
    final request = ++_ambientSceneRequest;
    if (value) {
      await _precacheAmbientScene(
          AmbientBackdrop.sceneForHour(DateTime.now().hour));
    }
    if (!mounted || request != _ambientSceneRequest) return;
    setState(() {
      _ambientSceneAuto = value;
      _lastAutoSceneIndex = AmbientBackdrop.sceneForHour(DateTime.now().hour);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAmbientSceneAutoKey, value);
  }

  int get _effectiveAmbientSceneIndex =>
      _ambientSceneAuto ? _lastAutoSceneIndex : _ambientSceneIndex;

  Future<void> _precacheAmbientScene(int index) async {
    if (index < 0 || index >= AmbientBackdrop.sceneAssets.length) return;
    try {
      await precacheImage(
          AssetImage(AmbientBackdrop.sceneAssets[index]), context);
    } catch (_) {
      // A failed prefetch should not prevent selecting the background.
    }
  }

  Future<void> _setAmbientShade(double shade) async {
    setState(() => _ambientShade = shade);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kAmbientShadeKey, shade);
  }

  void _previewGlassClarity(double value) {
    setState(() => _glassClarity = value);
    GlassTuning.clarity.value = value;
  }

  Future<void> _saveGlassClarity(double value) async {
    _previewGlassClarity(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kGlassClarityKey, value);
  }

  Future<void> _setAmbientCustomPortraitX(double x) async {
    setState(() => _ambientCustomPortraitX = x);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kAmbientCustomPortraitXKey, x);
  }

  Future<String?> _importAmbientScene() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final sourcePath = picked?.files.single.path;
    if (sourcePath == null) return null;
    final source = File(sourcePath);
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}'
      '${Platform.pathSeparator}ambient_backgrounds',
    );
    await directory.create(recursive: true);
    final extension = sourcePath.split('.').last.toLowerCase();
    final target = File('${directory.path}${Platform.pathSeparator}'
        'personal_${DateTime.now().millisecondsSinceEpoch}.$extension');
    await source.copy(target.path);
    if (!mounted) return target.path;
    setState(() {
      _ambientCustomPath = target.path;
      _ambientSceneIndex = AmbientBackdrop.sceneAssets.length;
      _ambientSceneAuto = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAmbientCustomPathKey, target.path);
    await prefs.setInt(_kAmbientSceneKey, _ambientSceneIndex);
    await prefs.setInt(_kAmbientSceneCatalogVersionKey, 1);
    await prefs.setBool(_kAmbientSceneAutoKey, false);
    return target.path;
  }

  // Windows 托盘初始化 + 点击提醒跳转监听
  Future<void> _initTrayAndNavigation() async {
    // 点击提醒 → 切到对应页面并唤起窗口
    ReminderService.instance.pendingNavigation
        .addListener(_onReminderNavigation);

    if (!Platform.isWindows) return;
    final prefs = await SharedPreferences.getInstance();
    _trayResident = prefs.getBool(_kTrayResidentKey) ?? true;

    try {
      final iconPath = await ReminderService.instance.prepareTrayIcon();
      if (iconPath != null) {
        trayManager.addListener(this);
        await trayManager.setIcon(iconPath);
        await trayManager.setToolTip('待办事项（关闭后驻留托盘，提醒继续可用）');
        final menu = Menu(
          items: [
            MenuItem(key: 'show', label: '显示主窗口'),
            MenuItem.separator(),
            MenuItem(key: 'exit', label: '退出（提醒将不可用）'),
          ],
        );
        await trayManager.setContextMenu(menu);
      }
    } catch (e) {
      debugPrint('托盘初始化失败（不影响其他功能）: $e');
    }
  }

  void _onReminderNavigation() {
    final target = ReminderService.instance.pendingNavigation.value;
    if (target == null) return;
    setState(() => _currentIndex = target);
    ReminderService.instance.pendingNavigation.value = null;
    if (Platform.isWindows) {
      windowManager.show();
      windowManager.focus();
    }
  }

  // 恢复上次使用的分类筛选
  Future<void> _loadCategoryFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(_kCategoryFilterKey);
      if (name == null || name.isEmpty) return;
      final match =
          TaskCategory.values.where((c) => c.name == name).firstOrNull;
      if (match != null && mounted) {
        setState(() => _selectedCategoryFilter = match);
      }
    } catch (_) {
      // 读取失败显示全部
    }
  }

  Future<void> _saveCategoryFilter(TaskCategory? filter) async {
    _selectedCategoryFilter = filter;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCategoryFilterKey, filter?.name ?? '');
    } catch (_) {}
  }

  // 加载开机自启动状态
  Future<void> _loadAutoStartState() async {
    if (Platform.isWindows) {
      final enabled = await AutoStartService.instance.isAutoStartEnabled();
      if (mounted) {
        setState(() => _autoStartEnabled = enabled);
      }
    }
  }

  // 切换开机自启动
  Future<void> _toggleAutoStart(bool value) async {
    if (Platform.isWindows) {
      final success = await AutoStartService.instance.setAutoStart(value);
      if (mounted && success) {
        setState(() => _autoStartEnabled = value);
      }
    }
  }

  // 显示设置对话框
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => _SettingsDialog(
        autoStartEnabled: _autoStartEnabled,
        onAutoStartChanged: _toggleAutoStart,
        trayResident: _trayResident,
        onTrayResidentChanged: (v) => setState(() => _trayResident = v),
        showAmbientBackground: _showAmbientBackground,
        fontColorMode: _fontColorMode,
        fontColorValue: _fontColorValue,
        onFontColorChanged: _setFontColor,
        onAiConfigChanged: () => _loadAiConfig(),
        alwaysOnTop: _alwaysOnTop,
        onAlwaysOnTopChanged: _setAlwaysOnTop,
        onAmbientBackgroundChanged: _setAmbientBackground,
        ambientSceneIndex: _ambientSceneIndex,
        ambientSceneAuto: _ambientSceneAuto,
        ambientCustomPath: _ambientCustomPath,
        ambientShade: _ambientShade,
        glassClarity: _glassClarity,
        ambientCustomPortraitX: _ambientCustomPortraitX,
        onAmbientSceneChanged: _setAmbientScene,
        onAmbientSceneAutoChanged: _setAmbientSceneAuto,
        onAmbientShadeChanged: _setAmbientShade,
        onGlassClarityPreview: _previewGlassClarity,
        onGlassClarityChanged: _saveGlassClarity,
        onAmbientCustomPortraitXChanged: _setAmbientCustomPortraitX,
        onImportAmbientScene: _importAmbientScene,
        onDataRestored: () {
          // 恢复数据后刷新首页；其余页面建议重启应用刷新
          _loadTodos();
          _loadStreak();
          ReminderService.instance.requestReschedule();
        },
      ),
    );
  }

  @override
  void dispose() {
    _ambientClockTimer?.cancel();
    _updateCheckTimer?.cancel();
    windowManager.removeListener(this);
    if (Platform.isWindows) {
      trayManager.removeListener(this);
    }
    ReminderService.instance.pendingNavigation
        .removeListener(_onReminderNavigation);
    _controller.dispose();
    _quickInputFocus.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (Platform.isWindows) {
      // 托盘驻留：关闭按钮 = 隐藏窗口（进程保留，提醒继续可用）
      if (_trayResident && !_forceExit) {
        await windowManager.hide();
        return;
      }
      try {
        // 记住窗口状态（最大化时只记标志，避免把最大化时的位置存成"普通位置"）
        final prefs = await SharedPreferences.getInstance();
        final maximized = await windowManager.isMaximized();
        if (maximized) {
          await prefs.setBool(_kWindowMaximized, true);
        } else {
          final size = await windowManager.getSize();
          final position = await windowManager.getPosition();
          await prefs.setDouble(_kWindowWidth, size.width);
          await prefs.setDouble(_kWindowHeight, size.height);
          await prefs.setDouble(_kWindowX, position.dx);
          await prefs.setDouble(_kWindowY, position.dy);
          await prefs.setBool(_kWindowMaximized, false);
        }
      } catch (_) {
        // 保存失败不阻止关闭
      }
    }
    await windowManager.destroy();
  }

  // ==================== 托盘交互（Windows） ====================

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键弹出托盘菜单（tray_manager 自动处理）
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'exit') {
      _exitApp();
    }
  }

  // 真正退出：保存窗口状态并销毁
  Future<void> _exitApp() async {
    _forceExit = true;
    try {
      await trayManager.destroy();
    } catch (_) {}
    try {
      if (await windowManager.isVisible()) {
        await windowManager.close(); // 走 onWindowClose 的保存逻辑
      } else {
        // 隐藏状态下直接保存并销毁
        if (Platform.isWindows) {
          final maximized = await windowManager.isMaximized();
          final prefs = await SharedPreferences.getInstance();
          if (!maximized) {
            final size = await windowManager.getSize();
            final position = await windowManager.getPosition();
            await prefs.setDouble(_kWindowWidth, size.width);
            await prefs.setDouble(_kWindowHeight, size.height);
            await prefs.setDouble(_kWindowX, position.dx);
            await prefs.setDouble(_kWindowY, position.dy);
          }
          await prefs.setBool(_kWindowMaximized, maximized);
        }
        await windowManager.destroy();
      }
    } catch (_) {
      try {
        await windowManager.destroy();
      } catch (_) {}
    }
  }

  Future<void> _loadTodos() async {
    setState(() => _isLoading = true);
    // 获取选中日期的任务（包括每日习惯）
    final todos = await _db.getTodosForDate(_selectedDate);
    if (!mounted) return;
    final recentFuture = _isToday ? _loadRecentActivity(DateTime.now()) : null;
    setState(() {
      _todos = todos;
      _isLoading = false;
      _recentFuture = recentFuture;
    });
    if (_isToday) _loadTodayBrief();
  }

  Future<void> _addTodo(String text) async {
    if (text.trim().isEmpty) return;
    final isDdl = _quickKind == 'ddl';
    final deadline = isDdl ? _quickDeadline : null;
    final todo = TodoItem.create(
      title: text.trim(),
      date: _selectedDate, // 使用选中的日期
      // DDL 任务固定为一次性：有明确截止的事不存在"每日重复"
      taskType:
          _quickKind == 'recurring' ? TaskType.recurring : TaskType.oneTime,
      category: _selectedCategory, // 使用选中的分类
      deadline: deadline,
      // 设了截止时间即自动到点提醒（正好在截止时刻，无提前量）
      enableReminder: deadline != null,
      remindBeforeMinutes: deadline != null ? 0 : 15,
    );
    await _db.addTodo(todo);
    _controller.clear();
    setState(() => _quickDeadline = null);
    _loadTodos();
    ReminderService.instance.requestReschedule();
  }

  /// 选择快速添加的截止时间：先选日期，再选时间；取消则保持原值
  Future<void> _pickQuickDeadline() async {
    final now = DateTime.now();
    final initial = _quickDeadline ?? now.add(const Duration(hours: 2));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    setState(() {
      _quickDeadline = time == null
          ? DateTime(date.year, date.month, date.day, 23, 59)
          : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String get _quickDeadlineLabel {
    final deadline = _quickDeadline;
    if (deadline == null) return '';
    final p2 = (int v) => v.toString().padLeft(2, '0');
    return '${deadline.month}月${deadline.day}日 ${p2(deadline.hour)}:${p2(deadline.minute)}';
  }

  Future<void> _toggleTodo(int id) async {
    await _db.toggleTodo(id, _selectedDate); // 传入当前查看的日期

    // 播放音效
    GamificationService.instance.playCheckSound();

    await _loadTodos();
    await _loadStreak();
    await _loadTodayBrief(); // 头部"今天完成了 N 件事"即时刷新

    // 完成状态变化会影响提醒（已完成待办不再提醒）
    ReminderService.instance.requestReschedule();

    // 检查是否所有任务都完成了
    if (_todos.isNotEmpty && _todos.every((todo) => todo.isCompleted)) {
      // 播放庆祝动画
      setState(() => _shouldPlayConfetti = true);
      GamificationService.instance.playAllCompleteSound();

      // 延迟重置动画状态
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() => _shouldPlayConfetti = false);
        }
      });
    }
  }

  // 加载连续打卡天数
  Future<void> _loadStreak() async {
    final streak = await _db.getCurrentStreak();
    if (mounted) {
      setState(() => _currentStreak = streak);
    }
  }

  Future<void> _deleteTodo(int id) async {
    // 删除前确认
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务'),
        content: const Text('确定要删除这个任务吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.deleteTodo(id);
    if (mounted) _loadTodos();
    ReminderService.instance.requestReschedule();
  }

  // 编辑任务
  Future<void> _editTodo(TodoItem todo) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _TodoEditDialog(todo: todo),
    );
    if (saved == true) {
      await _db.updateTodo(todo);
      if (mounted) {
        _loadTodos();
        _loadStreak();
      }
      ReminderService.instance.requestReschedule();
    }
  }

  Future<void> _changeDate(DateTime newDate) async {
    setState(() => _selectedDate = newDate);
    _loadTodos();
  }

  // 根据筛选条件过滤任务
  List<TodoItem> get _filteredTodos {
    if (_selectedCategoryFilter == null) {
      return _todos;
    }
    return _todos
        .where((todo) => todo.category == _selectedCategoryFilter)
        .toList();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  void _startDragging() {
    windowManager.startDragging();
  }

  Future<void> _syncWindowMaximized() async {
    if (!Platform.isWindows) return;
    final maximized = await windowManager.isMaximized();
    if (mounted && _windowMaximized != maximized) {
      setState(() => _windowMaximized = maximized);
    }
  }

  // 顶部按钮、F11 和双击拖拽栏共用同一条最大化/还原路径。
  Future<void> _toggleMaximize() async {
    if (!Platform.isWindows) return;
    final maximized = await windowManager.isMaximized();
    if (maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    if (mounted) setState(() => _windowMaximized = !maximized);
  }

  Future<void> _setFocusImmersive(bool value) async {
    if (!mounted) return;
    setState(() => _focusImmersive = value);
    if (!Platform.isWindows) {
      await SystemChrome.setEnabledSystemUIMode(
          value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _windowMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _windowMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final concentrating = _currentIndex == 5;
    final immersiveFocus = concentrating && _focusImmersive;
    final ambient = _showAmbientBackground;

    return AmbientPaletteScope(
      palette: _ambientPalette,
      enabled: ambient,
      foregroundOverride: ambient && _fontColorMode != 'auto'
          ? _ambientPalette.primaryText
          : null,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (!Platform.isWindows || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.f11) {
            _toggleMaximize();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (immersiveFocus) {
              _setFocusImmersive(false);
              return KeyEventResult.handled;
            }
            if (_windowMaximized) {
              _toggleMaximize();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: ConfettiCelebrationWidget(
          play: _shouldPlayConfetti,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  ambient ? Brightness.light : Brightness.dark,
              statusBarBrightness: ambient ? Brightness.dark : Brightness.light,
            ),
            child: RepaintBoundary(
              child: Scaffold(
                extendBody: true,
                body: Stack(
                  children: [
                    Positioned.fill(child: _buildAppBackdrop()),
                    if (!Platform.isWindows && !immersiveFocus)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: MediaQuery.paddingOf(context).top,
                        child: ColoredBox(
                          color: ambient
                              ? const Color(0x66172936)
                              : AppColors.canvas.withValues(alpha: .92),
                        ),
                      ),
                    Column(
                      children: [
                        // Custom Title Bar (with streak display)
                        if (!immersiveFocus)
                          SafeArea(
                            bottom: false,
                            left: false,
                            right: false,
                            child: _buildTitleBarWithStreak(theme),
                          ),

                        // 今日进度条（只在今日任务页显示）
                        Expanded(
                          child: Row(children: [
                            if (wide && !immersiveFocus)
                              _buildDesktopNav(theme),
                            Expanded(
                                child: IndexedStack(
                              index: _currentIndex,
                              children: [
                                PageFrame(child: _buildTodoListPage(theme)),
                                PageFrame(
                                  maxWidth: 1440,
                                  ambient: ambient,
                                  child: PlanPage(
                                    key: ValueKey(_planVersion),
                                    darkBackground: ambient,
                                  ),
                                ),
                                PageFrame(
                                    ambient: ambient,
                                    child: StatisticsPage(
                                      key: ValueKey(_statisticsVersion),
                                      darkBackground: ambient,
                                      onOpenToday: () => _navigateTo(0),
                                    )),
                                PageFrame(
                                  maxWidth: 1080,
                                  ambient: ambient,
                                  child: RecordHubPage(
                                    darkBackground: ambient,
                                    onOpenMemo: () => _navigateTo(4),
                                    onOpenFitness: () => _navigateTo(6),
                                    onOpenDiet: () => _navigateTo(7),
                                    onOpenExpense: () => _navigateTo(8),
                                    onOpenSummary: () => _navigateTo(9),
                                  ),
                                ),
                                PageFrame(
                                    maxWidth:
                                        double.infinity, // 备忘录满宽：左侧贴导航、右侧直达窗口边界
                                    ambient: ambient,
                                    child: AmbientReadingTheme(
                                      enabled: ambient,
                                      child: const MemoPage(),
                                    )),
                                PomodoroPage(
                                  onExit: () => _navigateTo(0),
                                  onOpenTodo: () => _navigateTo(0),
                                  focusImmersive: _focusImmersive,
                                  onFocusImmersiveChanged: _setFocusImmersive,
                                  inheritBackdrop: _showAmbientBackground,
                                ),
                                PageFrame(
                                    maxWidth: 860,
                                    ambient: ambient,
                                    child: AmbientReadingTheme(
                                      enabled: ambient,
                                      child: const FitnessPage(),
                                    )),
                                PageFrame(
                                    ambient: ambient,
                                    child: AmbientReadingTheme(
                                      enabled: ambient,
                                      child: const DietPage(),
                                    )),
                                PageFrame(
                                    ambient: ambient,
                                    child: AmbientReadingTheme(
                                      enabled: ambient,
                                      child: const ExpensePage(),
                                    )),
                                PageFrame(
                                  maxWidth: 1080,
                                  ambient: ambient,
                                  child: MorePage(
                                    key: ValueKey(_moreVersion),
                                    onOpenMemo: () => _navigateTo(4),
                                    onOpenPomodoro: () => _navigateTo(5),
                                    onOpenFitness: () => _navigateTo(6),
                                    onOpenDiet: () => _navigateTo(7),
                                    onOpenExpense: () => _navigateTo(8),
                                    darkBackground: ambient,
                                    summaryOnly: true,
                                  ),
                                ),
                              ],
                            )),
                          ]),
                        ),
                      ],
                    ),
                    // AI 悬浮球：已配置且非沉浸模式时显示
                    if (_aiConfig.isConfigured && !immersiveFocus)
                      AiFloatingOrb(
                        config: _aiConfig,
                        service: AiService.instance,
                        // 导航高度 56 + 上下留白 16 + 球与底栏间隙 12。
                        minBottom: wide
                            ? 16
                            : 84 + MediaQuery.paddingOf(context).bottom,
                      ),
                  ],
                ),
                bottomNavigationBar:
                    wide || immersiveFocus ? null : _buildBottomNav(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 把用户选择的字体颜色套到场景调色板上（auto = 跟随场景原配色）
  AmbientPalette get _ambientPalette => _applyFontColorOverride(
      AmbientPalette.forScene(_effectiveAmbientSceneIndex));

  AmbientPalette _applyFontColorOverride(AmbientPalette base) {
    switch (_fontColorMode) {
      case 'white':
        return base.withFontColor(
            Colors.white, Colors.white.withValues(alpha: .85));
      case 'black':
        return base.withFontColor(
            const Color(0xFF172A3A), const Color(0xC0172A3A));
      case 'custom':
        if (_fontColorValue != null) {
          final color = Color(_fontColorValue!);
          return base.withFontColor(color, color.withValues(alpha: .85));
        }
        return base;
      default:
        return base;
    }
  }

  void _setFontColor(String mode, int? value) {
    setState(() {
      _fontColorMode = mode;
      _fontColorValue = value;
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_kFontColorModeKey, mode);
      if (value == null) {
        prefs.remove(_kFontColorValueKey);
      } else {
        prefs.setInt(_kFontColorValueKey, value);
      }
    });
  }

  Widget _buildAppBackdrop() {
    if (!_showAmbientBackground) {
      return const ColoredBox(color: AppColors.canvas);
    }
    return AmbientBackdrop(
      compact: MediaQuery.sizeOf(context).width < 680,
      sceneIndex: _effectiveAmbientSceneIndex,
      customPath: _ambientCustomPath,
      customPortraitX: _ambientCustomPortraitX,
      shade: _ambientShade,
    );
  }

  /// 底部导航栏
  Widget _buildBottomNav(ThemeData theme) {
    final nav = BottomNavigationBar(
      currentIndex: _currentIndex == 1
          ? 1
          : _currentIndex == 5
              ? 2
              : _currentIndex == 0 || _currentIndex == 2
                  ? 0
                  : 3,
      onTap: (index) => _navigateTo(const [0, 1, 5, 3][index]),
      // 细长屏底部导航：未选中白色，聚焦到哪页哪项橘色
      selectedItemColor: AppColors.warmAmber,
      unselectedItemColor: _showAmbientBackground
          ? _ambientPalette.secondaryText
          : Colors.white.withValues(alpha: .95),
      backgroundColor: Colors.transparent,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedFontSize: 12,
      unselectedFontSize: 11,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.wb_sunny_outlined),
          label: '今天',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today_outlined),
          label: '计划',
        ),
        BottomNavigationBarItem(
          icon: _FocusGlyph(selected: _currentIndex == 5),
          label: '专注',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.book_outlined),
          label: '生活',
        ),
      ],
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: GlassPanel(
          level: GlassSurfaceLevel.dark,
          radius: 26,
          opacity: .76,
          shadow: true,
          child: nav,
        ),
      ),
    );
  }

  void _navigateTo(int index) {
    final leavingFocusImmersive = index != 5 && _focusImmersive;
    setState(() {
      _currentIndex = index;
      if (index != 5) _focusImmersive = false;
      if (index == 1) _planVersion++;
      if (index == 2) _statisticsVersion++;
      if (index == 3 || index == 9) _moreVersion++;
    });
    if (leavingFocusImmersive && !Platform.isWindows) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (index == 0) {
      _loadTodos();
      _loadStreak();
      _loadAutoStartState();
    }
    if (Platform.isWindows) {
      _syncWindowMaximized();
    }
  }

  /// 左侧浮动玻璃导航栏：脱离边缘、悬浮于环境之上。
  /// 照片背景 = 深墨蓝玻璃；纸面模式 = 中性浅玻璃（避免浅底上过重）。
  Widget _buildDesktopNav(ThemeData theme) {
    final ambient = _showAmbientBackground;
    final collapsed = MediaQuery.sizeOf(context).width < 1180 && !_navExpanded;
    final palette = _ambientPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 16),
      child: DecoratedBox(
        // 阴影画在裁切之外，托起悬浮感
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: ambient ? .22 : .12),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: AppColors.ink.withValues(alpha: .10),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 8 * GlassTuning.blurScale(_glassClarity),
              sigmaY: 8 * GlassTuning.blurScale(_glassClarity),
            ),
            child: Container(
              width: collapsed ? 68 : 204,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: ambient
                      ? [
                          palette.tint.withValues(
                              alpha: (palette.tintOpacity *
                                      1.3 *
                                      GlassTuning.tintScale(_glassClarity))
                                  .clamp(.18, .72)),
                          palette.tint.withValues(
                              alpha: (palette.tintOpacity *
                                      GlassTuning.tintScale(_glassClarity))
                                  .clamp(.14, .64)),
                        ]
                      : [
                          const Color(0xFFF4F2EC).withValues(alpha: .72),
                          const Color(0xFFECE9E0).withValues(alpha: .66),
                        ],
                ),
                border: Border.all(
                    color: ambient
                        ? palette.edge
                        : Colors.white.withValues(alpha: .80)),
                borderRadius: BorderRadius.circular(24),
              ),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    collapsed ? 6 : 12, 14, collapsed ? 6 : 12, 16),
                children: [
                  if (MediaQuery.sizeOf(context).width < 1180)
                    Tooltip(
                      message: collapsed ? '展开侧栏' : '收起侧栏',
                      child: IconButton(
                        onPressed: () =>
                            setState(() => _navExpanded = !_navExpanded),
                        icon: Icon(collapsed
                            ? Icons.menu_open_outlined
                            : Icons.menu_outlined),
                        color: ambient ? palette.primaryText : AppColors.ink,
                      ),
                    ),
                  _navGroupLabel('核心视图', collapsed),
                  _desktopNavItem(theme, 0, '今天', Icons.wb_sunny_outlined),
                  _desktopNavItem(
                      theme, 1, '计划', Icons.calendar_today_outlined),
                  _desktopNavItem(theme, 5, '专注', Icons.timer_outlined),
                  const SizedBox(height: 14),
                  _navGroupLabel('记录与看板', collapsed),
                  _desktopNavItem(theme, 3, '生活', Icons.book_outlined),
                  const SizedBox(height: 14),
                  _navGroupLabel('回顾与数据', collapsed),
                  _desktopNavItem(theme, 2, '周回顾', Icons.insights_outlined),
                  _desktopNavItem(theme, 9, '月度总结', Icons.auto_graph_outlined),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navGroupLabel(String text, bool collapsed) {
    final ambient = _showAmbientBackground;
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        child: Divider(
          height: 1,
          color: ambient ? Colors.white.withValues(alpha: .22) : AppColors.line,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 0, 9),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: ambient ? _ambientPalette.secondaryText : AppColors.muted,
          fontWeight: FontWeight.w600,
          letterSpacing: 2.4,
        ),
      ),
    );
  }

  Widget _desktopNavItem(
      ThemeData theme, int index, String label, IconData icon) {
    final selected = _currentIndex == index ||
        (index == 3 && const [4, 6, 7, 8].contains(_currentIndex));
    final ambient = _showAmbientBackground;
    final collapsed = MediaQuery.sizeOf(context).width < 1180 && !_navExpanded;
    final palette = _ambientPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => _navigateTo(index),
            borderRadius: BorderRadius.circular(14),
            hoverColor: ambient
                ? Colors.white.withValues(alpha: .07)
                : Colors.white.withValues(alpha: .55),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 0 : 12, vertical: 12),
              decoration: selected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      // Active state stays in the same cool glass palette.
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: ambient
                            ? [
                                palette.primaryText.withValues(alpha: .18),
                                palette.primaryText.withValues(alpha: .08),
                              ]
                            : [
                                Colors.white.withValues(alpha: .85),
                                AppColors.actionFill.withValues(alpha: .55),
                              ],
                      ),
                      border: Border.all(
                          color: ambient ? palette.edge : Colors.white),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: .14),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    )
                  : null,
              child: Row(
                  mainAxisAlignment: collapsed
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Icon(icon,
                        size: 19,
                        color: selected
                            ? (ambient
                                ? palette.primaryText
                                : AppColors.actionInk)
                            : (ambient
                                ? palette.secondaryText
                                : AppColors.muted)),
                    if (!collapsed) const SizedBox(width: 12),
                    if (!collapsed)
                      Text(label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 14,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected
                                ? (ambient
                                    ? palette.primaryText
                                    : AppColors.ink)
                                : (ambient
                                    ? palette.secondaryText
                                    : AppColors.muted),
                          )),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  /// 带连续打卡显示的标题栏：轻玻璃，与背景融合
  Widget _buildTitleBarWithStreak(ThemeData theme) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 12 * GlassTuning.blurScale(_glassClarity),
          sigmaY: 12 * GlassTuning.blurScale(_glassClarity),
        ),
        child: Container(
          height: 56,
          padding: const EdgeInsets.only(left: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: const [0, .55, 1],
              colors: [
                const Color(0xFF142834).withValues(
                    alpha: .36 * GlassTuning.tintScale(_glassClarity)),
                const Color(0xFF172A34).withValues(
                    alpha: .27 * GlassTuning.tintScale(_glassClarity)),
                const Color(0xFF302819).withValues(
                    alpha: .22 * GlassTuning.tintScale(_glassClarity)),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: .10),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart:
                      Platform.isWindows ? (_) => _startDragging() : null,
                  onDoubleTap: Platform.isWindows ? _toggleMaximize : null,
                  child: SizedBox(
                    height: 56,
                    child: Row(children: [
                      // 琥珀微光点 + 衬线字标：克制的品牌记号
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.warmAmber,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.warmAmber.withValues(alpha: .55),
                              blurRadius: 7,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('学习桌',
                          style: AppType.editorial(
                              size: 17,
                              weight: FontWeight.w600,
                              letterSpacing: 1.5,
                              color: _showAmbientBackground
                                  ? _ambientPalette.primaryText
                                  : Colors.white)),
                      const Spacer(),
                      StreakDisplayWidget(streak: _currentStreak),
                      const SizedBox(width: 10),
                    ]),
                  ),
                ),
              ),
              // 窗口置顶图钉：钉住 = 绿色斜图钉（微信样式）；仅宽屏（手机全屏无此需求）
              if (Platform.isWindows && wide)
                _WindowButton(
                  icon: Icons.push_pin,
                  tooltip: _alwaysOnTop ? '取消窗口置顶' : '窗口置顶',
                  iconColor: _alwaysOnTop
                      ? const Color(0xFF4CD08D)
                      : Colors.white.withValues(alpha: .55),
                  rotate: _alwaysOnTop ? -pi / 4 : 0,
                  onPressed: () => _setAlwaysOnTop(!_alwaysOnTop),
                ),
              // 设置按钮
              _WindowButton(
                icon: Icons.settings_outlined,
                tooltip: '设置',
                onPressed: _showSettingsDialog,
              ),
              if (Platform.isWindows)
                Tooltip(
                  message: _windowMaximized ? '还原小窗' : '最大化窗口',
                  child: _WindowButton(
                    icon: _windowMaximized
                        ? Icons.filter_none
                        : Icons.crop_square,
                    onPressed: _toggleMaximize,
                  ),
                ),
              // Windows 平台才显示窗口控制按钮
              if (Platform.isWindows) ...[
                const SizedBox(width: 4),
                Row(
                  children: [
                    _WindowButton(
                      icon: Icons.minimize,
                      tooltip: '最小化',
                      onPressed: () async {
                        final isMinimized = await windowManager.isMinimized();
                        if (isMinimized) {
                          await windowManager.restore();
                        } else {
                          await windowManager.minimize();
                        }
                      },
                    ),
                    _WindowButton(
                      icon: Icons.close,
                      danger: true,
                      tooltip: '关闭窗口',
                      onPressed: () async {
                        await windowManager.close();
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 待处理任务：未完成且未过期（一次性任务过截止时刻自动消失），
  /// 按截止时间升序、同序按添加先后。首页待处理卡与"接下来做"共用。
  List<TodoItem> _activeTodos() {
    final todos = _filteredTodos
        .where((todo) => !todo.isCompleted && !todo.isExpired())
        .toList()
      ..sort((a, b) {
        final aDate = a.deadline ?? DateTime(9999);
        final bDate = b.deadline ?? DateTime(9999);
        final byDate = aDate.compareTo(bDate);
        return byDate != 0 ? byDate : a.sortOrder.compareTo(b.sortOrder);
      });
    return todos;
  }

  Widget _buildTodoListPage(ThemeData theme) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final width = MediaQuery.sizeOf(context).width;
    final ambient = _showAmbientBackground;
    final palette = _ambientPalette;
    final active = _activeTodos();
    final completed = _filteredTodos.where((todo) => todo.isCompleted).toList();
    // 已过期未完成：不进待处理，但收进"已过期"分组保持可达（可编辑改期）
    final expired = _filteredTodos
        .where((todo) => !todo.isCompleted && todo.isExpired())
        .toList();

    return LayoutBuilder(builder: (context, bounds) {
      final twoColumn =
          bounds.maxWidth >= WindowSizeClass.twoColumnMinWidth && _isToday;
      if (!twoColumn) {
        return _homeSingleColumn(theme, width, active, completed, expired);
      }
      return _homeTwoColumn(
          theme, width, ambient, palette, active, completed, expired);
    });
  }

  /// 窄内容（小窗/手机/历史日期）：保持原单列流。
  Widget _homeSingleColumn(ThemeData theme, double width, List<TodoItem> active,
      List<TodoItem> completed, List<TodoItem> expired) {
    final ambient = _showAmbientBackground;
    final side = width < 680 ? 18.0 : 32.0;
    return ListView(
        key: const PageStorageKey<String>('today-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            width: double.infinity,
            decoration: ambient
                ? null
                : BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_todayWash(), AppColors.canvas],
                    ),
                  ),
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 848),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    side, width < 680 ? 20 : 30, side, width < 680 ? 8 : 13),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _homeGreetingHeader(theme, width),
                      SizedBox(height: width < 680 ? 22 : 30),
                      ..._homeGreetingBody(theme, width),
                    ]),
              ),
            )),
          ),
          Padding(
              padding: EdgeInsets.fromLTRB(
                  side, width < 680 ? 12 : 18, side, width < 680 ? 20 : 26),
              child: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 784),
                child: _homeTasksCard(theme, active, completed, expired),
              ))),
          Padding(
            padding: EdgeInsets.fromLTRB(side, 4, side, 42),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 784),
                child: _buildTodayContext(theme),
              ),
            ),
          ),
        ]);
  }

  /// 宽内容（≥ WindowSizeClass.twoColumnMinWidth 且为今天）：
  /// 问候语为通栏头部，下方左主列（接下来做/快速添加/今日任务）+
  /// 右侧列（今天发生的事 + 最近），右栏顶边与"接下来做"卡片精确对齐。
  Widget _homeTwoColumn(
      ThemeData theme,
      double width,
      bool ambient,
      AmbientPalette palette,
      List<TodoItem> active,
      List<TodoItem> completed,
      List<TodoItem> expired) {
    final side = width < 680 ? 18.0 : 32.0;
    return ListView(
      key: const PageStorageKey<String>('today-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Container(
          width: double.infinity,
          decoration: ambient
              ? null
              : BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_todayWash(), AppColors.canvas],
                  ),
                ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Padding(
                padding: EdgeInsets.fromLTRB(side, 30, side, 42),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _homeGreetingHeader(theme, width),
                    const SizedBox(height: 26),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ..._homeGreetingBody(theme, width),
                              const SizedBox(height: 18),
                              _homeTasksCard(theme, active, completed, expired),
                            ],
                          ),
                        ),
                        const SizedBox(width: 28),
                        Expanded(flex: 3, child: _buildTodayContext(theme)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 问候区头部（时段问候 + 情境行 + 日期按钮），单列/双列共用。
  Widget _homeGreetingHeader(ThemeData theme, double width) {
    final ambient = _showAmbientBackground;
    final palette = _ambientPalette;
    final darkBackdrop = ambient;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_overlineDate(),
            style: TextStyle(
              fontFamily: AppTypography.sans,
              fontSize: 11.5,
              color: darkBackdrop ? palette.secondaryText : AppColors.muted,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.6,
              shadows: darkBackdrop ? [palette.textShadow] : null,
            )),
        const SizedBox(height: 13),
        Text(_isToday ? _greeting() : '这一天',
            style: AppType.editorial(
              size: width < 680 ? 34 : 46,
              weight: FontWeight.w600,
              color: darkBackdrop ? palette.primaryText : AppColors.ink,
              letterSpacing: width < 680 ? .8 : 1.2,
            ).copyWith(
              shadows: darkBackdrop ? [palette.textShadow] : null,
            )),
        const SizedBox(height: 12),
        Text(_contextLine(),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              color: darkBackdrop ? palette.secondaryText : AppColors.muted,
              shadows: darkBackdrop ? [palette.textShadow] : null,
            )),
      ])),
      if (!_isToday) ...[
        _GlassGhostButton(
          label: '回到今天',
          icon: Icons.undo,
          onTap: () => _changeDate(DateTime.now()),
        ),
        const SizedBox(width: 8),
      ],
      _GlassIconCircle(
        icon: Icons.calendar_month_outlined,
        onDark: darkBackdrop,
        tooltip: '选择日期',
        onTap: () => _selectDate(context),
      ),
    ]);
  }

  /// 问候头部以下的正文起点（接下来做 + 快速添加），单列/双列共用。
  List<Widget> _homeGreetingBody(ThemeData theme, double width) {
    final darkBackdrop = _showAmbientBackground;
    return [
      _buildNowHero(theme),
      SizedBox(height: width < 680 ? 12 : 14),
      _buildQuickInput(theme, darkBackdrop),
    ];
  }

  /// 今日任务卡（待处理 + 已完成 + 已过期），单列/双列共用
  Widget _homeTasksCard(ThemeData theme, List<TodoItem> active,
      List<TodoItem> completed, List<TodoItem> expired) {
    final ambient = _showAmbientBackground;
    final palette = _ambientPalette;
    return _TodayContentSurface(
      dark: ambient,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // 栏目词 + 大数字计数：编辑式层级
            Text(active.isEmpty ? '今日任务' : '待处理',
                style: TextStyle(
                  fontFamily: AppTypography.sans,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.4,
                  color: ambient ? palette.secondaryText : AppColors.muted,
                )),
            if (active.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text('${active.length}',
                  style: AppType.display(
                    size: 21,
                    weight: FontWeight.w600,
                    color: ambient ? palette.primaryText : AppColors.ink,
                  ).copyWith(fontFeatures: AppType.tabular)),
            ],
            const Spacer(),
            PopupMenuButton<String>(
              tooltip: '筛选任务',
              onSelected: (value) => setState(() => _saveCategoryFilter(
                  value == 'all' ? null : TaskCategory.values.byName(value))),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'all', child: Text('全部任务')),
                for (final category in TaskCategory.values)
                  PopupMenuItem(
                      value: category.name, child: Text(category.displayName)),
              ],
              color: AppColors.paper,
              child: _GlassGhostButton(
                label: _selectedCategoryFilter?.displayName ?? '全部',
                icon: Icons.tune,
                plain: true,
                compact: true,
              ),
            ),
          ]),
          const SizedBox(height: 15),
          if (active.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  _todos.isEmpty
                      ? Icons.edit_calendar_outlined
                      : Icons.check_circle_outline,
                  size: 25,
                  color: ambient ? palette.secondaryText : AppColors.muted,
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          _todos.isEmpty
                              ? '写下今天最想完成的一件事。'
                              : completed.isNotEmpty
                                  ? '待处理的任务都完成了。'
                                  : '这个分类暂时没有待处理任务。',
                          style: theme.textTheme.bodyLarge?.copyWith(
                              color: ambient
                                  ? palette.primaryText
                                  : AppColors.muted)),
                      if (_todos.isEmpty) const SizedBox(height: 6),
                      if (_todos.isEmpty)
                        Text('在上方输入，按回车即可添加。',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: ambient
                                    ? palette.secondaryText
                                    : AppColors.muted)),
                      if (_todos.isEmpty) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _quickInputFocus.requestFocus,
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          label: const Text('写下第一件事'),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                ambient ? palette.primaryText : AppColors.navy,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ])),
              ]),
            ),
          for (var index = 0; index < active.length; index++) ...[
            _TodoListItem(
                onDark: ambient,
                todo: active[index],
                selectedDate: _selectedDate,
                onToggle: () => _toggleTodo(active[index].id),
                onEdit: () => _editTodo(active[index]),
                onDelete: () => _deleteTodo(active[index].id)),
            if (index < active.length - 1)
              Divider(
                height: 1,
                indent: 50,
                endIndent: 10,
                color: ambient
                    ? Colors.white.withValues(alpha: .09)
                    : AppColors.line.withValues(alpha: .40),
              ),
          ],
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 14),
            TextButton.icon(
                onPressed: () =>
                    setState(() => _showCompleted = !_showCompleted),
                icon: Icon(
                    _showCompleted ? Icons.expand_less : Icons.expand_more,
                    size: 18),
                label: Text('今天完成 ${completed.length} 项'),
                style: TextButton.styleFrom(
                  foregroundColor:
                      ambient ? palette.secondaryText : AppColors.navy,
                )),
            if (_showCompleted) ...[
              const SizedBox(height: 6),
              for (var index = 0; index < completed.length; index++) ...[
                _TodoListItem(
                    onDark: ambient,
                    todo: completed[index],
                    selectedDate: _selectedDate,
                    onToggle: () => _toggleTodo(completed[index].id),
                    onEdit: () => _editTodo(completed[index]),
                    onDelete: () => _deleteTodo(completed[index].id)),
                if (index < completed.length - 1)
                  Divider(
                    height: 1,
                    indent: 50,
                    endIndent: 10,
                    color: ambient
                        ? Colors.white.withValues(alpha: .09)
                        : AppColors.line.withValues(alpha: .40),
                  ),
              ],
            ],
          ],
        ]),
      ),
    );
  }

  // ==================== 今日仪表盘 ====================

  String _overlineDate() {
    final now = _selectedDate;
    final weekday = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][now.weekday - 1];
    return '${now.month}月${now.day}日 $weekday';
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return '上午好';
    if (hour >= 11 && hour < 13) return '中午好';
    if (hour >= 13 && hour < 18) return '下午好';
    if (hour >= 18 && hour < 23) return '晚上好';
    return '夜深了';
  }

  Color _todayWash() {
    if (!_isToday) return AppColors.canvas;
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return const Color(0xFFFFF9EF);
    if (hour >= 12 && hour < 18) return const Color(0xFFF2F5F5);
    return const Color(0xFFF0F2F4);
  }

  String _contextLine() {
    if (!_isToday) {
      final remaining = _todos.where((todo) => !todo.isCompleted).length;
      return remaining > 0 ? '还有 $remaining 件事待完成' : '这一天没有待处理的任务';
    }
    final brief = _brief;
    final activeCount = _todos.where((todo) => !todo.isCompleted).length;
    final hour = DateTime.now().hour;
    if (hour >= 18 || hour < 5) {
      final done = _todos.where((todo) => todo.isCompleted).length;
      final focus = brief?.focusMinutes ?? 0;
      return done > 0
          ? '今天完成了 $done 件事${focus > 0 ? ' · 专注 $focus 分钟' : ''}'
          : '今天还留有一些余地，随时可以开始。';
    }
    final next = brief?.nextCourseAt;
    if (next != null) {
      final minutes = next.difference(DateTime.now()).inMinutes;
      if (minutes > 0 && minutes <= 90) return '下一节课还有 $minutes 分钟';
    }
    final courses = brief?.courseCountToday ?? 0;
    if (courses > 0) return '今天有 $courses 节课 · $activeCount 个任务';
    return activeCount > 0 ? '今天有 $activeCount 个任务' : '今天还没有安排，写下第一件事';
  }

  /// 正在发生：下一节课（有课时）或下一件事，二选一的主卡
  Widget _buildNowHero(ThemeData theme) {
    final palette = _ambientPalette;
    final brief = _brief;
    final active = _activeTodos();

    final hasCourse = _isToday && brief?.nextCourseName != null;
    final title = hasCourse
        ? brief!.nextCourseName!
        : (active.isEmpty
            ? (_todos.isEmpty ? '从写下一件事开始' : '今天的任务已完成')
            : active.first.title);
    final String? meta = hasCourse ? brief!.nextCourseLocation : null;
    final String? startLabel = hasCourse ? brief!.nextCourseStartLabel : null;

    return LayoutBuilder(builder: (context, bounds) {
      final spacious = bounds.maxWidth >= 620;
      return GlassPanel(
        level: GlassSurfaceLevel.dark,
        radius: 28,
        blur: 18,
        opacity: .66,
        shadow: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: hasCourse ? () => _navigateTo(1) : null,
            child: Stack(children: [
              // 室内暖灯打在卡面上：右上角一束极弱暖光
              Positioned(
                top: -46,
                right: -36,
                child: IgnorePointer(
                  child: Container(
                    width: 300,
                    height: 230,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(.3, .35),
                        radius: .95,
                        colors: [
                          AppColors.warmAmber.withValues(alpha: .17),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    spacious ? 28 : 22, 22, spacious ? 28 : 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.amber,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.amber.withValues(alpha: .60),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(hasCourse ? '即将开始的课程' : '接下来做',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.secondaryText,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.8,
                            fontSize: 11.5,
                          )),
                      const Spacer(),
                      if (startLabel != null)
                        Text(startLabel,
                            style: AppType.display(
                              size: 22,
                              color: AppColors.warmCream,
                            ).copyWith(fontFeatures: AppType.tabular))
                      else if (spacious && active.isNotEmpty)
                        Text('${active.length.toString().padLeft(2, '0')} / 待办',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: palette.secondaryText,
                                fontFeatures: AppType.tabular)),
                    ]),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 660),
                      child: Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.display(
                            size: spacious ? 29 : 25,
                            weight: FontWeight.w600,
                            height: 1.32,
                            letterSpacing: .3,
                            color: palette.primaryText,
                          )),
                    ),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                        child: Text(
                          hasCourse
                              ? [
                                  if (meta != null && meta.isNotEmpty) meta,
                                  if (brief?.nextCourseAt != null) '查看课表安排',
                                ].join(' · ')
                              : active.isEmpty
                                  ? '从一件小事开始'
                                  : '${active.first.category.displayName} · 现在可以开始',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.secondaryText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      _SoftActionButton(
                        label: '开始专注',
                        icon: Icons.play_arrow_rounded,
                        onTap: () => _navigateTo(5),
                      ),
                    ]),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }

  /// 快速输入：浅玻璃输入条 + 轻量暖光「添加」按钮 + 选项胶囊
  Widget _buildQuickInput(ThemeData theme, bool onDark) {
    final palette = _ambientPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 10 * GlassTuning.blurScale(_glassClarity),
                  sigmaY: 10 * GlassTuning.blurScale(_glassClarity),
                ),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: onDark
                        ? LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              palette.tint.withValues(
                                  alpha: (palette.tintOpacity *
                                          1.15 *
                                          GlassTuning.tintScale(_glassClarity))
                                      .clamp(.16, .68)),
                              palette.tint.withValues(
                                  alpha: (palette.tintOpacity *
                                          GlassTuning.tintScale(_glassClarity))
                                      .clamp(.12, .60)),
                            ],
                          )
                        : LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: .72),
                              Colors.white.withValues(alpha: .56),
                            ],
                          ),
                    border: Border.all(
                      color: onDark
                          ? palette.edge
                          : Colors.white.withValues(alpha: .80),
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _quickInputFocus,
                    onSubmitted: _addTodo,
                    textInputAction: TextInputAction.done,
                    cursorColor: onDark ? palette.primaryText : AppColors.navy,
                    cursorWidth: 2.8,
                    cursorRadius: const Radius.circular(1.4),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onDark ? palette.primaryText : AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      hintText: '写下下一件要做的事',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: onDark ? palette.secondaryText : AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                      prefixIcon: Icon(Icons.add,
                          size: 21,
                          color: onDark
                              ? AppColors.warmCream.withValues(alpha: .90)
                              : AppColors.navy),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          _SoftActionButton(
            label: '添加',
            icon: Icons.add,
            onTap: () => _addTodo(_controller.text),
            compact: true,
          ),
        ]),
        const SizedBox(height: 10),
        // 任务类型下拉：一次性 / 长久习惯 / DDL；每种类型的后续选项不同
        Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PopupMenuButton<String>(
                tooltip: '选择任务类型',
                onSelected: (value) {
                  setState(() {
                    _quickKind = value;
                    // 切出 DDL 时清掉暂存的截止时间
                    if (value != 'ddl') _quickDeadline = null;
                  });
                  // 选 DDL 后立即打开截止时间选择
                  if (value == 'ddl' && _quickDeadline == null) {
                    _pickQuickDeadline();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'oneTime',
                      child: Row(children: [
                        Icon(Icons.flag_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('一次性'),
                      ])),
                  const PopupMenuItem(
                      value: 'recurring',
                      child: Row(children: [
                        Icon(Icons.repeat, size: 18),
                        SizedBox(width: 10),
                        Text('长久习惯'),
                      ])),
                  const PopupMenuItem(
                      value: 'ddl',
                      child: Row(children: [
                        Icon(Icons.schedule, size: 18),
                        SizedBox(width: 10),
                        Text('DDL · 到点提醒'),
                      ])),
                ],
                color: AppColors.paper,
                child: _GlassGhostButton(
                  label: '${_quickKindLabel} ▾',
                  icon: _quickKind == 'ddl' ? Icons.schedule : Icons.tune,
                  plain: true,
                  onDark: onDark,
                ),
              ),
              if (_quickKind == 'ddl' && _quickDeadline != null)
                _GlassIconCircle(
                  icon: Icons.close,
                  onDark: onDark,
                  tooltip: '清除截止时间',
                  onTap: () => setState(() => _quickDeadline = null),
                ),
              // 一次性 / 长久习惯：直接展开分类选择
              if (_quickKind != 'ddl')
                for (final category in TaskCategory.values)
                  _OptionChip(
                    label: category.displayName,
                    selected: _selectedCategory == category,
                    onDark: onDark,
                    onTap: () => setState(() => _selectedCategory = category),
                  ),
            ]),
      ],
    );
  }

  /// 生活条：训练 / 饮食 / 支出 / 专注，一行四个真实数字
  Widget _buildLifeStrip(ThemeData theme) {
    final palette = _ambientPalette;
    final brief = _brief;
    if (brief == null) {
      return Text('正在整理今天的记录',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: palette.secondaryText));
    }
    final facts = <(String, String, int)>[
      if (brief.focusMinutes > 0) ('投入时间', '${brief.focusMinutes} 分钟', -1),
      if (brief.workoutsToday > 0) ('训练', '${brief.workoutsToday} 次', 6),
      if (brief.dietCount > 0) ('饮食', '${brief.dietCount} 餐', 7),
      if (brief.expenseTodayCents != 0)
        ('支出', formatCents(brief.expenseTodayCents), 8),
    ];
    if (facts.isEmpty) {
      return TextButton.icon(
        onPressed: () => _navigateTo(3),
        icon: const Icon(Icons.arrow_outward, size: 16),
        label: const Text('从今天的一条记录开始'),
        style: TextButton.styleFrom(
          foregroundColor: palette.primaryText,
          padding: EdgeInsets.zero,
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < facts.length; index += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _lifeStat(
                    theme,
                    facts[index].$1,
                    facts[index].$2,
                    () => facts[index].$3 == -1
                        ? Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const FocusInsightsPage()))
                        : _navigateTo(facts[index].$3)),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: index + 1 < facts.length
                    ? _lifeStat(
                        theme,
                        facts[index + 1].$1,
                        facts[index + 1].$2,
                        () => facts[index + 1].$3 == -1
                            ? Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const FocusInsightsPage()))
                            : _navigateTo(facts[index + 1].$3))
                    : const SizedBox.shrink(),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _lifeStat(
      ThemeData theme, String label, String value, VoidCallback onTap) {
    final palette = _ambientPalette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: Colors.white.withValues(alpha: .07),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.display(
                size: 29,
                weight: FontWeight.w600,
                color: palette.primaryText,
              ).copyWith(fontFeatures: AppType.tabular)),
          const SizedBox(height: 4),
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: palette.secondaryText, letterSpacing: 1)),
        ]),
      ),
    );
  }

  Widget _buildTodayContext(ThemeData theme) {
    if (!_isToday) return const SizedBox.shrink();
    final palette = _ambientPalette;
    return LayoutBuilder(builder: (context, bounds) {
      final wide = bounds.maxWidth >= 620;
      final arc = _buildDayArc(theme);
      final life =
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('生活记录',
            style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.2,
                color: palette.secondaryText)),
        const SizedBox(height: 16),
        _buildLifeStrip(theme),
      ]);
      final timeButton = _GlassGhostButton(
        label: '时间分布',
        icon: Icons.pie_chart_outline,
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const FocusInsightsPage())),
        onDark: true,
      );
      final weekButton = _GlassGhostButton(
        label: '周回顾',
        icon: Icons.arrow_forward,
        onTap: () => _navigateTo(2),
        onDark: true,
      );
      final heading = Text('今天发生的事',
          style: theme.textTheme.bodySmall?.copyWith(
              color: palette.secondaryText,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
              letterSpacing: 2.2));
      return GlassPanel(
        level: GlassSurfaceLevel.dark,
        radius: 26,
        opacity: .62,
        blur: 16,
        shadow: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(wide ? 28 : 20, 21, wide ? 28 : 20, 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (wide)
              Row(children: [
                heading,
                const Spacer(),
                timeButton,
                const SizedBox(width: 8),
                weekButton,
              ])
            else ...[
              heading,
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [timeButton, weekButton]),
            ],
            const SizedBox(height: 20),
            wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 6, child: arc),
                    const SizedBox(width: 30),
                    Container(
                      width: 1,
                      height: 128,
                      color: Colors.white.withValues(alpha: .12),
                    ),
                    const SizedBox(width: 30),
                    Expanded(flex: 4, child: life),
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        arc,
                        const SizedBox(height: 26),
                        life,
                      ]),
            const SizedBox(height: 18),
            Divider(color: Colors.white.withValues(alpha: .15), height: 1),
            const SizedBox(height: 16),
            _buildRecentActivity(theme),
          ]),
        ),
      );
    });
  }

  /// 今日轨迹：课程 / 任务 / 专注 / 训练落在一条时间轴上
  Widget _buildDayArc(ThemeData theme) {
    final palette = _ambientPalette;
    final events = _brief?.events ?? const <_ArcEvent>[];
    final now = DateTime.now();
    final timedEvents = events.where((event) => event.timed).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('今天的记录',
              style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.2,
                  color: palette.secondaryText)),
          const Spacer(),
          if (timedEvents.isNotEmpty)
            Text('${timedEvents.length} 个时刻',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.secondaryText,
                    fontFeatures: AppType.tabular)),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: CustomPaint(
            size: Size.infinite,
            painter: _DayArcPainter(
                events: timedEvents,
                now: now,
                labelColor: palette.secondaryText),
          ),
        ),
        const SizedBox(height: 7),
        if (timedEvents.isEmpty)
          Text('完成任务或记下一件事后，今天的记录会出现在这里。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: palette.secondaryText))
      ],
    );
  }

  Widget _buildRecentActivity(ThemeData theme) {
    final palette = _ambientPalette;
    final today = DateTime.now();
    String when(_RecentActivity activity) {
      final at = activity.at;
      if (at.year == today.year &&
          at.month == today.month &&
          at.day == today.day) {
        return activity.timed
            ? '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'
            : '今天';
      }
      final yesterday = today.subtract(const Duration(days: 1));
      return at.year == yesterday.year &&
              at.month == yesterday.month &&
              at.day == yesterday.day
          ? '昨天'
          : '${at.month}月${at.day}日';
    }

    return FutureBuilder<List<_RecentActivity>>(
      future: _recentFuture,
      builder: (context, snapshot) {
        final recent = snapshot.data ?? const <_RecentActivity>[];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('最近',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: palette.primaryText)),
            const Spacer(),
            Text('近 7 天',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: palette.secondaryText)),
          ]),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Icon(Icons.auto_stories_outlined,
                    size: 18, color: palette.secondaryText),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                      snapshot.connectionState == ConnectionState.done
                          ? '还没有记录，记下一件今天发生的事。'
                          : '正在整理最近的记录…',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: palette.secondaryText)),
                ),
                if (snapshot.connectionState == ConnectionState.done)
                  TextButton(
                    onPressed: () => _navigateTo(3),
                    style: TextButton.styleFrom(
                        foregroundColor: palette.primaryText),
                    child: const Text('去记录'),
                  ),
              ]),
            ),
          for (final activity in recent) ...[
            const SizedBox(height: 7),
            InkWell(
              onTap: () => _navigateTo(activity.moduleIndex),
              borderRadius: BorderRadius.circular(9),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(
                    width: 54,
                    child: Text(when(activity),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: palette.secondaryText,
                            fontFeatures: AppType.tabular)),
                  ),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: activity.moduleIndex == 5
                          ? AppColors.actionFill
                          : Colors.white.withValues(alpha: .8),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(activity.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: palette.primaryText)),
                  ),
                  Icon(Icons.chevron_right,
                      size: 16, color: palette.secondaryText),
                ]),
              ),
            ),
          ],
        ]);
      },
    );
  }

  Future<List<_RecentActivity>> _loadRecentActivity(DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: 6));
    final end = today.add(const Duration(days: 1));
    final isar = IsarService.instance.isar;
    final recent = <_RecentActivity>[];
    try {
      final tasks = await isar.todoItems
          .filter()
          .isCompletedEqualTo(true)
          .completedAtBetween(start, end, includeUpper: false)
          .findAll();
      for (final task in tasks) {
        final at = task.completedAt;
        if (at != null) recent.add(_RecentActivity(at, '完成 ${task.title}', 0));
      }
    } catch (_) {}
    try {
      final sessions = await isar.pomodoroSessions
          .filter()
          .startedAtBetween(start, end, includeUpper: false)
          .completedEqualTo(true)
          .typeEqualTo(PomodoroPhaseType.focus)
          .findAll();
      for (final session in sessions) {
        recent.add(_RecentActivity(
            session.startedAt,
            session.taskTitle?.isNotEmpty == true
                ? '专注 ${session.taskTitle}'
                : '专注 ${session.durationSeconds ~/ 60} 分钟',
            5));
      }
    } catch (_) {}
    try {
      final workouts = await isar.workoutLogs
          .filter()
          .startedAtBetween(start, end, includeUpper: false)
          .completedEqualTo(true)
          .findAll();
      for (final log in workouts) {
        recent.add(_RecentActivity(log.startedAt, '完成训练 ${log.title}', 6));
      }
    } catch (_) {}
    try {
      final logs = await isar.dietLogs
          .filter()
          .dateBetween(start, end, includeUpper: false)
          .findAll();
      for (final log in logs) {
        final timed = log.createdAt.year == log.date.year &&
            log.createdAt.month == log.date.month &&
            log.createdAt.day == log.date.day;
        recent.add(_RecentActivity(timed ? log.createdAt : log.date,
            '${log.mealType.displayName} · ${log.food}', 7,
            timed: timed));
      }
    } catch (_) {}
    try {
      final items = await isar.expenses
          .filter()
          .dateBetween(start, end, includeUpper: false)
          .findAll();
      for (final item in items) {
        recent.add(_RecentActivity(
            item.date,
            '消费 · ${item.counterparty.isEmpty ? item.category : item.counterparty} ${formatCents(item.amountCents)}',
            8,
            timed: false));
      }
    } catch (_) {}
    try {
      final memos = await MemoService.instance.getAllMemos();
      for (final memo in memos) {
        if (memo.updatedAt.isBefore(start) || !memo.updatedAt.isBefore(end)) {
          continue;
        }
        final title = memo.title.trim();
        recent.add(_RecentActivity(
            memo.updatedAt, '备忘录 · ${title.isEmpty ? '未命名' : title}', 4));
      }
    } catch (_) {}
    recent.sort((a, b) => b.at.compareTo(a.at));
    return recent.take(8).toList();
  }

  Future<void> _loadTodayBrief() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      List<Course> courses = [];
      List<ClassTimeConfig> times = [];
      try {
        final semester = await CourseService.instance.ensureActiveSemester();
        if (!today.isBefore(semester.startDate) &&
            !today.isAfter(semester.getEndDate())) {
          courses = await CourseService.instance.getCoursesForDay(
              today.weekday, semester.getWeekOf(today),
              semester: semester.name);
          times = await CourseService.instance.getTimeConfigs();
        }
      } catch (_) {}

      DateTime? courseAt(Course course) {
        for (final slot in times) {
          if (slot.firstPeriod <= course.startPeriod &&
              slot.lastPeriod >= course.startPeriod) {
            return DateTime(today.year, today.month, today.day,
                slot.startMinutes ~/ 60, slot.startMinutes % 60);
          }
        }
        return null;
      }

      final focus = await FocusAnalyticsService.forDay(now);
      var dietCount = 0;
      var dietLogs = <DietLog>[];
      try {
        dietLogs = await DietService.instance.getLogsForDate(now);
        dietCount = dietLogs.length;
      } catch (_) {}
      var expenseCents = 0;
      var todayExpenses = <Expense>[];
      try {
        final monthItems = await ExpenseService.instance.getForMonth(now);
        todayExpenses = monthItems
            .where((item) =>
                item.date.year == today.year &&
                item.date.month == today.month &&
                item.date.day == today.day)
            .toList();
        expenseCents = todayExpenses.fold<int>(
            0,
            (sum, item) =>
                sum +
                (item.kind == ExpenseKind.refund
                    ? -item.amountCents
                    : item.amountCents));
      } catch (_) {}
      var workoutsToday = 0;
      List<WorkoutLog> recentWorkouts = [];
      try {
        recentWorkouts =
            await TrainingService.instance.getWorkoutHistory(limit: 60);
        workoutsToday = recentWorkouts
            .where((log) =>
                log.startedAt.year == today.year &&
                log.startedAt.month == today.month &&
                log.startedAt.day == today.day &&
                log.completed)
            .length;
      } catch (_) {}

      final events = <_ArcEvent>[];
      for (final course in courses) {
        final at = courseAt(course);
        if (at != null) events.add(_ArcEvent(at, _ArcKind.course, course.name));
      }
      for (final todo in _todos) {
        final at = todo.completedAt;
        if (todo.isCompleted &&
            at != null &&
            at.year == today.year &&
            at.month == today.month &&
            at.day == today.day) {
          events.add(_ArcEvent(at, _ArcKind.task, '完成 ${todo.title}'));
        }
      }
      try {
        final isar = IsarService.instance.isar;
        final sessions = await isar.pomodoroSessions
            .filter()
            .startedAtGreaterThan(today)
            .completedEqualTo(true)
            .typeEqualTo(PomodoroPhaseType.focus)
            .findAll();
        for (final session in sessions) {
          events.add(_ArcEvent(
              session.startedAt,
              _ArcKind.focus,
              session.taskTitle?.isNotEmpty == true
                  ? '专注 ${session.taskTitle}'
                  : '专注 ${session.durationSeconds ~/ 60} 分钟'));
        }
      } catch (_) {}
      for (final log in recentWorkouts) {
        if (log.completed &&
            log.startedAt.year == today.year &&
            log.startedAt.month == today.month &&
            log.startedAt.day == today.day) {
          events.add(
              _ArcEvent(log.startedAt, _ArcKind.training, '完成训练 ${log.title}'));
        }
      }
      for (final log in dietLogs) {
        final timed = log.createdAt.year == today.year &&
            log.createdAt.month == today.month &&
            log.createdAt.day == today.day;
        events.add(_ArcEvent(log.createdAt, _ArcKind.diet,
            '${log.mealType.displayName} · ${log.food}', timed));
      }
      for (final item in todayExpenses) {
        events.add(_ArcEvent(
            item.date,
            _ArcKind.expense,
            '消费 · ${item.counterparty.isEmpty ? item.category : item.counterparty}',
            false));
      }

      Course? nextCourse;
      DateTime? nextAt;
      for (final course in courses) {
        final at = courseAt(course);
        if (at != null && at.isAfter(now)) {
          nextCourse = course;
          nextAt = at;
          break;
        }
      }
      String? nextStartLabel;
      if (nextCourse != null) {
        for (final slot in times) {
          if (slot.firstPeriod <= nextCourse.startPeriod &&
              slot.lastPeriod >= nextCourse.startPeriod) {
            nextStartLabel = slot.startLabel;
            break;
          }
        }
      }

      if (mounted) {
        setState(() => _brief = _TodayBrief(
              nextCourseName: nextCourse?.name,
              nextCourseLocation: nextCourse?.location,
              nextCourseStartLabel: nextStartLabel,
              nextCourseAt: nextAt,
              courseCountToday: courses.length,
              focusMinutes: focus.totalSeconds ~/ 60,
              dietCount: dietCount,
              expenseTodayCents: expenseCents,
              workoutsToday: workoutsToday,
              events: events,
            ));
      }
    } catch (e) {
      debugPrint('今日概览加载失败: $e');
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)), // 允许选择未来一年内的日期
    );
    if (picked != null) {
      _changeDate(picked);
    }
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;
  final String? tooltip;

  /// 激活态颜色（如窗口置顶的绿色图钉）；null 时用默认白
  final Color? iconColor;

  /// 激活态旋转角度（图钉斜插样式）
  final double rotate;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.tooltip,
    this.iconColor,
    this.rotate = 0,
  });

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onPressed,
      hoverColor: danger
          ? const Color(0x99B85850)
          : Colors.white.withValues(alpha: .16),
      child: SizedBox(
        width: 52,
        height: 56,
        child: Center(
          child: Transform.rotate(
            angle: rotate,
            child: Icon(
              icon,
              size: 20,
              color: iconColor ??
                  (danger
                      ? const Color(0xFFF6C9C2)
                      : Colors.white.withValues(alpha: .88)),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Quiet solid action: readable on glass without drawing a bright yellow block.
class _SoftActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;

  const _SoftActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<_SoftActionButton> createState() => _SoftActionButtonState();
}

class _SoftActionButtonState extends State<_SoftActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 15 : 19,
            vertical: widget.compact ? 9 : 11,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _hover
                  ? [const Color(0xFFE9F0EE), AppColors.actionFill]
                  : [AppColors.actionFill, AppColors.actionFillDeep],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .65)),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: _hover ? .20 : .12),
                blurRadius: _hover ? 16 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 19, color: AppColors.actionInk),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: const TextStyle(
                  fontFamily: AppTypography.sans,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .4,
                  color: AppColors.actionInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 玻璃幽灵按钮：低调的次级动作（筛选 / 时间分布 / 周回顾等），
/// 深色玻璃上为白玻璃胶囊，纸面上为浅底描边。
/// [plain] 为纯装饰模式（作为 PopupMenuButton 的 child 时不拦截手势）。
class _GlassGhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool onDark;
  final bool compact;
  final bool plain;

  const _GlassGhostButton({
    required this.label,
    this.onTap,
    this.icon,
    this.onDark = true,
    this.compact = false,
    this.plain = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AmbientPaletteScope.maybeOf(context)?.palette;
    final fg = onDark
        ? palette?.secondaryText ?? Colors.white.withValues(alpha: .82)
        : AppColors.navy;
    Widget buildChild(Color hover) {
      // 底色跟随玻璃清晰度滑杆的磨砂程度
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 6.5 : 8,
        ),
        decoration: BoxDecoration(
          color: onDark
              ? Colors.white.withValues(alpha: .10)
              : Colors.white.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: onDark
                ? Colors.white.withValues(alpha: .18)
                : Colors.white.withValues(alpha: .80),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.sans,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: .3,
                color: fg,
              ),
            ),
          ],
        ),
      );
    }

    if (plain) {
      return Material(
        color: onDark
            ? Colors.white.withValues(alpha: .09)
            : Colors.white.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
        child: buildChild(Colors.transparent),
      );
    }
    return Material(
      color: onDark
          ? Colors.white.withValues(alpha: .09)
          : Colors.white.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        hoverColor: onDark
            ? Colors.white.withValues(alpha: .08)
            : Colors.white.withValues(alpha: .30),
        child: buildChild(Colors.transparent),
      ),
    );
  }
}

/// 玻璃图标圆：悬空图标（日期选择等）的小容器
class _GlassIconCircle extends StatelessWidget {
  final IconData icon;
  final bool onDark;
  final VoidCallback onTap;
  final String? tooltip;

  const _GlassIconCircle({
    required this.icon,
    required this.onDark,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: onDark
          ? Colors.white.withValues(alpha: .10)
          : Colors.white.withValues(alpha: .62),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        hoverColor: onDark
            ? Colors.white.withValues(alpha: .10)
            : Colors.white.withValues(alpha: .32),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: onDark
                  ? Colors.white.withValues(alpha: .20)
                  : Colors.white.withValues(alpha: .85),
            ),
          ),
          child: Icon(
            icon,
            size: 19,
            color:
                onDark ? Colors.white.withValues(alpha: .85) : AppColors.navy,
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// 选项胶囊：任务类型 / 分类的轻量选择器（替代默认 ChoiceChip）
class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool onDark;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onDark = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.actionFill.withValues(alpha: onDark ? .28 : 1),
                    AppColors.actionFillDeep
                        .withValues(alpha: onDark ? .14 : .55),
                  ],
                )
              : null,
          color: selected
              ? null
              : (onDark
                  ? Colors.white.withValues(alpha: .08)
                  : Colors.white.withValues(alpha: .65)),
          border: Border.all(
            color: selected
                ? (onDark
                    ? Colors.white.withValues(alpha: .34)
                    : AppColors.actionFillDeep.withValues(alpha: .70))
                : (onDark ? Colors.white.withValues(alpha: .16) : Colors.white),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTypography.sans,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? (onDark ? AppColors.actionFill : AppColors.actionInk)
                : (onDark
                    ? Colors.white.withValues(alpha: .78)
                    : AppColors.muted),
          ),
        ),
      ),
    );
  }
}

// 任务类型选择按钮
class _TaskTypeButton extends StatelessWidget {
  final TaskType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _TaskTypeButton({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.forestSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.forest
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              type == TaskType.recurring ? Icons.repeat : Icons.task_alt,
              size: 16,
              color: isSelected
                  ? AppColors.forest
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              type == TaskType.recurring ? '每日习惯' : '一次性',
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? AppColors.forest
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayContentSurface extends StatelessWidget {
  const _TodayContentSurface({required this.child, required this.dark});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) => GlassPanel(
        level: dark ? GlassSurfaceLevel.dark : GlassSurfaceLevel.solid,
        radius: 26,
        opacity: dark ? .68 : .78,
        blur: 18,
        shadow: true,
        child: child,
      );
}

class _TodoListItem extends StatelessWidget {
  final TodoItem todo;
  final DateTime selectedDate;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool onDark;

  const _TodoListItem({
    required this.todo,
    required this.selectedDate,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AmbientPaletteScope.maybeOf(context)?.palette;
    final now = DateTime.now();
    final isToday = selectedDate.year == now.year &&
        selectedDate.month == now.month &&
        selectedDate.day == now.day;
    final checkboxEnabled = !todo.taskType.isRecurring || isToday;
    final deadline = todo.deadline;
    final soon = deadline != null &&
        !todo.isCompleted &&
        deadline.difference(now) <= const Duration(hours: 24);
    final categoryColor = switch (todo.category) {
      TaskCategory.study => onDark ? const Color(0xFFCADBE8) : AppColors.navy,
      TaskCategory.health => onDark ? const Color(0xFFC9D9C5) : AppColors.moss,
      TaskCategory.life => onDark ? const Color(0xFFE7D9C5) : AppColors.olive,
      TaskCategory.work => onDark ? const Color(0xFFD1D7E0) : AppColors.slate,
    };
    return Column(children: [
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          hoverColor: Colors.white.withValues(alpha: onDark ? .08 : .38),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11.5),
            child: Row(children: [
              Semantics(
                button: true,
                label: todo.isCompleted ? '标记为未完成' : '完成任务',
                child: InkWell(
                  onTap: checkboxEnabled ? onToggle : null,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: 23,
                      height: 23,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: todo.isCompleted
                            ? (onDark ? AppColors.warmCream : AppColors.navy)
                            : Colors.transparent,
                        border: Border.all(
                          color: todo.isCompleted
                              ? (onDark ? AppColors.warmCream : AppColors.navy)
                              : (onDark
                                  ? Colors.white.withValues(alpha: .62)
                                  : AppColors.muted),
                          width: 1.5,
                        ),
                      ),
                      child: todo.isCompleted
                          ? Icon(Icons.check,
                              size: 15,
                              color: onDark ? AppColors.warmInk : Colors.white)
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(todo.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: todo.isCompleted
                              ? (onDark
                                  ? palette?.secondaryText
                                      .withValues(alpha: .65)
                                  : AppColors.muted)
                              : (onDark
                                  ? palette?.primaryText ?? Colors.white
                                  : AppColors.ink),
                          decoration: todo.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        )),
                    const SizedBox(height: 5),
                    Row(children: [
                      if (todo.taskType.isRecurring) ...[
                        Icon(Icons.repeat,
                            size: 13,
                            color: onDark
                                ? palette?.secondaryText ?? Colors.white60
                                : AppColors.muted),
                        const SizedBox(width: 4),
                      ],
                      // 分类色点：一行里的轻量层级记号
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: categoryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(todo.category.displayName,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: categoryColor)),
                      if (deadline != null) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            '${deadline.month}月${deadline.day}日 ${deadline.hour.toString().padLeft(2, '0')}:${deadline.minute.toString().padLeft(2, '0')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: soon
                                  ? const Color(0xFFF2D499)
                                  : (onDark
                                      ? palette?.secondaryText
                                      : AppColors.muted),
                              fontWeight:
                                  soon ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '任务操作',
                icon: Icon(Icons.more_horiz,
                    color: onDark ? Colors.white54 : AppColors.muted, size: 20),
                onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 3),
    ]);
  }
}

// 设置对话框
class _SettingsDialog extends StatefulWidget {
  final bool autoStartEnabled;
  final Function(bool) onAutoStartChanged;
  final VoidCallback? onDataRestored;
  final Function(bool)? onTrayResidentChanged;
  final bool trayResident;
  final bool showAmbientBackground;
  final ValueChanged<bool> onAmbientBackgroundChanged;
  final int ambientSceneIndex;
  final String fontColorMode;
  final int? fontColorValue;
  final void Function(String mode, int? value) onFontColorChanged;
  final VoidCallback onAiConfigChanged;
  final bool alwaysOnTop;
  final ValueChanged<bool> onAlwaysOnTopChanged;
  final bool ambientSceneAuto;
  final String? ambientCustomPath;
  final double ambientShade;
  final double glassClarity;
  final double ambientCustomPortraitX;
  final ValueChanged<int> onAmbientSceneChanged;
  final ValueChanged<bool> onAmbientSceneAutoChanged;
  final ValueChanged<double> onAmbientShadeChanged;
  final ValueChanged<double> onGlassClarityPreview;
  final ValueChanged<double> onGlassClarityChanged;
  final ValueChanged<double> onAmbientCustomPortraitXChanged;
  final Future<String?> Function() onImportAmbientScene;

  const _SettingsDialog({
    required this.autoStartEnabled,
    required this.fontColorMode,
    required this.fontColorValue,
    required this.onFontColorChanged,
    required this.onAiConfigChanged,
    required this.alwaysOnTop,
    required this.onAlwaysOnTopChanged,
    required this.onAutoStartChanged,
    this.onDataRestored,
    this.onTrayResidentChanged,
    this.trayResident = true,
    required this.showAmbientBackground,
    required this.onAmbientBackgroundChanged,
    required this.ambientSceneIndex,
    required this.ambientSceneAuto,
    required this.ambientCustomPath,
    required this.ambientShade,
    required this.glassClarity,
    required this.ambientCustomPortraitX,
    required this.onAmbientSceneChanged,
    required this.onAmbientSceneAutoChanged,
    required this.onAmbientShadeChanged,
    required this.onGlassClarityPreview,
    required this.onGlassClarityChanged,
    required this.onAmbientCustomPortraitXChanged,
    required this.onImportAmbientScene,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  AiConfig _aiConfig = const AiConfig();
  String _appVersion = '';
  String _updateState = 'idle'; // idle | checking | latest | available | error
  ReleaseInfo? _newRelease;
  String? _updateError;

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {}
  }

  Future<void> _checkForUpdate() async {
    setState(() => _updateState = 'checking');
    try {
      final info = await PackageInfo.fromPlatform();
      final release = await UpdateService.instance.fetchLatestRelease();
      if (!mounted) return;
      if (release == null) {
        setState(() {
          _updateState = 'latest';
          _updateError = null;
        });
        return;
      }
      final newer = UpdateService.isNewerVersion(release.version, info.version);
      setState(() {
        _newRelease = release;
        _updateState = newer ? 'available' : 'latest';
        _updateError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updateState = 'error';
        _updateError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openDownload() async {
    final release = _newRelease;
    if (release == null) return;
    final isAndroid = Platform.isAndroid;
    final url = isAndroid
        ? (release.androidUrl ?? release.pageUrl)
        : (release.windowsUrl ?? release.pageUrl);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _updateAiConfig(AiConfig config) async {
    await AiService.instance.saveConfig(config);
    if (mounted) setState(() => _aiConfig = config);
    widget.onAiConfigChanged();
  }

  // 字体颜色的本地镜像：showDialog 路由不随父重建，
  // 选择后需要 setState 才能即时看到选中态变化
  late String _localFontMode = widget.fontColorMode;
  late int? _localFontValue = widget.fontColorValue;
  late bool _autoStartEnabled;
  late bool _showAmbientBackground;
  late int _ambientSceneIndex;
  late bool _ambientSceneAuto;
  late String? _ambientCustomPath;
  late double _ambientShade;
  late double _glassClarity;
  late double _ambientCustomPortraitX;

  // 数据备份与恢复
  bool _dataBusy = false;
  String? _dataStatus;
  bool _dataStatusIsError = false;
  String _autoBackupInfo = '';

  // 通知与后台
  late bool _trayResident;

  @override
  void initState() {
    super.initState();
    _autoStartEnabled = widget.autoStartEnabled;
    _showAmbientBackground = widget.showAmbientBackground;
    _ambientSceneIndex = widget.ambientSceneIndex;
    _ambientSceneAuto = widget.ambientSceneAuto;
    _ambientCustomPath = widget.ambientCustomPath;
    _ambientShade = widget.ambientShade;
    _glassClarity = widget.glassClarity;
    _ambientCustomPortraitX = widget.ambientCustomPortraitX;
    _trayResident = widget.trayResident;
    _loadAppVersion();
    _loadAutoBackupInfo();
    AiService.instance.loadConfig().then((config) {
      if (mounted) setState(() => _aiConfig = config);
    });
  }

  Future<void> _saveTrayResident(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tray_resident', value);
    } catch (_) {}
  }

  Future<void> _loadAutoBackupInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final at = prefs.getString(BackupService.lastAutoBackupAtKey);
    if (!mounted) return;
    if (at == null) {
      setState(() => _autoBackupInfo = '暂无自动备份记录');
      return;
    }
    final verified = prefs.getBool(BackupService.lastAutoBackupVerifiedKey);
    final dt = DateTime.tryParse(at);
    final time = dt != null
        ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : at;
    setState(() {
      _autoBackupInfo = '上次自动备份：$time'
          '（迁移后验证${verified == true ? '通过' : '未通过/未执行'}，'
          '备份位于文档目录 backups 文件夹）';
    });
  }

  Future<void> _exportData() async {
    setState(() {
      _dataBusy = true;
      _dataStatus = null;
    });
    try {
      final file =
          await BackupService.instance.exportToFile(IsarService.instance.isar);
      if (!mounted) return;
      if (Platform.isAndroid || Platform.isIOS) {
        // 移动端导出文件在应用私有目录，系统文件选择器无法访问；
        // 直接调起系统分享，由用户选择"保存到文件"或发送到电脑
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)],
          title: '待办数据备份',
        ));
        setState(() {
          _dataStatus = '已生成备份文件并调起系统分享（可"保存到文件"或发送出去）';
          _dataStatusIsError = false;
        });
      } else {
        setState(() {
          _dataStatus = '已导出到：${file.path}';
          _dataStatusIsError = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dataStatus = '导出失败：$e';
        _dataStatusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _dataBusy = false);
    }
  }

  Future<void> _restoreData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('覆盖恢复'),
        content: const Text(
          '恢复将清空当前设备的全部数据（待办、课程、备忘录、打卡记录等），'
          '并用所选备份文件整体替换。此操作不可撤销，确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('继续恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: '选择备份文件',
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    setState(() {
      _dataBusy = true;
      _dataStatus = null;
    });
    try {
      final json = await File(path).readAsString();
      final summary = await BackupService.instance
          .restoreFromJson(json, IsarService.instance.isar);
      widget.onDataRestored?.call();
      if (!mounted) return;
      setState(() {
        _dataStatus = '已恢复 ${summary.total} 条记录'
            '${summary.verified ? '（验证通过）' : '（验证未通过，请检查备份文件）'}。'
            '建议重启应用以刷新所有页面。';
        _dataStatusIsError = !summary.verified;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dataStatus = '恢复失败：$e';
        _dataStatusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _dataBusy = false);
    }
  }

  /// 关于与更新：当前版本 + 检查更新 + 下载入口
  Widget _aboutUpdateSection(ThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.system_update, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text('关于与更新', style: theme.textTheme.titleSmall),
        const Spacer(),
        Text('当前版本 v${_appVersion.isEmpty ? "…" : _appVersion}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
      const SizedBox(height: 4),
      if (_updateState == 'checking')
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
        )
      else ...[
        if (_updateState == 'available' && _newRelease != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('发现新版本 v${_newRelease!.version}',
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600)),
                  if (_newRelease!.notes.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_newRelease!.notes.trim(),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _openDownload,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('前往下载'),
                  ),
                ]),
          ),
        ] else if (_updateState == 'error') ...[
          Text('检查失败：$_updateError',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
        ] else if (_updateState == 'latest')
          Text('已是最新版本。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        TextButton.icon(
          onPressed: _checkForUpdate,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('检查更新'),
        ),
      ],
    ]);
  }

  /// AI 助手配置：端点 / Key / 模型 / 数据上传范围 / 测试连接
  Widget _aiSection(ThemeData theme) {
    final config = _aiConfig;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text('AI 助手', style: theme.textTheme.titleSmall),
        const Spacer(),
        Switch(
          value: config.enabled,
          onChanged: (v) => _updateAiConfig(config.copyWith(enabled: v)),
        ),
      ]),
      if (config.enabled) ...[
        TextField(
          controller: TextEditingController(text: config.baseUrl),
          onSubmitted: (v) =>
              _updateAiConfig(config.copyWith(baseUrl: v.trim())),
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'API 地址（OpenAI 兼容）',
            hintText: AiConfig.defaultBaseUrl,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: TextEditingController(text: config.apiKey),
          obscureText: true,
          onSubmitted: (v) =>
              _updateAiConfig(config.copyWith(apiKey: v.trim())),
          decoration: InputDecoration(
            isDense: true,
            labelText: 'API Key（仅保存在本机）',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.check, size: 18),
              tooltip: '保存',
              onPressed: () =>
                  _updateAiConfig(config.copyWith(apiKey: config.apiKey)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: TextEditingController(text: config.model),
              onSubmitted: (v) =>
                  _updateAiConfig(config.copyWith(model: v.trim())),
              decoration: const InputDecoration(
                isDense: true,
                labelText: '模型（可选预设或手动输入）',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: '常用模型预设',
            onSelected: (value) {
              // 选择预设时联动对应的 API 地址
              final match = AiConfig.modelPresets
                  .firstWhere((p) => p.$2 == value, orElse: () => ('', '', ''));
              _updateAiConfig(config.copyWith(
                  model: value,
                  baseUrl: match.$3.isEmpty ? config.baseUrl : match.$3));
            },
            itemBuilder: (context) => [
              for (final group
                  in AiConfig.modelPresets.map((p) => p.$1).toSet()) ...[
                PopupMenuItem<String>(
                    enabled: false,
                    child: Text(group,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.primary))),
                for (final (_, model, _)
                    in AiConfig.modelPresets.where((p) => p.$1 == group))
                  PopupMenuItem<String>(
                      value: model,
                      child: Text(model, style: theme.textTheme.bodyMedium)),
              ],
            ],
            color: AppColors.paper,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.list, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text('预设',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text('允许 AI 读取的数据（用于生成建议）', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final (key, label) in const [
            ('scopeTodos', '任务'),
            ('scopeCourses', '课程'),
            ('scopeFocus', '专注'),
            ('scopeTraining', '训练'),
            ('scopeDiet', '饮食'),
            ('scopeFatLoss', '减脂目标'),
          ])
            FilterChip(
              label: Text(label),
              selected: switch (key) {
                'scopeTodos' => config.scopeTodos,
                'scopeCourses' => config.scopeCourses,
                'scopeFocus' => config.scopeFocus,
                'scopeTraining' => config.scopeTraining,
                'scopeDiet' => config.scopeDiet,
                _ => config.scopeFatLoss,
              },
              onSelected: (v) => _updateAiConfig(switch (key) {
                'scopeTodos' => config.copyWith(scopeTodos: v),
                'scopeCourses' => config.copyWith(scopeCourses: v),
                'scopeFocus' => config.copyWith(scopeFocus: v),
                'scopeTraining' => config.copyWith(scopeTraining: v),
                'scopeDiet' => config.copyWith(scopeDiet: v),
                _ => config.copyWith(scopeFatLoss: v),
              }),
              visualDensity: VisualDensity.compact,
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final reply = await AiService.instance
                    .testConnection(config)
                    .timeout(const Duration(seconds: 20));
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('连接成功：$reply')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          '连接失败：${e.toString().replaceFirst('Exception: ', '')}')));
                }
              }
            },
            icon: const Icon(Icons.wifi_tethering, size: 16),
            label: const Text('测试连接'),
          ),
        ]),
        Text(
            '发送内容为按上面勾选范围构建的今日数据摘要；'
            'Key 仅保存在本机。悬浮球会在配置完成后出现。',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
      ],
      const Divider(),
    ]);
  }

  Widget _fontColorDot({
    required String label,
    required String mode,
    required Color? color,
    required bool selected,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        setState(() {
          _localFontMode = mode;
          _localFontValue = mode == 'custom' ? color?.toARGB32() : null;
        });
        widget.onFontColorChanged(
            mode, mode == 'custom' ? color?.toARGB32() : null);
      },
      child: Column(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color ?? theme.colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: color == null
              ? Center(
                  child: Text('自动',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600)))
              : selected
                  ? Icon(Icons.check,
                      size: 18,
                      color: color.computeLuminance() > .45
                          ? Colors.black87
                          : Colors.white)
                  : null,
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ]),
    );
  }

  /// 提醒权限状态区块：通知权限 / 精确闹钟，点击直接申请
  List<Widget> _reminderPermissionSection(ThemeData theme) {
    return [
      Text('提醒权限', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      FutureBuilder<bool>(
        future: ReminderService.instance.notificationsEnabled(),
        builder: (context, snapshot) {
          final ok = snapshot.data ?? true;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              ok ? Icons.notifications_active : Icons.notifications_off,
              color: ok
                  ? theme.colorScheme.primary
                  : const Color(0xFFA66A10), // 深琥珀：纸面上对比度达标
            ),
            title: const Text('系统通知权限'),
            subtitle: Text(ok ? '已允许' : '未允许，提醒将无法显示'),
            trailing: ok
                ? null
                : TextButton(
                    onPressed: () async {
                      await ReminderService.instance
                          .requestNotificationPermission();
                      if (mounted) setState(() {});
                    },
                    child: const Text('去开启'),
                  ),
          );
        },
      ),
      FutureBuilder<bool>(
        future: ReminderService.instance.exactAlarmsEnabled(),
        builder: (context, snapshot) {
          final ok = snapshot.data ?? true;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              ok ? Icons.alarm_on : Icons.alarm_off,
              color: ok ? theme.colorScheme.primary : const Color(0xFFA66A10),
            ),
            title: const Text('精确闹钟'),
            subtitle: Text(ok ? '已允许，提醒准时触发' : '未允许，提醒可能延迟几分钟'),
            trailing: ok
                ? null
                : TextButton(
                    onPressed: () async {
                      await ReminderService.instance
                          .requestExactAlarmsPermission();
                      if (mounted) setState(() {});
                    },
                    child: const Text('去开启'),
                  ),
          );
        },
      ),
      const Divider(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewColor = switch (_localFontMode) {
      'white' => Colors.white,
      'black' => const Color(0xFF172A3A),
      'custom' => _localFontValue == null
          ? Colors.white
          : Color(_localFontValue!),
      _ => const Color(0xFFF5F7F6),
    };

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.settings, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          const Text('设置'),
        ],
      ),
      content: SingleChildScrollView(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI 助手配置
          _aiSection(theme),
          const SizedBox(height: 6),
          // 关于与更新
          _aboutUpdateSection(theme),
          const SizedBox(height: 6),
          if (Platform.isWindows)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.alwaysOnTop,
              onChanged: widget.onAlwaysOnTopChanged,
              title: const Text('窗口置顶'),
              subtitle: const Text('像微信一样钉在屏幕上，点击其他窗口也不会被遮住'),
            ),
          // 提醒权限状态（仅 Android）：竖屏手机提醒是最核心的触达
          if (Platform.isAndroid) ..._reminderPermissionSection(theme),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showAmbientBackground,
            onChanged: (value) {
              setState(() => _showAmbientBackground = value);
              widget.onAmbientBackgroundChanged(value);
            },
            title: const Text('沉浸背景'),
            subtitle: const Text('背景照片会适配当前窗口，内容保持清晰'),
          ),
          if (_showAmbientBackground) ...[
            const SizedBox(height: 12),
            Text('字体颜色', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('自定义背景配不上场景色时，手动指定文字颜色',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _fontColorDot(
                  label: '自动',
                  mode: 'auto',
                  color: null,
                  selected: _localFontMode == 'auto'),
              _fontColorDot(
                  label: '白',
                  mode: 'white',
                  color: Colors.white,
                  selected: _localFontMode == 'white'),
              _fontColorDot(
                  label: '黑',
                  mode: 'black',
                  color: const Color(0xFF172A3A),
                  selected: _localFontMode == 'black'),
              for (final preset in const [
                Color(0xFFFFE9C8),
                Color(0xFFBFE3FF),
                Color(0xFFC9F0D8),
                Color(0xFFFFD6E0),
                Color(0xFFE3D5FF),
                Color(0xFFFFE0B2),
                Color(0xFFB2EBF2),
                Color(0xFFF5F7F6),
              ])
                _fontColorDot(
                  label: '',
                  mode: 'custom',
                  color: preset,
                  selected: _localFontMode == 'custom' &&
                      _localFontValue == preset.toARGB32(),
                ),
            ]),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: previewColor.computeLuminance() < .35
                    ? const Color(0xFFDCE6EC)
                    : const Color(0xFF263643),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '文字颜色预览 · 今天要完成的事',
                style: TextStyle(
                  color: previewColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('背景场景', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: const Text('随时间'),
                selected: _ambientSceneAuto,
                onSelected: (_) {
                  setState(() => _ambientSceneAuto = true);
                  widget.onAmbientSceneAutoChanged(true);
                },
              ),
              for (var index = 0;
                  index < AmbientBackdrop.sceneAssets.length;
                  index++)
                ChoiceChip(
                  label: Text(AmbientBackdrop.sceneNames[index]),
                  selected: !_ambientSceneAuto && _ambientSceneIndex == index,
                  onSelected: (_) {
                    setState(() {
                      _ambientSceneIndex = index;
                      _ambientSceneAuto = false;
                    });
                    widget.onAmbientSceneChanged(index);
                  },
                ),
              if (_ambientCustomPath != null)
                ChoiceChip(
                  label: const Text('我的照片'),
                  selected: !_ambientSceneAuto &&
                      _ambientSceneIndex == AmbientBackdrop.sceneAssets.length,
                  onSelected: (_) {
                    setState(() {
                      _ambientSceneIndex = AmbientBackdrop.sceneAssets.length;
                      _ambientSceneAuto = false;
                    });
                    widget.onAmbientSceneChanged(_ambientSceneIndex);
                  },
                ),
              ActionChip(
                avatar:
                    const Icon(Icons.add_photo_alternate_outlined, size: 17),
                label: const Text('导入照片'),
                onPressed: () async {
                  final path = await widget.onImportAmbientScene();
                  if (!mounted || path == null) return;
                  setState(() {
                    _ambientCustomPath = path;
                    _ambientSceneIndex = AmbientBackdrop.sceneAssets.length;
                    _ambientSceneAuto = false;
                  });
                },
              ),
            ]),
            const SizedBox(height: 6),
            Text('随时间：05–09 日出 · 09–17 午后 · 17–20 晚霞 · 20–05 夜色。',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Text('背景明暗', style: theme.textTheme.titleSmall),
            Slider(
              value: _ambientShade,
              min: .04,
              max: .24,
              onChanged: (value) {
                setState(() => _ambientShade = value);
                widget.onAmbientShadeChanged(value);
              },
            ),
            Text('只调整照片，不改变文字和按钮。', style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('玻璃通透度', style: theme.textTheme.titleSmall)),
              Text('${(_glassClarity * 100).round()}%',
                  style: theme.textTheme.bodySmall),
            ]),
            Slider(
              value: _glassClarity,
              min: 0,
              max: 1,
              onChanged: (value) {
                setState(() => _glassClarity = value);
                widget.onGlassClarityPreview(value);
              },
              onChangeEnd: widget.onGlassClarityChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('更磨砂', style: theme.textTheme.bodySmall),
                Text('更通透', style: theme.textTheme.bodySmall),
              ],
            ),
            if (!_ambientSceneAuto &&
                _ambientSceneIndex == AmbientBackdrop.sceneAssets.length &&
                _ambientCustomPath != null) ...[
              const SizedBox(height: 12),
              Text('竖屏照片裁切', style: theme.textTheme.titleSmall),
              Slider(
                value: _ambientCustomPortraitX,
                min: -1,
                max: 1,
                onChanged: (value) {
                  setState(() => _ambientCustomPortraitX = value);
                  widget.onAmbientCustomPortraitXChanged(value);
                },
              ),
              Text('左右移动裁切焦点，宽屏仍保持居中。', style: theme.textTheme.bodySmall),
            ],
          ],
          const Divider(height: 32),
          Text(
            '开机自启动',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '启用后，应用将在 Windows 启动时自动运行',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _autoStartEnabled,
            onChanged: (value) {
              setState(() => _autoStartEnabled = value);
              widget.onAutoStartChanged(value);
            },
            title: Text(
              _autoStartEnabled ? '已启用开机自启动' : '未启用开机自启动',
              style: theme.textTheme.bodyMedium,
            ),
            subtitle: Text(
              _autoStartEnabled ? '应用将随系统启动' : '需要手动启动应用',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 32),
          // 通知与后台
          Text(
            '通知与后台',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ReminderService.instance.statusDescription(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _trayResident,
              onChanged: (v) {
                setState(() => _trayResident = v);
                widget.onTrayResidentChanged?.call(v);
                _saveTrayResident(v);
              },
              title: const Text('关闭窗口时驻留系统托盘'),
              subtitle: const Text('驻留时提醒持续可用；关闭后点关闭按钮将真正退出，提醒不再可用'),
            ),
          ],
          const Divider(height: 32),
          // 数据备份与恢复
          Text(
            '数据备份与恢复',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _autoBackupInfo,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _dataBusy ? null : _exportData,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: const Text('导出数据'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _dataBusy ? null : _restoreData,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('恢复数据'),
              ),
            ],
          ),
          if (_dataBusy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          if (_dataStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      _dataStatus!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _dataStatusIsError
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  if (!_dataStatusIsError && _dataStatus!.contains('导出'))
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      tooltip: '复制路径',
                      onPressed: () {
                        final path =
                            _dataStatus!.replaceFirst('已导出到：', '').trim();
                        Clipboard.setData(ClipboardData(text: path));
                      },
                    ),
                ],
              ),
            ),
        ],
      )),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

// 任务编辑对话框
class _TodoEditDialog extends StatefulWidget {
  final TodoItem todo;

  const _TodoEditDialog({required this.todo});

  @override
  State<_TodoEditDialog> createState() => _TodoEditDialogState();
}

class _TodoEditDialogState extends State<_TodoEditDialog> {
  late TextEditingController _titleController;
  late TextEditingController _notesController;
  late TaskType _type;
  late TaskCategory _category;
  late DateTime _date;

  // 提醒
  bool _remindEnabled = false;
  DateTime? _startTime;
  DateTime? _deadline;
  int _remindLead = 15;
  bool _customLead = false;
  final TextEditingController _customLeadController = TextEditingController();

  // 每日习惯的打卡提醒（与一次性任务的提醒相互独立）
  bool _habitRemindOn = false;
  int _habitRemindMinutes = 21 * 60; // 默认 21:00

  static const List<int> _presetLeads = [5, 10, 15, 30, 60, 120];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.todo.title);
    _notesController = TextEditingController(text: widget.todo.notes ?? '');
    _type = widget.todo.taskType;
    _category = widget.todo.category;
    _date = widget.todo.createdDate;
    _remindEnabled = widget.todo.isReminderEnabled;
    _startTime = widget.todo.startTime;
    _deadline = widget.todo.deadline;
    _remindLead = widget.todo.remindBeforeMinutes;
    _customLead = !_presetLeads.contains(_remindLead);
    if (_customLead) {
      _customLeadController.text = '$_remindLead';
    }
    _habitRemindOn =
        widget.todo.isReminderEnabled && widget.todo.habitRemindMinutes != null;
    _habitRemindMinutes = widget.todo.habitRemindMinutes ?? 21 * 60;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _customLeadController.dispose();
    super.dispose();
  }

  Widget _dateTimeRow({
    required ThemeData theme,
    required String label,
    required DateTime? value,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onPick,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value != null
                          ? '${value.year}-${p2(value.month)}-${p2(value.day)} ${p2(value.hour)}:${p2(value.minute)}'
                          : '$label（未设置）',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: value != null
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (value != null)
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            tooltip: '清除${label.replaceAll('时间', '')}时间',
            onPressed: onClear,
          ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickDateTime(bool isDeadline) async {
    final initial = (isDeadline ? _deadline : _startTime) ??
        DateTime(_date.year, _date.month, _date.day, 9, 0);
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    );
    if (time == null || !mounted) return;
    final value =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isDeadline) {
        _deadline = value;
      } else {
        _startTime = value;
      }
    });
  }

  Future<void> _pickHabitTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: _habitRemindMinutes ~/ 60, minute: _habitRemindMinutes % 60),
    );
    if (time == null || !mounted) return;
    setState(() => _habitRemindMinutes = time.hour * 60 + time.minute);
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标题不能为空')),
      );
      return;
    }

    var lead = _remindLead;
    if (_customLead) {
      lead = int.tryParse(_customLeadController.text.trim()) ?? 0;
      if (lead < 0) lead = 0;
    }
    if (_remindEnabled && _startTime == null && _deadline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开启提醒需要先设置开始时间或截止时间')),
      );
      return;
    }

    final todo = widget.todo;
    todo.title = title;
    todo.taskType = _type;
    todo.category = _category;
    todo.notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    todo.createdDate = DateTime(_date.year, _date.month, _date.day);
    todo.startTime = _startTime;
    todo.deadline = _deadline;
    if (_type.isRecurring) {
      // 每日习惯：走打卡提醒体系（每天固定时刻）
      todo.isReminderEnabled = _habitRemindOn;
      todo.habitRemindMinutes = _habitRemindOn ? _habitRemindMinutes : null;
    } else {
      todo.isReminderEnabled = _remindEnabled;
      todo.habitRemindMinutes = null;
    }
    todo.remindBeforeMinutes = lead;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekday =
        ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][_date.weekday - 1];

    return AlertDialog(
      title: const Text('编辑任务'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '标题',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 类型
              Text('类型',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _TaskTypeButton(
                    type: TaskType.oneTime,
                    isSelected: _type == TaskType.oneTime,
                    onTap: () => setState(() => _type = TaskType.oneTime),
                  ),
                  const SizedBox(width: 8),
                  _TaskTypeButton(
                    type: TaskType.recurring,
                    isSelected: _type == TaskType.recurring,
                    onTap: () => setState(() => _type = TaskType.recurring),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 分类
              Text('分类',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TaskCategory.values
                    .map((category) => _CategoryButton(
                          category: category,
                          isSelected: _category == category,
                          onTap: () => setState(() => _category = category),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),

              // 日期（一次性任务=任务日期；每日习惯=开始日期）
              Text(
                _type.isRecurring ? '开始日期（此前日期不计入统计）' : '任务日期',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDate,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 20),
                      const SizedBox(width: 12),
                      Text(
                          '${_date.year}年${_date.month}月${_date.day}日 $weekday'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              const Divider(),
              if (_type.isRecurring) ...[
                // 每日习惯：每天固定时刻的打卡提醒
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _habitRemindOn,
                  onChanged: (v) => setState(() => _habitRemindOn = v),
                  title: const Text('打卡提醒'),
                  subtitle: const Text('每天在固定时刻提醒打卡（需系统通知权限）'),
                ),
                if (_habitRemindOn)
                  InkWell(
                    onTap: _pickHabitTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: theme.colorScheme.outlineVariant),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule, size: 18),
                          const SizedBox(width: 8),
                          Text(
                              '每天 ${(_habitRemindMinutes ~/ 60).toString().padLeft(2, '0')}:${(_habitRemindMinutes % 60).toString().padLeft(2, '0')} 提醒打卡'),
                        ],
                      ),
                    ),
                  ),
              ] else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _remindEnabled,
                  onChanged: (v) => setState(() => _remindEnabled = v),
                  title: const Text('提醒'),
                  subtitle: const Text('到点后发送系统通知（需系统通知权限）'),
                ),
                if (_remindEnabled) ...[
                  _dateTimeRow(
                    theme: theme,
                    label: '开始时间',
                    value: _startTime,
                    onPick: () => _pickDateTime(false),
                    onClear: () => setState(() => _startTime = null),
                  ),
                  const SizedBox(height: 8),
                  _dateTimeRow(
                    theme: theme,
                    label: '截止时间',
                    value: _deadline,
                    onPick: () => _pickDateTime(true),
                    onClear: () => setState(() => _deadline = null),
                  ),
                  const SizedBox(height: 12),
                  Text('提前提醒',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._presetLeads.map((lead) => ChoiceChip(
                            label: Text('$lead 分钟'),
                            selected: !_customLead && _remindLead == lead,
                            onSelected: (_) => setState(() {
                              _customLead = false;
                              _remindLead = lead;
                            }),
                            visualDensity: VisualDensity.compact,
                          )),
                      ChoiceChip(
                        label: const Text('自定义'),
                        selected: _customLead,
                        onSelected: (_) => setState(() => _customLead = true),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (_customLead)
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _customLeadController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: '分钟',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '提醒优先按截止时间计算，未设置截止时间则按开始时间',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

// 筛选按钮
class _CategoryButton extends StatelessWidget {
  final TaskCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryButton({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getCategoryColor(category);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? color
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              category.displayName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(TaskCategory category) {
    return AppColors.navy;
  }
}

// ==================== 今日仪表盘数据 ====================

class _TodayBrief {
  final String? nextCourseName;
  final String? nextCourseLocation;
  final String? nextCourseStartLabel;
  final DateTime? nextCourseAt;
  final int courseCountToday;
  final int focusMinutes;
  final int dietCount;
  final int expenseTodayCents;
  final int workoutsToday;
  final List<_ArcEvent> events;

  const _TodayBrief({
    this.nextCourseName,
    this.nextCourseLocation,
    this.nextCourseStartLabel,
    this.nextCourseAt,
    required this.courseCountToday,
    required this.focusMinutes,
    required this.dietCount,
    required this.expenseTodayCents,
    required this.workoutsToday,
    required this.events,
  });
}

class _RecentActivity {
  const _RecentActivity(this.at, this.title, this.moduleIndex,
      {this.timed = true});

  final DateTime at;
  final String title;
  final int moduleIndex;
  final bool timed;
}

enum _ArcKind { course, task, focus, training, diet, expense }

class _ArcEvent {
  final DateTime at;
  final _ArcKind kind;
  final String? detail;
  final bool timed;
  const _ArcEvent(this.at, this.kind, [this.detail, this.timed = true]);
}

/// 今日轨迹：6:00-24:00 的一条时间轴，事件以小点落位，琥珀竖线标记现在。
class _DayArcPainter extends CustomPainter {
  final List<_ArcEvent> events;
  final DateTime now;
  final Color labelColor;

  _DayArcPainter({
    required this.events,
    required this.now,
    required this.labelColor,
  });

  static const _startHour = 6.0;
  static const _spanHours = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height * 0.62;
    double xOf(DateTime time) {
      final hours = time.hour + time.minute / 60.0 - _startHour;
      return (hours.clamp(0.0, _spanHours) / _spanHours) * size.width;
    }

    // 基线：一道极轻的承载线
    final base = Paint()
      ..color = Colors.white.withValues(alpha: .30)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), base);

    // 小时刻度与标签
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: .34)
      ..strokeWidth = 1;
    for (final hour in const [6, 9, 12, 15, 18, 21, 24]) {
      final x = (hour - _startHour) / _spanHours * size.width;
      canvas.drawLine(Offset(x, cy - 3), Offset(x, cy + 3), tick);
      _label(canvas, '$hour', Offset(x, cy - 22),
          align: hour == 6
              ? TextAlign.left
              : (hour == 24 ? TextAlign.right : TextAlign.center),
          width: 30);
    }

    // 事件：颜色各异的小记号，专注与训练带微弱光晕
    for (final event in events) {
      if (!event.timed) continue;
      final x = xOf(event.at);
      switch (event.kind) {
        case _ArcKind.course:
          final paint = Paint()..color = const Color(0xFFBFD3E0);
          canvas.drawCircle(Offset(x, cy), 3.5, paint);
        case _ArcKind.task:
          final paint = Paint()
            ..color = Colors.white.withValues(alpha: .92)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawCircle(Offset(x, cy), 3.5, paint);
        case _ArcKind.focus:
          final halo = Paint()..color = AppColors.amber.withValues(alpha: .22);
          canvas.drawCircle(Offset(x, cy), 8, halo);
          final paint = Paint()..color = AppColors.amber;
          canvas.drawCircle(Offset(x, cy), 3.8, paint);
        case _ArcKind.training:
          final halo = Paint()
            ..color = const Color(0xFFB9CDB0).withValues(alpha: .18);
          canvas.drawCircle(Offset(x, cy), 7.5, halo);
          final paint = Paint()..color = const Color(0xFFB9CDB0);
          final rect =
              Rect.fromCenter(center: Offset(x, cy), width: 6, height: 6);
          canvas.drawRect(rect, paint);
        case _ArcKind.diet:
          canvas.drawCircle(
              Offset(x, cy), 3.5, Paint()..color = const Color(0xFFD6C7AD));
        case _ArcKind.expense:
          canvas.drawCircle(
              Offset(x, cy), 3.5, Paint()..color = const Color(0xFFB7C6D3));
      }
    }

    // 现在：琥珀竖线 + 光晕，标记"正在发生"
    if (now.hour + now.minute / 60.0 >= _startHour) {
      final x = xOf(now);
      final halo = Paint()..color = AppColors.amber.withValues(alpha: .20);
      canvas.drawCircle(Offset(x, cy), 7, halo);
      final nowPaint = Paint()
        ..color = AppColors.amber
        ..strokeWidth = 1.8;
      canvas.drawLine(Offset(x, cy - 11), Offset(x, cy + 7), nowPaint);
      canvas.drawCircle(Offset(x, cy), 2.2, nowPaint);
    }
  }

  void _label(Canvas canvas, String text, Offset at,
      {required TextAlign align, required double width}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppTypography.sans,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: labelColor,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: width);
    var dx = at.dx - width / 2;
    if (align == TextAlign.left) dx = at.dx;
    if (align == TextAlign.right) dx = at.dx - width;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(_DayArcPainter old) =>
      old.labelColor != labelColor ||
      old.now != now ||
      old.events.length != events.length ||
      old.now.difference(now).inMinutes != 0;
}

/// 底部导航中心的专注符号：克制的圆环，选中时琥珀点亮
class _FocusGlyph extends StatelessWidget {
  final bool selected;
  const _FocusGlyph({required this.selected});

  @override
  Widget build(BuildContext context) {
    // 与底部导航配色一致：未选白色，选中橘色圆环
    final color = selected
        ? AppColors.warmAmber
        : AmbientPaletteScope.maybeOf(context)?.palette.secondaryText ??
            Colors.white.withValues(alpha: .95);
    return Container(
      width: 30,
      height: 30,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? AppColors.amber : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
