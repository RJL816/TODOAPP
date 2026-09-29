import 'dart:convert';

import 'package:http/http.dart' as http;

/// 应用内检查更新：读取 GitHub Releases 最新版本，与当前版本比对。
/// Windows 资产匹配 .zip，Android 匹配 .apk；找不到资产时回退发布页。
class UpdateService {
  static UpdateService? _instance;
  static UpdateService get instance {
    _instance ??= UpdateService._();
    return _instance!;
  }

  UpdateService._();

  static const String repoOwner = 'RJL816';
  static const String repoName = 'TODOAPP';
  static const String releasesApi =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
  static const String releasesPage =
      'https://github.com/$repoOwner/$repoName/releases/latest';

  /// 解析并比较版本号：支持 'v1.2.3' / '1.2.3' / '1.2.3+4'。
  /// 返回 -1/0/1（a 相对 b）。缺失段按 0 处理。
  static int compareVersions(String a, String b) {
    final pa = _versionParts(a);
    final pb = _versionParts(b);
    for (var i = 0; i < 3; i++) {
      final cmp = pa[i].compareTo(pb[i]);
      if (cmp != 0) return cmp;
    }
    return 0;
  }

  static List<int> _versionParts(String version) {
    var v = version.trim().replaceFirst(RegExp(r'^v'), '');
    final plus = v.indexOf('+');
    if (plus >= 0) v = v.substring(0, plus);
    final parts = v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts.take(3).toList();
  }

  static bool isNewerVersion(String remote, String current) =>
      compareVersions(remote, current) > 0;

  /// 拉取最新 Release 信息。无任何已发布版本（404）时返回 null。
  Future<ReleaseInfo?> fetchLatestRelease() async {
    final response = await http.get(Uri.parse(releasesApi), headers: {
      'User-Agent': 'todo-app-update-check',
      'Accept': 'application/vnd.github+json',
    }).timeout(const Duration(seconds: 20));

    if (response.statusCode == 404) return null;
    if (response.statusCode == 403) {
      throw Exception('GitHub 访问受限，请稍后再试');
    }
    if (response.statusCode != 200) {
      throw Exception('获取更新信息失败（${response.statusCode}）');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes))
        as Map<String, dynamic>;
    final tag = data['tag_name']?.toString() ?? '';
    final assets = (data['assets'] as List? ?? [])
        .map((a) => a['browser_download_url']?.toString() ?? '')
        .where((u) => u.isNotEmpty)
        .toList();
    return ReleaseInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      notes: data['body']?.toString() ?? '',
      pageUrl: data['html_url']?.toString() ?? releasesPage,
      windowsUrl: _findAsset(assets, ['.zip']),
      androidUrl: _findAsset(assets, ['.apk']),
    );
  }

  String? _findAsset(List<String> assets, List<String> extensions) {
    for (final ext in extensions) {
      for (final url in assets) {
        if (url.toLowerCase().endsWith(ext)) return url;
      }
    }
    return null;
  }
}

class ReleaseInfo {
  final String version;
  final String notes;
  final String pageUrl;
  final String? windowsUrl;
  final String? androidUrl;

  bool get hasWindowsDownload => windowsUrl != null;
  bool get hasAndroidDownload => androidUrl != null;

  const ReleaseInfo({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.windowsUrl,
    this.androidUrl,
  });
}
