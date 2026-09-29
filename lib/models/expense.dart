import 'package:isar/isar.dart';

part 'expense.g.dart';

enum ExpenseKind { expense, refund, transfer, income, neutral }

enum ExpenseSource { manual, wechat }

@Collection()
class Expense {
  Id id = Isar.autoIncrement;

  @Index()
  late DateTime date;

  /// Always a non-negative number of cents. Direction is represented by kind.
  late int amountCents;
  @Enumerated(EnumType.name)
  late ExpenseKind kind;
  late String category;
  late String paymentMethod;
  late String counterparty;
  late String product;
  String? notes;
  @Enumerated(EnumType.name)
  late ExpenseSource source;

  /// Imported trade number. Manual entries leave this null; Isar 3's unique
  /// nullable index treats multiple nulls as a conflict, so import enforces
  /// uniqueness transactionally instead.
  @Index()
  String? tradeNo;
  String? merchantNo;
  String? relatedTradeNo;
  String? status;

  /// For transfer entries the user may explicitly count them as spending.
  late bool includeInSpending;

  /// A fully refunded original payment with no separate refund row.
  late int inferredRefundCents;

  Expense();

  Expense.create({
    required this.date,
    required this.amountCents,
    this.kind = ExpenseKind.expense,
    this.category = '其他',
    this.paymentMethod = '其他',
    this.counterparty = '',
    this.product = '',
    this.notes,
    this.source = ExpenseSource.manual,
    this.tradeNo,
    this.merchantNo,
    this.relatedTradeNo,
    this.status,
    this.includeInSpending = false,
    this.inferredRefundCents = 0,
  });

  int get grossCents => kind == ExpenseKind.expense ||
          (kind == ExpenseKind.transfer && includeInSpending)
      ? amountCents
      : 0;
  int get refundCents =>
      kind == ExpenseKind.refund ? amountCents : inferredRefundCents;
  int get netCents => grossCents - refundCents;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'amountCents': amountCents,
        'kind': kind.name,
        'category': category,
        'paymentMethod': paymentMethod,
        'counterparty': counterparty,
        'product': product,
        'notes': notes,
        'source': source.name,
        'tradeNo': tradeNo,
        'merchantNo': merchantNo,
        'relatedTradeNo': relatedTradeNo,
        'status': status,
        'includeInSpending': includeInSpending,
        'inferredRefundCents': inferredRefundCents,
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense()
    ..id = json['id'] as int? ?? Isar.autoIncrement
    ..date = DateTime.parse(json['date'] as String)
    ..amountCents = json['amountCents'] as int
    ..kind = ExpenseKind.values.firstWhere((v) => v.name == json['kind'],
        orElse: () => ExpenseKind.expense)
    ..category = json['category'] as String? ?? '其他'
    ..paymentMethod = json['paymentMethod'] as String? ?? '其他'
    ..counterparty = json['counterparty'] as String? ?? ''
    ..product = json['product'] as String? ?? ''
    ..notes = json['notes'] as String?
    ..source = ExpenseSource.values.firstWhere((v) => v.name == json['source'],
        orElse: () => ExpenseSource.manual)
    ..tradeNo = json['tradeNo'] as String?
    ..merchantNo = json['merchantNo'] as String?
    ..relatedTradeNo = json['relatedTradeNo'] as String?
    ..status = json['status'] as String?
    ..includeInSpending = json['includeInSpending'] as bool? ?? false
    ..inferredRefundCents = json['inferredRefundCents'] as int? ?? 0;
}
