import 'package:flutter/material.dart';
import '../ui/frosted_form_dialog.dart';

import '../models/diet_log.dart';
import '../services/diet_service.dart';
import '../services/fat_loss_service.dart';
import '../ui/glass_panel.dart';

/// 饮食页：按日期记录四餐，营养字段可选；只做记录与回顾
class DietPage extends StatefulWidget {
  const DietPage({super.key});

  @override
  State<DietPage> createState() => _DietPageState();
}

class _DietPageState extends State<DietPage> {
  final DietService _svc = DietService.instance;
  DateTime _date = DateTime.now();
  Map<MealType, List<DietLog>> _logsByMeal = {};
  DietDaySummary _summary = const DietDaySummary(
      count: 0,
      calories: 0,
      hasCalorieData: false,
      proteinGrams: 0,
      carbsGrams: 0,
      fatGrams: 0);
  bool _isLoading = true;
  FatLossProfile? _fatProfile;

  bool get _isToday {
    final now = DateTime.now();
    return _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadFatProfile();
  }

  Future<void> _loadFatProfile() async {
    final profile = await FatLossService.instance.loadProfile();
    if (mounted) setState(() => _fatProfile = profile);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final logs = await _svc.getLogsForDate(_date);
    _summary = await _svc.getSummaryForDate(_date);
    final grouped = <MealType, List<DietLog>>{};
    for (final type in MealType.values) {
      grouped[type] = [];
    }
    for (final log in logs) {
      grouped[log.mealType]!.add(log);
    }
    if (mounted) {
      setState(() {
        _logsByMeal = grouped;
        _isLoading = false;
      });
    }
  }

