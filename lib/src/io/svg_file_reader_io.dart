import 'dart:io' as io;

/// Returns the filesystem path for a `dart:io` [File].
String svgFilePath(Object file) => (file as io.File).path;

/// Reads UTF-8 contents from a `dart:io` [File].
Future<String> readSvgFileAsString(Object file) =>
    (file as io.File).readAsString();
