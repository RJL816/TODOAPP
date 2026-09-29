import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';
import '../models/daily_completion.dart';
import '../models/memo.dart';
import '../models/pomodoro_session.dart';
import '../models/training.dart';
import '../models/diet_log.dart';
import '../models/expense.dart';
import '../models/todo_item.dart';
import '../models/class_time_config.dart';

/// 应用数据版本。
///
/// 含义：每当 Isar 集合 schema 或应用层数据迁移逻辑发生变化时 +1。
/// v2：备份/恢复机制引入；v3：新增 ClassTimeConfig 集合、SemesterConfig.isActive；
/// v4：TodoItem 新增提醒字段（startTime/deadline/remindBeforeMinutes/isReminderEnabled）；
/// v5：新增 PomodoroSession 集合；v6：新增健身与饮食集合
/// （TrainingPlan/PlanExercise/WorkoutLog/WorkoutSet/DietLog）；v7：新增 Expense。
/// 旧版本首次用新版本打开数据库**之前**（Isar.open 之前，因为打开即自动迁移
/// schema），会先把原库文件复制为可验证的备份；迁移后再比对条数验证。
class BackupService {
  static const int kAppDataVersion = 9;
  static const String _versionKey = 'app_data_version';

  /// Isar 默认库名（Isar.open 未指定 name 时为 "default" → 文件 default.isar）
  static const String dbFileName = 'default.isar';

  /// 导出的格式标识与随库导出的偏好键
  static const String exportFormat = 'todoapp.backup';
  static const List<String> exportedPrefKeys = ['last_opened_date'];

  // 设置页展示用的键
  static const String lastAutoBackupAtKey = 'last_auto_backup_at';
  static const String lastAutoBackupCountsKey = 'last_auto_backup_counts';
  static const String lastAutoBackupVerifiedKey = 'last_auto_backup_verified';

  BackupService._()
      : _dirOverride = null,
        _prefsOverride = null;

  /// 测试注入口：指定文档目录与偏好存储，避免触碰真实数据
  @visibleForTesting
  BackupService.forTest(this._dirOverride, this._prefsOverride);

  static BackupService? _instance;
  static BackupService get instance => _instance ??= BackupService._();

  final Directory? _dirOverride;
  final SharedPreferences? _prefsOverride;

  Future<Directory> _documentsDir() => _dirOverride != null
      ? Future.value(_dirOverride)
      : getApplicationDocumentsDirectory();

  Future<SharedPreferences> _getPrefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  // ==================== 打开前自动备份 ====================

  /// 在 Isar.open 之前调用。
  ///
  /// - 已是当前版本：跳过，返回 null；
  /// - 旧版本且存在旧库文件：复制到 backups/auto_<时间戳>/ 下，
  ///   并用"临时目录中的隔离 Isar 实例"打开备份副本来统计各集合条数
  ///   （可校验 = 副本能被当前 schema 打开且条数可读）。隔离验证会改动副本，
  ///   因此验证使用备份的再拷贝，备份本体保持迁移前的原始快照；
  /// - 备份成功（或全新安装无库文件）才推进版本号；失败则不推进，下次启动重试；
  /// - 应用降级（存储版本高于当前版本）时不备份也不动版本号。
  Future<AutoBackupResult?> ensureBackupBeforeOpen() async {
    final prefs = await _getPrefs();
    final storedVersion = prefs.getInt(_versionKey);
    if (storedVersion == kAppDataVersion) return null;
    if (storedVersion != null && storedVersion > kAppDataVersion) return null;

    final dir = await _documentsDir();
    final dbFile = File('${dir.path}/$dbFileName');

    AutoBackupResult? result;
    if (await dbFile.exists()) {
      result = await _createVerifiedBackup(dbFile);
    }

    final ok = result == null || result.success;
    if (!ok) return result;

    await prefs.setInt(_versionKey, kAppDataVersion);
    if (result != null) {
      await prefs.setString(
          lastAutoBackupAtKey, DateTime.now().toIso8601String());
      await prefs.setString(lastAutoBackupCountsKey, jsonEncode(result.counts));
      await prefs.setBool(
          lastAutoBackupVerifiedKey, false); // 待 verifyAfterOpen 确认
    }
    return result;
  }

