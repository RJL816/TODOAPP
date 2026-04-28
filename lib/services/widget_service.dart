import 'dart:convert';
import 'dart:io';
import 'package:home_widget/home_widget.dart';
import '../models/course.dart';

/// Android 桌面小部件服务
/// 用于同步考试数据到桌面小部件
class WidgetService {
  static WidgetService? _instance;
  static WidgetService get instance {
    _instance ??= WidgetService._();
    return _instance!;
  }
  WidgetService._();

  /// Widget 名称（与 AndroidManifest 中注册的一致）
  static const String _androidWidgetName = 'ExamWidgetProvider';
  
  /// 初始化 Widget 服务
  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    
    // 设置 App Group（iOS 需要，Android 可选）
    // await HomeWidget.setAppGroupId('group.com.example.todo_app');
  }

  /// 同步考试数据到桌面小部件
  Future<void> syncExams(List<Exam> exams) async {
    if (!Platform.isAndroid) return;
    
    try {
      // 筛选未来的考试并按时间排序
      final now = DateTime.now();
      final upcomingExams = exams
          .where((e) => e.examDateTime.isAfter(now))
          .toList()
        ..sort((a, b) => a.examDateTime.compareTo(b.examDateTime));
      
      // 转换为 JSON 格式
      final examsData = upcomingExams.map((exam) => {
        'name': exam.name,
        'examTime': exam.examDateTime.millisecondsSinceEpoch,
        'location': exam.location,
      }).toList();
      
      // 保存到 SharedPreferences
      await HomeWidget.saveWidgetData<String>('exams_data', jsonEncode(examsData));
      
      // 通知 Widget 更新
      await HomeWidget.updateWidget(
        androidName: _androidWidgetName,
      );
    } catch (e) {
      print('同步 Widget 数据失败: $e');
    }
  }

  /// 清空 Widget 数据
  Future<void> clearExams() async {
    if (!Platform.isAndroid) return;
    
    try {
      await HomeWidget.saveWidgetData<String>('exams_data', '[]');
      await HomeWidget.updateWidget(
        androidName: _androidWidgetName,
      );
    } catch (e) {
      print('清空 Widget 数据失败: $e');
    }
  }
}
