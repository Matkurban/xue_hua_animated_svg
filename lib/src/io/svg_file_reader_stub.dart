/// Stub path accessor when `dart:io` is unavailable.
String svgFilePath(Object file) {
  throw UnsupportedError(
    'AnimatedSvgPicture.file is not supported on this platform '
    '(requires dart:io).',
  );
}

/// Stub reader when `dart:io` is unavailable.
Future<String> readSvgFileAsString(Object file) {
  throw UnsupportedError(
    'AnimatedSvgPicture.file is not supported on this platform '
    '(requires dart:io).',
  );
}
