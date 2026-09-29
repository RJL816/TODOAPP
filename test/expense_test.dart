import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel_wps/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo_app/models/expense.dart';
import 'package:todo_app/services/expense_service.dart';
import 'package:todo_app/services/isar_service.dart';
import 'package:todo_app/services/wechat_bill_parser.dart';

import 'isar_test_base.dart';

const bill = '''微信支付账单明细,,,,,,,,,,
本明细仅供个人对账使用,,,,,,,,,,
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-09-01 12:01:02,商户消费,"食堂,一楼",午饭,支出,¥12.30,零钱,支付成功,`WX001,`M001,"备注,午餐"
2026-09-02 12:01:02,商户消费,商店,外套,支出,¥100.00,零钱,已全额退款,`WX002,`M002,/
2026-09-03 12:01:02,退款,商店,外套,收入,¥100.00,零钱,退款成功,`RF002,`M002,/
2026-09-04 12:01:02,转账,朋友,/,支出,¥50.00,零钱,朋友已收钱,`TR001,/,/
2026-09-05 12:01:02,零钱充值,银行,/,/,¥200.00,银行卡,充值完成,`NE001,/,/
2026-09-06 12:01:02,商户消费,书店,书,支出,¥3.05,零钱,支付成功,`WX001,`M003,/
''';

void main() {
  setUpAll(initIsarCoreForTests);

  test('金额只用整数分，拒绝多余小数', () {
    expect(WechatBillParser.parseCents('¥0.01'), 1);
    expect(WechatBillParser.parseCents('1,234.56'), 123456);
    expect(WechatBillParser.parseCents('0.001'), isNull);
  });

  test('个人账单表头、引号、退款、转账和文件内重复', () {
    final rows = WechatBillParser.parseCsv(bill);
    expect(rows.length, 6);
    expect(rows.first.expense.counterparty, '食堂,一楼');
    expect(rows.first.expense.notes, '备注,午餐');
    expect(rows.first.expense.amountCents, 1230);
    expect(rows[1].expense.inferredRefundCents, 10000);
    expect(rows[2].expense.kind, ExpenseKind.refund);
    expect(rows[3].expense.kind, ExpenseKind.transfer);
    expect(rows[3].selected, isFalse);
    expect(rows[4].expense.kind, ExpenseKind.neutral);
    expect(rows[5].duplicateInFile, isTrue);
  });

  test('失败交易不会默认导入', () {
    final rows = WechatBillParser.parseCsv('''
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-09-24 12:00:00,商户消费,商店,商品,支出,¥20.00,零钱,支付失败,FAILED1,/,/
''');
    expect(rows.single.selected, isFalse);
    expect(rows.single.warning, contains('未完成'));
  });

  test('ZIP 中的 CSV 与直接导入得到相同交易', () {
    final archive = Archive()
      ..addFile(
          ArchiveFile('bill.csv', utf8.encode(bill).length, utf8.encode(bill)));
    final bytes = ZipEncoder().encode(archive)!;
    expect(WechatBillParser.parseFile(bytes, fileName: '账单.zip').length, 6);
    expect(() => WechatBillParser.parseCsv('商户账单,金额'), throwsFormatException);
  });

  test('XLSX 个人明细可按表头解析', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    const header = [
      '交易时间',
      '交易类型',
      '交易对方',
      '商品',
      '收/支',
      '金额(元)',
      '支付方式',
      '当前状态',
      '交易单号',
      '商户单号',
      '备注'
    ];
    const entry = [
      '2026-09-24 12:30:00',
      '商户消费',
      '食堂',
      '午饭',
      '支出',
      '¥12.30',
      '零钱',
      '支付成功',
      'WXXLSX',
      'MXLSX',
      '/'
    ];
    sheet.appendRow(header.map(TextCellValue.new).toList());
    sheet.appendRow(entry.map(TextCellValue.new).toList());
    final bytes = workbook.encode()!;
    final rows = WechatBillParser.parseFile(bytes, fileName: '账单.xlsx');
    expect(rows.single.expense.amountCents, 1230);
    expect(rows.single.expense.tradeNo, 'WXXLSX');
  });

  test('导入去重，独立退款冲掉推断退款，汇总不双扣', () async {
    final isar = await openTestIsar();
    IsarService.instance.initForTest(isar);
    final service = ExpenseService.instance;
    final rows = WechatBillParser.parseCsv(bill);
    expect(await service.importConfirmed(rows), 3);
    final entries = await service.getForMonth(DateTime(2026, 9));
    expect(entries.length, 3);
    final original = entries.singleWhere((e) => e.tradeNo == 'WX002');
    expect(original.inferredRefundCents, 0);
    final summary = ExpenseService.summarize(entries);
    expect(summary.grossCents, 11230);
    expect(summary.refundCents, 10000);
    expect(summary.netCents, 1230);
    expect(summary.byCategory['餐饮'], 1230);

    final again = WechatBillParser.parseCsv(bill);
    await service.markDuplicates(again);
    expect(again.first.duplicateInDatabase, isTrue);
    expect(await service.importConfirmed(again), 0);
    expect(await isar.expenses.count(), 3);
  });

  test('无独立退款行的全额退款仍保留毛支出并冲减净支出', () async {
    final isar = await openTestIsar();
    IsarService.instance.initForTest(isar);
    final e = Expense.create(
        date: DateTime(2026, 9, 1),
        amountCents: 5000,
        inferredRefundCents: 5000);
    await ExpenseService.instance.save(e);
    final summary = ExpenseService.summarize(
        await ExpenseService.instance.getForMonth(DateTime(2026, 9)));
    expect(summary.grossCents, 5000);
    expect(summary.refundCents, 5000);
    expect(summary.netCents, 0);
  });

  test('手动记录可连续保存、编辑和删除，空交易单号不冲突', () async {
    final isar = await openTestIsar();
    IsarService.instance.initForTest(isar);
    final service = ExpenseService.instance;
    final first = Expense.create(date: DateTime(2026, 9, 24),
        amountCents: 120, category: '餐饮');
    first.id = await service.save(first);
    await service.save(Expense.create(date: DateTime(2026, 9, 24),
        amountCents: 230, category: '交通'));
    expect((await service.getForMonth(DateTime(2026, 9))).length, 2);
    first.amountCents = 150;
    await service.save(first);
    expect(ExpenseService.summarize(await service.getForMonth(DateTime(2026, 9))).netCents, 380);
    await service.delete(first.id);
    expect((await service.getForMonth(DateTime(2026, 9))).single.amountCents, 230);
  });
}
