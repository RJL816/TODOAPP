import 'dart:convert';
import 'dart:typed_data';

/// 最小 .xls（BIFF8 / Excel 97-2003）读取器。
///
/// 教务系统导出的课表是 BIFF8 老格式，Dart 生态没有维护良好的 xls 读取包
/// （spreadsheet_decoder 2.x 已移除 xls 支持）。本类只做这一件事：
/// 读出第一个工作表的单元格文本矩阵，供课程导入解析。
///
/// 不支持公式单元格（返回 null）、图表/宏表、多工作表——课表用不到。
List<List<String?>> decodeXlsFirstSheet(Uint8List bytes) {
  final workbook = _CfbReader(bytes).findStream('Workbook') ??
      _CfbReader(bytes).findStream('Book');
  if (workbook == null) {
    throw Exception('不是有效的 .xls 文件（缺少 Workbook 流）');
  }
  return _BiffReader(workbook).readFirstSheet();
}

// ==================== CFB（复合文档）容器 ====================

class _CfbReader {
  _CfbReader(this.data) {
    _parse();
  }

  final Uint8List data;
  late int _sectorSize;
  late int _miniSectorSize;
  late int _miniCutoff;
  late Uint8List _fat;
  late Uint8List _miniFat;
  late Uint8List _miniStream;
  final Map<String, Uint8List> _streams = {};

  int _u32(int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);

  Uint8List _readChain(int start, int size, Uint8List fat, int sectorSize) {
    final chunks = <int>[];
    var sector = start;
    var guard = 0;
    while (sector >= 0 && sector < fat.length ~/ 4 && guard++ < 1 << 20) {
      chunks.add(sector);
      sector = readU32(fat, sector * 4);
      // 0xFFFFFFFE = end of chain
      if (sector == 0xFFFFFFFE) break;
    }
    final out = BytesBuilder(copy: false);
    for (final s in chunks) {
      final begin = 512 + s * sectorSize;
      final end = begin + sectorSize;
      out.add(data.sublist(begin, end.clamp(0, data.length)));
    }
    final bytes = out.toBytes();
    return bytes.length > size ? bytes.sublist(0, size) : bytes;
  }

  void _parse() {
    if (data.length < 512 ||
        data[0] != 0xD0 ||
        data[1] != 0xCF ||
        data[2] != 0x11 ||
        data[3] != 0xE0) {
      throw Exception('不是有效的 .xls 文件（缺少 OLE2 头）');
    }
    _sectorSize = 1 << _readU16(data, 0x1E);
    _miniSectorSize = 1 << _readU16(data, 0x20);
    _miniCutoff = _u32(0x38);
    final firstDir = _u32(0x30);
    final firstMiniFat = _u32(0x3C);
    final firstDifat = _u32(0x44);
    final numDifat = _u32(0x48);

    // DIFAT：头 109 项 + 可选扩展链
    final fatSectors = <int>[];
    for (var i = 0; i < 109; i++) {
      final v = _u32(0x4C + i * 4);
      if (v != 0xFFFFFFFF) fatSectors.add(v);
    }
    var difat = firstDifat;
    var guard = 0;
    while (difat != 0xFFFFFFFE && numDifat > 0 && guard++ < 1 << 16) {
      final sectorBegin = 512 + difat * _sectorSize;
      final perSector = _sectorSize ~/ 4 - 1;
      for (var i = 0; i < perSector; i++) {
        final v = _u32(sectorBegin + i * 4);
        if (v != 0xFFFFFFFF && v != 0xFFFFFFFC) fatSectors.add(v);
      }
      difat = _u32(sectorBegin + _sectorSize - 4);
    }

    final fatBuilder = BytesBuilder(copy: false);
    for (final s in fatSectors) {
      fatBuilder.add(
          data.sublist(512 + s * _sectorSize, 512 + (s + 1) * _sectorSize));
    }
    _fat = fatBuilder.toBytes();

    // 目录
    final dirData = _readChain(firstDir, 1 << 24, _fat, _sectorSize);
    final entries = <_CfbEntry>[];
    for (var off = 0; off + 128 <= dirData.length; off += 128) {
      final nameLen = _readU16(dirData, off + 64);
      if (nameLen < 2) continue;
      final type = dirData[off + 66];
      // WPS 等生成器会把 nameLen 写到含尾部 null 填充的长度，需截断
      var name = utf16leToString(dirData, off, nameLen - 2);
      final nullIndex = name.indexOf('\x00');
      if (nullIndex >= 0) name = name.substring(0, nullIndex);
      entries.add(_CfbEntry(
        name: name,
        isRoot: type == 5,
        isStream: type == 2,
        startSector: dirData[off + 116] |
            (dirData[off + 117] << 8) |
            (dirData[off + 118] << 16) |
            (dirData[off + 119] << 24),
        size: dirData[off + 120] |
            (dirData[off + 121] << 8) |
            (dirData[off + 122] << 16) |
            (dirData[off + 123] << 24),
      ));
    }

    // Root entry 的流是 mini stream 容器
    final root = entries.firstWhere((e) => e.isRoot,
        orElse: () => throw Exception('OLE2 缺少 Root Entry'));
    _miniStream = _readChain(root.startSector, root.size, _fat, _sectorSize);
    _miniFat = firstMiniFat != 0xFFFFFFFE
        ? _readChain(firstMiniFat, 1 << 24, _fat, _sectorSize)
        : Uint8List(0);

    for (final entry in entries) {
      if (!entry.isStream) continue;
      final bytes = _readStream(entry);
      _streams[entry.name.toUpperCase()] = bytes;
    }
  }

