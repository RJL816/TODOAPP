import 'dart:convert';

import '../models/class_time_config.dart';
import '../models/course.dart';
import '../models/todo_item.dart';

/// 提醒目标页（点击提醒后跳转）
enum ReminderTarget { todo, course, exam }

/// 通知渠道（Android 分渠道管理重要性/声音）
abstract final class ReminderChannels {
  static const ddl = 'ddl'; // DDL 与待办（高优先级 + 声音）
  static const habit = 'habit'; // 习惯打卡提醒
  static const schedule = 'schedule'; // 课程、考试与训练提醒
  static const pomodoro = 'pomodoro'; // 番茄钟（高优先级）
}

/// 单条提醒的跨平台抽象：
/// Android → flutter_local_notifications zonedSchedule；Windows → local_notifier + 定时器
class ReminderOccurrence {
  final int id;
  final DateTime fireAt;
  final String title;
  final String body;
  final String payload;
  final ReminderTarget target;

  /// Android 通知渠道（见 [ReminderChannels]）
  final String channel;

  const ReminderOccurrence({
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.payload,
    required this.target,
    this.channel = ReminderChannels.ddl,
  });
}

// ==================== 通知 ID 派生（稳定、可取消、防重复）====================

/// 待办提醒 id：10 万段
int todoReminderId(int todoId) => 100000 + todoId;

/// 习惯每日打卡提醒 id：40 万段（与一次性待办提醒互不冲突）
int habitReminderId(int todoId) => 400000 + todoId;

/// 课程提醒 id：按"课程 × 周次"逐次派生（同一门课每周的提醒各自独立）
int courseReminderId(int courseId, int week) => 2000000 + courseId * 1000 + week;

/// 考试提醒 id：300 万段
int examReminderId(int examId) => 3000000 + examId;

// ==================== 触发时刻计算（纯函数，供测试与双端复用）====================

String _fmt(DateTime t) {
  String p2(int v) => v.toString().padLeft(2, '0');
  final wd = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][t.weekday - 1];
  return '$wd ${p2(t.month)}-${p2(t.day)} ${p2(t.hour)}:${p2(t.minute)}';
}

/// 待办提醒：锚点优先取截止时间，其次开始时间；已完成/未开启/无锚点/已过期 → null
ReminderOccurrence? todoOccurrence(TodoItem todo, {DateTime? now}) {
  if (!todo.isReminderEnabled || todo.isCompleted) return null;
  final anchor = todo.deadline ?? todo.startTime;
  if (anchor == null) return null;

  final fireAt =
      anchor.subtract(Duration(minutes: todo.remindBeforeMinutes));
  final n = now ?? DateTime.now();
  if (!fireAt.isAfter(n)) return null;

  final isDeadline = todo.deadline != null;
  return ReminderOccurrence(
    id: todoReminderId(todo.id),
    fireAt: fireAt,
    title: '待办提醒：${todo.title}',
    body: isDeadline
        ? '截止 ${_fmt(anchor)}'
        : '${_fmt(anchor)} 开始',
    payload: jsonEncode({'type': 'todo', 'id': todo.id}),
    target: ReminderTarget.todo,
    channel: todo.taskType.isRecurring
        ? ReminderChannels.habit
        : ReminderChannels.ddl,
  );
}

/// 每日习惯打卡提醒：recurring 任务设了 habitRemindMinutes 即每天固定时刻提醒。
/// [completedToday] 表示今天已打卡（调用方查 DailyCompletion 得出）：
/// 已打卡 → 排明天同一时刻；未打卡 → 今天时刻未过则今天提醒，已过则明天。
/// 这样打卡后重排会自动排出明天的提醒，避免"打卡取消通知后次日失效"。
/// Android 侧按每日重复（matchDateTimeComponents.time）排程。
ReminderOccurrence? habitOccurrence(TodoItem todo,
    {required bool completedToday, DateTime? now}) {
  final minutes = todo.habitRemindMinutes;
  if (!todo.isReminderEnabled ||
      !todo.taskType.isRecurring ||
      minutes == null) {
    return null;
  }
  if (minutes < 0 || minutes >= 24 * 60) return null;

  final n = now ?? DateTime.now();
  var fireAt = DateTime(n.year, n.month, n.day, minutes ~/ 60, minutes % 60);
  // 已打卡（或今天时刻已过）→ 从明天开始提醒
  if (completedToday || !fireAt.isAfter(n)) {
    fireAt = fireAt.add(const Duration(days: 1));
  }

  return ReminderOccurrence(
    id: habitReminderId(todo.id),
    fireAt: fireAt,
    title: '打卡提醒：${todo.title}',
    body: '今天的打卡还没完成',
    payload: jsonEncode({'type': 'todo', 'id': todo.id}),
    target: ReminderTarget.todo,
    channel: ReminderChannels.habit,
  );
}

