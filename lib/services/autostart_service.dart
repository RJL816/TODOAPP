import 'dart:io';
import 'package:flutter/services.dart';

/// 开机自启动服务
/// 通过平台通道与 Windows 原生代码通信，操作注册表实现开机自启动
class AutoStartService {
  AutoStartService._private();

  static final AutoStartService instance = AutoStartService._private();

  static const MethodChannel _channel = MethodChannel('com.todo.app/autostart');

  bool _isEnabled = false;

  /// 初始化服务，检查当前自启动状态
  Future<void> init() async {
    if (Platform.isWindows) {
      try {
        _isEnabled = await isAutoStartEnabled();
      } catch (e) {
        _isEnabled = false;
      }
    }
  }

  /// 设置开机自启动
  /// [enable] true 启用，false 禁用
  /// 返回是否设置成功
  Future<bool> setAutoStart(bool enable) async {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('setAutoStart', {
        'enable': enable,
      });
      _isEnabled = result ?? false;
      return _isEnabled;
    } catch (e) {
      return false;
    }
  }

  /// 检查是否已启用开机自启动
  Future<bool> isAutoStartEnabled() async {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('isAutoStartEnabled');
      _isEnabled = result ?? false;
      return _isEnabled;
    } catch (e) {
      return false;
    }
  }

  /// 获取当前自启动状态（从缓存读取）
  bool get isEnabled => _isEnabled;

  /// 切换自启动状态
  Future<bool> toggle() async {
    return setAutoStart(!_isEnabled);
  }
}
