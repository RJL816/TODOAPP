import 'dart:convert';

import 'package:flutter/material.dart';
import '../ui/app_theme.dart';
import '../ui/glass_panel.dart';
import '../ui/muscle_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/training.dart';
import '../services/training_service.dart';
import '../services/reminder_service.dart';
import '../services/exercise_muscles.dart';
import 'training_cycle_dialog.dart';

/// 健身页：今日训练 + 循环计划 + 训练历史
class FitnessPage extends StatefulWidget {
  const FitnessPage({super.key});

  @override
  State<FitnessPage> createState() => _FitnessPageState();
}

class _FitnessPageState extends State<FitnessPage> {
  final TrainingService _svc = TrainingService.instance;

  List<TrainingPlan> _allPlans = [];
  List<TrainingPlan> _todayPlans = [];
  List<WorkoutLog> _history = [];
  int _weekCount = 0;
  bool _isLoading = true;
  bool _remindEnabled = true;
  int? _remindMinutes;
  List<PlanExercise> _todayExercises = [];
  List<ExerciseVolume> _weekVolumes = [];
  Map<String, MuscleGroup> _muscleOverrides = {};
  MuscleGroup _selectedMuscle = MuscleGroup.chest;
  bool _muscleTouched = false;
  bool _showWeekCoverage = false;
  BodyView _mobileBodyView = BodyView.front;
  static const _muscleOverridesKey = 'training_muscle_overrides_v1';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    _allPlans = await _svc.getAllPlans();
    _todayPlans = await _svc.getPlansForDate(now);
    _history = await _svc.getWorkoutHistory(limit: 200);
    _weekCount = await _svc.workoutCountThisWeek(now);
    _todayExercises = _todayPlans.isEmpty
        ? []
        : await _svc.getExercisesForPlan(_todayPlans.first.id);
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final weeklyLogs = _history.where((log) =>
        log.completed &&
        !log.date.isBefore(monday) &&
        log.date.isBefore(monday.add(const Duration(days: 7))));
    final weeklySets = await Future.wait(
        weeklyLogs.map((log) => _svc.getSetsForWorkout(log.id)));
    final counts = <String, int>{};
    for (final sets in weeklySets) {
      for (final set in sets) {
        counts.update(set.exerciseName, (value) => value + 1,
            ifAbsent: () => 1);
      }
    }
    _weekVolumes = [
      for (final entry in counts.entries)
        ExerciseVolume(entry.key, entry.value),
    ];
    _showWeekCoverage = _todayExercises.isEmpty && _weekVolumes.isNotEmpty;
    try {
      final prefs = await SharedPreferences.getInstance();
      _remindEnabled = prefs.getBool(TrainingService.remindEnabledKey) ?? true;
      _remindMinutes = prefs.getInt(TrainingService.remindTimeKey);
      final saved = prefs.getString(_muscleOverridesKey);
      if (saved != null) {
        final decoded = jsonDecode(saved) as Map<String, dynamic>;
        _muscleOverrides = {
          for (final entry in decoded.entries)
            if (MuscleGroup.values.any((group) => group.name == entry.value))
              entry.key: MuscleGroup.values.byName(entry.value as String),
        };
      }
    } catch (_) {}
    final initialVolumes = _showWeekCoverage
        ? _weekVolumes
        : _todayExercises.map(
            (exercise) => ExerciseVolume(exercise.name, exercise.plannedSets));
    final initialScores =
        muscleScores(initialVolumes, overrides: _muscleOverrides);
    if (initialScores.isNotEmpty) {
      _selectedMuscle = initialScores.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      _mobileBodyView =
          _isBackMuscle(_selectedMuscle) ? BodyView.back : BodyView.front;
    }
    _muscleTouched = initialScores.isNotEmpty;
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _toggleRemind(bool value) async {
    setState(() => _remindEnabled = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(TrainingService.remindEnabledKey, value);
    } catch (_) {}
  }

