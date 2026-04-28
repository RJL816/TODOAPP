import 'dart:io';
import 'package:excel_wps/excel.dart';
import '../models/course.dart';
import 'excel_preprocessor.dart';

/// 课程导入服务
/// 负责从教务系统导出的 Excel 文件中解析课程信息
/// 支持 .xlsx 格式（.xls 需转换后导入）
class CourseImportService {
  static CourseImportService? _instance;
  static CourseImportService get instance {
    _instance ??= CourseImportService._();
    return _instance!;
  }
  CourseImportService._();

  /// 从 Excel 文件导入课程
  /// @param filePath Excel 文件路径（支持 .xlsx 和 .xls）
  /// @return 解析出的课程列表
  Future<List<Course>> importFromExcel(String filePath) async {
    final normalizedPath = filePath.trim();
    final isXls = normalizedPath.toLowerCase().endsWith('.xls') && 
                  !normalizedPath.toLowerCase().endsWith('.xlsx');

    // 先检查文件是否存在
    final file = File(normalizedPath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $normalizedPath');
    }

    // xls 格式暂不支持，提示用户转换
    if (isXls) {
      throw Exception(
        '暂不支持 .xls 格式文件。\n\n'
        '请用 Excel 或 WPS 打开文件，然后"另存为" .xlsx 格式后再导入。\n\n'
        '步骤：打开文件 → 文件 → 另存为 → 选择"Excel 工作簿 (*.xlsx)"'
      );
    }

    // xlsx 格式使用 excel_wps 解析
    // 尝试预处理文件，修复格式问题
    File? fixedFile;
    try {
      fixedFile = await ExcelPreprocessor.preprocess(file);
    } catch (e) {
      // 预处理失败，使用原始文件
    }

    try {
      // 解析文件（优先使用修复后的文件）
      final courses = await _parseXlsxFile(fixedFile ?? file);

      if (courses.isEmpty) {
        throw Exception('未能解析到任何课程，请确认文件是教务系统导出的课表文件。');
      }

      return courses;
    } finally {
      // 清理临时文件
      if (fixedFile != null && await fixedFile.exists()) {
        await fixedFile.delete();
      }
    }
  }

  /// 使用 excel_wps 包解析 xlsx 文件
  Future<List<Course>> _parseXlsxFile(File file) async {
    // 从文件读取并解析
    final List<int> bytes = await file.readAsBytes();

    try {
      // 使用 excel_wps 包的 decodeBytes 方法
      final Excel excel = Excel.decodeBytes(bytes);

      final courses = <Course>[];
      String? currentSemester;

      // 获取第一个工作表
      final Sheet sheet = excel.tables.values.first;

      // 获取工作表的数据范围
      if (sheet.rows.isEmpty) {
        throw Exception('工作表为空');
      }

      final lastRow = sheet.rows.length;

      // 解析学期信息（第2行，索引1）
      if (lastRow >= 2) {
        final row = sheet.rows[1]; // 索引1表示第2行
        if (row.isNotEmpty) {
          final cellText = _getCellValue(row[0]);
          if (cellText != null) {
            final semesterMatch = RegExp(r'学年学期[：:]\s*(\d{4}-\d{4}-\d)').firstMatch(cellText);
            if (semesterMatch != null && semesterMatch.group(1) != null) {
              currentSemester = semesterMatch.group(1)!;
            }
          }
        }
      }

      // 课程数据从第4行开始（行索引3，数组从0开始计数）
      final timeSlotConfig = [
        {'rowIndex': 3, 'period': 1},  // 第一大节（第4行，索引3）
        {'rowIndex': 4, 'period': 3},  // 第二大节（第5行，索引4）
        {'rowIndex': 5, 'period': 5},  // 第三大节（第6行，索引5）
        {'rowIndex': 6, 'period': 7},  // 第四大节（第7行，索引6）
        {'rowIndex': 7, 'period': 9},  // 第五大节（第8行，索引7）
      ];

      for (var slot in timeSlotConfig) {
        final rowIndex = slot['rowIndex'] as int;

        if (rowIndex >= lastRow) break;

        final row = sheet.rows[rowIndex];

        for (int weekday = 1; weekday <= 7; weekday++) {
          // Excel表格第0列是时间段，第1列开始是周一到周日
          final colIndex = weekday; // weekday=1→colIndex=1(周一), weekday=7→colIndex=7(周日)
          if (colIndex >= row.length) break;

          final cellText = _getCellValue(row[colIndex]);

          if (cellText == null || cellText.trim().isEmpty) continue;
          if (cellText.contains('第') && cellText.contains('节')) continue;

          final parsedCourses = _parseCourseCell(cellText, weekday, slot['period'] as int, currentSemester);
          courses.addAll(parsedCourses);
        }
      }

      return courses;
    } catch (e) {
      throw Exception('Excel 解析失败: $e');
    }
  }

