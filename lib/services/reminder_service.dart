import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:isar/isar.dart';
import 'package:local_notifier/local_notifier.dart' as ln;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/course.dart';
import '../models/daily_completion.dart';
import '../models/todo_item.dart';
import 'course_service.dart';
import 'reminder_calc.dart';
import 'isar_service.dart';

/// 双端提醒服务
///
/// - Android：flutter_local_notifications 的 zonedSchedule（插件自行持久化排定通知，
///   开机由插件的 boot receiver 恢复；Android 13+ 需通知权限，12+ 精确提醒需
///   "闹钟和提醒"特殊权限，未授予时降级为不精确提醒）。
/// - Windows：local_notifier 系统通知 + 进程内定时器。依赖托盘驻留（关窗=隐藏到托盘）；
///   从托盘退出后提醒不可用，此限制在设置页明示。进程存活期间每 6 小时全量重排兜底。
///
/// 提醒排程为"全量重算"模型：任何数据变更（待办/课程/考试/学期/节次配置）后调用
/// [requestReschedule]（防抖合并），由 [rescheduleAll] 取消全部后按最新数据重排，
/// 从根上避免"改了数据旧提醒还在"的错配问题。
class ReminderService {
  static ReminderService? _instance;
  static ReminderService get instance => _instance ??= ReminderService._();
  ReminderService._();

  static const String courseRemindEnabledKey = 'course_remind_enabled';

  final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();

  /// 惰性获取：local_notifier 实例化时会注册平台回调，
  /// 延迟到 Windows 初始化时再触碰，避免单元测试环境缺 Binding 报错
  ln.LocalNotifier get _localNotifier => ln.LocalNotifier.instance;

  Timer? _refreshTimer; // Windows 周期补排
  Timer? _rescheduleDebounce;
  final List<Timer> _timers = []; // Windows 进程内定时器
  final Map<int, Timer> _oneShotTimers = {}; // Windows 一次性通知定时器
  final List<ln.LocalNotification> _shown = []; // Windows 保活引用

  bool _initialized = false;
  bool _notificationsAllowed = false;
  bool _exactAllowed = false;
  bool _timezoneOk = false;

  /// 点击提醒后要跳转的页面索引（0=今日任务 1=课表 5=番茄钟），主页面监听
  final ValueNotifier<int?> pendingNavigation = ValueNotifier(null);

  /// 番茄钟结束通知的固定 ID（阶段 3 复用）
  static const int pomodoroNotificationId = 4000000;

  /// 额外排程提供者：全量重排（cancelAll）时需要保留/补充的即时通知，
  /// 如进行中的番茄钟结束通知、训练提醒（滚动窗口）。
  /// 各服务通过 [addExtraOccurrencesProvider] 注册。
  final List<Future<List<ReminderOccurrence>> Function()> _extraProviders = [];

  void addExtraOccurrencesProvider(
      Future<List<ReminderOccurrence>> Function() provider) {
    if (!_extraProviders.contains(provider)) {
      _extraProviders.add(provider);
    }
  }

  bool get notificationsAllowed => _notificationsAllowed;
  bool get exactAllowed => _exactAllowed;

