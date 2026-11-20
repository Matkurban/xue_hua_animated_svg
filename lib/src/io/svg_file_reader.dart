/// Conditional file reader entry exporting the `dart:io` implementation on
/// native platforms and the unsupported stub on web.
///
/// 条件导出文件读取入口：原生平台导出 `dart:io` 实现，Web 平台导出桩实现。
library;

export 'svg_file_reader_stub.dart'
    if (dart.library.io) 'svg_file_reader_io.dart';