  void _changeDate(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
    _loadData();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _loadData();
    }
  }

  // ==================== 增删改 ====================

  Future<void> _addOrEditLog({DietLog? existing, MealType? initialMeal}) async {
    final result = await showDialog<DietLog>(
      context: context,
      builder: (context) => _DietEditDialog(
        existing: existing,
        initialMeal: initialMeal,
        date: _date,
      ),
    );
    if (result != null) {
      if (existing == null) {
        await _svc.addLog(result);
      } else {
        await _svc.updateLog(result);
      }
      await _loadData();
    }
  }

  Future<void> _deleteLog(DietLog log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('确定删除"${log.food}"吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) {
      await _svc.deleteLog(log.id);
      await _loadData();
    }
  }

  Future<void> _copyYesterday(MealType type) async {
    final yesterday = _date.subtract(const Duration(days: 1));
    final source = (await _svc.getLogsForDate(yesterday))
        .where((log) => log.mealType == type)
        .toList();
    if (!mounted) return;
    if (source.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('昨天的${type.displayName}没有记录')));
      return;
    }
    if ((_logsByMeal[type] ?? []).isNotEmpty) {
      final append = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text('复制昨天的${type.displayName}？'),
                content: const Text('这会追加到当前餐次，已有记录会保留。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('追加')),
                ],
              ));
      if (append != true) return;
    }
    await _svc.copyPreviousMeal(_date, type);
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已复制 ${source.length} 条${type.displayName}记录')));
    }
  }

  // ==================== 构建 ====================

  MealType get _suggestedMeal {
    final hour = DateTime.now().hour;
    if (hour < 10) return MealType.breakfast;
    if (hour < 15) return MealType.lunch;
    if (hour < 21) return MealType.dinner;
    return MealType.snack;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final hasNutrition = _logsByMeal.values.expand((logs) => logs).any((log) =>
        log.calories != null ||
        log.proteinGrams != null ||
        log.carbsGrams != null ||
        log.fatGrams != null);
    final narrow = MediaQuery.sizeOf(context).width < 680;
    return ListView(
      padding: EdgeInsets.fromLTRB(narrow ? 18 : 32, 28, narrow ? 18 : 32, 42),
      children: [
        Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('饮食记录', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('按时间记下每天的餐食。',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            Row(children: [
              IconButton(
                  onPressed: () => _changeDate(-1),
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '前一天'),
              Expanded(
                  child: InkWell(
                      onTap: _pickDate,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                              '${_date.year}年${_date.month}月${_date.day}日${_isToday ? '（今天）' : ''}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall)))),
              IconButton(
                  onPressed: _isToday ? null : () => _changeDate(1),
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '后一天'),
            ]),
            const SizedBox(height: 15),
            FilledButton.icon(
                onPressed: () => _addOrEditLog(initialMeal: _suggestedMeal),
                icon: const Icon(Icons.add),
                label: const Text('记录一餐')),
            const SizedBox(height: 18),
            _fatLossCard(theme),
            if (_summary.count == 0) ...[
              const SizedBox(height: 17),
              Text('今天还没记录餐食。从一餐开始就好。',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (hasNutrition) ...[
              const SizedBox(height: 25),
              Text('已填写的营养信息', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 6, children: [
                if (_summary.hasCalorieData)
                  Text('${_summary.calories} 千卡',
                      style: theme.textTheme.bodyMedium),
                if (_summary.proteinGrams > 0)
                  Text('蛋白 ${_summary.proteinGrams}g',
                      style: theme.textTheme.bodyMedium),
                if (_summary.carbsGrams > 0)
                  Text('碳水 ${_summary.carbsGrams}g',
                      style: theme.textTheme.bodyMedium),
                if (_summary.fatGrams > 0)
                  Text('脂肪 ${_summary.fatGrams}g',
                      style: theme.textTheme.bodyMedium),
              ]),
            ],
            const SizedBox(height: 28),
            for (final type in MealType.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: GlassPanel(
                  level: GlassSurfaceLevel.light,
                  radius: 18,
                  opacity: .43,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                    child: _buildMealSection(theme, type),
                  ),
                ),
              ),
          ]),
        ))
      ],
    );
  }

  /// 减脂计划卡：目标热量 / 三大营养素 / 今日进度；未设置时给引导入口
  Widget _fatLossCard(ThemeData theme) {
    final profile = _fatProfile;
    final targets = profile == null ? null : FatLossService.computeTargets(profile);
    return GlassPanel(
      level: GlassSurfaceLevel.light,
      radius: 18,
      opacity: .43,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        child: targets == null
            ? Row(children: [
                Icon(Icons.track_changes,
                    color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('减脂计划', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text('按身体数据计算每日热量与三大营养素目标',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    theme.colorScheme.onSurfaceVariant)),
                      ]),
                ),
                TextButton(
                    onPressed: _editFatProfile,
                    child: const Text('开始设置')),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.track_changes,
                      color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('减脂计划', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  TextButton(
                      onPressed: _editFatProfile, child: const Text('编辑')),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Text('每日目标 ${targets.targetKcal} 千卡',
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 14),
                  Text(
                      _isToday
                          ? '今日已摄入 ${_summary.calories} 千卡'
                          : '当日摄入 ${_summary.calories} 千卡',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: targets.targetKcal <= 0
                        ? 0
                        : (_summary.calories / targets.targetKcal)
                            .clamp(0.0, 1.0),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(spacing: 16, children: [
                  Text('蛋白 ≥ ${targets.proteinG}g',
                      style: theme.textTheme.bodySmall),
                  Text('脂肪 ≤ ${targets.fatG}g',
                      style: theme.textTheme.bodySmall),
                  Text('碳水 ≤ ${targets.carbG}g',
                      style: theme.textTheme.bodySmall),
                  Text('基础代谢 ${targets.bmr.round()} 千卡',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ]),
                const SizedBox(height: 6),
                Text('计算仅供参考，不构成医疗建议；体重明显变化后请重新设置。',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurfaceVariant)),
              ]),
      ),
    );
  }

  Future<void> _editFatProfile() async {
    final result = await showDialog<FatLossProfile>(
      context: context,
      builder: (context) =>
          _FatLossProfileDialog(existing: _fatProfile),
    );
    if (result != null) {
      await FatLossService.instance.saveProfile(result);
      if (mounted) setState(() => _fatProfile = result);
    }
  }

  Widget _buildMealSection(ThemeData theme, MealType type) {
    final logs = _logsByMeal[type] ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
            width: 60,
            child: Text(type.displayName, style: theme.textTheme.titleSmall)),
        if (logs.isNotEmpty)
          Text('${logs.length} 条',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const Spacer(),
        IconButton(
            onPressed: () => _copyYesterday(type),
            icon: const Icon(Icons.content_copy_outlined, size: 18),
            tooltip: '复制昨天的${type.displayName}'),
        IconButton(
            onPressed: () => _addOrEditLog(initialMeal: type),
            icon: const Icon(Icons.add, size: 20),
            tooltip: '添加${type.displayName}'),
      ]),
      for (final log in logs)
        ListTile(
            contentPadding: const EdgeInsets.only(left: 0, right: 0),
            title: Text(log.food),
            subtitle:
                _logSubtitle(log).isEmpty ? null : Text(_logSubtitle(log)),
            trailing: PopupMenuButton<String>(
                tooltip: '餐食操作',
                onSelected: (value) => value == 'edit'
                    ? _addOrEditLog(existing: log)
                    : _deleteLog(log),
                itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ]),
            onTap: () => _addOrEditLog(existing: log)),
      if (logs.isEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 60, bottom: 5),
          child: Text('尚未记录',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
    ]);
  }

  String _logSubtitle(DietLog log) {
    final parts = <String>[];
    if (log.calories != null) parts.add('${log.calories} 千卡');
    if (log.proteinGrams != null) parts.add('蛋白 ${log.proteinGrams}g');
    if (log.carbsGrams != null) parts.add('碳水 ${log.carbsGrams}g');
    if (log.fatGrams != null) parts.add('脂肪 ${log.fatGrams}g');
    if (log.notes != null && log.notes!.isNotEmpty) parts.add(log.notes!);
    return parts.join(' · ');
  }
}