  Future<AutoBackupResult> _createVerifiedBackup(File dbFile) async {
    final ts = DateTime.now();
    final stamp = _fileStamp(ts);
    final backupDir = Directory('${dbFile.parent.path}/backups/auto_$stamp');
    String? reason;
    Map<String, int> counts = {};
    try {
      await backupDir.create(recursive: true);
      final snapshot = File('${backupDir.path}/$dbFileName');
      await dbFile.copy(snapshot.path);

      // 隔离验证：把快照再拷贝到临时目录，用当前 schema 打开并统计条数。
      // 用副本验证是为了保持快照本体是"迁移前原始文件"。
      final verifyDir =
          await Directory.systemTemp.createTemp('todoapp_backup_verify');
      try {
        await snapshot.copy('${verifyDir.path}/$dbFileName');
        final verifyIsar = await Isar.open(_schemas, directory: verifyDir.path);
        try {
          counts = await _collectionCounts(verifyIsar);
        } finally {
          await verifyIsar.close(deleteFromDisk: true);
        }
      } finally {
        await verifyDir.delete(recursive: true);
      }
    } catch (e) {
      reason = e.toString();
    }

    return AutoBackupResult(
      success: reason == null,
      path: reason == null ? backupDir.path : null,
      counts: counts,
      failedReason: reason,
    );
  }

  // ==================== 迁移后验证 ====================

  /// 打开数据库并完成应用层迁移之后调用：
  /// 真实库各集合条数应与备份时统计一致，否则说明迁移可能丢失数据（备份已保留）。
  Future<bool> verifyAfterOpen(Isar isar, AutoBackupResult? backup) async {
    final prefs = await _getPrefs();
    if (backup == null || !backup.success) return false;
    final actual = await _collectionCounts(isar);
    final verified = _sameCounts(actual, backup.counts);
    await prefs.setBool(lastAutoBackupVerifiedKey, verified);
    return verified;
  }

  // ==================== 全量导出 ====================

