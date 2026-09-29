import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../models/todo_item.dart';
import '../services/isar_service.dart';
import '../services/focus_analytics_service.dart';
import '../services/pomodoro_service.dart';
import '../ui/app_theme.dart';
import '../ui/ambient_backdrop.dart';
import '../ui/ambient_palette.dart';
import '../ui/glass_panel.dart';
import 'focus_insights_page.dart';

/// 番茄钟页面：进度环 + 沉浸模式
class PomodoroPage extends StatefulWidget {
  final VoidCallback? onExit;
  final VoidCallback? onOpenTodo;
  final bool? focusImmersive;
  final Future<void> Function(bool)? onFocusImmersiveChanged;

  /// 全局环境背景开启且专注页未自选专属场景时，直接透传全局背景，
  /// 避免两层照片在标题栏下缘拼出硬分割线。
  final bool inheritBackdrop;

  const PomodoroPage({
    super.key,
    this.onExit,
    this.onOpenTodo,
    this.focusImmersive,
    this.onFocusImmersiveChanged,
    this.inheritBackdrop = false,
  });

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  final PomodoroService _svc = PomodoroService.instance;
  static const _sceneKey = 'focus_scene_index';
  static const _sceneAutoKey = 'focus_scene_auto';
  static const _scenes = [
    _FocusScene('assets/backgrounds/alpine_night.png', '山间夜色'),
    _FocusScene('background1.png', '雪山湖畔'),
    _FocusScene('background2.png', '晴日草原', quarterTurns: 3),
    _FocusScene('background3.png', '山间列车'),
    _FocusScene('background4.png', '窗边晚霞'),
    _FocusScene('background5.png', '日落雪原'),
    _FocusScene('assets/backgrounds/alpine_noon.png', '山间午后'),
    _FocusScene('assets/backgrounds/alpine_dawn.png', '山间日出'),
    _FocusScene('assets/backgrounds/alpine_dusk.png', '山间晚霞'),
  ];
  int _sceneIndex = 6;
  bool _sceneAuto = true;
  int _sceneRequest = 0;
  int _lastAutoSceneIndex = _focusSceneForHour(DateTime.now().hour);
  Timer? _sceneClockTimer;
  String? _customScenePath;
  bool _todoDrawerOpen = false;
  double _sceneX = 0;
  double _sceneY = 0;
  double _sceneShade = 0.16;
  List<TodoItem> _todayTodos = [];
  StreamSubscription<void>? _todoSubscription;
  PomodoroRunPhase? _lastPhase;
  bool _endingManually = false;
  bool _completionDialogOpen = false;

  static int _focusSceneForHour(int hour) =>
      switch (AmbientBackdrop.sceneForHour(hour)) {
        0 => 6,
        1 => 8,
        2 => 0,
        _ => 7,
      };

