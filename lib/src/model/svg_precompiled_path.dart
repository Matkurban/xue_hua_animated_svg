import 'dart:typed_data';
import 'dart:ui' as ui;

/// Precompiled path command type for isomorphic Path Morphing & zero-string runtime path building.
enum SvgPathCmdType {
  moveTo, // 2 coords: x, y
  lineTo, // 2 coords: x, y
  cubicTo, // 6 coords: x1, y1, x2, y2, x, y
  quadTo, // 4 coords: x1, y1, x, y
  arcTo, // 7 coords: rx, ry, xAxisRotationDeg, largeArcFlag, sweepFlag, x, y
  close, // 0 coords
}

/// Precompiled path instruction sequence stored in contiguous typed arrays.
///
/// Enables zero-allocation path building and O(N) isomorphic path morphing.
class PrecompiledSvgPath {
  final List<SvgPathCmdType> commands;
  final Float64List coords;

  const PrecompiledSvgPath({required this.commands, required this.coords});

  /// Number of coordinates consumed by [cmd].
  static int coordCountFor(SvgPathCmdType cmd) {
    switch (cmd) {
      case SvgPathCmdType.moveTo:
      case SvgPathCmdType.lineTo:
        return 2;
      case SvgPathCmdType.quadTo:
        return 4;
      case SvgPathCmdType.cubicTo:
        return 6;
      case SvgPathCmdType.arcTo:
        return 7;
      case SvgPathCmdType.close:
        return 0;
    }
  }

  /// Checks whether [other] is isomorphic (identical command sequence and coord count).
  bool isIsomorphicWith(PrecompiledSvgPath other) {
    if (commands.length != other.commands.length ||
        coords.length != other.coords.length) {
      return false;
    }
    for (int i = 0; i < commands.length; i++) {
      if (commands[i] != other.commands[i]) return false;
    }
    return true;
  }

  /// Populates [outPath] from [commands] and [activeCoords] (which may be [coords]
  /// or an interpolated morphed buffer).
  void buildUiPath(ui.Path outPath, [Float64List? activeCoords]) {
    final c = activeCoords ?? coords;
    int offset = 0;
    for (int i = 0; i < commands.length; i++) {
      switch (commands[i]) {
        case SvgPathCmdType.moveTo:
          outPath.moveTo(c[offset], c[offset + 1]);
          offset += 2;
        case SvgPathCmdType.lineTo:
          outPath.lineTo(c[offset], c[offset + 1]);
          offset += 2;
        case SvgPathCmdType.quadTo:
          outPath.quadraticBezierTo(
            c[offset],
            c[offset + 1],
            c[offset + 2],
            c[offset + 3],
          );
          offset += 4;
        case SvgPathCmdType.cubicTo:
          outPath.cubicTo(
            c[offset],
            c[offset + 1],
            c[offset + 2],
            c[offset + 3],
            c[offset + 4],
            c[offset + 5],
          );
          offset += 6;
        case SvgPathCmdType.arcTo:
          final rx = c[offset].abs();
          final ry = c[offset + 1].abs();
          final rotDeg = c[offset + 2];
          final largeArc = c[offset + 3] >= 0.5;
          final sweep = c[offset + 4] >= 0.5;
          final endX = c[offset + 5];
          final endY = c[offset + 6];
          if (rx == 0.0 || ry == 0.0) {
            outPath.lineTo(endX, endY);
          } else {
            outPath.arcToPoint(
              ui.Offset(endX, endY),
              radius: ui.Radius.elliptical(rx, ry),
              rotation: rotDeg,
              largeArc: largeArc,
              clockwise: sweep,
            );
          }
          offset += 7;
        case SvgPathCmdType.close:
          outPath.close();
      }
    }
  }
}
