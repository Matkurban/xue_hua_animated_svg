/// Stub path accessor when `dart:io` is unavailable (e.g. Flutter Web).
/// 当 `dart:io` 不可用（如 Flutter Web）时的路径访问桩函数，调用时抛出 [UnsupportedError]。
///
/// - [file]: Placeholder file object. 占位文件对象。
String svgFilePath(Object file) {
  throw UnsupportedError(
    'AnimatedSvgPicture.file is not supported on this platform '
    '(requires dart:io).',
  );
}

/// Stub reader when `dart:io` is unavailable (e.g. Flutter Web).
/// 当 `dart:io` 不可用（如 Flutter Web）时的文件读取桩函数，调用时抛出 [UnsupportedError]。
///
/// - [file]: Placeholder file object. 占位文件对象。
Future<String> readSvgFileAsString(Object file) {
  throw UnsupportedError(
    'AnimatedSvgPicture.file is not supported on this platform '
    '(requires dart:io).',
  );
}