// ==================== 记录编辑对话框 ====================

class _DietEditDialog extends StatefulWidget {
  final DietLog? existing;
  final MealType? initialMeal;
  final DateTime date;

  const _DietEditDialog({
    this.existing,
    this.initialMeal,
    required this.date,
  });

  @override
  State<_DietEditDialog> createState() => _DietEditDialogState();
}

class _DietEditDialogState extends State<_DietEditDialog> {
  late TextEditingController _foodController;
  late TextEditingController _notesController;
  late TextEditingController _caloriesController;
  late TextEditingController _proteinController;
  late TextEditingController _carbsController;
  late TextEditingController _fatController;
  late MealType _meal;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _foodController = TextEditingController(text: e?.food ?? '');
    _notesController = TextEditingController(text: e?.notes ?? '');
    _caloriesController =
        TextEditingController(text: e?.calories?.toString() ?? '');
    _proteinController =
        TextEditingController(text: e?.proteinGrams?.toString() ?? '');
    _carbsController =
        TextEditingController(text: e?.carbsGrams?.toString() ?? '');
    _fatController = TextEditingController(text: e?.fatGrams?.toString() ?? '');
    _meal = e?.mealType ?? widget.initialMeal ?? MealType.breakfast;
  }

  @override
  void dispose() {
    _foodController.dispose();
    _notesController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  void _save() {
    final food = _foodController.text.trim();
    if (food.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入食物描述')),
      );
      return;
    }
    final log = widget.existing ??
        DietLog.create(date: widget.date, mealType: _meal, food: food)
      ..date = DateTime(widget.date.year, widget.date.month, widget.date.day)
      ..createdAt = DateTime.now();
    log.mealType = _meal;
    log.food = food;
    log.notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();
    log.calories = int.tryParse(_caloriesController.text.trim());
    log.proteinGrams = int.tryParse(_proteinController.text.trim());
    log.carbsGrams = int.tryParse(_carbsController.text.trim());
    log.fatGrams = int.tryParse(_fatController.text.trim());
    Navigator.pop(context, log);
  }

  @override
  Widget build(BuildContext context) {
    return FrostedFormDialog(
      title: Text(widget.existing == null ? '添加饮食记录' : '编辑饮食记录'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 餐次
              Wrap(
                spacing: 8,
                children: MealType.values
                    .map((m) => ChoiceChip(
                          label: Text(m.displayName),
                          selected: _meal == m,
                          onSelected: (_) => setState(() => _meal = m),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _foodController,
                decoration: const InputDecoration(
                  labelText: '食物 *',
                  hintText: '如 牛肉面 / 香蕉一根',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _numField(_caloriesController, '热量千卡'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _numField(_proteinController, '蛋白质g'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _numField(_carbsController, '碳水g'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _numField(_fatController, '脂肪g'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 4),
              Text(
                '营养字段全部可选——只做记录，不会生成饮食目标',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Widget _numField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// 减脂计划设置表单
class _FatLossProfileDialog extends StatefulWidget {
  final FatLossProfile? existing;
  const _FatLossProfileDialog({this.existing});

  @override
  State<_FatLossProfileDialog> createState() => _FatLossProfileDialogState();
}

class _FatLossProfileDialogState extends State<_FatLossProfileDialog> {
  late String _gender;
  late final TextEditingController _age;
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late double _activity;
  late int _deficit;

  static const activities = [
    (1.2, '久坐'),
    (1.375, '轻度活动'),
    (1.55, '中度活动'),
    (1.725, '高强度'),
  ];
  static const deficits = [
    (300, '温和 · 每月约 1.2kg'),
    (500, '标准 · 每月约 2kg'),
    (750, '激进 · 需谨慎'),
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _gender = e?.gender ?? 'm';
    _age = TextEditingController(text: (e?.age ?? 25).toString());
    _height = TextEditingController(text: (e?.heightCm ?? 170).toString());
    _weight = TextEditingController(text: (e?.weightKg ?? 65).toString());
    _activity = e?.activityFactor ?? 1.375;
    _deficit = e?.deficit ?? 500;
  }

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  FatLossProfile? _collect() {
    final age = int.tryParse(_age.text.trim());
    final height = double.tryParse(_height.text.trim());
    final weight = double.tryParse(_weight.text.trim());
    if (age == null ||
        age <= 0 ||
        height == null ||
        height < 100 ||
        height > 250 ||
        weight == null ||
        weight < 30 ||
        weight > 300) {
      return null;
    }
    return FatLossProfile(
      gender: _gender,
      age: age,
      heightCm: height,
      weightKg: weight,
      activityFactor: _activity,
      deficit: _deficit,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('减脂计划设置'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('性别', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                ChoiceChip(
                    label: const Text('男'),
                    selected: _gender == 'm',
                    onSelected: (_) => setState(() => _gender = 'm')),
                ChoiceChip(
                    label: const Text('女'),
                    selected: _gender == 'f',
                    onSelected: (_) => setState(() => _gender = 'f')),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _age,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: '年龄', border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: _height,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: '身高 cm',
                            border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: _weight,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: '体重 kg',
                            border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 16),
              Text('日常活动量', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (factor, label) in activities)
                    ChoiceChip(
                        label: Text(label),
                        selected: _activity == factor,
                        onSelected: (_) => setState(() => _activity = factor)),
                ],
              ),
              const SizedBox(height: 16),
              Text('减脂力度（每日热量缺口）', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Column(
                children: [
                  for (final (value, label) in deficits)
                    RadioListTile<int>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: value,
                      groupValue: _deficit,
                      onChanged: (v) =>
                          setState(() => _deficit = v ?? 500),
                      title: Text('$value 千卡/天'),
                      subtitle: Text(label),
                    ),
                ],
              ),
              Text('目标热量不会低于健康下限（女 1200 / 男 1500 千卡）。',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: () {
            final profile = _collect();
            if (profile == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请检查年龄、身高、体重的数值')));
              return;
            }
            Navigator.pop(context, profile);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
