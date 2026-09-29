import 'package:isar/isar.dart';

import '../models/diet_log.dart';
import 'isar_service.dart';

/// 饮食服务：按日期记录与回顾（只做记录，不生成目标）
class DietService {
  static DietService? _instance;
  static DietService get instance => _instance ??= DietService._();
  DietService._();

  /// 某天的全部饮食记录（按记录时间排序）
  Future<List<DietLog>> getLogsForDate(DateTime date) async {
    final isar = IsarService.instance.isar;
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return await isar.dietLogs
        .filter()
        .dateBetween(start, end, includeLower: true, includeUpper: false)
        .sortByCreatedAt()
        .findAll();
  }

  Future<int> addLog(DietLog log) async {
    final isar = IsarService.instance.isar;
    return await isar.writeTxn(() async => await isar.dietLogs.put(log));
  }

  Future<void> updateLog(DietLog log) async {
    final isar = IsarService.instance.isar;
    await isar.writeTxn(() async {
      await isar.dietLogs.put(log);
    });
  }

  Future<void> deleteLog(int id) async {
    final isar = IsarService.instance.isar;
    await isar.writeTxn(() async {
      await isar.dietLogs.delete(id);
    });
  }

  /// Copies one meal from the preceding day in a single transaction.
  Future<int> copyPreviousMeal(DateTime target, MealType type) async {
    final previous = target.subtract(const Duration(days: 1));
    final source = (await getLogsForDate(previous))
        .where((log) => log.mealType == type)
        .toList();
    if (source.isEmpty) return 0;
    final date = DateTime(target.year, target.month, target.day);
    final copies = [
      for (final log in source)
        DietLog.create(
            date: date,
            mealType: type,
            food: log.food,
            notes: log.notes,
            calories: log.calories,
            proteinGrams: log.proteinGrams,
            carbsGrams: log.carbsGrams,
            fatGrams: log.fatGrams),
    ];
    final isar = IsarService.instance.isar;
    await isar.writeTxn(() async => isar.dietLogs.putAll(copies));
    return copies.length;
  }

  /// 某天的汇总（营养字段仅对填写的记录求和）
  Future<DietDaySummary> getSummaryForDate(DateTime date) async {
    final logs = await getLogsForDate(date);
    int calories = 0, protein = 0, carbs = 0, fat = 0;
    int calorieEntries = 0;
    for (final log in logs) {
      if (log.calories != null) {
        calorieEntries++;
        calories += log.calories!;
      }
      protein += log.proteinGrams ?? 0;
      carbs += log.carbsGrams ?? 0;
      fat += log.fatGrams ?? 0;
    }
    return DietDaySummary(
      count: logs.length,
      calories: calories,
      hasCalorieData: calorieEntries > 0,
      proteinGrams: protein,
      carbsGrams: carbs,
      fatGrams: fat,
    );
  }
}

/// 一天的饮食汇总
class DietDaySummary {
  final int count;
  final int calories;
  final bool hasCalorieData;
  final int proteinGrams;
  final int carbsGrams;
  final int fatGrams;

  const DietDaySummary({
    required this.count,
    required this.calories,
    required this.hasCalorieData,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });
}
