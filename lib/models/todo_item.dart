import 'package:isar/isar.dart';

part 'todo_item.g.dart';

/// 任务类型枚举
enum TaskType {
  oneTime, // 一次性任务
  recurring; // 每日重复任务（习惯）

  bool get isRecurring => this == TaskType.recurring;
}

/// 任务分类枚举
enum TaskCategory {
  work,     // 工作
  life,     // 生活
  study,    // 学习
  health;   // 健康

  String get displayName {
    switch (this) {
      case TaskCategory.work:
        return '工作';
      case TaskCategory.life:
        return '生活';
      case TaskCategory.study:
        return '学习';
      case TaskCategory.health:
        return '健康';
    }
  }

  String get icon {
    return displayName;
  }
}

@Collection()
class TodoItem {
  Id id = Isar.autoIncrement;

  @Index()
  late String title;

  late bool isCompleted;

  @Index()
  late DateTime createdDate;

  /// 创建时间戳（用于排序）
  late int createdAt;

  /// 完成时间（可选，用于统计）
  DateTime? completedAt;

  /// 任务类型：一次性任务 或 每日重复任务
  @Enumerated(EnumType.name)
  late TaskType taskType;

  /// 任务分类
  @Enumerated(EnumType.name)
  late TaskCategory category;

  /// 任务备注
  String? notes;

  /// 排序权重（用于拖拽排序）
  late int sortOrder;

  /// 开始时间（可选，提醒锚点之一）
  DateTime? startTime;

  /// 截止时间（可选，提醒优先锚点）
  DateTime? deadline;

  /// 提前提醒分钟数（默认 15）
  late int remindBeforeMinutes = 15;

  /// 是否开启提醒
  late bool isReminderEnabled = false;

  /// 每日习惯的打卡提醒时刻（当天分钟数，如 21:00 = 1260；null = 不提醒）。
  /// 仅 recurring 任务使用；与一次性的 deadline 提醒体系相互独立。
  int? habitRemindMinutes;

  TodoItem() {
    // 默认为一次性任务，兼容旧数据
    taskType = TaskType.oneTime;
    category = TaskCategory.life;
    sortOrder = 0;
  }

  /// 创建新任务的工厂方法
  TodoItem.create({
    required this.title,
    required DateTime date,
    this.taskType = TaskType.oneTime,
    this.category = TaskCategory.life,
    this.notes,
    this.deadline,
    bool enableReminder = false,
    int remindBeforeMinutes = 15,
  })  : isCompleted = false,
        createdDate = _normalizeDate(date),
        createdAt = DateTime.now().millisecondsSinceEpoch,
        sortOrder = DateTime.now().millisecondsSinceEpoch {
    isReminderEnabled = enableReminder;
    this.remindBeforeMinutes = remindBeforeMinutes;
  }

  /// 是否已过期：一次性任务的截止时刻已过（展示层用它从"待处理"里隐藏；
  /// 数据保留在库中，历史统计不受影响）。
  bool isExpired({DateTime? now}) {
    if (taskType != TaskType.oneTime) return false;
    final deadline = this.deadline;
    if (deadline == null) return false;
    return deadline.isBefore(now ?? DateTime.now());
  }

  /// 将日期归一化（去除时分秒）
  static DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// 转换为 JSON（用于备份导出）
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
        'createdDate': createdDate.toIso8601String(),
        'createdAt': createdAt,
        'completedAt': completedAt?.toIso8601String(),
        'taskType': taskType.name,
        'category': category.name,
        'notes': notes,
        'sortOrder': sortOrder,
        'startTime': startTime?.toIso8601String(),
        'deadline': deadline?.toIso8601String(),
        'remindBeforeMinutes': remindBeforeMinutes,
        'isReminderEnabled': isReminderEnabled,
        'habitRemindMinutes': habitRemindMinutes,
      };

  /// 从 JSON 创建（用于导入/恢复）
  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem()
    ..id = (json['id'] as int?) ?? Isar.autoIncrement
    ..title = json['title'] as String
    ..isCompleted = json['isCompleted'] as bool
    ..createdDate = DateTime.parse(json['createdDate'] as String)
    ..createdAt = json['createdAt'] as int
    ..completedAt = json['completedAt'] != null
        ? DateTime.parse(json['completedAt'] as String)
        : null
    ..taskType = json['taskType'] != null
        ? TaskType.values.firstWhere(
            (e) => e.name == json['taskType'],
            orElse: () => TaskType.oneTime,
          )
        : TaskType.oneTime
    ..category = json['category'] != null
        ? TaskCategory.values.firstWhere(
            (e) => e.name == json['category'],
            orElse: () => TaskCategory.life,
          )
        : TaskCategory.life
    ..notes = json['notes'] as String?
    ..sortOrder = json['sortOrder'] as int? ?? 0
    ..startTime = json['startTime'] != null
        ? DateTime.parse(json['startTime'] as String)
        : null
    ..deadline = json['deadline'] != null
        ? DateTime.parse(json['deadline'] as String)
        : null
    ..remindBeforeMinutes = json['remindBeforeMinutes'] as int? ?? 15
    ..isReminderEnabled = json['isReminderEnabled'] as bool? ?? false
    ..habitRemindMinutes = json['habitRemindMinutes'] as int?;
}
