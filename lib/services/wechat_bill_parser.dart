import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel_wps/excel.dart';

import '../models/expense.dart';

/// Parses a personal WeChat Pay reconciliation export, never merchant API bills.
/// The header is discovered by name because exports include variable preamble lines.
class WechatBillParser {
  static const requiredHeaders = <String>{
    '交易时间',
    '交易类型',
    '交易对方',
    '收/支',
    '支付方式',
    '当前状态',
    '交易单号'
  };

  static List<WechatImportRow> parseFile(List<int> bytes,
      {required String fileName, String? zipPassword}) {
    if (fileName.toLowerCase().endsWith('.zip')) {
      try {
        final archive = ZipDecoder().decodeBytes(bytes, password: zipPassword);
        final billFiles = archive.files
            .where((f) =>
                f.isFile &&
                (f.name.toLowerCase().endsWith('.csv') ||
                    f.name.toLowerCase().endsWith('.xlsx')) &&
                !f.name.contains('__MACOSX'))
            .toList();
        if (billFiles.isEmpty) {
          throw const FormatException(
              '压缩包内没有 CSV 或 XLSX 文件，请确认微信导出的是“用于个人对账”的明细');
        }
        final rows = <WechatImportRow>[
          for (final file in billFiles)
            ...(file.name.toLowerCase().endsWith('.xlsx')
                ? parseXlsxBytes((file.content as List).cast<int>())
                : parseCsvBytes((file.content as List).cast<int>())),
        ];
        final seen = <String>{};
        for (final row in rows) {
          final tradeNo = row.expense.tradeNo;
          if (tradeNo != null && !seen.add(tradeNo)) row.duplicateInFile = true;
        }
        return rows;
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException(
            '无法解开账单 ZIP；请检查解压密码，或先手动解压并选择其中的 CSV/XLSX 文件');
      }
    }
    if (fileName.toLowerCase().endsWith('.xlsx')) return parseXlsxBytes(bytes);
    if (!fileName.toLowerCase().endsWith('.csv')) {
      throw const FormatException('请选择微信支付导出的 CSV、XLSX 或 ZIP 文件');
    }
    return parseCsvBytes(bytes);
  }

  static List<WechatImportRow> parseXlsxBytes(List<int> bytes) {
    try {
      final workbook = Excel.decodeBytes(bytes);
      if (workbook.tables.isEmpty) {
        throw const FormatException('XLSX 文件没有工作表');
      }
      final sheet = workbook.tables.values.first;
      String value(Data? cell) {
        final content = cell?.value;
        if (content == null) return '';
        if (content is DateTimeCellValue) {
          String p2(int n) => n.toString().padLeft(2, '0');
          return '${content.year}-${p2(content.month)}-${p2(content.day)} '
              '${p2(content.hour)}:${p2(content.minute)}:${p2(content.second)}';
        }
        return content.toString();
      }

      String escape(String cell) => '"${cell.replaceAll('"', '""')}"';
      return parseCsv(sheet.rows
          .map((row) => row.map((cell) => escape(value(cell))).join(','))
          .join('\n'));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法读取 XLSX 明细；请确认是微信支付官方导出的个人账单');
    }
  }

