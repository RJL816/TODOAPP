import 'package:isar/isar.dart';

part 'course.g.dart';

/// 学期配置
@Collection()
class SemesterConfig {
  Id id = Isar.autoIncrement;

  /// 学期名称，如 2025-2026-1
  @Index()
  late String name;

  /// 开学日期（第一周周一）
  @Index()
  late DateTime startDate;

  /// 总周数
  late int totalWeeks;

  SemesterConfig();

  /// 创建新学期配置
  SemesterConfig.create({
    required this.name,
    required this.startDate,
    this.totalWeeks = 20,
  });

  /// 计算当前是第几周
  /// 返回值：1-totalWeeks，如果超出范围则返回最接近的值
  int getCurrentWeek() {
    final now = DateTime.now();
    // 计算从开学日期到现在的天数差
    final daysDiff = now.difference(startDate).inDays;

    // 向下取整得到周次，+1因为第一周从0天开始
    int week = (daysDiff / 7).floor() + 1;

    // 确保在有效范围内
    if (week < 1) week = 1;
    if (week > totalWeeks) week = totalWeeks;

    return week;
  }

  /// 检查当前日期是否在学期内
  bool isInSemester() {
    final now = DateTime.now();
    final endDate = startDate.add(Duration(days: totalWeeks * 7 - 1));
    return now.isAfter(startDate.subtract(const Duration(days: 1))) &&
           now.isBefore(endDate.add(const Duration(days: 1)));
  }

  /// 获取学期结束日期
  DateTime getEndDate() {
    return startDate.add(Duration(days: totalWeeks * 7 - 1));
  }
}

/// 课程信息
@Collection()
class Course {
  Id id = Isar.autoIncrement;

  /// 课程名称
  @Index()
  late String name;

  /// 教师姓名
  late String teacher;

  /// 上课地点
  late String location;

  /// 星期几 (1-7, 1=周一, 7=周日)
  @Index()
  late int weekday;

  /// 开始节次 (1-10)
  late int startPeriod;

  /// 结束节次 (1-10)
  late int endPeriod;

  /// 周次范围字符串，如 "1-12" 或 "11-13,15,17-18"
  @Index()
  late String weekRange;

  /// 所属学期
  @Index()
  late String semester;

  /// 颜色（用于UI显示）
  late int colorArgb;

  /// 备注
  String? notes;

  Course() {
    semester = '2025-2026-1';
    colorArgb = _generateRandomColor();
    weekRange = '1-18';
    teacher = '';
    location = '';
  }

  /// 创建新课程
  Course.create({
    required this.name,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    required this.weekRange,
    required this.semester,
    this.teacher = '',
    this.location = '',
    this.notes,
    int? colorArgb,
  }) : colorArgb = colorArgb ?? _generateRandomColor();

  /// 柔和配色方案（饱和度适中，易于区分）
  static const List<int> courseColors = [
    0xFF5C6BC0, // 靛蓝
    0xFF7E57C2, // 深紫
    0xFFAB47BC, // 紫色
    0xFFEC407A, // 粉红
    0xFFEF5350, // 红色
    0xFFFF7043, // 深橙
    0xFFFFA726, // 橙色
    0xFFFFCA28, // 琥珀
    0xFF66BB6A, // 绿色
    0xFF26A69A, // 蓝绿
    0xFF29B6F6, // 浅蓝
    0xFF42A5F5, // 蓝色
  ];

  /// 生成随机颜色
  static int _generateRandomColor() {
    final now = DateTime.now();
    final seed = now.millisecondsSinceEpoch % courseColors.length;
    return courseColors[seed >= 0 ? seed : 0];
  }

  /// 根据课程名生成固定颜色（相同课程名颜色相同）
  static int getColorForName(String name) {
    if (name.isEmpty) return courseColors[0];
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return courseColors[(hash.abs()) % courseColors.length];
  }

  /// 检查指定周次是否有课
  /// @param weekNum 周次数（1-20）
  /// @return 如果该周有课返回true，否则返回false
  bool hasClassInWeek(int weekNum) {
    return _parseWeekRange(weekRange).contains(weekNum);
  }