  Uint8List _readStream(_CfbEntry entry) {
    if (entry.size < _miniCutoff) {
      // 小流：存在 mini stream 里，用 miniFAT 链
      final chunks = <int>[];
      var sector = entry.startSector;
      var guard = 0;
      while (sector >= 0 &&
          sector < _miniFat.length ~/ 4 &&
          guard++ < 1 << 20) {
        chunks.add(sector);
        sector = _readU32(_miniFat, sector * 4);
        if (sector == 0xFFFFFFFE) break;
      }
      final out = BytesBuilder(copy: false);
      for (final s in chunks) {
        final begin = s * _miniSectorSize;
        out.add(_miniStream.sublist(
            begin, (begin + _miniSectorSize).clamp(0, _miniStream.length)));
      }
      final bytes = out.toBytes();
      return bytes.length > entry.size
          ? bytes.sublist(0, entry.size)
          : bytes;
    }
    return _readChain(entry.startSector, entry.size, _fat, _sectorSize);
  }

  Uint8List? findStream(String name) => _streams[name.toUpperCase()];
}

class _CfbEntry {
  final String name;
  final bool isRoot;
  final bool isStream;
  final int startSector;
  final int size;
  _CfbEntry({
    required this.name,
    required this.isRoot,
    required this.isStream,
    required this.startSector,
    required this.size,
  });
}

// ==================== BIFF8 记录遍历 ====================

class _BiffReader {
  _BiffReader(this.data);
  final Uint8List data;

  List<List<String?>> readFirstSheet() {
    final cells = <int, Map<int, String?>>{};
    int? sheetOffset;

    // 第一遍：workbook globals —— SST 共享字符串表 + 第一个工作表位置
    var offset = 0;
    final sstChunks = <Uint8List>[];
    var sstDone = false;
    while (offset + 4 <= data.length) {
      final id = readU16(data, offset);
      final len = readU16(data, offset + 2);
      final body = Uint8List.sublistView(data, offset + 4, offset + 4 + len);
      if (id == 0x0085) {
        // BOUNDSHEET：取第一个工作表的 BOF 偏移
        sheetOffset ??= readU32(body, 0);
      } else if (id == 0x00FC && !sstDone) {
        sstChunks.add(body);
        // SST 可能被 Continue(0x3C) 记录延续
        var next = offset + 4 + len;
        while (next + 4 <= data.length && readU16(data, next) == 0x003C) {
          final clen = readU16(data, next + 2);
          sstChunks
              .add(Uint8List.sublistView(data, next + 4, next + 4 + clen));
          next += 4 + clen;
        }
        sstDone = true;
        offset = next;
        continue;
      } else if (id == 0x000A) {
        break;
      }
      offset += 4 + len;
    }

    final sst = _parseSst(sstChunks);

    // 第二遍：工作表内的单元格记录
    if (sheetOffset != null && sheetOffset < data.length) {
      offset = sheetOffset;
      final rowsSeen = <int>{};
      while (offset + 4 <= data.length) {
        final id = readU16(data, offset);
        final len = readU16(data, offset + 2);
        if (id == 0x000A) break; // EOF
        final body = Uint8List.sublistView(data, offset + 4, offset + 4 + len);
        if (len >= 4) {
          final row = readU16(body, 0);
          final col = readU16(body, 2);
          switch (id) {
            case 0x00FD: // LABELSST：row, col, ixfe(2), isst(4)
              rowsSeen.add(row);
              if (len >= 10) {
                final index = readU32(body, 6);
                if (index < sst.length) {
                  cells.putIfAbsent(row, () => {})[col] = sst[index];
                }
              }
              break;
            case 0x0204: // LABEL（内联字符串）：row, col, ixfe(2), 字符串
              rowsSeen.add(row);
              if (len >= 6) {
                final parsed = readXlsString(body, 6);
                cells.putIfAbsent(row, () => {})[col] = parsed.$1;
              }
              break;
            case 0x0203: // NUMBER
              if (len >= 14) {
                final bd = ByteData.sublistView(body, 6, 14);
                cells.putIfAbsent(row, () => {})[col] =
                    _fmtNum(bd.getFloat64(0));
              }
              break;
            case 0x027E: // RK
              if (len >= 10) {
                final value = _rkToNumber(body, 6);
                if (value != null) {
                  cells.putIfAbsent(row, () => {})[col] = _fmtNum(value);
                }
              }
              break;
            case 0x00BD: // MULRK
              if (len >= 6) {
                final count = (len - 6) ~/ 6;
                for (var i = 0; i < count; i++) {
                  final value = _rkToNumber(body, 4 + i * 6 + 2);
                  if (value != null) {
                    cells.putIfAbsent(row, () => {})[col + i] =
                        _fmtNum(value);
                  }
                }
              }
              break;
          }
        }
        offset += 4 + len;
      }
    }

    if (cells.isEmpty) return const [];
    final maxRow = cells.keys.reduce((a, b) => a > b ? a : b);
    final grid = List<List<String?>>.generate(maxRow + 1, (_) => []);
    cells.forEach((row, cols) {
      if (row < 0 || row >= grid.length) return;
      final maxCol = cols.keys.isEmpty
          ? -1
          : cols.keys.reduce((a, b) => a > b ? a : b);
      final line = List<String?>.filled(maxCol + 1, null);
      cols.forEach((col, text) {
        if (col >= 0 && col < line.length) line[col] = text;
      });
      grid[row] = line;
    });
    return grid;
  }

