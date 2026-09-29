import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../services/expense_service.dart';
import '../services/wechat_bill_parser.dart';
import '../ui/app_theme.dart';
import '../ui/glass_panel.dart';
import '../ui/frosted_form_dialog.dart';

const expenseCategories = [
  '餐饮',
  '购物',
  '交通',
  '居住',
  '医疗',
  '学习',
  '娱乐',
  '人情',
  '其他'
];
const expenseKinds = <ExpenseKind, String>{
  ExpenseKind.expense: '支出',
  ExpenseKind.refund: '退款',
  ExpenseKind.transfer: '转账',
  ExpenseKind.income: '收入',
  ExpenseKind.neutral: '资金往来',
};

String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final value = cents.abs();
  return '$sign¥${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
}

class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key});
  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  final _service = ExpenseService.instance;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Expense> _items = [];
  bool _busy = false;
  String? _error;
  bool _showGross = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _service.getForMonth(_month);
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  Future<void> _edit([Expense? expense]) async {
    final saved = await showDialog<bool>(
        context: context, builder: (_) => _ExpenseEditor(expense: expense));
    if (saved == true) _load();
  }

  Future<void> _delete(Expense expense) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('删除这笔记录？'),
                content: const Text('删除后无法撤销。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'))
                ]));
    if (confirmed != true) return;
    await _service.delete(expense.id);
    _load();
  }

  Future<void> _import() async {
    if (_busy) return;
    final chosen = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'zip'],
        withData: true);
    if (chosen == null || chosen.files.isEmpty || !mounted) return;
    final picked = chosen.files.single;
    String? password;
    if (picked.name.toLowerCase().endsWith('.zip')) {
      final controller = TextEditingController();
      password = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('账单压缩包密码'),
                  content: TextField(
                      controller: controller,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: '微信提供的解压密码')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text),
                        child: const Text('继续'))
                  ]));
      controller.dispose();
      if (password == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final bytes = picked.bytes ?? await File(picked.path!).readAsBytes();
      final rows = WechatBillParser.parseFile(bytes,
          fileName: picked.name, zipPassword: password);
      await _service.markDuplicates(rows);
      if (!mounted) return;
      final imported = await showDialog<int>(
          context: context, builder: (_) => _ImportPreview(rows: rows));
      if (imported != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导入 $imported 笔记录')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is FormatException ? e.message : '导入失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ExpenseService.summarize(_items);
    final categories = summary.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 720;
      final side = compact ? 18.0 : 32.0;
      return ListView(
        padding: EdgeInsets.fromLTRB(side, compact ? 24 : 34, side, 32),
        children: [
          if (compact) ...[
            _heading(theme),
            const SizedBox(height: 18),
            _monthSelector(theme),
            const SizedBox(height: 16),
            _actions(),
          ] else ...[
            Row(children: [
              Expanded(child: _heading(theme)),
              const SizedBox(width: 24),
              _monthSelector(theme),
            ]),
            const SizedBox(height: 20),
            _actions(),
          ],
          if (_busy)
            const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator()),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error))),
          const SizedBox(height: 28),
          if (_items.isNotEmpty && constraints.maxWidth >= 840)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 7, child: _summaryCard(theme, summary)),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: _categoryCard(theme, categories)),
            ])
          else if (_items.isNotEmpty) ...[
            _summaryCard(theme, summary),
            const SizedBox(height: 16),
            _categoryCard(theme, categories),
          ],
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 30),
            Row(children: [
              Text('收支明细', style: theme.textTheme.titleLarge),
              const SizedBox(width: 10),
              Text('${_items.length} 笔',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 14),
            GlassPanel(
              opacity: .65,
              child: Column(children: [
                for (var index = 0; index < _items.length; index++) ...[
                  if (index > 0)
                    const Divider(height: 1, color: AppColors.line),
                  _transactionRow(theme, _items[index], compact),
                ],
              ]),
            ),
          ] else
            _emptySummary(theme),
          const SizedBox(height: 16),
          Text('账单只在本机处理；退款按发生月份冲减，跨月可能出现负净支出。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );
    });
  }

  Widget _heading(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('消费记录', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 5),
          Text('看清钱花在了哪里，也留下生活的细节。',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );

  Widget _emptySummary(ThemeData theme) => GlassPanel(
        level: GlassSurfaceLevel.light,
        opacity: .48,
        shadow: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 26),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_monthLabel(),
                style: AppType.overline(
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Text(formatCents(0),
                    maxLines: 1,
                    style: AppType.display(
                        size: 48,
                        weight: FontWeight.w600,
                        color: theme.colorScheme.onSurface)),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: .28),
                    width: 5,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 7),
            Text('本月还没有支出记录。先记下一笔，这里会出现分类去向。',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      );

  String _monthLabel() {
    const names = [
      '',
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER'
    ];
    return names[_month.month];
  }

  Widget _monthSelector(ThemeData theme) => Container(
        decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF1D2932).withValues(alpha: .45)
                : AppColors.paper.withValues(alpha: .52),
            border: Border.all(
                color: Colors.white.withValues(
                    alpha: theme.brightness == Brightness.dark ? .22 : .72)),
            borderRadius: BorderRadius.circular(13)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
              tooltip: '上个月'),
          Text('${_month.year}年${_month.month}月',
              style: theme.textTheme.titleSmall),
          IconButton(
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
              tooltip: '下个月'),
        ]),
      );

  Widget _actions() => Wrap(spacing: 10, runSpacing: 10, children: [
        FilledButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('记一笔')),
        TextButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('导入微信账单')),
      ]);

  Widget _summaryCard(ThemeData theme, ExpenseSummary summary) => GlassPanel(
      level: GlassSurfaceLevel.light,
      opacity: .54,
      shadow: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 232),
        padding: const EdgeInsets.all(26),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_monthLabel(),
              style:
                  AppType.overline(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(_showGross ? '本月毛支出' : '本月净支出',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                  formatCents(
                      _showGross ? summary.grossCents : summary.netCents),
                  style: AppType.display(
                      size: 52,
                      weight: FontWeight.w600,
                      letterSpacing: -1,
                      color: theme.colorScheme.onSurface))),
          const SizedBox(height: 18),
          Wrap(spacing: 22, runSpacing: 8, children: [
            _summaryMetric(theme, '毛支出', formatCents(summary.grossCents)),
            _summaryMetric(theme, '已退款', formatCents(summary.refundCents)),
          ]),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => setState(() => _showGross = !_showGross),
              style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  padding: EdgeInsets.zero),
              child: Text(_showGross ? '查看净支出' : '查看毛支出')),
        ]),
      ));

  Widget _summaryMetric(ThemeData theme, String label, String amount) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(amount,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontFeatures: AppType.tabular)),
        ],
      );

  Widget _categoryCard(
      ThemeData theme, List<MapEntry<String, int>> categories) {
    final max = categories
        .where((e) => e.value > 0)
        .fold<int>(0, (value, e) => e.value > value ? e.value : value);
    return GlassPanel(
      level: GlassSurfaceLevel.solid,
      opacity: .69,
      child: Container(
        constraints: const BoxConstraints(minHeight: 248),
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('分类去向', style: theme.textTheme.titleMedium),
          const SizedBox(height: 3),
          Text('按本月净支出统计',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          if (categories.isEmpty)
            Text('记下第一笔后，这里会显示支出分布。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
          else
            for (final entry in categories) ...[
              Row(children: [
                Expanded(
                    child: Text(entry.key, style: theme.textTheme.bodyMedium)),
                Text(formatCents(entry.value),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                      value:
                          max == 0 || entry.value <= 0 ? 0 : entry.value / max,
                      minHeight: 5,
                      backgroundColor: AppColors.forestSoft,
                      color: AppColors.olive)),
              const SizedBox(height: 12),
            ],
        ]),
      ),
    );
  }

  Widget _transactionRow(ThemeData theme, Expense item, bool compact) {
    final date =
        '${item.date.month.toString().padLeft(2, '0')}/${item.date.day.toString().padLeft(2, '0')}';
    final title =
        item.counterparty.isNotEmpty ? item.counterparty : item.category;
    final amount = formatCents(
        item.kind == ExpenseKind.refund ? -item.amountCents : item.amountCents);
    return InkWell(
      onTap: () => _edit(item),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: compact ? 12 : 18, vertical: 13),
        child: Row(children: [
          Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                  color: AppColors.forestSoft,
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(
                  item.kind == ExpenseKind.refund
                      ? Icons.keyboard_return
                      : Icons.payments_outlined,
                  size: 19,
                  color: AppColors.forest)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall),
                Text(
                    '$date  ·  ${expenseKinds[item.kind]}  ·  ${item.category}  ·  ${item.paymentMethod}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                if (item.product.isNotEmpty)
                  Text(item.product,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
              ])),
          const SizedBox(width: 8),
          Text(amount,
              style: theme.textTheme.titleSmall?.copyWith(
                  color: item.kind == ExpenseKind.refund
                      ? AppColors.olive
                      : theme.colorScheme.onSurface)),
          PopupMenuButton<String>(
            tooltip: '记录操作',
            onSelected: (choice) =>
                choice == 'edit' ? _edit(item) : _delete(item),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ]),
      ),
    );
  }
}