  /// 初始化（在数据库服务之后调用）
  Future<void> init() async {
    if (_initialized) return;

    if (Platform.isAndroid) {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
        _timezoneOk = true;
      } catch (e) {
        // 时区名解析失败时提醒时刻可能有偏差，记录但不阻断
        debugPrint('时区初始化失败: $e');
      }

      const androidInit =
          AndroidInitializationSettings('@drawable/ic_notification');
      await _fln.initialize(
        settings: const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      final androidImpl = _fln.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Android 13+ 通知运行时权限
      _notificationsAllowed =
          await androidImpl?.requestNotificationsPermission() ?? false;
      // Android 12+ 精确提醒特殊权限（未授予时系统会引导；已授予则直接返回 true）
      try {
        _exactAllowed =
            await androidImpl?.requestExactAlarmsPermission() ?? false;
      } catch (_) {
        _exactAllowed = false;
      }

      // 冷启动：通过点击通知（或其"完成"按钮）打开应用
      final launch = await _fln.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _onNotificationResponse(launch!.notificationResponse!);
      }
    } else if (Platform.isWindows) {
      await _localNotifier.setup(appName: '待办事项');
      _notificationsAllowed = true;
      _exactAllowed = true; // 进程内定时器即精确
      _timezoneOk = true;
      // 驻留期间的周期补排：进程意外长期运行时兜底续排
      _refreshTimer = Timer.periodic(
        const Duration(hours: 6),
        (_) => rescheduleAll(),
      );
    }

    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    // 待办通知的「完成」按钮：直接勾掉任务，不跳页
    if (response.actionId == 'mark_done' &&
        response.payload != null &&
        response.payload!.isNotEmpty) {
      try {
        final map = jsonDecode(response.payload!) as Map<String, dynamic>;
        if (map['type'] == 'todo' && map['id'] is int) {
          _completeTodoFromAction(map['id'] as int);
          return;
        }
      } catch (_) {}
    }
    _handlePayload(response.payload);
  }

  /// 通知上的「完成」：写库后由 watchLazy 自动刷新界面，并重排剩余提醒
  Future<void> _completeTodoFromAction(int todoId) async {
    try {
      await IsarService.instance.toggleTodo(todoId, DateTime.now());
      requestReschedule();
    } catch (e) {
      debugPrint('通知完成操作失败: $e');
    }
  }

  /// 供设置页查询/申请的权限状态
  Future<bool> notificationsEnabled() async {
    if (!Platform.isAndroid) return _notificationsAllowed;
    final androidImpl = _fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await androidImpl?.areNotificationsEnabled() ?? _notificationsAllowed;
  }

  Future<bool> exactAlarmsEnabled() async {
    if (!Platform.isAndroid) return _exactAllowed;
    try {
      return await _fln
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.canScheduleExactNotifications() ??
          _exactAllowed;
    } catch (_) {
      return _exactAllowed;
    }
  }

  Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    final androidImpl = _fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    _notificationsAllowed =
        await androidImpl?.requestNotificationsPermission() ?? false;
  }

  Future<void> requestExactAlarmsPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _fln
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
      _exactAllowed = await exactAlarmsEnabled();
    } catch (_) {}
  }

  void _handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      switch (map['type']) {
        case 'todo':
          pendingNavigation.value = 0;
          break;
        case 'course':
        case 'exam':
          pendingNavigation.value = 1;
          break;
        case 'pomodoro':
          pendingNavigation.value = 5;
          break;
        case 'training':
          pendingNavigation.value = 6;
          break;
      }
    } catch (_) {}
  }

  /// 数据变更后的重排请求（防抖 500ms 合并多次变更）
  void requestReschedule() {
    _rescheduleDebounce?.cancel();
    _rescheduleDebounce = Timer(const Duration(milliseconds: 500), () {
      rescheduleAll();
    });
  }

  /// 全量重排：取消全部已排定提醒，按当前数据重新计算并排定
  Future<void> rescheduleAll() async {
    if (!_initialized) return;
    try {
      final occurrences = await _collectOccurrences();
      if (Platform.isAndroid) {
        await _scheduleAndroid(occurrences);
      } else if (Platform.isWindows) {
        _scheduleWindows(occurrences);
      }
      debugPrint('提醒重排完成：${occurrences.length} 条');
    } catch (e) {
      debugPrint('提醒重排失败: $e');
    }
  }

  Future<List<ReminderOccurrence>> _collectOccurrences() async {
    final isar = IsarService.instance.isar;
    final now = DateTime.now();
    final result = <ReminderOccurrence>[];

    // 待办提醒
    final todos = await isar.todoItems.where().findAll();
    // 今日已打卡的习惯集合（打卡提醒需据此排明天而非今天）
    final todayNormalized = DateTime(now.year, now.month, now.day);
    final completedTodayIds = (await isar.dailyCompletions
            .filter()
            .dateEqualTo(todayNormalized)
            .findAll())
        .map((c) => c.todoId)
        .toSet();
    for (final todo in todos) {
      final o = todoOccurrence(todo, now: now);
      if (o != null) result.add(o);
      // 每日习惯的打卡提醒（每天固定时刻，Android 按日重复排程）
      final habit = habitOccurrence(todo,
          completedToday: completedTodayIds.contains(todo.id), now: now);
      if (habit != null) result.add(habit);
    }

    // 课程与考试提醒（可开关，默认开）
    final prefs = await SharedPreferences.getInstance();
    final courseEnabled = prefs.getBool(courseRemindEnabledKey) ?? true;
    if (courseEnabled) {
      final courseSvc = CourseService.instance;
      final semester = await courseSvc.ensureActiveSemester();
      final courses = await courseSvc.getAllCourses();
      final configs = await courseSvc.getTimeConfigs();
      result.addAll(courseOccurrences(
        semester: semester,
        courses: courses,
        timeConfigs: configs,
        now: now,
      ));

      final exams = await courseSvc.getAllExams();
      for (final exam in exams) {
        final o = examOccurrence(exam, now: now);
        if (o != null) result.add(o);
      }
    }

    // 汇总额外提供者（番茄钟进行中的通知、训练提醒等；cancelAll 会清掉所以需重排）
    for (final provider in _extraProviders) {
      try {
        final extra = await provider();
        for (final o in extra) {
          if (!result.any((e) => e.id == o.id)) result.add(o);
        }
      } catch (e) {
        debugPrint('额外排程提供者执行失败: $e');
      }
    }

    return result;
  }

  // ==================== 一次性通知（番茄钟等即时排程） ====================

  /// 在指定时刻发一条一次性通知（独立于全量重排的生命周期）
  Future<void> scheduleOneShot({
    required int id,
    required DateTime fireAt,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) return;
    try {
      if (Platform.isAndroid) {
        await _fln.cancel(id: id);
        await _fln.zonedSchedule(
          id: id,
          title: title,
          body: body,
          payload: payload,
          scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'reminders',
              '提醒',
              channelDescription: '待办、课程与考试提醒',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: _exactAllowed
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } else if (Platform.isWindows) {
        cancelOneShot(id);
        final delay = fireAt.difference(DateTime.now());
        if (delay <= Duration.zero) return;
        final timer = Timer(delay, () {
          _oneShotTimers.remove(id);
          _showWindowsNotification(ReminderOccurrence(
            id: id,
            fireAt: fireAt,
            title: title,
            body: body,
            payload: payload ?? '',
            target: ReminderTarget.todo,
          ));
        });
        _oneShotTimers[id] = timer;
      }
    } catch (e) {
      debugPrint('一次性通知排定失败: $e');
    }
  }

  /// 取消一次性通知
  void cancelOneShot(int id) {
    if (Platform.isWindows) {
      _oneShotTimers.remove(id)?.cancel();
    } else if (_initialized) {
      _fln.cancel(id: id);
    }
  }

  AndroidNotificationDetails _androidDetails(ReminderOccurrence o,
      {bool withTodoAction = false}) {
    final (String name, String description, Importance importance,
            Priority priority, bool vibration) =
        switch (o.channel) {
          ReminderChannels.habit => (
              '习惯打卡提醒',
              '每日习惯的定时打卡提醒',
              Importance.defaultImportance,
              Priority.defaultPriority,
              false,
            ),
          ReminderChannels.pomodoro => (
              '番茄钟提醒',
              '专注与休息阶段结束提醒',
              Importance.high,
              Priority.high,
              false,
            ),
          ReminderChannels.schedule => (
              '课程、考试与训练提醒',
              '上课、考试与训练安排的提前提醒',
              Importance.high,
              Priority.high,
              false,
            ),
          _ => (
              'DDL 与待办提醒',
              '任务截止与开始时间的提醒',
              Importance.high,
              Priority.high,
              true,
            ),
        };
    return AndroidNotificationDetails(
      o.channel,
      name,
      channelDescription: description,
      importance: importance,
      priority: priority,
      enableVibration: vibration,
      // 待办通知带「完成」按钮：点击直接打卡，不用进 App
      actions: withTodoAction
          ? [
              AndroidNotificationAction(
                'mark_done',
                '完成',
                showsUserInterface: true, // 回到应用内完成打卡并刷新
              ),
            ]
          : null,
    );
  }

  Future<void> _scheduleAndroid(List<ReminderOccurrence> occurrences) async {
    await _fln.cancelAll();
    for (final o in occurrences) {
      final isDailyHabit = o.id >= 400000 && o.id < 500000; // habitReminderId 段
      try {
        await _fln.zonedSchedule(
          id: o.id,
          title: o.title,
          body: o.body,
          payload: o.payload,
          scheduledDate: tz.TZDateTime.from(o.fireAt, tz.local),
          notificationDetails: NotificationDetails(
              android: _androidDetails(o,
                  withTodoAction: o.target == ReminderTarget.todo)),
          androidScheduleMode: _exactAllowed
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          // 习惯打卡：按"每天同一时刻"重复，无需逐日排程
          matchDateTimeComponents:
              isDailyHabit ? DateTimeComponents.time : null,
        );
      } catch (e) {
        debugPrint('排定提醒失败 (${o.id}): $e');
      }
    }
  }

  void _scheduleWindows(List<ReminderOccurrence> occurrences) {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    final now = DateTime.now();
    for (final o in occurrences) {
      final delay = o.fireAt.difference(now);
      if (delay <= Duration.zero) continue;
      _timers.add(Timer(delay, () => _showWindowsNotification(o)));
    }
  }

  void _showWindowsNotification(ReminderOccurrence o) {
    try {
      final notification = ln.LocalNotification(title: o.title, body: o.body);
      notification.onClick = () {
        _handlePayload(o.payload);
      };
      _shown.add(notification);
      if (_shown.length > 60) {
        _shown.removeRange(0, 30);
      }
      notification.show();
    } catch (e) {
      debugPrint('Windows 通知显示失败: $e');
    }
  }

  /// Windows 托盘图标：把资产中的 ico 解包到应用支持目录，返回磁盘路径
  /// （tray_manager 需要真实文件路径，不能直接用资产路径）
  Future<String?> prepareTrayIcon() async {
    if (!Platform.isWindows) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final iconFile = File('${dir.path}/tray_icon.ico');
      if (!await iconFile.exists()) {
        final data = await rootBundle.load('assets/tray_icon.ico');
        await iconFile.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true);
      }
      return iconFile.path;
    } catch (e) {
      debugPrint('托盘图标准备失败: $e');
      return null;
    }
  }

  /// 状态描述（设置页展示）
  String statusDescription() {
    if (Platform.isWindows) {
      return 'Windows 通知：${_notificationsAllowed ? "可用" : "不可用"}'
          '（关闭窗口将驻留系统托盘以保持提醒；从托盘退出后提醒不可用）';
    }
    if (Platform.isAndroid) {
      return '通知权限：${_notificationsAllowed ? "已授权" : "未授权（无法弹出提醒）"}\n'
          '精确提醒：${_exactAllowed ? "已授权" : "未授权（提醒可能有几分钟误差）"}'
          '${_timezoneOk ? "" : "\n时区初始化异常，提醒时刻可能偏差"}';
    }
    return '当前平台不支持提醒';
  }

  void dispose() {
    _refreshTimer?.cancel();
    _rescheduleDebounce?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    for (final t in _oneShotTimers.values) {
      t.cancel();
    }
    _oneShotTimers.clear();
  }
}
