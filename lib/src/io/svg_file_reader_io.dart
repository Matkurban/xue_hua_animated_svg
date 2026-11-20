import 'dart:io' as io;

/// Returns the filesystem path for a `dart:io` [io.File].
/// 返回 `dart:io` [io.File] 对应的文件系统路径。
///
/// - [file]: A `dart:io` [io.File] instance. `dart:io` 的 [io.File] 实例。
String svgFilePath(Object file) => (file as io.File).path;

/// Reads UTF-8 contents from a `dart:io` [io.File].
/// 从 `dart:io` [io.File] 读取 UTF-8 文本内容。
///
/// - [file]: A `dart:io` [io.File] instance. `dart:io` 的 [io.File] 实例。
Future<String> readSvgFileAsString(Object file) =>
    (file as io.File).readAsString();