class _ExpenseEditor extends StatefulWidget {
  final Expense? expense;
  const _ExpenseEditor({this.expense});
  @override
  State<_ExpenseEditor> createState() => _ExpenseEditorState();
}

class _ExpenseEditorState extends State<_ExpenseEditor> {
  late final TextEditingController _amount;
  late final TextEditingController _counterparty;
  late final TextEditingController _payment;
  late final TextEditingController _notes;
  late DateTime _date;
  late String _category;
  late ExpenseKind _kind;
  late bool _includeTransfer;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _amount = TextEditingController(
        text: e == null
            ? ''
            : '${e.amountCents ~/ 100}.${(e.amountCents % 100).toString().padLeft(2, '0')}');
    _counterparty = TextEditingController(text: e?.counterparty ?? '');
    _payment = TextEditingController(text: e?.paymentMethod ?? '微信');
    _notes = TextEditingController(text: e?.notes ?? '');
    _date = e?.date ?? DateTime.now();
    _category = e?.category ?? '其他';
    _kind = e?.kind ?? ExpenseKind.expense;
    _includeTransfer = e?.includeInSpending ?? false;
  }

  @override
  void dispose() {
    _amount.dispose();
    _counterparty.dispose();
    _payment.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = WechatBillParser.parseCents(_amount.text);
    if (cents == null || cents <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入大于 0、最多两位小数的金额')));
      return;
    }
    setState(() => _saving = true);
    try {
      final e =
          widget.expense ?? Expense.create(date: _date, amountCents: cents);
      e.date = _date;
      e.amountCents = cents;
      e.kind = _kind;
      e.category = _category;
      e.paymentMethod =
          _payment.text.trim().isEmpty ? '其他' : _payment.text.trim();
      e.counterparty = _counterparty.text.trim();
      e.notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
      e.includeInSpending = _includeTransfer;
      if (_kind != ExpenseKind.expense) {
        e.inferredRefundCents = 0;
      } else if (e.inferredRefundCents > 0) {
        e.inferredRefundCents = cents;
      }
      await ExpenseService.instance.save(e);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FrostedFormDialog(
        title: Text(widget.expense == null ? '记一笔' : '编辑记录'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: _amount,
                  autofocus: widget.expense == null,
                  textInputAction: TextInputAction.next,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: '金额（元）', prefixText: '¥ ')),
              const SizedBox(height: 10),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final category in expenseCategories.take(4))
                      ChoiceChip(
                          label: Text(category),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category)),
                  ])),
              const SizedBox(height: 8),
              DropdownButtonFormField<ExpenseKind>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: expenseKinds.entries
                      .map((e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _kind = v!)),
              DropdownButtonFormField<String>(
                  key: ValueKey(_category),
                  initialValue:
                      expenseCategories.contains(_category) ? _category : '其他',
                  decoration: const InputDecoration(labelText: '分类'),
                  items: expenseCategories
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => _category = v!)),
              if (_kind == ExpenseKind.transfer)
                SwitchListTile(
                    value: _includeTransfer,
                    title: const Text('计入消费'),
                    onChanged: (v) => setState(() => _includeTransfer = v)),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('日期'),
                  subtitle: Text('${_date.year}-${_date.month}-${_date.day}'),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100));
                    if (picked != null) setState(() => _date = picked);
                  }),
              TextField(
                  controller: _counterparty,
                  decoration: const InputDecoration(labelText: '交易对方或名称')),
              TextField(
                  controller: _payment,
                  decoration: const InputDecoration(labelText: '支付方式')),
              TextField(
                  controller: _notes,
                  decoration: const InputDecoration(labelText: '备注'),
                  maxLines: 2),
              if (widget.expense?.source == ExpenseSource.wechat)
                const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('此记录来自微信账单；交易标识保留用于下次导入去重。')),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: _saving ? null : _save, child: const Text('保存'))
        ],
      );
}

