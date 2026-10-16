import 'package:flutter/material.dart';

import '../models/training.dart';
import '../services/training_service.dart';
import '../ui/frosted_form_dialog.dart';

typedef TrainingCycleDraft = ({
  String name,
  DateTime startDate,
  List<TrainingCycleDay> days
});

class TrainingCycleDialog extends StatefulWidget {
  final List<TrainingPlan> existing;
  const TrainingCycleDialog({super.key, this.existing = const []});

  @override
  State<TrainingCycleDialog> createState() => _TrainingCycleDialogState();
}

class _TrainingCycleDialogState extends State<TrainingCycleDialog> {
  late final TextEditingController _name;
  late DateTime _start;
  final List<_DayDraft> _days = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final first = widget.existing.isEmpty ? null : widget.existing.first;
    _name = TextEditingController(text: first?.cycleName ?? '我的训练循环');
    _start = first?.cycleStartDate ?? DateTime.now();
    _initDays();
  }

  Future<void> _initDays() async {
    final count =
        widget.existing.isEmpty ? 4 : widget.existing.first.cycleLength ?? 7;
    final indexed = {for (final p in widget.existing) p.cycleDay: p};
    for (var i = 1; i <= count; i++) {
      final plan = indexed[i];
      final day = _DayDraft(
        title: plan?.isRestDay == true ? '' : plan?.name ?? '',
        rest: plan?.isRestDay ?? i == count,
      );
      if (plan != null) {
        final exercises =
            await TrainingService.instance.getExercisesForPlan(plan.id);
        for (final exercise in exercises) {
          day.actions.add(_ActionDraft(exercise.name, exercise.plannedSets,
              exercise.plannedReps, exercise.plannedWeightGrams));
        }
      }
      _days.add(day);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    for (final day in _days) {
      day.dispose();
    }
    super.dispose();
  }

  void _setLength(int length) {
    setState(() {
      while (_days.length < length) {
        _days.add(_DayDraft());
      }
      while (_days.length > length) {
        _days.removeLast().dispose();
      }
    });
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    final days = <TrainingCycleDay>[];
    for (var i = 0; i < _days.length; i++) {
      final day = _days[i];
      if (!day.rest && day.title.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('请填写第 ${i + 1} 天的训练主题，或设为休息日')),
        );
        return;
      }
      for (final action in day.actions
          .where((a) => !day.rest && a.name.text.trim().isNotEmpty)) {
        final reps = int.tryParse(action.reps.text.trim());
        final weight = double.tryParse(action.weight.text.trim());
        if ((action.reps.text.trim().isNotEmpty &&
                (reps == null || reps <= 0 || reps > 1000)) ||
            (action.weight.text.trim().isNotEmpty &&
                (weight == null ||
                    !weight.isFinite ||
                    weight < 0 ||
                    weight > 1000))) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('动作次数需为 1–1000 的整数，重量为 0–1000kg')));
          return;
        }
      }
      days.add(TrainingCycleDay(
        name: day.rest ? '休息日' : day.title.text.trim(),
        isRestDay: day.rest,
        exercises: day.rest
            ? []
            : [
                for (final action in day.actions)
                  if (action.name.text.trim().isNotEmpty)
                    PlanExercise.create(
                        planId: 0,
                        name: action.name.text.trim(),
                        plannedSets: action.sets,
                        plannedReps: int.tryParse(action.reps.text.trim()),
                        plannedWeightGrams:
                            double.tryParse(action.weight.text.trim()) == null
                                ? null
                                : (double.parse(action.weight.text.trim()) *
                                        1000)
                                    .round()),
              ],
      ));
    }
    Navigator.pop(
        context, (name: _name.text.trim(), startDate: _start, days: days));
  }

  Widget _actionEditor(_DayDraft day, int index) {
    final action = day.actions[index];
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: TextField(
                    controller: action.name,
                    decoration: const InputDecoration(
                        hintText: '动作名称', isDense: true))),
            const SizedBox(width: 8),
            DropdownButton<int>(
                value: action.sets,
                items: [
                  for (var n = 1; n <= 12; n++)
                    DropdownMenuItem(value: n, child: Text('$n 组'))
                ],
                onChanged: (value) => setState(() => action.sets = value ?? 3)),
            IconButton(
                tooltip: '删除动作',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    setState(() => day.actions.removeAt(index).dispose())),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: action.reps,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '每组次数（可选）', isDense: true))),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(
                    controller: action.weight,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: '重量 kg（可选）', isDense: true))),
          ]),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 650;
    return FrostedDialogSurface(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 650,
            maxHeight: (MediaQuery.sizeOf(context).height * .88 -
                    MediaQuery.viewInsetsOf(context).bottom)
                .clamp(220.0, double.infinity)),
        child: Padding(
          padding: EdgeInsets.all(compact ? 18 : 26),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.existing.isEmpty ? '创建训练循环' : '编辑训练循环',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 5),
                    Text('从起始日期的第 1 天开始，完成最后一天后自动回到第 1 天。',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 20),
                    TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                            labelText: '循环名称', hintText: '例如 推拉腿与休息')),
                    const SizedBox(height: 12),
                    Wrap(
                        spacing: 18,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final value = await showDatePicker(
                                  context: context,
                                  initialDate: _start,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100));
                              if (value != null) setState(() => _start = value);
                            },
                            icon: const Icon(Icons.event_outlined, size: 18),
                            label: Text(
                                '从 ${_start.year}年${_start.month}月${_start.day}日开始'),
                          ),
                          DropdownButton<int>(
                            value: _days.length,
                            items: [
                              for (var i = 1; i <= 14; i++)
                                DropdownMenuItem(
                                    value: i, child: Text('$i 天一循环'))
                            ],
                            onChanged: (value) {
                              if (value != null) _setLength(value);
                            },
                          ),
                        ]),
                    const SizedBox(height: 8),
                    Expanded(
                        child: ListView.separated(
                      itemCount: _days.length,
                      separatorBuilder: (_, __) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final day = _days[index];
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text('第 ${index + 1} 天',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const Spacer(),
                                const Text('休息'),
                                Switch(
                                    value: day.rest,
                                    onChanged: (value) =>
                                        setState(() => day.rest = value)),
                              ]),
                              if (!day.rest) ...[
                                TextField(
                                    controller: day.title,
                                    decoration: const InputDecoration(
                                        labelText: '训练主题',
                                        hintText: '例如 胸肩三头')),
                                const SizedBox(height: 10),
                                for (var actionIndex = 0;
                                    actionIndex < day.actions.length;
                                    actionIndex++)
                                  _actionEditor(day, actionIndex),
                                TextButton.icon(
                                    onPressed: () => setState(
                                        () => day.actions.add(_ActionDraft())),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('添加动作')),
                              ],
                            ]);
                      },
                    )),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消')),
                      const SizedBox(width: 8),
                      FilledButton(onPressed: _save, child: const Text('保存循环')),
                    ]),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DayDraft {
  final TextEditingController title;
  bool rest;
  final List<_ActionDraft> actions = [];
  _DayDraft({String title = '', this.rest = false})
      : title = TextEditingController(text: title);
  void dispose() {
    title.dispose();
    for (final action in actions) {
      action.dispose();
    }
  }
}

class _ActionDraft {
  final TextEditingController name, reps, weight;
  int sets;
  _ActionDraft([String value = '', this.sets = 3, int? count, int? grams])
      : name = TextEditingController(text: value),
        reps = TextEditingController(text: count?.toString() ?? ''),
        weight =
            TextEditingController(text: grams == null ? '' : '${grams / 1000}');
  void dispose() {
    name.dispose();
    reps.dispose();
    weight.dispose();
  }
}