  /// 解析 SST：前两个 u32（引用总数 / 唯一串数）后跟字符串数组
  List<String> _parseSst(List<Uint8List> chunks) {
    if (chunks.isEmpty) return const [];
    Uint8List body;
    if (chunks.length == 1) {
      body = chunks.first;
    } else {
      final builder = BytesBuilder(copy: false);
      for (final chunk in chunks) {
        builder.add(chunk);
      }
      body = builder.toBytes();
    }
    if (body.length < 8) return const [];
    final unique = readU32(body, 4);
    var pos = 8;
    final strings = <String>[];
    for (var i = 0; i < unique && pos + 3 <= body.length; i++) {
      final parsed = readXlsString(body, pos);
      strings.add(parsed.$1);
      if (i < 4) {
      }
      pos = parsed.$2;
    }
    return strings;
  }

  String? _fmtNum(double value) {
    if (value == value.truncateToDouble()) {
      return value.truncate().toString();
    }
    return value.toString();
  }

  double? _rkToNumber(Uint8List body, int offset) {
    final rk = readU32(body, offset);
    final asInt = rk & 0x80000000 != 0 ? rk - 0x100000000 : rk;
    final dividedBy100 = asInt & 0x1 != 0;
    final isInt = asInt & 0x2 != 0;
    if (isInt) {
      final value = asInt >> 2;
      return dividedBy100 ? value / 100 : value.toDouble();
    }
    final bd = ByteData(8)
      ..setUint32(0, 0)
      ..setUint32(4, rk & 0xFFFFFFFC);
    final value = bd.getFloat64(0);
    return dividedBy100 ? value / 100 : value;
  }
}

// ==================== 公共字节工具 ====================

int readU16(Uint8List data, int offset) =>
    data[offset] | (data[offset + 1] << 8);

int readU32(Uint8List data, int offset) =>
    data[offset] |
    (data[offset + 1] << 8) |
    (data[offset + 2] << 16) |
    (data[offset + 3] << 24);

int _readU16(Uint8List data, int offset) => readU16(data, offset);
int _readU32(Uint8List data, int offset) => readU32(data, offset);

String utf16leToString(Uint8List data, int offset, int charCount) {
  final units = <int>[];
  for (var i = 0; i < charCount; i++) {
    units.add(readU16(data, offset + i * 2));
  }
  return String.fromCharCodes(units);
}

/// 读取 BIFF 字符串（cch + flags [+ rich/ext 长度] + 文本），返回 (文本, 下一位置)
(String, int) readXlsString(Uint8List body, int start) {
  var pos = start;
  final cch = readU16(body, pos);
  final flags = body[pos + 2];
  pos += 3;
  // fHighByte：bit0=1 表示双字节（UTF-16LE），0 表示压缩的 8-bit
  final isUtf16 = flags & 0x1 != 0;
  final rich = flags & 0x8 != 0;
  final ext = flags & 0x4 != 0;
  var cRun = 0;
  var extSize = 0;
  if (rich) {
    cRun = readU16(body, pos);
    pos += 2;
  }
  if (ext) {
    extSize = readU32(body, pos);
    pos += 4;
  }
  String text;
  if (isUtf16) {
    text = utf16leToString(body, pos, cch);
    pos += cch * 2;
  } else {
    text = latin1.decode(body.sublist(pos, pos + cch), allowInvalid: true);
    pos += cch;
  }
  pos += cRun * 4 + extSize;
  return (text, pos);
}