  /// 获取单元格的值（处理不同类型的单元格）
  String? _getCellValue(Data? cell) {
    if (cell == null) return null;
    if (cell.value == null) return null;

    final value = cell.value;

    // 处理 CellValue 类型 - 根据不同类型提取字符串值
    if (value is TextCellValue) {
      // TextCellValue.value 返回 TextSpan，需要提取文本内容
      final textSpan = value.value;
      // 从 TextSpan 中提取文本
      final buffer = StringBuffer();
      _extractTextFromTextSpan(textSpan, buffer);
      return buffer.toString();
    } else if (value is IntCellValue) {
      return value.value.toString();
    } else if (value is DoubleCellValue) {
      return value.value.toString();
    } else if (value is BoolCellValue) {
      return value.value.toString();
    } else if (value is FormulaCellValue) {
      // 公式单元格，返回公式字符串
      return value.formula;
    } else if (value is DateCellValue || value is DateTimeCellValue || value is TimeCellValue) {
      return value.toString();
    } else {
      return value?.toString();
    }
  }

  /// 从 TextSpan 中提取纯文本内容
  void _extractTextFromTextSpan(dynamic span, StringBuffer buffer) {
    // 使用 span.text 属性获取文本
    if (span is TextSpan) {
      buffer.write(span.text ?? '');
      if (span.children != null) {
        for (final child in span.children!) {
          _extractTextFromTextSpan(child, buffer);
        }
      }
    }
  }

  /// 解析课程单元格内容
  List<Course> _parseCourseCell(String cellText, int weekday, int period, String? semester) {
    final courses = <Course>[];

    final lines = cellText
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.isEmpty) return courses;

    final courseCodePattern = RegExp(r'^\d{8}-\d+$');
    final courseCodeMatches = lines.where((line) => courseCodePattern.hasMatch(line)).toList();

    if (courseCodeMatches.length > 1) {
      final courseBlocks = _splitByCourseCodes(lines);
      for (var block in courseBlocks) {
        final course = _parseSingleCourse(block, weekday, period, semester);
        if (course != null) {
          courses.add(course);
        }
      }
    } else {
      final course = _parseSingleCourse(lines, weekday, period, semester);
      if (course != null) {
        courses.add(course);
      }
    }

    return courses;
  }

  /// 按课程代码分割行列表
  List<List<String>> _splitByCourseCodes(List<String> lines) {
    final blocks = <List<String>>[];
    List<String>? currentBlock;

    for (var line in lines) {
      if (RegExp(r'^\d{8}-\d+$').hasMatch(line)) {
        if (currentBlock != null && currentBlock.isNotEmpty) {
          blocks.add(currentBlock);
        }
        currentBlock = [line];
      } else {
        currentBlock ??= [];
        currentBlock.add(line);
      }
    }

    if (currentBlock != null && currentBlock.isNotEmpty) {
      blocks.add(currentBlock);
    }

    return blocks;
  }

  /// 解析单个课程信息
  Course? _parseSingleCourse(List<String> lines, int weekday, int period, String? semester) {
    if (lines.isEmpty) return null;

    String? name;
    String? teacher;
    String? location;
    String? weekRange;

    for (var line in lines) {
      if (line.trim().isEmpty) continue;

      if (RegExp(r'^\d{8}-\d+$').hasMatch(line)) continue;

      if (line.startsWith('(课堂派') || line.startsWith('(课堂')) continue;

      if (line.contains('[周]') || line.contains('周')) {
        final match = RegExp(r'(\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*)\[?\周]?').firstMatch(line);
        if (match != null && match.group(1) != null) {
          weekRange = match.group(1)!;
        }
        continue;
      }

      if (line.contains('教') || line.contains('楼') || line.contains('座')) {
        location = line.split('[').first.trim();
        continue;
      }

      if (line.contains('[') && line.contains('节')) continue;

      if (name == null) {
        if (line.length >= 2 && line.length <= 6 && _isAllChinese(line)) {
          name = line;
        } else {
          name = line;
        }
      } else if (teacher == null) {
        if (_isAllChinese(line) && line.length <= 6) {
          teacher = line;
        }
      }
    }

    if (name == null || name.isEmpty) {
      return null;
    }

    weekRange ??= '1-18';
    semester ??= '2025-2026-1';
    teacher ??= '';
    location ??= '';

    return Course.create(
      name: name,
      weekday: weekday,
      startPeriod: period,
      endPeriod: period + 1,
      weekRange: weekRange,
      semester: semester,
      teacher: teacher,
      location: location,
      colorArgb: Course.getColorForName(name),
    );
  }

  /// 检查字符串是否全由汉字组成
  bool _isAllChinese(String str) {
    return RegExp(r'^[\u4e00-\u9fa5]+$').hasMatch(str);
  }
}