  /// 全量导出为 JSON 字符串（7 个集合 + 备忘录标签关联 + 关键偏好键）。
  Future<String> exportAllToJson(Isar isar) async {
    final todos = await isar.todoItems.where().findAll();
    final completions = await isar.dailyCompletions.where().findAll();
    final courses = await isar.courses.where().findAll();
    final semesters = await isar.semesterConfigs.where().findAll();
    final exams = await isar.exams.where().findAll();
    final memos = await isar.memos.where().findAll();
    final tags = await isar.tags.where().findAll();
    final timeConfigs = await isar.classTimeConfigs.where().findAll();
    final pomodoros = await isar.pomodoroSessions.where().findAll();
    final trainingPlans = await isar.trainingPlans.where().findAll();
    final planExercises = await isar.planExercises.where().findAll();
    final workoutLogs = await isar.workoutLogs.where().findAll();
    final workoutSets = await isar.workoutSets.where().findAll();
    final dietLogs = await isar.dietLogs.where().findAll();
    final expenses = await isar.expenses.where().findAll();

    // IsarLinks 不在 toJson 里，单独导出 memoId → tagIds
    final tagLinks = <Map<String, dynamic>>[];
    for (final memo in memos) {
      await memo.tags.load();
      if (memo.tags.isEmpty) continue;
      tagLinks.add({
        'memoId': memo.id,
        'tagIds': memo.tags.map((t) => t.id).toList(),
      });
    }

    final prefs = await _getPrefs();
    final prefData = <String, Object?>{
      for (final k in exportedPrefKeys) k: prefs.getString(k),
    };

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'format': exportFormat,
      'version': kAppDataVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'collections': {
        'todoItems': todos.map((e) => e.toJson()).toList(),
        'dailyCompletions': completions.map((e) => e.toJson()).toList(),
        'courses': courses.map((e) => e.toJson()).toList(),
        'semesterConfigs': semesters.map((e) => e.toJson()).toList(),
        'exams': exams.map((e) => e.toJson()).toList(),
        'memos': memos.map((e) => e.toJson()).toList(),
        'tags': tags.map((e) => e.toJson()).toList(),
        'classTimeConfigs': timeConfigs.map((e) => e.toJson()).toList(),
        'pomodoroSessions': pomodoros.map((e) => e.toJson()).toList(),
        'trainingPlans': trainingPlans.map((e) => e.toJson()).toList(),
        'planExercises': planExercises.map((e) => e.toJson()).toList(),
        'workoutLogs': workoutLogs.map((e) => e.toJson()).toList(),
        'workoutSets': workoutSets.map((e) => e.toJson()).toList(),
        'dietLogs': dietLogs.map((e) => e.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
      },
      'memoTagLinks': tagLinks,
      'prefs': prefData,
    });
  }

  /// 导出到文档目录下的文件，返回该文件。
  Future<File> exportToFile(Isar isar) async {
    final json = await exportAllToJson(isar);
    final dir = await _documentsDir();
    final file =
        File('${dir.path}/todoapp_export_${_fileStamp(DateTime.now())}.json');
    await file.writeAsString(json, flush: true);
    return file;
  }

  // ==================== 覆盖恢复 ====================

  /// 从导出 JSON 覆盖恢复：清空现有全部集合后按原 ID 整体写回，并恢复
  /// 备忘录-标签关联与关键偏好键。完成后重新统计条数与源数据比对验证。
  ///
  /// 注意：这是"覆盖"而非"合并"——两台设备各自的自增 ID 可能重叠，
  /// 合并恢复需要稳定业务标识与冲突规则，见计划文档的独立设计项。
  Future<RestoreSummary> restoreFromJson(String jsonString, Isar isar) async {
    final warnings = <String>[];

    dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (e) {
      throw const FormatException('不是有效的 JSON 文件');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != exportFormat) {
      throw const FormatException('不是本应用的备份文件（格式标识不匹配）');
    }
    final version = decoded['version'] as int?;
    if (version == null || version > kAppDataVersion) {
      throw FormatException('备份版本不支持（$version），请使用新版本应用的导出文件');
    }
    if (version < kAppDataVersion) {
      warnings.add('备份来自旧版本（v$version），按当前结构恢复');
    }

    final cols = decoded['collections'] as Map<String, dynamic>;
    final todoItems = (cols['todoItems'] as List? ?? [])
        .map((e) => TodoItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final completions = (cols['dailyCompletions'] as List? ?? [])
        .map((e) => DailyCompletion.fromJson(e as Map<String, dynamic>))
        .toList();
    final courses = (cols['courses'] as List? ?? [])
        .map((e) => Course.fromJson(e as Map<String, dynamic>))
        .toList();
    final semesters = (cols['semesterConfigs'] as List? ?? [])
        .map((e) => SemesterConfig.fromJson(e as Map<String, dynamic>))
        .toList();
    final exams = (cols['exams'] as List? ?? [])
        .map((e) => Exam.fromJson(e as Map<String, dynamic>))
        .toList();
    final memos = (cols['memos'] as List? ?? [])
        .map((e) => Memo.fromJson(e as Map<String, dynamic>))
        .toList();
    final tags = (cols['tags'] as List? ?? [])
        .map((e) => Tag.fromJson(e as Map<String, dynamic>))
        .toList();
    final timeConfigs = (cols['classTimeConfigs'] as List? ?? [])
        .map((e) => ClassTimeConfig.fromJson(e as Map<String, dynamic>))
        .toList();
    final pomodoros = (cols['pomodoroSessions'] as List? ?? [])
        .map((e) => PomodoroSession.fromJson(e as Map<String, dynamic>))
        .toList();
    final trainingPlans = (cols['trainingPlans'] as List? ?? [])
        .map((e) => TrainingPlan.fromJson(e as Map<String, dynamic>))
        .toList();
    final planExercises = (cols['planExercises'] as List? ?? [])
        .map((e) => PlanExercise.fromJson(e as Map<String, dynamic>))
        .toList();
    final workoutLogs = (cols['workoutLogs'] as List? ?? [])
        .map((e) => WorkoutLog.fromJson(e as Map<String, dynamic>))
        .toList();
    final workoutSets = (cols['workoutSets'] as List? ?? [])
        .map((e) => WorkoutSet.fromJson(e as Map<String, dynamic>))
        .toList();
    final dietLogs = (cols['dietLogs'] as List? ?? [])
        .map((e) => DietLog.fromJson(e as Map<String, dynamic>))
        .toList();
    final expenses = (cols['expenses'] as List? ?? [])
        .map((e) => Expense.fromJson(e as Map<String, dynamic>))
        .toList();
    final links = (decoded['memoTagLinks'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();

    final prefs = await _getPrefs();
    final prefData = (decoded['prefs'] as Map<String, dynamic>? ?? {});

    await isar.writeTxn(() async {
      // 先清空，实现整库覆盖
      await isar.todoItems.clear();
      await isar.dailyCompletions.clear();
      await isar.courses.clear();
      await isar.semesterConfigs.clear();
      await isar.exams.clear();
      await isar.memos.clear();
      await isar.tags.clear();
      await isar.classTimeConfigs.clear();
      await isar.pomodoroSessions.clear();
      await isar.trainingPlans.clear();
      await isar.planExercises.clear();
      await isar.workoutLogs.clear();
      await isar.workoutSets.clear();
      await isar.dietLogs.clear();
      await isar.expenses.clear();

      // 按原 ID 写回，保持 DailyCompletion.todoId 等引用有效
      await isar.todoItems.putAll(todoItems);
      await isar.dailyCompletions.putAll(completions);
      await isar.courses.putAll(courses);
      await isar.semesterConfigs.putAll(semesters);
      await isar.exams.putAll(exams);
      await isar.memos.putAll(memos);
      await isar.tags.putAll(tags);
      await isar.classTimeConfigs.putAll(timeConfigs);
      await isar.pomodoroSessions.putAll(pomodoros);
      await isar.trainingPlans.putAll(trainingPlans);
      await isar.planExercises.putAll(planExercises);
      await isar.workoutLogs.putAll(workoutLogs);
      await isar.workoutSets.putAll(workoutSets);
      await isar.dietLogs.putAll(dietLogs);
      await isar.expenses.putAll(expenses);

      // 恢复备忘录-标签关联
      for (final link in links) {
        final memoId = link['memoId'] as int;
        final tagIds = (link['tagIds'] as List).cast<int>();
        final memo = await isar.memos.get(memoId);
        if (memo == null) {
          warnings.add('标签关联指向不存在的备忘录 #$memoId，已跳过');
          continue;
        }
        for (final tagId in tagIds) {
          final tag = await isar.tags.get(tagId);
          if (tag != null) memo.tags.add(tag);
        }
        await memo.tags.save();
      }
    });

    // 恢复关键偏好键
    for (final key in exportedPrefKeys) {
      final value = prefData[key] as String?;
      if (value != null) {
        await prefs.setString(key, value);
      }
    }

    // 恢复后验证：条数应与源数据一致
    final actual = await _collectionCounts(isar);
    final expected = {
      'todoItems': todoItems.length,
      'dailyCompletions': completions.length,
      'courses': courses.length,
      'semesterConfigs': semesters.length,
      'exams': exams.length,
      'memos': memos.length,
      'tags': tags.length,
      'classTimeConfigs': timeConfigs.length,
      'pomodoroSessions': pomodoros.length,
      'trainingPlans': trainingPlans.length,
      'planExercises': planExercises.length,
      'workoutLogs': workoutLogs.length,
      'workoutSets': workoutSets.length,
      'dietLogs': dietLogs.length,
      'expenses': expenses.length,
    };
    final verified = _sameCounts(actual, expected);
    if (!verified) {
      warnings.add('恢复后条数与备份不一致：${_describeDiff(actual, expected)}');
    }

    return RestoreSummary(
      restoredCounts: actual,
      verified: verified,
      warnings: warnings,
    );
  }

  // ==================== 内部工具 ====================

  static List<CollectionSchema<dynamic>> get _schemas => [
        TodoItemSchema,
        DailyCompletionSchema,
        CourseSchema,
        SemesterConfigSchema,
        ExamSchema,
        MemoSchema,
        TagSchema,
        ClassTimeConfigSchema,
        PomodoroSessionSchema,
        TrainingPlanSchema,
        PlanExerciseSchema,
        WorkoutLogSchema,
        WorkoutSetSchema,
        DietLogSchema,
        ExpenseSchema,
      ];

  static Future<Map<String, int>> _collectionCounts(Isar isar) async => {
        'todoItems': await isar.todoItems.count(),
        'dailyCompletions': await isar.dailyCompletions.count(),
        'courses': await isar.courses.count(),
        'semesterConfigs': await isar.semesterConfigs.count(),
        'exams': await isar.exams.count(),
        'memos': await isar.memos.count(),
        'tags': await isar.tags.count(),
        'classTimeConfigs': await isar.classTimeConfigs.count(),
        'pomodoroSessions': await isar.pomodoroSessions.count(),
        'trainingPlans': await isar.trainingPlans.count(),
        'planExercises': await isar.planExercises.count(),
        'workoutLogs': await isar.workoutLogs.count(),
        'workoutSets': await isar.workoutSets.count(),
        'dietLogs': await isar.dietLogs.count(),
        'expenses': await isar.expenses.count(),
      };

  static bool _sameCounts(Map<String, int> a, Map<String, int> b) {
    return a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
  }

  static String _describeDiff(Map<String, int> a, Map<String, int> b) {
    return a.keys.map((k) => '$k: 实际 ${a[k]} / 备份 ${b[k]}').join('；');
  }

  static String _fileStamp(DateTime ts) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${ts.year}${p2(ts.month)}${p2(ts.day)}_${p2(ts.hour)}${p2(ts.minute)}${p2(ts.second)}';
  }
}

/// 打开前自动备份的结果
class AutoBackupResult {
  final bool success;
  final String? path;
  final Map<String, int> counts;
  final String? failedReason;

  const AutoBackupResult({
    required this.success,
    this.path,
    this.counts = const {},
    this.failedReason,
  });
}

/// 覆盖恢复的结果
class RestoreSummary {
  final Map<String, int> restoredCounts;
  final bool verified;
  final List<String> warnings;

  const RestoreSummary({
    required this.restoredCounts,
    required this.verified,
    required this.warnings,
  });

  int get total => restoredCounts.values.fold(0, (a, b) => a + b);
}