/// 考试提醒：默认提前 30 分钟
ReminderOccurrence? examOccurrence(Exam exam, {DateTime? now, int leadMinutes = 30}) {
  final fireAt =
      exam.examDateTime.subtract(Duration(minutes: leadMinutes));
  final n = now ?? DateTime.now();
  if (!fireAt.isAfter(n)) return null;

  return ReminderOccurrence(
    id: examReminderId(exam.id),
    fireAt: fireAt,
    title: '考试提醒：${exam.name}',
    body: '${_fmt(exam.examDateTime)}'
        '${exam.location.isNotEmpty ? ' · ${exam.location}' : ''}',
    payload: jsonEncode({'type': 'exam', 'id': exam.id}),
    target: ReminderTarget.exam,
    channel: ReminderChannels.schedule,
  );
}

/// 课程提醒（整学期排程窗口）：
/// 对每门课解析其周次范围内的每一次上课（学期起始日期 + 周次 + 星期 + 节次时间配置），
/// 生成"上课前 leadMinutes 分钟"的提醒；只保留 now 之后的，按时间升序，
/// 超出 [maxCount] 时按"最近优先"截断（剩余部分由补排机制续上）。
///
/// 这是"8 天不开 App 提醒仍可用"的核心：窗口覆盖整学期而非未来 7 天。
List<ReminderOccurrence> courseOccurrences({
  required SemesterConfig semester,
  required List<Course> courses,
  required List<ClassTimeConfig> timeConfigs,
  DateTime? now,
  int leadMinutes = 30,
  int maxCount = 200,
}) {
  final n = now ?? DateTime.now();
  final result = <ReminderOccurrence>[];
  final weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  for (final course in courses) {
    // 该课程开始节次所在节段的上课时间
    ClassTimeConfig? section;
    for (final s in timeConfigs) {
      if (course.startPeriod >= s.firstPeriod && course.startPeriod <= s.lastPeriod) {
        section = s;
        break;
      }
    }

    for (final week in Course.parseWeekRange(course.weekRange)) {
      if (week < 1 || week > semester.totalWeeks) continue;

      final days = (week - 1) * 7 + (course.weekday - 1);
      final date = semester.startDate.add(Duration(days: days));
      final startMinutes = section?.startMinutes ?? 8 * 60;
      final classStart = DateTime(
        date.year,
        date.month,
        date.day,
        startMinutes ~/ 60,
        startMinutes % 60,
      );
      final fireAt = classStart.subtract(Duration(minutes: leadMinutes));
      if (!fireAt.isAfter(n)) continue;

      result.add(ReminderOccurrence(
        id: courseReminderId(course.id, week),
        fireAt: fireAt,
        title: '课程提醒：${course.name}',
        body: '$leadMinutes 分钟后上课 · ${weekdays[course.weekday]} '
            '${classStart.hour.toString().padLeft(2, '0')}:${classStart.minute.toString().padLeft(2, '0')}'
            '${course.location.isNotEmpty ? ' · ${course.location}' : ''}',
        payload: jsonEncode({'type': 'course', 'id': course.id}),
        target: ReminderTarget.course,
        channel: ReminderChannels.schedule,
      ));
    }
  }

  result.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  if (result.length > maxCount) {
    return result.sublist(0, maxCount); // 最近优先
  }
  return result;
}
