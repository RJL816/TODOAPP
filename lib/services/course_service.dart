import 'package:isar/isar.dart';
import '../models/course.dart';
import 'widget_service.dart';

/// 课程数据库服务
class CourseService {
  static CourseService? _instance;
  static Isar? _isar;

  static CourseService get instance {
    _instance ??= CourseService._();
    return _instance!;
  }

  CourseService._();

  /// 初始化服务
  Future<void> init(Isar isar) async {
    _isar = isar;
  }

  Isar get isar {
    if (_isar == null) {
      throw Exception('Isar database not initialized. Call init() first.');
    }
    return _isar!;
  }

  // ==================== 学期配置管理 ====================

  /// 获取或创建当前学期配置
  Future<SemesterConfig> getOrCreateCurrentSemester() async {
    final configs = await isar.semesterConfigs.where().findAll();

    if (configs.isEmpty) {
      // 没有配置，创建默认配置
      final now = DateTime.now();
      // 找到本周的周一作为开学日期
      final monday = _findMonday(now);

      final config = SemesterConfig.create(
        name: _generateDefaultSemesterName(now),
        startDate: monday,
        totalWeeks: 20,
      );

      await isar.writeTxn(() async {
        await isar.semesterConfigs.put(config);
      });

      return config;
    }

    // 返回第一个配置
    return configs.first;
  }

  /// 更新学期配置
  Future<void> updateSemesterConfig(SemesterConfig config) async {
    await isar.writeTxn(() async {
      await isar.semesterConfigs.put(config);
    });
  }

  /// 获取当前学期
  Future<SemesterConfig?> getCurrentSemester() async {
    final configs = await isar.semesterConfigs.where().findFirst();
    return configs;
  }

