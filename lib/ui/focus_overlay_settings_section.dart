import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/pomodoro_service.dart';
import '../services/reminder_service.dart';

/// 主设置中的明确入口；授权返回后自动完成用户刚刚发起的开启操作。
class FocusOverlaySettingsSection extends StatefulWidget {
  const FocusOverlaySettingsSection({super.key});
  @override
  State<FocusOverlaySettingsSection> createState() =>
      _FocusOverlaySettingsSectionState();
}

class _FocusOverlaySettingsSectionState
    extends State<FocusOverlaySettingsSection> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.todo.app/focus_overlay');
  final _service = PomodoroService.instance;
  bool _waitingPermission = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingPermission) {
      _finishPermission();
    }
  }

  Future<void> _finishPermission() async {
    _waitingPermission = false;
    try {
      if (await _channel.invokeMethod<bool>('canDrawOverlays') == true) {
        await _service.setFocusOverlayEnabled(true);
        if (mounted) setState(() => _message = '已开启；开始计时后显示悬浮钟表');
      } else if (mounted) {
        setState(() => _message = '尚未授予悬浮权限，通知栏计时仍可使用');
      }
    } catch (_) {
      if (mounted) setState(() => _message = '无法读取悬浮权限，请在系统设置中检查');
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (value &&
          await _channel.invokeMethod<bool>('canDrawOverlays') != true) {
        _waitingPermission = true;
        await _channel.invokeMethod('openOverlayPermissionSettings');
        if (mounted) setState(() => _message = '请允许显示在其他应用上层，返回后会自动开启');
      } else {
        await _service.setFocusOverlayEnabled(value);
      }
    } catch (_) {
      _waitingPermission = false;
      if (mounted) setState(() => _message = '暂时无法开启，请检查系统悬浮窗权限');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _service,
        builder: (context, _) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('专注与提醒', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.watch_later_outlined),
            title: const Text('悬浮钟表'),
            subtitle: const Text('切到其他应用也能看计时；可拖动，点击返回拾序'),
            value: _service.focusOverlayEnabled,
            onChanged: _busy ? null : _toggle,
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child:
                  Text(_message!, style: Theme.of(context).textTheme.bodySmall),
            ),
          Wrap(spacing: 8, children: [
            TextButton.icon(
              icon: const Icon(Icons.notifications_outlined, size: 18),
              label: const Text('通知与到点提醒'),
              onPressed: () async {
                final reminders = ReminderService.instance;
                if (!await reminders.notificationsEnabled()) {
                  await reminders.requestNotificationPermission();
                }
                if (!await reminders.exactAlarmsEnabled()) {
                  await reminders.requestExactAlarmsPermission();
                }
                if (!mounted) return;
                await _channel.invokeMethod('openFocusNotificationSettings');
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.battery_charging_full, size: 18),
              label: const Text('后台运行'),
              onPressed: () =>
                  _channel.invokeMethod('openFocusBackgroundSettings'),
            ),
          ]),
          Text('通知栏与锁屏会显示计时，到点发送提醒。若锁屏后延迟，可允许后台运行。',
              style: Theme.of(context).textTheme.bodySmall),
          const Divider(height: 28),
        ]),
      );
}
