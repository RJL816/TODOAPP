import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/weather_scene.dart';
import '../services/weather_background_service.dart';

class WeatherSettingsSection extends StatefulWidget {
  const WeatherSettingsSection({super.key, this.service});
  final WeatherBackgroundService? service;
  @override
  State<WeatherSettingsSection> createState() => _WeatherSettingsSectionState();
}

class _WeatherSettingsSectionState extends State<WeatherSettingsSection> {
  late final _service = widget.service ?? WeatherBackgroundService.instance;
  @override
  void initState() {
    super.initState();
    unawaited(_service.init());
  }

  Future<void> _selectCity() async {
    final input = TextEditingController();
    List<WeatherPlace> results = [];
    bool searching = false;
    String? message;
    int generation = 0;
    final route = DialogRoute<WeatherPlace>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) {
        Future<void> search() async {
          final query = input.text.trim();
          if (query.isEmpty) return;
          final request = ++generation;
          update(() {
            searching = true;
            message = null;
          });
          try {
            final found = await _service.searchCities(query);
            if (!dialogContext.mounted || request != generation) return;
            update(() {
              results = found;
              searching = false;
              if (found.isEmpty) message = '没有找到城市，可输入城市的中文名或英文名';
            });
          } catch (_) {
            if (dialogContext.mounted && request == generation) {
              update(() {
                searching = false;
                message = '城市搜索失败，请检查网络后重试';
              });
            }
          }
        }

        return AlertDialog(
          title: const Text('选择天气城市'),
          scrollable: true,
          content: SizedBox(
              width: 360,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Expanded(
                      child: TextField(
                    controller: input,
                    autofocus: true,
                    decoration:
                        const InputDecoration(hintText: '例如：北京 / Shanghai'),
                    onSubmitted: (_) => search(),
                  )),
                  IconButton(
                      onPressed: searching ? null : search,
                      tooltip: '搜索城市',
                      icon: const Icon(Icons.search)),
                ]),
                if (searching)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator()),
                if (message != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(message!)),
                if (results.isNotEmpty)
                  SizedBox(
                      height: 240,
                      child: ListView(
                        children: [
                          for (final item in results)
                            ListTile(
                              title: Text(item.name),
                              subtitle: Text(item.region),
                              onTap: () => Navigator.pop(dialogContext, item),
                            )
                        ],
                      )),
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'))
          ],
        );
      }),
    );
    final place = await Navigator.of(context).push(route);
    await route.completed;
    input.dispose();
    if (place != null && mounted) await _service.selectPlace(place);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final data = _service.snapshot;
          final weather = data == null
              ? ''
              : switch (weatherSceneForCode(data.code)) {
                  AmbientWeather.rain => '雨',
                  AmbientWeather.snow => '雪',
                  AmbientWeather.clear => data.code == 0 ? '晴' : '多云 / 雾',
                };
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.cloud_outlined),
                  title: const Text('随天气切换背景'),
                  subtitle: const Text('雨天与雪天会匹配当前背景的白天、日落、夜间或日出'),
                  value: _service.enabled,
                  onChanged: _service.setEnabled,
                ),
                if (_service.enabled) ...[
                  if (_service.place != null)
                    Text(_service.place!.label,
                        style: Theme.of(context).textTheme.titleSmall),
                  if (data != null && data.place.key == _service.place?.key)
                    Text(
                        '$weather · ${data.temperature.round()}°C · ${_service.automaticLocation ? '自动定位' : '手动城市'}',
                        style: Theme.of(context).textTheme.bodySmall),
                  Wrap(spacing: 6, children: [
                    TextButton.icon(
                        onPressed:
                            _service.busy ? null : _service.useDeviceLocation,
                        icon: const Icon(Icons.my_location, size: 18),
                        label: const Text('使用定位')),
                    TextButton.icon(
                        onPressed: _service.busy ? null : _selectCity,
                        icon: const Icon(Icons.location_city, size: 18),
                        label: const Text('选择城市')),
                    IconButton(
                        onPressed: _service.busy
                            ? null
                            : () => _service.refresh(force: true),
                        tooltip: '刷新天气',
                        icon: const Icon(Icons.refresh, size: 20)),
                  ]),
                  if (_service.busy) const LinearProgressIndicator(),
                  if (_service.error != null)
                    Text(_service.error!,
                        style: Theme.of(context).textTheme.bodySmall),
                  Text('位置仅用于获取天气，不持续定位。断网时短暂保留最近天气；自定义照片保持原样。',
                      style: Theme.of(context).textTheme.bodySmall),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => launchUrl(
                            Uri.parse('https://open-meteo.com/'),
                            mode: LaunchMode.externalApplication),
                        child: const Text('天气数据：Open-Meteo'),
                      )),
                ],
              ]);
        },
      );
}