  static List<WechatImportRow> parseCsvBytes(List<int> bytes) {
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('账单不是 UTF-8 编码；请将解压后的 CSV 转为 UTF-8 后重试');
    }
    return parseCsv(text);
  }

  static List<WechatImportRow> parseCsv(String text) {
    final rows = _csvRows(text.replaceFirst('\ufeff', ''));
    final headerAt = rows.indexWhere((row) =>
        requiredHeaders.every((h) => row.map(_clean).contains(h)) &&
        row.map(_clean).any((h) => h == '金额(元)' || h == '金额'));
    if (headerAt < 0) {
      throw const FormatException('未识别到微信个人账单表头；请确认文件含“交易时间、收/支、金额(元)、交易单号”等列');
    }
    final header = rows[headerAt].map(_clean).toList();
    int col(String name) => header.indexOf(name);
    final amountCol = col('金额(元)') >= 0 ? col('金额(元)') : col('金额');
    final result = <WechatImportRow>[];
    final seen = <String>{};
    for (var i = headerAt + 1; i < rows.length; i++) {
      final row = rows[i];
      String get(String name) {
        final index = col(name);
        return index >= 0 && index < row.length ? _clean(row[index]) : '';
      }

      if (row.every((cell) => cell.trim().isEmpty)) continue;
      final time = get('交易时间');
      // Footer totals and explanation lines do not contain a transaction time.
      final date = DateTime.tryParse(time.replaceAll('/', '-'));
      if (date == null) continue;
      if (amountCol >= row.length) continue;
      final amount = parseCents(_clean(row[amountCol]));
      if (amount == null || amount <= 0) continue;
      final type = get('交易类型');
      final direction = get('收/支');
      final status = get('当前状态');
      final counterparty = get('交易对方');
      final product = get('商品');
      final tradeNo = _identifier(get('交易单号'));
      final merchantNo = _identifier(get('商户单号'));
      ExpenseKind kind;
      if (type.contains('退款') || (direction == '收入' && status.contains('退款'))) {
        kind = ExpenseKind.refund;
      } else if (direction == '/' || direction.isEmpty) {
        kind = ExpenseKind.neutral;
      } else if (type.contains('转账') || type.contains('群收款')) {
        kind = ExpenseKind.transfer;
      } else if (direction == '收入') {
        kind = ExpenseKind.income;
      } else if (direction == '支出') {
        kind = ExpenseKind.expense;
      } else {
        kind = ExpenseKind.neutral;
      }
      final fullyRefunded = kind == ExpenseKind.expense &&
          (status.contains('全额退款') || status == '已退款');
      final invalid = RegExp(r'失败|关闭|已撤销|未支付|待支付|已取消').hasMatch(status);
      final expense = Expense.create(
        date: date,
        amountCents: amount,
        kind: kind,
        category: suggestCategory(type, counterparty, product),
        paymentMethod: get('支付方式').isEmpty ? '其他' : get('支付方式'),
        counterparty: counterparty,
        product: product,
        notes: get('备注').isEmpty ? null : get('备注'),
        source: ExpenseSource.wechat,
        tradeNo: tradeNo,
        merchantNo: merchantNo,
        status: status,
        inferredRefundCents: fullyRefunded ? amount : 0,
      );
      final repeated = tradeNo != null && !seen.add(tradeNo);
      result.add(WechatImportRow(
          expense: expense,
          selected: !invalid &&
              (kind == ExpenseKind.expense || kind == ExpenseKind.refund),
          duplicateInFile: repeated,
          warning: invalid
              ? '交易未完成，默认不导入；请核对状态'
              : status.contains('部分退款')
                  ? '部分退款金额无法从状态推断，请核对并单独记录退款'
                  : tradeNo == null
                      ? '缺少交易单号，无法自动去重'
                      : null));
    }
    if (result.isEmpty) {
      throw const FormatException('表头已识别，但没有读到有效交易；请检查是否导出了明细');
    }
    return result;
  }

  static String suggestCategory(
      String type, String counterparty, String product) {
    final value = '$type $counterparty $product';
    if (RegExp(r'餐|饭|食|外卖|奶茶|咖啡|超市').hasMatch(value)) return '餐饮';
    if (RegExp(r'地铁|公交|打车|滴滴|车票|加油').hasMatch(value)) return '交通';
    if (RegExp(r'药|医院|诊所|体检').hasMatch(value)) return '医疗';
    if (RegExp(r'学费|课程|书店|培训').hasMatch(value)) return '学习';
    if (RegExp(r'房租|物业|水费|电费|燃气').hasMatch(value)) return '居住';
    if (RegExp(r'电影|游戏|旅游|门票').hasMatch(value)) return '娱乐';
    if (RegExp(r'商户消费|购物|淘宝|京东').hasMatch(value)) return '购物';
    return '其他';
  }

  static int? parseCents(String raw) {
    final clean = raw.replaceAll(RegExp(r'[¥￥,\s]'), '');
    final match = RegExp(r'^\+?(\d+)(?:\.(\d{1,2}))?$').firstMatch(clean);
    if (match == null) return null;
    final whole = int.tryParse(match.group(1)!);
    if (whole == null) return null;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return whole * 100 + (int.tryParse(fraction) ?? 0);
  }

  static String _clean(String value) =>
      value.trim().replaceFirst(RegExp(r'^[`\uFEFF]'), '').trim();
  static String? _identifier(String value) =>
      value.isEmpty || value == '/' ? null : value;

  static List<List<String>> _csvRows(String source) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < source.length; i++) {
      final c = source[i];
      if (c == '"') {
        if (quoted && i + 1 < source.length && source[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (c == ',' && !quoted) {
        row.add(field.toString());
        field = StringBuffer();
      } else if ((c == '\n' || c == '\r') && !quoted) {
        if (c == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
        row.add(field.toString());
        rows.add(row);
        row = <String>[];
        field = StringBuffer();
      } else {
        field.write(c);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}

class WechatImportRow {
  final Expense expense;
  bool selected;
  bool categoryEdited = false;
  bool duplicateInFile;
  bool duplicateInDatabase = false;
  final String? warning;

  WechatImportRow(
      {required this.expense,
      required this.selected,
      this.duplicateInFile = false,
      this.warning});

  bool get canImport => selected && !duplicateInFile && !duplicateInDatabase;
}
