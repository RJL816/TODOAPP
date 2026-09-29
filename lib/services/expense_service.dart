import 'package:isar/isar.dart';

import '../models/expense.dart';
import 'isar_service.dart';
import 'wechat_bill_parser.dart';

class ExpenseService {
  static ExpenseService? _instance;
  static ExpenseService get instance => _instance ??= ExpenseService._();
  ExpenseService._();

  Isar get _isar => IsarService.instance.isar;

  Future<List<Expense>> getForMonth(DateTime month) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final items = await _isar.expenses
        .filter()
        .dateBetween(start, end, includeLower: true, includeUpper: false)
        .findAll();
    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  Future<int> save(Expense expense) async {
    if (expense.amountCents <= 0) throw const FormatException('金额必须大于零');
    return _isar.writeTxn(() async => _isar.expenses.put(expense));
  }

  Future<void> delete(int id) async {
    await _isar.writeTxn(() async {
      await _isar.expenses.delete(id);
    });
  }

  Future<void> markDuplicates(List<WechatImportRow> rows) async {
    final existing = await _isar.expenses.where().findAll();
    final ids = existing.map((e) => e.tradeNo).whereType<String>().toSet();
    for (final row in rows) {
      row.duplicateInDatabase =
          row.expense.tradeNo != null && ids.contains(row.expense.tradeNo);
    }
  }

  /// Import the confirmed preview in a single transaction. A second existence
  /// check protects against importing the same file from two preview dialogs.
  Future<int> importConfirmed(List<WechatImportRow> rows) async {
    return _isar.writeTxn(() async {
    final all = await _isar.expenses.where().findAll();
    final used = all.map((e) => e.tradeNo).whereType<String>().toSet();
    final selected = <Expense>[];
    final categoryEdited = <Expense>{};
    for (final row in rows) {
      if (!row.canImport) continue;
      final expense = row.expense;
      if (expense.tradeNo != null && !used.add(expense.tradeNo!)) continue;
      selected.add(expense);
      if (row.categoryEdited) categoryEdited.add(expense);
    }

    // Refunds inherit the category of an identifiable original payment. When
    // the export also contains a refund row, clear an inferred full refund on
    // the original so that it is subtracted only once.
    final byTrade = <String, Expense>{};
    final byMerchant = <String, Expense>{};
    for (final e in [...all, ...selected]) {
      if (e.kind != ExpenseKind.expense) continue;
      if (e.tradeNo != null) byTrade[e.tradeNo!] = e;
      if (e.merchantNo != null) byMerchant[e.merchantNo!] = e;
    }
    final changedOriginals = <Expense>{};
    for (final refund
        in [...all, ...selected].where((e) => e.kind == ExpenseKind.refund)) {
      final original = (refund.relatedTradeNo == null
              ? null
              : byTrade[refund.relatedTradeNo]) ??
          (refund.merchantNo == null ? null : byMerchant[refund.merchantNo]) ??
          (refund.tradeNo == null ? null : byTrade[refund.tradeNo]);
      if (original == null || identical(original, refund)) continue;
      if (refund.category == '其他' && !categoryEdited.contains(refund)) {
        refund.category = original.category;
      }
      refund.relatedTradeNo ??= original.tradeNo;
      if (original.inferredRefundCents != 0) {
        original.inferredRefundCents = 0;
        changedOriginals.add(original);
      }
    }
    for (final original in changedOriginals) {
      if (original.id != Isar.autoIncrement) {
        await _isar.expenses.put(original);
      }
    }
    await _isar.expenses.putAll(selected);
    return selected.length;
    });
  }

  static ExpenseSummary summarize(Iterable<Expense> items) {
    var gross = 0;
    var refunds = 0;
    final byCategory = <String, int>{};
    for (final expense in items) {
      gross += expense.grossCents;
      refunds += expense.refundCents;
      if (expense.netCents != 0) {
        byCategory.update(expense.category, (old) => old + expense.netCents,
            ifAbsent: () => expense.netCents);
      }
    }
    return ExpenseSummary(
        grossCents: gross,
        refundCents: refunds,
        netCents: gross - refunds,
        byCategory: byCategory);
  }
}

class ExpenseSummary {
  final int grossCents;
  final int refundCents;
  final int netCents;
  final Map<String, int> byCategory;
  const ExpenseSummary(
      {required this.grossCents,
      required this.refundCents,
      required this.netCents,
      required this.byCategory});
}
