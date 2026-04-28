import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Excel 文件预处理器
/// 用于修复教务系统导出的 Excel 文件中的格式问题
class ExcelPreprocessor {
  /// 预处理 Excel 文件，修复自定义格式问题
  /// 返回修复后的临时文件路径
  static Future<File> preprocess(File inputFile) async {
    // 创建临时文件
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/fixed_excel_${DateTime.now().millisecondsSinceEpoch}.xlsx');

    // 1. 读取原始 xlsx 文件（实际上是 ZIP 文件）
    final bytes = await inputFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 2. 创建输出 archive
    final outputArchive = Archive();

    // 3. 处理每个文件
    for (final file in archive) {
      // 跳过目录
      if (file.name.endsWith('/')) {
        continue;
      }

      // 只处理需要的文件
      if (file.name != 'xl/styles.xml' && file.name != 'xl/workbook.xml') {
        // 其他文件直接复制
        outputArchive.addFile(file);
        continue;
      }

      // 获取文件内容
      List<int> content = _getFileContent(file);
      if (content.isEmpty) {
        continue;
      }

      // 转换为字符串
      String contentStr;
      try {
        contentStr = utf8.decode(content);
      } catch (e) {
        // 如果 UTF-8 解码失败，跳过
        outputArchive.addFile(file);
        continue;
      }

      if (file.name == 'xl/styles.xml') {
        // 修复 styles.xml 中的格式问题
        try {
          final fixedContent = _fixStylesXml(contentStr);
          outputArchive.addFile(ArchiveFile(file.name, fixedContent.length, fixedContent));
        } catch (e) {
          // 如果修复失败，使用原文件
          outputArchive.addFile(file);
        }
      } else if (file.name == 'xl/workbook.xml') {
        // 修复 workbook.xml 中的格式问题
        try {
          final fixedContent = _fixWorkbookXml(contentStr);
          outputArchive.addFile(ArchiveFile(file.name, fixedContent.length, fixedContent));
        } catch (e) {
          // 如果修复失败，使用原文件
          outputArchive.addFile(file);
        }
      }
    }

    // 4. 写入临时文件
    final zipBytes = ZipEncoder().encode(outputArchive);
    await tempFile.writeAsBytes(zipBytes!);

    return tempFile;
  }

  /// 获取文件内容
  static List<int> _getFileContent(ArchiveFile file) {
    try {
      final content = file.content;
      if (content is List<int>) {
        return content;
      } else if (content is Uint8List) {
        return content.toList();
      } else {
        // 尝试转换为字节数组
        return List<int>.from(content ?? []);
      }
    } catch (e) {
      return [];
    }
  }

  /// 修复 styles.xml 中的自定义格式问题
  static List<int> _fixStylesXml(String xmlStr) {
    final document = XmlDocument.parse(xmlStr);

    // 找到 numFmts 元素
    final numFmts = document.findAllElements('numFmts').firstOrNull;

    if (numFmts != null) {
      // 获取当前最小的 numFmtId
      int minCustomId = 164; // 标准规定自定义格式从 164 开始
      final numFmtElements = numFmts.findAllElements('numFmt');

      for (final numFmt in numFmtElements) {
        final numFmtId = int.tryParse(numFmt.getAttribute('numFmtId') ?? '-1') ?? -1;
        if (numFmtId < minCustomId && numFmtId >= 0) {
          minCustomId = numFmtId;
        }
      }

      // 如果有小于 164 的自定义格式 ID，需要修复
      if (minCustomId < 164) {
        // 删除所有小于 164 的自定义格式
        final toRemove = <XmlElement>[];
        for (final numFmt in numFmtElements) {
          final numFmtId = int.tryParse(numFmt.getAttribute('numFmtId') ?? '-1') ?? -1;
          if (numFmtId < 164 && numFmtId >= 0) {
            toRemove.add(numFmt);
          }
        }

        // 删除元素
        for (final element in toRemove) {
          element.remove();
        }

        // 更新 count
        final remainingCount = numFmtElements.length - toRemove.length;
        if (remainingCount == 0) {
          // 如果没有自定义格式了，删除整个 numFmts 元素
          numFmts.remove();
        } else {
          numFmts.setAttribute('count', remainingCount.toString());
        }
      }
    }

    return utf8.encode(document.toXmlString());
  }

  /// 修复 workbook.xml 中的日期格式问题
  static List<int> _fixWorkbookXml(String xmlStr) {
    final document = XmlDocument.parse(xmlStr);

    // 移除可能导致问题的日期1904属性
    final workbookPr = document.findAllElements('workbookPr').firstOrNull;
    if (workbookPr != null) {
      workbookPr.setAttribute('date1904', '0');
    }

    return utf8.encode(document.toXmlString());
  }
}
