import 'dart:async';
import 'package:flutter/material.dart';
import '../services/workout_session_service.dart';
import '../pages/fitness_page.dart';

/// Remains available across the app's tabs, including after a cold start.
class WorkoutResumeBanner extends StatefulWidget {
  const WorkoutResumeBanner({super.key});
  @override
  State<WorkoutResumeBanner> createState() => _WorkoutResumeBannerState();
}

class _WorkoutResumeBannerState extends State<WorkoutResumeBanner>
    with WidgetsBindingObserver {
  final _service = WorkoutSessionService.instance;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.onOpenRequested = _open;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _service.active) setState(() {});
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _service.consumeOpenRequest());
  }

  void _open() {
    if (mounted) openActiveWorkout(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _service.syncNative();
      _service.consumeOpenRequest();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _service.flush().catchError((_) {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service.onOpenRequested = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          if (!_service.active) return const SizedBox.shrink();
          final seconds = DateTime.now()
              .difference(_service.startedAt!)
              .inSeconds
              .clamp(0, 9999999);
          final time =
              '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
          return Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: InkWell(
              onTap: _open,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.fitness_center, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          '${_service.title} · ${_service.manual ? '待补记' : time}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                  const Text('继续记录'),
                  const Icon(Icons.chevron_right, size: 18),
                ]),
              ),
            ),
          );
        },
      );
}
