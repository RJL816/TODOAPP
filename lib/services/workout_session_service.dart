import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/training.dart';

/// A draft is separate from completed workout history. Leaving a page never ends it.
class WorkoutSessionService extends ChangeNotifier {
  WorkoutSessionService() : _android = Platform.isAndroid;
  @visibleForTesting
  WorkoutSessionService.forTest({bool android = false}) : _android = android;
  final bool _android;
  static final instance = WorkoutSessionService();
  static const draftKey = 'active_workout_v1';
  static const overlayKey = 'workout_overlay_enabled';
  static const channel = MethodChannel('com.todo.app/workout');

  Map<String, dynamic>? _draft;
  Map<String, dynamic>? get draft => _draft == null
      ? null
      : jsonDecode(jsonEncode(_draft)) as Map<String, dynamic>;
  bool get active => _draft != null;
  String get title => _draft?['title'] as String? ?? '自由训练';
  bool get manual => _draft?['manual'] == true;
  DateTime? get startedAt => _draft == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(_draft!['start'] as int);
  bool overlayEnabled = false;
  String? nativeError;
  VoidCallback? onOpenRequested;
  Future<void> _writes = Future.value();
  Timer? _debounce;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    overlayEnabled = prefs.getBool(overlayKey) ?? false;
    _draft = null;
    final saved = prefs.getString(draftKey);
    if (saved != null) {
      try {
        final value = jsonDecode(saved) as Map<String, dynamic>;
        if (value['start'] is! int ||
            value['title'] is! String ||
            value['exercises'] is! List) {
          throw const FormatException();
        }
        if (value['manual'] is! bool ||
            value['minutes'] is! String ||
            (value['planId'] != null && value['planId'] is! int)) {
          throw const FormatException();
        }
        for (final ex in value['exercises'] as List) {
          if (ex is! Map || ex['name'] is! String || ex['sets'] is! List) {
            throw const FormatException();
          }
          for (final row in ex['sets'] as List) {
            if (row is! Map ||
                ['reps', 'weight', 'duration', 'notes']
                    .any((key) => row[key] is! String)) {
              throw const FormatException();
            }
          }
        }
        _draft = value;
      } catch (_) {
        _draft = null;
      }
    }
    if (_android) {
      channel.setMethodCallHandler((call) async {
        if (call.method == 'open') await consumeOpenRequest();
      });
    }
    await syncNative();
    notifyListeners();
  }

  Future<void> begin(TrainingPlan? plan, List<PlanExercise> exercises,
      {bool manual = false}) async {
    if (active) return; // A second start resumes the existing workout.
    _draft = {
      'title': plan?.name ?? '自由训练',
      'planId': plan?.id,
      'start': DateTime.now().millisecondsSinceEpoch,
      'manual': manual,
      'minutes': '',
      'exercises': [
        for (final ex in exercises)
          {
            'name': ex.name,
            'sets': [
              for (var i = 0; i < ex.plannedSets; i++)
                {
                  'reps': ex.plannedReps?.toString() ?? '',
                  'weight': ex.plannedWeightGrams == null
                      ? ''
                      : '${ex.plannedWeightGrams! / 1000}',
                  'duration': '',
                  'notes': '',
                }
            ],
          }
      ],
    };
    try {
      await flush();
    } catch (_) {
      _draft = null;
      rethrow;
    }
    await syncNative();
    notifyListeners();
  }

  void updateForm(String minutes, List<Map<String, dynamic>> exercises) {
    if (_draft == null) return;
    _draft!['minutes'] = minutes;
    _draft!['exercises'] = exercises;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      flush().catchError((Object error) {
        debugPrint('Workout draft: $error');
      });
    });
  }

  Future<void> flush() {
    _debounce?.cancel();
    final encoded = _draft == null ? null : jsonEncode(_draft);
    final next = _writes.catchError((_) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final ok = encoded == null
          ? await prefs.remove(draftKey)
          : await prefs.setString(draftKey, encoded);
      if (!ok) throw StateError('Unable to save workout draft');
    });
    _writes = next;
    return next;
  }

  Future<void> clear() async {
    final previous = _draft;
    _draft = null;
    try {
      await flush();
    } catch (_) {
      _draft = previous;
      rethrow;
    }
    await syncNative();
    notifyListeners();
  }

  Future<void> setOverlayEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(overlayKey, value);
    overlayEnabled = value;
    await syncNative();
    notifyListeners();
  }

  Future<void> syncNative() async {
    if (!_android) return;
    try {
      if (!active || manual) {
        await channel.invokeMethod('stop');
      } else {
        await channel.invokeMethod('sync', {
          'startEpochMs': startedAt!.millisecondsSinceEpoch,
          'title': title,
          'overlay': overlayEnabled,
        });
      }
      nativeError = null;
    } catch (_) {
      nativeError = '后台计时暂未启动，请检查通知和后台运行权限；训练草稿仍已保留';
    }
  }

  Future<void> consumeOpenRequest() async {
    if (!_android) return;
    try {
      if (await channel.invokeMethod<bool>('consumeOpen') == true && active) {
        onOpenRequested?.call();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
