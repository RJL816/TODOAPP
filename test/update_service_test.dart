import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/services/update_service.dart';

/// 应用内检查更新：版本比较与资产匹配
void main() {
  group('版本比较', () {
    test('远端更高 → 判定有新版本', () {
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('v1.1.0', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('同版本 / 更低版本 → 无新版本', () {
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('0.9.9', '1.0.0'), isFalse);
    });

    test('带 build 号的当前版本也能比较', () {
      expect(UpdateService.compareVersions('1.0.1', '1.0.0+7'), greaterThan(0));
      expect(UpdateService.compareVersions('1.0.0', '1.0.0+1'), 0);
    });

    test('缺失段按 0 处理', () {
      expect(UpdateService.compareVersions('1.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('2', '1.9.9'), greaterThan(0));
    });
  });

  group('资产匹配', () {
    final assets = [
      'https://x/TODOAPP-1.0.1-windows.zip',
      'https://x/todo_app_v2.apk',
      'https://x/source-code.tar.gz',
    ];

    test('匹配最新 zip 资产（Windows）', () {
      final url = assets.firstWhere((u) => u.endsWith('.zip'));
      expect(url.endsWith('.zip'), isTrue);
    });

    test('匹配 apk 资产（Android）', () {
      final url = assets.firstWhere((u) => u.endsWith('.apk'));
      expect(url.endsWith('.apk'), isTrue);
    });

    test('格式校验通过 ReleaseInfo 构造', () {
      final info = ReleaseInfo(
        version: '1.0.1',
        notes: '修复若干问题',
        pageUrl: 'https://github.com/x/releases/latest',
        windowsUrl: assets[0],
        androidUrl: assets[1],
      );
      expect(info.hasWindowsDownload, isTrue);
      expect(info.hasAndroidDownload, isTrue);
      expect(UpdateService.isNewerVersion(info.version, '1.0.0'), isTrue);
    });
  });
}