  int get _effectiveSceneIndex =>
      _sceneAuto ? _focusSceneForHour(DateTime.now().hour) : _sceneIndex;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChanged);
    _lastPhase = _svc.runningPhase;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _svc.completionChoicePending) _askTaskCompletion();
    });
    _loadTodayStats();
    _loadScene();
    _sceneClockTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!_sceneAuto || !mounted) return;
      final index = _focusSceneForHour(DateTime.now().hour);
      if (index != _lastAutoSceneIndex) {
        await _precacheScene(index);
        if (!mounted || !_sceneAuto) return;
        _lastAutoSceneIndex = index;
        _loadActiveSceneAppearance(index);
      }
    });
    _loadSoundPreference();
    _loadTodayTodos();
    try {
      _todoSubscription = IsarService.instance.isar.todoItems
          .watchLazy()
          .listen((_) => _loadTodayTodos());
    } catch (_) {}
  }

  Future<void> _loadSoundPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => PomodoroService.playSounds =
          prefs.getBool('focus_alert_sound') ?? true);
    }
  }

  Future<void> _toggleSound() async {
    setState(() => PomodoroService.playSounds = !PomodoroService.playSounds);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focus_alert_sound', PomodoroService.playSounds);
  }

  @override
  void dispose() {
    _sceneClockTimer?.cancel();
    _svc.removeListener(_onChanged);
    _todoSubscription?.cancel();
    if (_isImmersive && !Platform.isWindows) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
    if (_lastPhase != _svc.runningPhase) {
      final finishedFocus = _lastPhase == PomodoroRunPhase.focus &&
          _svc.runningPhase == null &&
          _svc.completionChoicePending;
      _lastPhase = _svc.runningPhase;
      _loadTodayStats();
      if (finishedFocus && !_endingManually) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _askTaskCompletion();
        });
      }
    }
  }

  Future<void> _loadScene() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selected = prefs.getInt(_sceneKey) ?? 6;
      final customPath = prefs.getString('focus_custom_scene');
      final validCustom = customPath != null && File(customPath).existsSync();
      final auto = prefs.getBool(_sceneAutoKey) ??
          (!prefs.containsKey(_sceneKey) && customPath == null);
      final catalogVersion = prefs.getInt('focus_scene_catalog_version') ?? 0;
      // Catalog v1 used index 7 for a personal image; older builds used 6.
      final oldCustom = catalogVersion < 2 &&
          (selected == 7 ||
              (catalogVersion == 0 && customPath != null && selected == 6));
      final restoredIndex =
          oldCustom ? (validCustom ? _scenes.length : 6) : selected;
      if (restoredIndex != selected) {
        await prefs.setInt(_sceneKey, restoredIndex);
      }
      await prefs.setInt('focus_scene_catalog_version', 2);
      if (mounted) {
        setState(() {
          _customScenePath = validCustom ? customPath : null;
          _sceneIndex = restoredIndex.clamp(0,
              _customScenePath == null ? _scenes.length - 1 : _scenes.length);
          _sceneAuto = auto;
          _lastAutoSceneIndex = _focusSceneForHour(DateTime.now().hour);
          final activeIndex = _effectiveSceneIndex;
          _sceneX = prefs.getDouble('focus_scene_${activeIndex}_x') ?? 0;
          _sceneY = prefs.getDouble('focus_scene_${activeIndex}_y') ?? 0;
          _sceneShade =
              (prefs.getDouble('focus_scene_${activeIndex}_shade') ?? 0.16)
                  .clamp(.08, .46);
        });
      }
    } catch (_) {}
  }

  Future<void> _selectScene(int index) async {
    final request = ++_sceneRequest;
    await _precacheScene(index);
    if (!mounted || request != _sceneRequest) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || request != _sceneRequest) return;
    setState(() {
      _sceneAuto = false;
      _sceneIndex = index;
      _sceneX = prefs.getDouble('focus_scene_${index}_x') ?? 0;
      _sceneY = prefs.getDouble('focus_scene_${index}_y') ?? 0;
      _sceneShade = (prefs.getDouble('focus_scene_${index}_shade') ?? 0.16)
          .clamp(.08, .46);
    });
    try {
      await prefs.setInt(_sceneKey, index);
      await prefs.setBool(_sceneAutoKey, false);
      await prefs.setInt('focus_scene_catalog_version', 2);
    } catch (_) {}
  }

  Future<void> _setSceneAuto() async {
    final request = ++_sceneRequest;
    await _precacheScene(_focusSceneForHour(DateTime.now().hour));
    if (!mounted || request != _sceneRequest) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || request != _sceneRequest) return;
    setState(() {
      _sceneAuto = true;
      _lastAutoSceneIndex = _focusSceneForHour(DateTime.now().hour);
      _sceneX = prefs.getDouble('focus_scene_${_lastAutoSceneIndex}_x') ?? 0;
      _sceneY = prefs.getDouble('focus_scene_${_lastAutoSceneIndex}_y') ?? 0;
      _sceneShade =
          (prefs.getDouble('focus_scene_${_lastAutoSceneIndex}_shade') ?? 0.16)
              .clamp(.08, .46);
    });
    await prefs.setBool(_sceneAutoKey, true);
  }

  Future<void> _loadActiveSceneAppearance(int index) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || !_sceneAuto || index != _effectiveSceneIndex) return;
    setState(() {
      _sceneX = prefs.getDouble('focus_scene_${index}_x') ?? 0;
      _sceneY = prefs.getDouble('focus_scene_${index}_y') ?? 0;
      _sceneShade = (prefs.getDouble('focus_scene_${index}_shade') ?? 0.16)
          .clamp(.08, .46);
    });
  }

  Future<void> _precacheScene(int index) async {
    if (index < 0 || index > _scenes.length || !mounted) return;
    if (index == _scenes.length && _customScenePath == null) return;
    try {
      if (index == _scenes.length) {
        await precacheImage(FileImage(File(_customScenePath!)), context);
      } else {
        await precacheImage(AssetImage(_scenes[index].asset), context);
      }
    } catch (_) {
      // Switching remains available even when an image cannot be prefetched.
    }
  }

  AmbientPalette _paletteForScene(int index) => switch (index) {
        0 => AmbientPalette.night,
        6 => AmbientPalette.daylight,
        7 => AmbientPalette.daylight,
        8 => AmbientPalette.dusk,
        _ => AmbientPalette.custom,
      };

  Future<void> _importScene() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = picked?.files.single.path;
    if (path == null) return;
    final source = File(path);
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}focus_backgrounds',
    );
    await directory.create(recursive: true);
    final extension = path.split('.').last.toLowerCase();
    final target = File(
      '${directory.path}${Platform.pathSeparator}personal_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await source.copy(target.path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('focus_custom_scene', target.path);
    if (!mounted) return;
    setState(() => _customScenePath = target.path);
    await _selectScene(_scenes.length);
  }

  Future<void> _saveScenePosition() async {
    final prefs = await SharedPreferences.getInstance();
    final index = _effectiveSceneIndex;
    await prefs.setDouble('focus_scene_${index}_x', _sceneX);
    await prefs.setDouble('focus_scene_${index}_y', _sceneY);
    await prefs.setDouble('focus_scene_${index}_shade', _sceneShade);
  }

  Future<void> _showSceneSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('调整画面', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              const Text('水平位置'),
              Slider(
                value: _sceneX,
                min: -1,
                max: 1,
                onChanged: (value) {
                  update(() => _sceneX = value);
                  setState(() {});
                  _saveScenePosition();
                },
              ),
              const Text('垂直位置'),
              Slider(
                value: _sceneY,
                min: -1,
                max: 1,
                onChanged: (value) {
                  update(() => _sceneY = value);
                  setState(() {});
                  _saveScenePosition();
                },
              ),
              const Text('文字背景明暗'),
              Slider(
                value: _sceneShade,
                min: 0.08,
                max: 0.46,
                onChanged: (value) {
                  update(() => _sceneShade = value);
                  setState(() {});
                  _saveScenePosition();
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _loadTodayTodos() async {
    try {
      final todos = await IsarService.instance.getTodayTodos();
      todos.sort((a, b) {
        if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
        final byDeadline = (a.deadline ?? DateTime(9999))
            .compareTo(b.deadline ?? DateTime(9999));
        return byDeadline != 0
            ? byDeadline
            : a.sortOrder.compareTo(b.sortOrder);
      });
      if (mounted) setState(() => _todayTodos = todos);
    } catch (_) {}
  }

  Future<void> _toggleTodayTodo(TodoItem todo) async {
    await IsarService.instance.toggleTodo(todo.id, DateTime.now());
    await _loadTodayTodos();
  }

  // ==================== 今日统计 ====================

  ({int minutes, int count}) _todayStats = (minutes: 0, count: 0);

  Future<void> _loadTodayStats() async {
    try {
      final stats = await FocusAnalyticsService.forDay(DateTime.now());
      if (mounted) {
        setState(() => _todayStats = (
              minutes: stats.totalSeconds ~/ 60,
              count: stats.focusCount,
            ));
      }
    } catch (_) {}
  }

  // ==================== 交互 ====================

  Future<void> _confirmAbort() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束这段专注'),
        content: const Text('可以保存已经投入的时间，也可以放弃这次记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'continue'),
            child: const Text('继续计时'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('放弃'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('结束并记录')),
        ],
      ),
    );
    if (choice == 'discard') {
      await _svc.abort();
    } else if (choice == 'save') {
      _endingManually = true;
      await _svc.finishCurrentFocus();
      _endingManually = false;
      if (mounted) await _askTaskCompletion();
    }
  }

  Future<void> _askTaskCompletion() async {
    if (_completionDialogOpen || !_svc.completionChoicePending) return;
    final title = _svc.associatedTaskTitle;
    if (title == null || title.isEmpty || !mounted) {
      await _svc.resolveTaskCompletion();
      return;
    }
    _completionDialogOpen = true;
    try {
      final done = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('这件事完成了吗？'),
                content: Text(title),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('还要继续')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('已完成')),
                ],
              ));
      if (done == true) {
        final id = _svc.associatedTodoId;
        if (id != null) {
          final current = _todayTodos.where((t) => t.id == id).toList();
          if (current.isNotEmpty && !current.first.isCompleted) {
            await _toggleTodayTodo(current.first);
          }
        }
        await _svc.setCustomTask(null);
      } else {
        await _svc.resolveTaskCompletion();
      }
    } finally {
      _completionDialogOpen = false;
    }
  }

  /// 选择关联的待办
  Future<void> _pickTodo() async {
    final todos = await IsarService.instance.getTodayTodos();
    if (!mounted) return;
    final controller = TextEditingController();
    final picked = await showDialog<({int? id, String? title})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('这次专注做什么'),
        content: SizedBox(
          width: 380,
          height: 400,
          child: Column(children: [
            TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: '新建一件专注事项', hintText: '例如 阅读论文、整理笔记'),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.pop(context, (id: null, title: value.trim()));
                  }
                }),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () {
                      if (controller.text.trim().isNotEmpty) {
                        Navigator.pop(
                            context, (id: null, title: controller.text.trim()));
                      }
                    },
                    child: const Text('使用这个事项'))),
            const Divider(),
            Expanded(
                child: ListView(children: [
              if (_svc.associatedTaskTitle != null)
                ListTile(
                  leading: const Icon(Icons.link_off, size: 20),
                  title: const Text('清除当前事项'),
                  onTap: () => Navigator.pop(context, (id: null, title: null)),
                ),
              if (todos.isEmpty)
                const ListTile(title: Text('今天暂无待办，可以在上方新建事项')),
              ...todos.map((t) => ListTile(
                    dense: true,
                    leading: Icon(
                      t.isCompleted
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      size: 18,
                      color: t.isCompleted ? AppColors.navy : null,
                    ),
                    title: Text(t.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle:
                        t.taskType.isRecurring ? const Text('每日习惯') : null,
                    onTap: () =>
                        Navigator.pop(context, (id: t.id, title: t.title)),
                  )),
            ])),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (picked != null) {
      await _svc.setAssociatedTodo(picked.id, title: picked.title);
    }
  }

  Future<void> _showDurationSettings() async {
    final focusCtrl = TextEditingController(text: '${_svc.focusMinutes}');
    final shortCtrl = TextEditingController(text: '${_svc.shortBreakMinutes}');
    final longCtrl = TextEditingController(text: '${_svc.longBreakMinutes}');
    final intervalCtrl =
        TextEditingController(text: '${_svc.longBreakInterval}');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('番茄钟设置'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _durationField(focusCtrl, '专注时长（分钟）'),
              _durationField(shortCtrl, '短休息（分钟）'),
              _durationField(longCtrl, '长休息（分钟）'),
              _durationField(intervalCtrl, '每几个番茄进入长休息'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved == true) {
      await _svc.saveDurations(
        focus: int.tryParse(focusCtrl.text.trim()) ?? 25,
        shortBreak: int.tryParse(shortCtrl.text.trim()) ?? 5,
        longBreak: int.tryParse(longCtrl.text.trim()) ?? 15,
        interval: int.tryParse(intervalCtrl.text.trim()) ?? 4,
      );
    }
    focusCtrl.dispose();
    shortCtrl.dispose();
    longCtrl.dispose();
    intervalCtrl.dispose();
  }

  Widget _durationField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  // ==================== 沉浸模式 ====================

  bool _immersive = false;
  bool get _isImmersive => widget.focusImmersive ?? _immersive;

  Future<void> _toggleImmersive(bool enable) async {
    if (widget.onFocusImmersiveChanged != null) {
      await widget.onFocusImmersiveChanged!(enable);
      return;
    }
    setState(() => _immersive = enable);
    if (!Platform.isWindows) {
      await SystemChrome.setEnabledSystemUIMode(
          enable ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _leaveRoom() async {
    if (_isImmersive) await _toggleImmersive(false);
    widget.onExit?.call();
  }

  @override
  void deactivate() {
    if (_isImmersive && !Platform.isWindows) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.deactivate();
  }

  // ==================== 构建 ====================

  String _formatRemaining(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _phaseLabel {
    final phase = _svc.runningPhase;
    if (phase == null) return '番茄钟';
    switch (phase) {
      case PomodoroRunPhase.focus:
        return '专注中';
      case PomodoroRunPhase.shortBreak:
        return '短休息';
      case PomodoroRunPhase.longBreak:
        return '长休息';
    }
  }

  Color get _phaseColor {
    final phase = _svc.runningPhase;
    if (phase == PomodoroRunPhase.shortBreak ||
        phase == PomodoroRunPhase.longBreak) {
      return const Color(0xFFB9D5D6);
    }
    return AppColors.amber;
  }

  @override
  Widget build(BuildContext context) {
    final selectedFontColor =
        AmbientPaletteScope.maybeOf(context)?.foregroundOverride;
    return LayoutBuilder(builder: (context, bounds) {
      final compact = bounds.maxWidth < 680 || bounds.maxHeight < 540;
      final side = compact ? 18.0 : 36.0;
      final active = _svc.isRunning || _svc.isPaused;
      final sceneIndex = _effectiveSceneIndex;
      final scene = _scenes[sceneIndex < _scenes.length ? sceneIndex : 0];
      final custom = sceneIndex == _scenes.length && _customScenePath != null;
      // 全局环境开启且未自选专属场景 → 透传全局背景，只保留聚焦暗角
      final inherit = widget.inheritBackdrop && _sceneAuto && !custom;
      return AmbientPaletteScope(
        palette: selectedFontColor == null
            ? _paletteForScene(sceneIndex)
            : _paletteForScene(sceneIndex).withFontColor(
                selectedFontColor, selectedFontColor.withValues(alpha: .85)),
        enabled: true,
        foregroundOverride: selectedFontColor,
        child: Stack(children: [
          if (!inherit)
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: compact ? 1100 : 1700),
                switchInCurve: Curves.easeInOutCubic,
                switchOutCurve: Curves.easeInOutCubic,
                child: custom
                    ? Image.file(
                        File(_customScenePath!),
                        key: ValueKey(sceneIndex),
                        fit: BoxFit.cover,
                        alignment: Alignment(_sceneX, _sceneY),
                        width: bounds.maxWidth,
                        height: bounds.maxHeight,
                      )
                    : scene.quarterTurns == 0
                        ? Image.asset(
                            scene.asset,
                            key: ValueKey(sceneIndex),
                            fit: BoxFit.cover,
                            alignment: Alignment(_sceneX, _sceneY),
                            width: bounds.maxWidth,
                            height: bounds.maxHeight,
                          )
                        : RotatedBox(
                            key: ValueKey(sceneIndex),
                            quarterTurns: scene.quarterTurns,
                            child: Image.asset(
                              scene.asset,
                              fit: BoxFit.cover,
                              alignment: Alignment(_sceneX, _sceneY),
                              width: bounds.maxHeight,
                              height: bounds.maxWidth,
                            ),
                          ),
              ),
            ),
          if (!inherit)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // 顶部留一段透明，避免与标题栏交界处出现硬分割线
                    stops: const [0, .10, .55, 1],
                    colors: [
                      const Color(0xFF101F2C).withValues(alpha: 0),
                      const Color(0xFF101F2C)
                          .withValues(alpha: _sceneShade * 0.58),
                      const Color(0xFF101F2C)
                          .withValues(alpha: _sceneShade * 0.37),
                      const Color(0xFF101F2C)
                          .withValues(alpha: _sceneShade * 0.75),
                    ],
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -.12),
                    radius: .88,
                    stops: const [0, .48, 1],
                    colors: [
                      const Color(0xFF0D1A25)
                          .withValues(alpha: _isImmersive ? .26 : .44),
                      const Color(0xFF0D1A25)
                          .withValues(alpha: _isImmersive ? .10 : .18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_svc.runningPhase == PomodoroRunPhase.shortBreak ||
              _svc.runningPhase == PomodoroRunPhase.longBreak)
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xFFB9D5D6).withValues(alpha: 0.07),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(side, 12, side, compact ? 15 : 25),
              child: Stack(children: [
                Align(alignment: Alignment.topCenter, child: _buildTopBar()),
                Positioned.fill(
                  top: 72,
                  bottom: active && !_isImmersive ? 124 : 64,
                  child: LayoutBuilder(builder: (context, area) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: area.maxHeight),
                        child: Center(
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: compact ? 360 : 590),
                            child: _buildFocusContent(compact: compact),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                if (active && !_isImmersive)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _buildControls(Theme.of(context)),
                  ),
                if (!_isImmersive)
                  Positioned(
                    right: 0,
                    bottom: compact ? (active ? 62 : 0) : 0,
                    width: compact
                        ? (bounds.maxWidth - side * 2).clamp(0.0, 350.0)
                        : 310,
                    child: _buildTodoDrawer(),
                  ),
              ]),
            ),
          ),
        ]),
      );
    });
  }

  Widget _buildTopBar() {
    const white = Color(0xFFF9F7F2);
    final narrow = MediaQuery.sizeOf(context).width < 680;
    if (_isImmersive) {
      return Row(children: [
        GlassPanel(
          level: GlassSurfaceLevel.dark,
          radius: 18,
          opacity: .38,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _toggleImmersive(false),
              borderRadius: BorderRadius.circular(18),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.arrow_back, size: 18, color: white),
                  SizedBox(width: 7),
                  Text('退出沉浸', style: TextStyle(color: white)),
                ]),
              ),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: Platform.isWindows
                ? (_) => windowManager.startDragging()
                : null,
            child: const SizedBox(height: 52),
          ),
        ),
        GlassPanel(
          level: GlassSurfaceLevel.dark,
          radius: 16,
          opacity: .38,
          child: IconButton(
            onPressed: _toggleSound,
            tooltip: PomodoroService.playSounds ? '关闭提示音' : '开启提示音',
            icon: Icon(
              PomodoroService.playSounds
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
              color: white,
            ),
          ),
        ),
      ]);
    }
    return Row(children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: narrow ? 132 : 230),
        child: _svc.isRunning || _svc.isPaused
            ? _buildTaskLink()
            : TextButton.icon(
                onPressed: _leaveRoom,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: Text(
                    MediaQuery.sizeOf(context).width < 360 ? '返回' : '返回今天'),
                style: TextButton.styleFrom(foregroundColor: white),
              ),
      ),
      Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart:
              Platform.isWindows ? (_) => windowManager.startDragging() : null,
          child: const SizedBox(height: 56),
        ),
      ),
      GlassPanel(
        level: GlassSurfaceLevel.dark,
        radius: 15,
        opacity: .38,
        blur: 10,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          PopupMenuButton<int>(
            tooltip: '切换背景',
            onSelected: (value) {
              if (value == -1) {
                _importScene();
              } else if (value == -2) {
                _showSceneSettings();
              } else if (value == -3) {
                _toggleSound();
              } else if (value == -4) {
                _setSceneAuto();
              } else {
                _selectScene(value);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: -4,
                child: Row(children: [
                  const Text('随时间切换'),
                  if (_sceneAuto) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.check, size: 16, color: AppColors.amber),
                  ],
                ]),
              ),
              const PopupMenuDivider(),
              for (var i = 0; i < _scenes.length; i++)
                PopupMenuItem(
                  value: i,
                  child: Row(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: _scenes[i].quarterTurns == 0
                          ? Image.asset(_scenes[i].asset,
                              width: 47, height: 32, fit: BoxFit.cover)
                          : RotatedBox(
                              quarterTurns: _scenes[i].quarterTurns,
                              child: Image.asset(_scenes[i].asset,
                                  width: 32, height: 47, fit: BoxFit.cover),
                            ),
                    ),
                    const SizedBox(width: 11),
                    Text(_scenes[i].label),
                    if (!_sceneAuto && i == _sceneIndex) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.check, size: 16, color: AppColors.amber),
                    ],
                  ]),
                ),
              if (_customScenePath != null)
                PopupMenuItem(value: _scenes.length, child: const Text('我的照片')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: -1, child: Text('导入自己的照片')),
              const PopupMenuItem(value: -2, child: Text('调整画面')),
              if (narrow)
                PopupMenuItem(
                    value: -3,
                    child:
                        Text(PomodoroService.playSounds ? '关闭提示音' : '开启提示音')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              child: Icon(Icons.landscape_outlined, color: white, size: 21),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FocusInsightsPage())),
            tooltip: '今日专注统计',
            icon: const Icon(Icons.pie_chart_outline, color: white, size: 21),
          ),
          if (!narrow)
            IconButton(
              onPressed: () async {
                await _toggleSound();
              },
              tooltip: PomodoroService.playSounds ? '关闭提示音' : '开启提示音',
              icon: Icon(
                PomodoroService.playSounds
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
                color: white,
                size: 21,
              ),
            ),
          if (!narrow)
            TextButton.icon(
              onPressed: () => _toggleImmersive(!_isImmersive),
              icon: Icon(
                _isImmersive ? Icons.fullscreen_exit : Icons.fullscreen,
                color: white,
                size: 20,
              ),
              label: Text(
                _isImmersive ? '退出沉浸' : '沉浸模式',
                style: const TextStyle(color: white),
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(108, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            )
          else
            IconButton(
              onPressed: () => _toggleImmersive(!_isImmersive),
              tooltip: _isImmersive ? '退出沉浸模式' : '进入沉浸模式',
              icon: Icon(
                  _isImmersive ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: white),
            ),
          if (!_svc.isRunning && !_svc.isPaused)
            IconButton(
              onPressed: _showDurationSettings,
              tooltip: '计时设置',
              icon: const Icon(Icons.tune, color: white),
            ),
          if (_svc.isRunning || _svc.isPaused)
            IconButton(
              onPressed: _leaveRoom,
              tooltip: '返回今天',
              icon: const Icon(Icons.close, color: white, size: 20),
            ),
        ]),
      ),
    ]);
  }

  Widget _buildFocusContent({required bool compact}) {
    final theme = Theme.of(context);
    final short = MediaQuery.sizeOf(context).height < 650;
    const white = Color(0xFFF9F7F2);
    final palette =
        AmbientPaletteScope.maybeOf(context)?.palette ?? AmbientPalette.night;
    final remaining = _svc.remainingSeconds();
    final planned = _svc.currentPlannedSeconds();
    final progress =
        planned > 0 ? (1 - remaining / planned).clamp(0.0, 1.0) : 0.0;
    final time = _svc.isRunning || _svc.isPaused
        ? _formatRemaining(remaining)
        : '${_svc.focusMinutes.toString().padLeft(2, '0')}:00';
    final active = _svc.isRunning || _svc.isPaused;
    final end =
        _svc.targetEndTime ?? DateTime.now().add(Duration(seconds: remaining));
    final endLabel =
        '预计 ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')} 结束';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(_svc.isPaused ? '已暂停' : _phaseLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _isImmersive ? palette.primaryText : _phaseColor,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 10),
        if (_isImmersive)
          Text(
            time,
            maxLines: 1,
            style: AppType.display(
              size: short ? 62 : (compact ? 76 : 118),
              weight: FontWeight.w500,
              color: palette.primaryText,
              height: 1.1,
            ).copyWith(
              letterSpacing: -2,
              fontFeatures: AppType.tabular,
              shadows: [palette.textShadow],
            ),
          )
        else
          GlassPanel(
            level: GlassSurfaceLevel.dark,
            radius: 180,
            opacity: .28,
            blur: 8,
            child: Container(
              width: short ? 136 : (compact ? 190 : 254),
              height: short ? 136 : (compact ? 190 : 254),
              padding: const EdgeInsets.all(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 1.5,
                    color: _phaseColor,
                    backgroundColor: white.withValues(alpha: .23),
                  ),
                  Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        time,
                        maxLines: 1,
                        style: theme.textTheme.displayLarge?.copyWith(
                          color: white,
                          fontFamily: AppTypography.sans,
                          fontSize: short ? 34 : (compact ? 44 : 60),
                          fontWeight: FontWeight.w300,
                          letterSpacing: -1.5,
                          height: 1.2,
                          fontFeatures: AppType.tabular,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(height: short ? 10 : (_isImmersive ? 14 : 23)),
        Text(
            active
                ? (_svc.isPaused ? '继续时，从这里接上' : endLabel)
                : '给眼前的事，留一段完整时间。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.secondaryText,
            )),
        if (_isImmersive) ...[
          const SizedBox(height: 18),
          _buildTaskLink(),
          if (active) ...[
            const SizedBox(height: 22),
            _buildControls(theme),
          ],
        ],
        if (!active) ...[
          SizedBox(height: short ? 10 : 29),
          if (!_isImmersive) _buildTaskLink(),
          SizedBox(height: short ? 10 : 20),
          _buildControls(theme),
          SizedBox(height: short ? 8 : 14),
          Text('今天已投入 ${_todayStats.minutes} 分钟',
              style: theme.textTheme.bodySmall?.copyWith(
                color: white.withValues(alpha: 0.66),
              )),
        ],
      ],
    );
  }

  Widget _buildTaskLink() {
    const white = Color(0xFFF9F7F2);
    TodoItem? linked;
    for (final todo in _todayTodos) {
      if (todo.id == _svc.associatedTodoId) {
        linked = todo;
        break;
      }
    }
    return InkWell(
      onTap: _svc.isRunning || _svc.isPaused ? null : _pickTodo,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(linked == null ? Icons.add_link : Icons.link,
              size: 17, color: AppColors.amber),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              linked?.title ?? _svc.associatedTaskTitle ?? '选择或新建专注事项',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: white.withValues(alpha: 0.87),
                  ),
            ),
          ),
          if (!_svc.isRunning && !_svc.isPaused) ...[
            const SizedBox(width: 7),
            Icon(Icons.chevron_right,
                size: 16, color: white.withValues(alpha: 0.65)),
          ],
        ]),
      ),
    );
  }

  Widget _buildTodayBoard() => FocusTodoBoard(
        todos: _todayTodos,
        associatedTodoId: _svc.associatedTodoId,
        onToggle: _toggleTodayTodo,
        onOpenTodo: widget.onOpenTodo,
      );

  Widget _buildTodoDrawer() {
    final remaining = _todayTodos.where((todo) => !todo.isCompleted).length;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_todoDrawerOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _buildTodayBoard(),
            ),
          GlassPanel(
            level: GlassSurfaceLevel.dark,
            radius: 14,
            opacity: .48,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _todoDrawerOpen = !_todoDrawerOpen),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.checklist, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('今日待办 · $remaining',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white)),
                    const SizedBox(width: 7),
                    Icon(
                        _todoDrawerOpen
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        color: Colors.white,
                        size: 17),
                  ]),
                ),
              ),
            ),
          ),
        ]);
  }

  Widget _buildControls(ThemeData theme) {
    const white = Color(0xFFF9F7F2);
    final mainStyle = FilledButton.styleFrom(
      backgroundColor: AppColors.actionFill,
      foregroundColor: AppColors.actionInk,
      side: BorderSide(color: white.withValues(alpha: .42)),
      padding: const EdgeInsets.symmetric(horizontal: 27, vertical: 16),
      textStyle: theme.textTheme.titleSmall,
    );
    if (_svc.isRunning || _svc.isPaused) {
      return Wrap(spacing: 14, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: _svc.isPaused ? _svc.resume : _svc.pause,
          icon: Icon(_svc.isPaused ? Icons.play_arrow : Icons.pause,
              color: AppColors.ink),
          label: Text(_svc.isPaused ? '继续专注' : '暂停'),
          style: mainStyle,
        ),
        TextButton.icon(
          onPressed: _confirmAbort,
          icon: const Icon(Icons.stop_outlined, size: 18),
          label: const Text('结束本次'),
          style: TextButton.styleFrom(
            foregroundColor: white.withValues(alpha: 0.86),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
          ),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FilledButton.icon(
        onPressed: () => _svc.startPhase(PomodoroRunPhase.focus),
        icon: const Icon(Icons.play_arrow, color: AppColors.ink),
        label: const Text('开始专注'),
        style: mainStyle,
      ),
      if (_svc.suggestedNext != null) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 10, children: [
          TextButton.icon(
            onPressed: () => _svc.startPhase(_svc.suggestedNext!),
            icon: const Icon(Icons.self_improvement, size: 18),
            label: Text(_svc.suggestedNext == PomodoroRunPhase.longBreak
                ? '开始长休息'
                : '开始短休息'),
            style: TextButton.styleFrom(foregroundColor: white),
          ),
          TextButton(
            onPressed: _svc.skipSuggestion,
            style: TextButton.styleFrom(
                foregroundColor: white.withValues(alpha: 0.68)),
            child: const Text('跳过'),
          ),
        ]),
      ],
    ]);
  }
}