class _ImportPreview extends StatefulWidget {
  final List<WechatImportRow> rows;
  const _ImportPreview({required this.rows});
  @override
  State<_ImportPreview> createState() => _ImportPreviewState();
}

class _ImportPreviewState extends State<_ImportPreview> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.rows.where((r) => r.canImport).length;
    final duplicates = widget.rows
        .where((r) => r.duplicateInFile || r.duplicateInDatabase)
        .length;
    return Dialog(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          '导入前预览 · ${widget.rows.length} 笔（重复 $duplicates 笔）',
                          style: Theme.of(context).textTheme.titleLarge)),
                  const SizedBox(height: 6),
                  const Text('默认仅勾选支出和退款；转账、收入和资金往来需手动勾选。请逐笔核对分类及退款。'),
                  const SizedBox(height: 8),
                  Expanded(
                      child: ListView.builder(
                          itemCount: widget.rows.length,
                          itemBuilder: (context, i) {
                            final row = widget.rows[i];
                            final e = row.expense;
                            final duplicate =
                                row.duplicateInFile || row.duplicateInDatabase;
                            return Card(
                                child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CheckboxListTile(
                                              contentPadding: EdgeInsets.zero,
                                              dense: true,
                                              value: row.selected && !duplicate,
                                              onChanged: duplicate
                                                  ? null
                                                  : (v) => setState(() => row
                                                      .selected = v ?? false),
                                              title: Text(
                                                  '${e.date.year}-${e.date.month}-${e.date.day}  ${e.counterparty.isEmpty ? e.product : e.counterparty}  ${formatCents(e.amountCents)}'),
                                              subtitle: Text(
                                                  '${expenseKinds[e.kind]} · ${e.status ?? ''} · ${e.paymentMethod}${duplicate ? ' · 已重复，跳过' : ''}')),
                                          if (!duplicate)
                                            Wrap(
                                                spacing: 8,
                                                runSpacing: 4,
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                children: [
                                                  SizedBox(
                                                      width: 130,
                                                      child: DropdownButtonFormField<
                                                              ExpenseKind>(
                                                          initialValue: e.kind,
                                                          isExpanded: true,
                                                          decoration:
                                                              const InputDecoration(
                                                                  labelText:
                                                                      '类型',
                                                                  isDense:
                                                                      true),
                                                          items: expenseKinds
                                                              .entries
                                                              .map((v) =>
                                                                  DropdownMenuItem(
                                                                      value:
                                                                          v.key,
                                                                      child: Text(v
                                                                          .value)))
                                                              .toList(),
                                                          onChanged: (v) =>
                                                              setState(() {
                                                                e.kind = v!;
                                                                if (v !=
                                                                    ExpenseKind
                                                                        .expense) {
                                                                  e.inferredRefundCents =
                                                                      0;
                                                                }
                                                              }))),
                                                  SizedBox(
                                                      width: 130,
                                                      child: DropdownButtonFormField<
                                                              String>(
                                                          initialValue:
                                                              expenseCategories
                                                                      .contains(e
                                                                          .category)
                                                                  ? e.category
                                                                  : '其他',
                                                          isExpanded: true,
                                                          decoration:
                                                              const InputDecoration(
                                                                  labelText:
                                                                      '分类',
                                                                  isDense:
                                                                      true),
                                                          items: expenseCategories
                                                              .map((v) =>
                                                                  DropdownMenuItem(
                                                                      value: v,
                                                                      child: Text(
                                                                          v)))
                                                              .toList(),
                                                          onChanged: (v) =>
                                                              setState(() {
                                                                e.category = v!;
                                                                row.categoryEdited =
                                                                    true;
                                                              }))),
                                                  if (e.kind ==
                                                      ExpenseKind.transfer)
                                                    FilterChip(
                                                        label:
                                                            const Text('计入消费'),
                                                        selected:
                                                            e.includeInSpending,
                                                        onSelected: (v) =>
                                                            setState(() =>
                                                                e.includeInSpending =
                                                                    v)),
                                                ]),
                                          if (e.inferredRefundCents > 0)
                                            const Text(
                                                '状态显示全额退款：若无独立退款行，将自动冲减本笔'),
                                          if (row.warning != null)
                                            Text(row.warning!,
                                                style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .error)),
                                          if (e.tradeNo != null)
                                            Text('交易单号：${e.tradeNo}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall),
                                        ])));
                          })),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('将导入 $selected 笔'),
                    const SizedBox(width: 12),
                    TextButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: _saving || selected == 0
                            ? null
                            : () async {
                                setState(() => _saving = true);
                                try {
                                  final count = await ExpenseService.instance
                                      .importConfirmed(widget.rows);
                                  if (context.mounted) {
                                    Navigator.pop(context, count);
                                  }
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('导入失败：$error')));
                                  }
                                  if (mounted) setState(() => _saving = false);
                                }
                              },
                        child: const Text('确认导入')),
                  ]),
                ]))));
  }
}