  /// 找到指定日期所在周的周一
  DateTime _findMonday(DateTime date) {
    final weekday = date.weekday; // 1=周一, 7=周日
    final monday = date.subtract(Duration(days: weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  /// 根据日期生成默认学期名称
  String _generateDefaultSemesterName(DateTime date) {
    final year = date.year;
    final month = date.month;

    // 2-8月为第一学期，9-1月为第二学期
    if (month >= 2 && month <= 8) {
      return '$year-${year + 1}-1'; // 如 2025-2026-1
    } else {
      if (month == 1) {
        return '${year - 1}-$year-2'; // 如 2024-2025-2
      } else {
        return '$year-${year + 1}-1'; // 如 2025-2026-1
      }
    }
  }

  // ==================== 课程CRUD操作 ====================

  /// 导入课程（清除旧数据）
  Future<void> importCourses(List<Course> courses, String semester) async {
    await isar.writeTxn(() async {
      // 删除该学期的旧课程
      await isar.courses.filter().semesterEqualTo(semester).deleteAll();

      // 添加新课程
      for (var course in courses) {
        course.semester = semester;
        await isar.courses.put(course);
      }
    });
  }

  /// 添加课程
  Future<int> addCourse(Course course) async {
    return await isar.writeTxn(() async {
      return await isar.courses.put(course);
    });
  }

  /// 更新课程
  Future<void> updateCourse(Course course) async {
    await isar.writeTxn(() async {
      await isar.courses.put(course);
    });
  }

  /// 删除课程
  Future<bool> deleteCourse(int id) async {
    return await isar.writeTxn(() async {
      return await isar.courses.delete(id);
    });
  }

  /// 清空所有课程
  Future<void> clearAllCourses() async {
    await isar.writeTxn(() async {
      await isar.courses.clear();
    });
  }

  /// 获取所有课程
  Future<List<Course>> getAllCourses() async {
    return await isar.courses.where().findAll();
  }

  // ==================== 课程查询 ====================

  /// 获取指定周的课程表
  /// @param weekNum 周次数（1-20）
  /// @return Map<星期几, 课程列表>，key为1-7
  Future<Map<int, List<Course>>> getWeeklySchedule(int weekNum) async {
    final allCourses = await isar.courses.where().findAll();

    // 筛选指定周有课的课程（过滤掉已结课的课程）
    final weekCourses = allCourses.where((course) {
      return course.hasClassInWeek(weekNum);
    }).toList();

    // 按星期分组
    final result = <int, List<Course>>{};
    for (var i = 1; i <= 7; i++) {
      result[i] = [];
    }

    for (var course in weekCourses) {
      result[course.weekday]!.add(course);
    }

    // 每天的课程按节次排序
    for (var list in result.values) {
      list.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    }

    return result;
  }

  /// 获取指定周的课程列表
  /// @param weekNum 周次数
  /// @return 该周的所有课程，已按星期和节次排序
  Future<List<Course>> getCoursesForWeek(int weekNum) async {
    final allCourses = await isar.courses.where().findAll();

    return allCourses.where((course) {
      return course.hasClassInWeek(weekNum);
    }).toList()
      ..sort((a, b) {
        // 先按星期排序，再按节次排序
        if (a.weekday != b.weekday) {
          return a.weekday.compareTo(b.weekday);
        }
        return a.startPeriod.compareTo(b.startPeriod);
      });
  }

  /// 获取指定日期的课程
  /// @param weekday 星期几（1-7）
  /// @param weekNum 周次数
  /// @return 该天的课程列表，按节次排序
  Future<List<Course>> getCoursesForDay(int weekday, int weekNum) async {
    final allCourses = await isar.courses.where().findAll();

    return allCourses.where((course) {
      return course.weekday == weekday && course.hasClassInWeek(weekNum);
    }).toList()
      ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
  }

  /// 获取当前时间的课程
  /// @return 当前正在进行的课程，如果没有返回null
  Future<Course?> getCurrentCourse() async {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=周一, 7=周日
    final hour = now.hour;
    final minute = now.minute;

    // 计算当前是第几节
    int currentPeriod = _getCurrentPeriod(hour, minute);
    if (currentPeriod == 0) return null;

    final semester = await getOrCreateCurrentSemester();
    final currentWeek = semester.getCurrentWeek();

    final todayCourses = await getCoursesForDay(weekday, currentWeek);

    for (var course in todayCourses) {
      if (currentPeriod >= course.startPeriod &&
          currentPeriod <= course.endPeriod) {
        return course;
      }
    }

    return null;
  }

  /// 获取下一节课程
  Future<Course?> getNextCourse() async {
    final now = DateTime.now();
    final weekday = now.weekday;
    final hour = now.hour;
    final minute = now.minute;

    final currentPeriod = _getCurrentPeriod(hour, minute);
    final semester = await getOrCreateCurrentSemester();
    final currentWeek = semester.getCurrentWeek();

    // 先看今天还有没有课
    final todayCourses = await getCoursesForDay(weekday, currentWeek);
    for (var course in todayCourses) {
      if (course.startPeriod > currentPeriod) {
        return course;
      }
    }

    // 今天没课了，看明天的第一节课
    final tomorrow = weekday < 7 ? weekday + 1 : 1;
    final tomorrowWeek = weekday < 7 ? currentWeek : currentWeek + 1;
    final tomorrowCourses = await getCoursesForDay(tomorrow, tomorrowWeek);

    if (tomorrowCourses.isNotEmpty) {
      return tomorrowCourses.first;
    }

    return null;
  }

  /// 根据当前时间计算当前是第几节
  /// @param hour 小时（0-23）
  /// @param minute 分钟（0-59）
  /// @return 节次（1-10），如果不在上课时间返回0
  int _getCurrentPeriod(int hour, int minute) {
    final totalMinutes = hour * 60 + minute;

    // 时间段定义（分钟）
    final periods = [
      {'start': 8 * 60, 'end': 9 * 60 + 40},      // 08:00-09:40 第1-2节
      {'start': 10 * 60, 'end': 11 * 60 + 40},   // 10:00-11:40 第3-4节
      {'start': 14 * 60 + 30, 'end': 16 * 60 + 10}, // 14:30-16:10 第5-6节
      {'start': 16 * 60 + 30, 'end': 18 * 60 + 10}, // 16:30-18:10 第7-8节
      {'start': 19 * 60 + 30, 'end': 21 * 60 + 10}, // 19:30-21:10 第9-10节
    ];

    for (int i = 0; i < periods.length; i++) {
      final period = periods[i];
      if (totalMinutes >= period['start']! && totalMinutes <= period['end']!) {
        return i * 2 + 1; // 返回该时间段的开始节次
      }
    }

    return 0;
  }

  // ==================== 统计功能 ====================

  /// 获取课程数量统计
  /// @param weekNum 周次数
  /// @return Map<'total'|'completed', 数量>
  Future<Map<String, int>> getCourseCountStatistics(int weekNum) async {
    final courses = await getCoursesForWeek(weekNum);
    final total = courses.length;

    // 统计已结课的课程数量
    int completed = 0;
    for (var course in courses) {
      if (!course.hasClassInWeek(weekNum)) {
        completed++;
      }
    }

    return {
      'total': total,
      'active': courses.where((c) => c.hasClassInWeek(weekNum)).length,
      'completed': completed,
    };
  }

  /// 调试：打印所有课程信息
  Future<Map<String, dynamic>> debugGetAllCoursesInfo() async {
    final courses = await isar.courses.where().findAll();

    return {
      'total': courses.length,
      'courses': courses.map((c) => {
        'name': c.name,
        'weekday': c.weekday,
        'period': '${c.startPeriod}-${c.endPeriod}',
        'weekRange': c.weekRange,
        'teacher': c.teacher,
        'location': c.location,
      }).toList(),
    };
  }

  // ==================== 考试管理 ====================

  /// 添加考试
  Future<int> addExam(Exam exam) async {
    final id = await isar.writeTxn(() async {
      return await isar.exams.put(exam);
    });
    // 同步到桌面小部件
    _syncExamsToWidget();
    return id;
  }

  /// 更新考试
  Future<void> updateExam(Exam exam) async {
    await isar.writeTxn(() async {
      await isar.exams.put(exam);
    });
    // 同步到桌面小部件
    _syncExamsToWidget();
  }

  /// 删除考试
  Future<void> deleteExam(int id) async {
    await isar.writeTxn(() async {
      await isar.exams.delete(id);
    });
    // 同步到桌面小部件
    _syncExamsToWidget();
  }

  /// 同步考试数据到桌面小部件
  Future<void> _syncExamsToWidget() async {
    try {
      final exams = await getAllExams();
      await WidgetService.instance.syncExams(exams);
    } catch (e) {
      // 忽略同步错误
    }
  }

  /// 获取所有考试
  Future<List<Exam>> getAllExams() async {
    return await isar.exams.where().sortByExamDateTime().findAll();
  }

  /// 获取即将到来的考试（未来的考试）
  Future<List<Exam>> getUpcomingExams() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final exams = await isar.exams
        .filter()
        .examDateTimeGreaterThan(today.subtract(const Duration(days: 1)))
        .sortByExamDateTime()
        .findAll();
    
    return exams;
  }

  /// 获取指定学期的考试
  Future<List<Exam>> getExamsForSemester(String semester) async {
    return await isar.exams
        .filter()
        .semesterEqualTo(semester)
        .sortByExamDateTime()
        .findAll();
  }

  /// 获取指定日期范围内的考试
  Future<List<Exam>> getExamsInDateRange(DateTime start, DateTime end) async {
    return await isar.exams
        .filter()
        .examDateTimeBetween(start, end)
        .sortByExamDateTime()
        .findAll();
  }

  /// 获取本周的考试
  Future<List<Exam>> getExamsForCurrentWeek() async {
    final now = DateTime.now();
    final weekday = now.weekday;
    final monday = now.subtract(Duration(days: weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    
    final startOfWeek = DateTime(monday.year, monday.month, monday.day);
    final endOfWeek = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);
    
    return await getExamsInDateRange(startOfWeek, endOfWeek);
  }

  /// 清空所有考试
  Future<void> clearAllExams() async {
    await isar.writeTxn(() async {
      await isar.exams.clear();
    });
  }
}