class _FocusScene {
  final String asset;
  final String label;
  final int quarterTurns;
  const _FocusScene(this.asset, this.label, {this.quarterTurns = 0});
}

class FocusTodoBoard extends StatelessWidget {
  final List<TodoItem> todos;
  final int? associatedTodoId;
  final ValueChanged<TodoItem> onToggle;
  final VoidCallback? onOpenTodo;

  const FocusTodoBoard({
    super.key,
    required this.todos,
    required this.associatedTodoId,
    required this.onToggle,
    this.onOpenTodo,
  });

  @override
  Widget build(BuildContext context) {
    const white = Color(0xFFF9F7F2);
    final theme = Theme.of(context);
    final remaining = todos.where((todo) => !todo.isCompleted).length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x661A2A3A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: white.withValues(alpha: 0.34)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 30,
                  offset: Offset(0, 12))
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('今日待办',
                  style: theme.textTheme.titleSmall?.copyWith(color: white)),
              const Spacer(),
              Text('$remaining 项待处理',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: white.withValues(alpha: 0.64),
                  )),
            ]),
            const SizedBox(height: 11),
            Divider(height: 1, color: white.withValues(alpha: 0.17)),
            const SizedBox(height: 8),
            if (todos.isEmpty) ...[
              Text('今天还没有待办。先写下一件事。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: white.withValues(alpha: 0.80),
                  )),
              if (onOpenTodo != null)
                TextButton(
                  onPressed: onOpenTodo,
                  style: TextButton.styleFrom(foregroundColor: AppColors.amber),
                  child: const Text('打开今日待办'),
                ),
            ] else
              SizedBox(
                height: (todos.length * 48.0).clamp(48.0, 220.0).toDouble(),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: todos.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (context, index) {
                    final todo = todos[index];
                    return InkWell(
                      onTap: () => onToggle(todo),
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 46,
                        child: Row(children: [
                          Icon(
                            todo.isCompleted
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: todo.isCompleted
                                ? AppColors.amber
                                : white.withValues(alpha: 0.72),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(todo.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: todo.isCompleted
                                      ? white.withValues(alpha: 0.52)
                                      : white,
                                  decoration: todo.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor:
                                      white.withValues(alpha: 0.52),
                                )),
                          ),
                          if (todo.id == associatedTodoId)
                            const Icon(Icons.link,
                                size: 15, color: AppColors.amber),
                        ]),
                      ),
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