  Future<void> _assignMuscle(String exercise, MuscleGroup group) async {
    setState(() {
      _muscleOverrides[normalizeExerciseName(exercise)] = group;
      _selectedMuscle = group;
      _muscleTouched = true;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _muscleOverridesKey,
        jsonEncode(
            _muscleOverrides.map((key, value) => MapEntry(key, value.name))));
  }

  bool _isBackMuscle(MuscleGroup group) => const {
        MuscleGroup.rearDelts,
        MuscleGroup.traps,
        MuscleGroup.lats,
        MuscleGroup.lowerBack,
        MuscleGroup.glutes,
        MuscleGroup.hamstrings,
        MuscleGroup.calves,
        MuscleGroup.triceps,
      }.contains(group);

  void _selectCoverage(bool showWeek) {
    final volumes = showWeek
        ? _weekVolumes
        : _todayExercises.map(
            (exercise) => ExerciseVolume(exercise.name, exercise.plannedSets));
    final scores = muscleScores(volumes, overrides: _muscleOverrides);
    setState(() {
      _showWeekCoverage = showWeek;
      if (scores.isNotEmpty) {
        _selectedMuscle =
            scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
        _mobileBodyView =
            _isBackMuscle(_selectedMuscle) ? BodyView.back : BodyView.front;
      }
      _muscleTouched = scores.isNotEmpty;
    });
  }

  Widget _reminderMenu() {
    final remindLabel = _remindEnabled
        ? '训练提醒 · 每天 ${_remindTimeLabel}'
        : '训练提醒 · 已关闭';
    return PopupMenuButton<String>(
      tooltip: '训练提醒设置',
      onSelected: (value) {
        if (value == 'toggle') {
          _toggleRemind(!_remindEnabled);
        } else if (value == 'time') {
          _pickRemindTime();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'toggle',
          child: Text(_remindEnabled ? '关闭训练提醒' : '开启训练提醒'),
        ),
        const PopupMenuItem(
          value: 'time',
          child: Row(children: [
            Icon(Icons.schedule, size: 18),
            SizedBox(width: 8),
            Text('提醒时间'),
          ]),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: .7)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.notifications_outlined,
              size: 17,
              color: _remindEnabled
                  ? Theme.of(context).colorScheme.primary
                  : AppColors.muted),
          const SizedBox(width: 6),
          Text(remindLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  String get _remindTimeLabel {
    final minutes =
        _remindMinutes ?? TrainingService.defaultRemindMinutes;
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickRemindTime() async {
    final current = _remindMinutes ?? TrainingService.defaultRemindMinutes;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (time == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        TrainingService.remindTimeKey, time.hour * 60 + time.minute);
    if (mounted) {
      setState(() => _remindMinutes = time.hour * 60 + time.minute);
    }
    // 提醒时间变化后重排未来 30 天窗口
    ReminderService.instance.requestReschedule();
  }

  // ==================== 计划编辑 ====================

  Future<void> _editPlan({TrainingPlan? plan}) async {
    final groupId = plan?.cycleGroupId;
    final existing = groupId == null
        ? <TrainingPlan>[]
        : _allPlans.where((p) => p.cycleGroupId == groupId).toList();
    final result = await showDialog<TrainingCycleDraft>(
      context: context,
      builder: (context) => TrainingCycleDialog(existing: existing),
    );
    if (result != null) {
      await _svc.saveCycle(
          groupId: groupId,
          name: result.name,
          startDate: result.startDate,
          days: result.days);
      await _loadData();
    }
  }

  List<List<TrainingPlan>> _cycleGroups() {
    final groups = <int, List<TrainingPlan>>{};
    for (final plan in _allPlans) {
      groups.putIfAbsent(plan.cycleGroupId ?? plan.id, () => []).add(plan);
    }
    return groups.values.toList();
  }

  Future<void> _deletePlan(TrainingPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除训练计划'),
        content: Text('确定要删除“${plan.cycleName ?? plan.name}”整个循环吗？历史训练记录保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (plan.cycleGroupId != null) {
        await _svc.deleteCycle(plan.cycleGroupId!);
      } else {
        await _svc.deletePlan(plan.id);
      }
      await _loadData();
    }
  }

  /// 把今日计划添加为今日健康类待办（关联待办入口）
  Future<void> _addPlanAsTodo(TrainingPlan plan) async {
    final id = await _svc.addPlanAsTodoForDate(plan, DateTime.now());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(id != null ? '已添加为今日待办：训练：${plan.name}' : '添加失败')),
      );
    }
  }

  // ==================== 训练进行 ====================

  Future<void> _startWorkout(TrainingPlan? plan) async {
    final exercises = plan != null
        ? await _svc.getExercisesForPlan(plan.id)
        : <PlanExercise>[];
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => _WorkoutSessionPage(
        plan: plan,
        plannedExercises: exercises,
      ),
    ));
    await _loadData();
  }

  Future<void> _viewWorkout(WorkoutLog log) async {
    final sets = await _svc.getSetsForWorkout(log.id);
    if (!mounted) return;
    final grouped = <String, List<WorkoutSet>>{};
    for (final s in sets) {
      grouped.putIfAbsent(s.exerciseName, () => []).add(s);
    }
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(log.title),
        content: SizedBox(
          width: 440,
          height: 400,
          child: sets.isEmpty
              ? const Center(child: Text('没有组记录'))
              : ListView(
                  children: grouped.entries
                      .expand((e) => [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                              child: Text(e.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                            ...e.value.map((s) => ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 12,
                                    child: Text('${s.setIndex}',
                                        style: const TextStyle(fontSize: 11)),
                                  ),
                                  title: Text(s.displaySummary),
                                )),
                          ])
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('删除训练记录'),
                  content: const Text('确定删除这次训练及其全部组记录吗？'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('删除')),
                  ],
                ),
              );
              if (confirmed == true) {
                await _svc.deleteWorkout(log.id);
                await _loadData();
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ==================== 构建 ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_allPlans.isEmpty) {
      return ListView(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width < 680 ? 18 : 32,
          vertical: 28,
        ),
        children: [
          Row(children: [
            Expanded(
                child: Text('健身训练', style: theme.textTheme.headlineMedium)),
            _reminderMenu(),
          ]),
          const SizedBox(height: 22),
          Text('从今天的一次训练开始。', style: theme.textTheme.titleLarge),
          const SizedBox(height: 7),
          Text('设定起始日期和循环天数，逐天安排动作；也可以先自由训练。',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 8, children: [
            GlassPanel(
              level: GlassSurfaceLevel.light,
              radius: 14,
              opacity: .6,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _editPlan(),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add, size: 19, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('创建训练循环',
                        style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary)),
                  ]),
                ),
              ),
            ),
            GlassPanel(
              level: GlassSurfaceLevel.light,
              radius: 14,
              opacity: .6,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _startWorkout(null),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.play_arrow,
                        size: 19, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Text('开始自由训练',
                        style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary)),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 30),
          _muscleAtlas(theme),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 32),
            _sectionTitle(theme, '训练历史'),
            for (final log in _history.take(10))
              ListTile(
                  title: Text(log.title),
                  subtitle:
                      Text('${log.startedAt.month}月${log.startedAt.day}日'),
                  onTap: () => _viewWorkout(log)),
          ],
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 680 ? 18 : 32,
        vertical: 28,
      ),
      children: [
        Text('生活记录 / MOVEMENT',
            style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.olive,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Row(children: [
          Expanded(child: Text('健身训练', style: theme.textTheme.headlineMedium)),
          _reminderMenu(),
        ]),
        const SizedBox(height: 5),
        Text('计划今天的运动，也记录每一次完成。',
            style: theme.textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 28),
        // Today's session is the single visual focus of this page.
        _sectionTitle(theme, '今日训练'),
        if (_todayPlans.isEmpty)
          Text('今天是休息日，或循环尚未开始。',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant))
        else ...[
          _todayTrainingFeature(theme, _todayPlans.first),
          for (final plan in _todayPlans.skip(1))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(plan.name),
              trailing: const Icon(Icons.arrow_forward, size: 18),
              onTap: () => _startWorkout(plan),
            ),
        ],
        const SizedBox(height: 8),
        // 快速开始自由训练 + 本周统计
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _startWorkout(null),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('自由训练'),
            ),
            const Spacer(),
            Text(
              '本周已完成 $_weekCount 次训练',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),

        const SizedBox(height: 25),
        _muscleAtlas(theme),

        const SizedBox(height: 20),
        // 按起始日期循环的完整安排
        Row(
          children: [
            Expanded(child: _sectionTitle(theme, '训练循环')),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新建计划',
              onPressed: () => _editPlan(),
            ),
          ],
        ),
        if (_allPlans.isEmpty)
          Text('点击右上角 + 创建训练计划。',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant))
        else
          ..._cycleGroups().map((group) {
            final first = group.first;
            final activeDay =
                TrainingService.cycleDayForDate(first, DateTime.now());
            return Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(first.cycleName ?? first.name,
                                style: theme.textTheme.titleMedium),
                            Text(
                                '${first.cycleLength ?? 7} 天一循环 · ${first.cycleStartDate?.month ?? 1}月${first.cycleStartDate?.day ?? 1}日开始',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                          ])),
                      IconButton(
                          tooltip: '编辑循环',
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          onPressed: () => _editPlan(plan: first)),
                      PopupMenuButton<String>(
                          tooltip: '循环操作',
                          onSelected: (value) {
                            if (value == 'delete') _deletePlan(first);
                          },
                          itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'delete', child: Text('删除循环'))
                              ]),
                    ]),
                    const SizedBox(height: 8),
                    for (final day in group)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: SizedBox(
                            width: 52,
                            child: Text('第 ${day.cycleDay ?? day.weekday} 天',
                                style: TextStyle(
                                    fontWeight: day.cycleDay == activeDay
                                        ? FontWeight.w700
                                        : FontWeight.w500))),
                        title: Text(day.isRestDay ? '休息与恢复' : day.name),
                        trailing:
                            day.cycleDay == activeDay ? const Text('今天') : null,
                        onTap: () => _editPlan(plan: first),
                      ),
                    const Divider(height: 1, color: AppColors.line),
                  ]),
            );
          }),

        if (_history.isNotEmpty) ...[
          const SizedBox(height: 24),
          _sectionTitle(theme, '训练历史'),
          ..._history.take(10).map((log) => Column(children: [
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    log.completed ? Icons.check_circle : Icons.cancel_outlined,
                    color: log.completed
                        ? AppColors.navy
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  title: Text(log.title),
                  subtitle: Text(
                      '${log.startedAt.month}-${log.startedAt.day} ${log.startedAt.hour.toString().padLeft(2, '0')}:${log.startedAt.minute.toString().padLeft(2, '0')}'),
                  onTap: () => _viewWorkout(log),
                ),
                const Divider(height: 1, color: AppColors.line),
              ])),
        ],
      ],
    );
  }

  Widget _todayTrainingFeature(ThemeData theme, TrainingPlan plan) {
    return GlassPanel(
      level: GlassSurfaceLevel.light,
      opacity: .49,
      shadow: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('今天练什么',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.navy)),
            ),
            PopupMenuButton<String>(
              tooltip: '训练计划操作',
              icon: const Icon(Icons.more_horiz, color: AppColors.ink),
              onSelected: (value) {
                if (value == 'todo') _addPlanAsTodo(plan);
                if (value == 'edit') _editPlan(plan: plan);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'todo', child: Text('添加为今日待办')),
                PopupMenuItem(value: 'edit', child: Text('编辑计划')),
              ],
            ),
          ]),
          Text(plan.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.display(
                  size: 32, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 12),
          FutureBuilder<List<PlanExercise>>(
            future: _svc.getExercisesForPlan(plan.id),
            builder: (context, snapshot) {
              final exercises = snapshot.data ?? [];
              return Text(
                exercises.isEmpty
                    ? '还没有添加动作'
                    : '${exercises.length} 个动作  ·  ${exercises.map((e) => e.name).join('、')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              );
            },
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => _startWorkout(plan),
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始训练'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _muscleAtlas(ThemeData theme) {
    final volumes = _showWeekCoverage
        ? _weekVolumes
        : _todayExercises
            .map((exercise) =>
                ExerciseVolume(exercise.name, exercise.plannedSets))
            .toList();
    final scores = muscleScores(volumes, overrides: _muscleOverrides);
    final related = volumes
        .where((exercise) => targetsForExercise(exercise.name,
                override:
                    _muscleOverrides[normalizeExerciseName(exercise.name)])
            .any((target) => target.group == _selectedMuscle))
        .toList();
    final unknown = volumes
        .where((exercise) => targetsForExercise(exercise.name,
                override:
                    _muscleOverrides[normalizeExerciseName(exercise.name)])
            .isEmpty)
        .toList();

    Widget diagram(BodyView view) =>
        Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).width < 900 ? 360 : 390,
            child: MuscleMap(
              view: view,
              scores: scores,
              selected: _muscleTouched ? _selectedMuscle : null,
              onSelect: (group) => setState(() {
                _selectedMuscle = group;
                _muscleTouched = true;
              }),
            ),
          ),
          const SizedBox(height: 4),
          Text(view == BodyView.front ? '前视' : '后视',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]);

    Widget details() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已选肌群',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 7),
            Text(_muscleTouched ? _selectedMuscle.label : '选择一个肌群',
                style: AppType.display(
                    size: 25,
                    weight: FontWeight.w600,
                    color: theme.colorScheme.onSurface)),
            const SizedBox(height: 5),
            Text(
                scores[_selectedMuscle] == null
                    ? '该肌群暂无关联动作'
                    : '${related.fold<int>(0, (total, item) => total + item.sets)} 组关联动作',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 18),
            if (related.isNotEmpty) ...[
              Text('关联动作', style: theme.textTheme.titleSmall),
              const SizedBox(height: 5),
              for (final exercise in related)
                _muscleExerciseRow(theme, exercise),
            ] else
              Text(
                  volumes.isEmpty
                      ? (_showWeekCoverage
                          ? '本周还没有完成的训练组。'
                          : '添加训练动作后，图谱会标出关联肌群。')
                      : '点击人体上的其他区域查看动作。',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (unknown.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('待指定肌群', style: theme.textTheme.titleSmall),
              const SizedBox(height: 5),
              for (final exercise in unknown)
                _muscleExerciseRow(theme, exercise),
            ],
            const SizedBox(height: 18),
            Text(
                '颜色根据${_showWeekCoverage ? '本周已完成' : '今日计划'}的组数与动作关联生成，仅供训练记录参考。',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        );

    return GlassPanel(
      level: GlassSurfaceLevel.solid,
      radius: 24,
      opacity: .75,
      shadow: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('训练肌群图谱', style: theme.textTheme.titleMedium)),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('今日')),
                ButtonSegment(value: true, label: Text('本周')),
              ],
              selected: {_showWeekCoverage},
              showSelectedIcon: false,
              onSelectionChanged: (values) => _selectCoverage(values.first),
            ),
          ]),
          const SizedBox(height: 17),
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 700) {
              return Column(children: [
                SegmentedButton<BodyView>(
                  segments: const [
                    ButtonSegment(value: BodyView.front, label: Text('正面')),
                    ButtonSegment(value: BodyView.back, label: Text('背面')),
                  ],
                  selected: {_mobileBodyView},
                  showSelectedIcon: false,
                  onSelectionChanged: (values) =>
                      setState(() => _mobileBodyView = values.first),
                ),
                const SizedBox(height: 10),
                diagram(_mobileBodyView),
                const SizedBox(height: 22),
                Align(alignment: Alignment.centerLeft, child: details()),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  flex: 3,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        diagram(BodyView.front),
                        diagram(BodyView.back)
                      ])),
              const SizedBox(width: 22),
              Expanded(flex: 2, child: details()),
            ]);
          }),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => launchUrl(Uri.parse(
                'https://www.figma.com/community/file/1320468164820924031')),
            child: Text('人体图谱：Ryan Graves · CC BY 4.0',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  decoration: TextDecoration.underline,
                )),
          ),
        ]),
      ),
    );
  }

  Widget _muscleExerciseRow(ThemeData theme, ExerciseVolume exercise) {
    final targets = targetsForExercise(exercise.name,
        override: _muscleOverrides[normalizeExerciseName(exercise.name)]);
    final primary = targets
        .where((target) => target.primary)
        .map((target) => target.group.label)
        .join('、');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(exercise.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          Text('$primary · ${exercise.sets} 组',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
        PopupMenuButton<MuscleGroup>(
          tooltip: '指定${exercise.name}的主肌群',
          icon: const Icon(Icons.tune, size: 18),
          onSelected: (group) => _assignMuscle(exercise.name, group),
          itemBuilder: (_) => [
            for (final group in MuscleGroup.values)
              PopupMenuItem(value: group, child: Text(group.label)),
          ],
        ),
      ]),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style:
            theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ==================== 训练进行页 ====================

class _WorkoutSessionPage extends StatefulWidget {
  final TrainingPlan? plan;
  final List<PlanExercise> plannedExercises;

  const _WorkoutSessionPage({
    required this.plan,
    required this.plannedExercises,
  });

  @override
  State<_WorkoutSessionPage> createState() => _WorkoutSessionPageState();
}

class _WorkoutSessionPageState extends State<_WorkoutSessionPage> {
  final TrainingService _svc = TrainingService.instance;
  late DateTime _startedAt;
  final List<_SessionExercise> _exercises = [];

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    for (final pe in widget.plannedExercises) {
      final ex = _SessionExercise(name: pe.name);
      for (int i = 1; i <= pe.plannedSets; i++) {
        ex.sets.add(_SessionSet());
      }
      _exercises.add(ex);
    }
    if (_exercises.isEmpty) {
      _exercises.add(_SessionExercise(name: ''));
    }
  }

  void _addExercise() {
    setState(() => _exercises.add(_SessionExercise(name: '')));
  }

  Future<void> _confirmDiscard() async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束训练'),
        content: const Text('已记录的内容将不会保存，确定退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续训练'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('不保存退出'),
          ),
        ],
      ),
    );
    if (exit == true && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _finish() async {
    final log = WorkoutLog.create(
      date: DateTime.now(),
      title: widget.plan?.name ?? '自由训练',
      startedAt: _startedAt,
      endedAt: DateTime.now(),
      planId: widget.plan?.id,
      completed: true,
    );
    final sets = <WorkoutSet>[];
    for (final ex in _exercises) {
      final name = ex.nameController.text.trim();
      if (name.isEmpty) continue;
      for (int i = 0; i < ex.sets.length; i++) {
        final s = ex.sets[i];
        final hasData = (s.repsController.text.trim().isNotEmpty &&
                int.tryParse(s.repsController.text.trim()) != null) ||
            (s.weightController.text.trim().isNotEmpty &&
                double.tryParse(s.weightController.text.trim()) != null) ||
            (s.durationController.text.trim().isNotEmpty &&
                int.tryParse(s.durationController.text.trim()) != null) ||
            (s.notesController.text.trim().isNotEmpty);
        if (!hasData) continue;
        sets.add(WorkoutSet.create(
          workoutId: 0,
          exerciseName: name,
          setIndex: i + 1,
          reps: int.tryParse(s.repsController.text.trim()),
          weightGrams: s.weightController.text.trim().isEmpty
              ? null
              : ((double.tryParse(s.weightController.text.trim()) ?? 0) * 1000)
                  .round(),
          durationSeconds: int.tryParse(s.durationController.text.trim()),
          notes: s.notesController.text.trim().isEmpty
              ? null
              : s.notesController.text.trim(),
        ));
      }
    }
    await _svc.saveWorkout(log: log, sets: sets);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('训练已记录（${sets.length} 组）')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elapsed = DateTime.now().difference(_startedAt);

    return Scaffold(
      appBar: AppBar(
        title: Text('训练中：${widget.plan?.name ?? '自由训练'}'),
        actions: [
          TextButton(
            onPressed: _finish,
            child: const Text('完成训练'),
          ),
        ],
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmDiscard();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '开始于 ${_startedAt.hour.toString().padLeft(2, '0')}:${_startedAt.minute.toString().padLeft(2, '0')}'
              '（已进行 ${elapsed.inMinutes} 分钟）',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            ..._exercises.asMap().entries.map((entry) {
              final index = entry.key;
              final ex = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: ex.nameController,
                              decoration: const InputDecoration(
                                hintText: '动作名',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 20),
                            color: theme.colorScheme.error,
                            onPressed: () =>
                                setState(() => _exercises.removeAt(index)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 组表头
                      Row(
                        children: [
                          const SizedBox(width: 28),
                          _fieldLabel(theme, '次数'),
                          _fieldLabel(theme, '重量kg'),
                          _fieldLabel(theme, '时长分'),
                          const SizedBox(width: 72),
                        ],
                      ),
                      ...ex.sets.asMap().entries.map((setEntry) {
                        final i = setEntry.key;
                        final s = setEntry.value;
                        return Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text('${i + 1}',
                                  style: theme.textTheme.bodySmall),
                            ),
                            Expanded(
                              child: _miniField(s.repsController, '12'),
                            ),
                            Expanded(
                              child: _miniField(s.weightController, '60'),
                            ),
                            Expanded(
                              child: _miniField(s.durationController, '30'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  setState(() => ex.sets.removeAt(i)),
                            ),
                          ],
                        );
                      }),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => ex.sets.add(_SessionSet())),
                        icon: const Icon(Icons.add, size: 16),
                        label:
                            const Text('加一组', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4)),
                      ),
                    ],
                  ),
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: _addExercise,
              icon: const Icon(Icons.add),
              label: const Text('添加动作'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(ThemeData theme, String text) {
    return Expanded(
      child: Text(text,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }

  Widget _miniField(TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

class _SessionExercise {
  final TextEditingController nameController;
  final List<_SessionSet> sets = [];

  _SessionExercise({required String name})
      : nameController = TextEditingController(text: name);
}

class _SessionSet {
  final TextEditingController repsController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  final TextEditingController durationController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
}