  /// 解析周次范围字符串，返回有课的周次列表
  /// @param range 周次范围字符串，如 "1-12" 或 "11-13,15,17-18"
  /// @return 有课的周次列表，已排序
  static List<int> parseWeekRange(String range) {
    final weeks = <int>[];

    // 移除空格和[周]标记
    String cleanRange = range.replaceAll(' ', '').replaceAll('[周]', '').replaceAll('周', '');

    if (cleanRange.isEmpty) {
      return weeks;
    }

    // 按逗号分割多个范围
    final parts = cleanRange.split(',');

    for (var part in parts) {
      part = part.trim();
      if (part.isEmpty) continue;

      if (part.contains('-')) {
        // 处理范围，如 "1-12"
        final nums = part.split('-');
        if (nums.length == 2) {
          try {
            final start = int.parse(nums[0]);
            final end = int.parse(nums[1]);
            for (int i = start; i <= end; i++) {
              weeks.add(i);
            }
          } catch (e) {
            // 解析失败，跳过
            continue;
          }
        }
      } else {
        // 处理单个周次，如 "15"
        try {
          weeks.add(int.parse(part));
        } catch (e) {
          // 解析失败，跳过
          continue;
        }
      }
    }

    // 去重并排序
    final uniqueWeeks = weeks.toSet().toList();
    uniqueWeeks.sort();

    return uniqueWeeks;
  }

  /// 获取课程的开始周次
  int getStartWeek() {
    final weeks = _parseWeekRange(weekRange);
    return weeks.isEmpty ? 1 : weeks.first;
  }

  /// 获取课程的结束周次
  int getEndWeek() {
    final weeks = _parseWeekRange(weekRange);
    return weeks.isEmpty ? 20 : weeks.last;
  }

  /// 内部方法：解析周次范围
  List<int> _parseWeekRange(String range) {
    return Course.parseWeekRange(range);
  }

  /// 转换为JSON（用于调试）
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'teacher': teacher,
        'location': location,
        'weekday': weekday,
        'startPeriod': startPeriod,
        'endPeriod': endPeriod,
        'weekRange': weekRange,
        'semester': semester,
        'colorArgb': colorArgb,
        'notes': notes,
      };
}

/// 考试信息
@Collection()
class Exam {
  Id id = Isar.autoIncrement;

  /// 考试名称（科目名称）
  @Index()
  late String name;

  /// 考试日期和时间
  @Index()
  late DateTime examDateTime;

  /// 考试时长（分钟）
  late int durationMinutes;

  /// 考试地点
  late String location;

  /// 所属学期
  @Index()
  late String semester;

  /// 备注
  String? notes;

  /// 颜色（用于UI显示）
  late int colorArgb;

  /// 是否已完成（考试已过）
  late bool isCompleted;

  Exam() {
    semester = '2025-2026-1';
    colorArgb = 0xFFE91E63; // 默认粉红色
    durationMinutes = 120;
    location = '';
    isCompleted = false;
  }

  /// 创建新考试
  Exam.create({
    required this.name,
    required this.examDateTime,
    this.durationMinutes = 120,
    this.location = '',
    required this.semester,
    this.notes,
    int? colorArgb,
  }) : colorArgb = colorArgb ?? 0xFFE91E63,
       isCompleted = false;

  /// 获取距离考试的天数
  /// 返回负数表示已过，0表示今天，正数表示还有几天
  int getDaysUntilExam() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final examDate = DateTime(examDateTime.year, examDateTime.month, examDateTime.day);
    return examDate.difference(today).inDays;
  }

  /// 检查考试是否已过
  bool isPast() {
    return getDaysUntilExam() < 0;
  }

  /// 检查是否是今天
  bool isToday() {
    return getDaysUntilExam() == 0;
  }

  /// 获取格式化的倒计时文本
  String getCountdownText() {
    final days = getDaysUntilExam();
    if (days < 0) {
      return '已结束';
    } else if (days == 0) {
      return '今天考试！';
    } else if (days == 1) {
      return '明天考试';
    } else if (days <= 7) {
      return '还有 $days 天';
    } else {
      return '还有 $days 天';
    }
  }

  /// 获取格式化的时间字符串
  String getFormattedTime() {
    final hour = examDateTime.hour.toString().padLeft(2, '0');
    final minute = examDateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// 获取格式化的日期字符串
  String getFormattedDate() {
    return '${examDateTime.month}月${examDateTime.day}日';
  }

  /// 转换为JSON（用于调试）
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'examDateTime': examDateTime.toIso8601String(),
        'durationMinutes': durationMinutes,
        'location': location,
        'semester': semester,
        'notes': notes,
        'colorArgb': colorArgb,
        'isCompleted': isCompleted,
      };
}
