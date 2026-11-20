import 'dart:typed_data';
import 'dart:ui' as ui;

/// Precompiled path command type for isomorphic Path Morphing and zero-string runtime path building.
/// 预编译路径指令类型枚举，用于同构路径形变与运行期零字符串解析路径构建。
enum SvgPathCmdType {
  /// Move current point (`M`, 2 coords: `x, y`). 移动到指定点（2 坐标）。
  moveTo,

  /// Straight line segment (`L`, 2 coords: `x, y`). 直线段（2 坐标）。
  lineTo,

  /// Cubic Bézier curve (`C`, 6 coords: `x1, y1, x2, y2, x, y`). 三次贝塞尔曲线（6 坐标）。
  cubicTo,

  /// Quadratic Bézier curve (`Q`, 4 coords: `x1, y1, x, y`). 二次贝塞尔曲线（4 坐标）。
  quadTo,

  /// Elliptical arc (`A`, 7 coords: `rx, ry, xAxisRotationDeg, largeArcFlag, sweepFlag, x, y`). 椭圆弧（7 坐标）。
  arcTo,

  /// Close current subpath (`Z`, 0 coords). 闭合当前子路径（0 坐标）。
  close,
}

/// Precompiled path instruction sequence stored in contiguous typed arrays.
/// 存储在连续类型化数组中的预编译路径指令序列，支持零分配构建与 O(N) 同构路径形变。
class PrecompiledSvgPath {
  /// Canonical absolute path command sequence.
  /// 规范化后的绝对路径指令序列。
  final List<SvgPathCmdType> commands;

  /// Flattened coordinate buffer matching [commands].
  /// 与 [commands] 对应的扁平化浮点坐标缓冲区。
  final Float64List coords;

  /// Creates a [PrecompiledSvgPath].
  /// 创建一个 [PrecompiledSvgPath] 预编译路径对象。
  ///
  /// - [commands]: Canonical path commands. 规范化路径指令列表。
  /// - [coords]: Flattened coordinate buffer. 扁平坐标数组。
  const PrecompiledSvgPath({required this.commands, required this.coords});

  /// Returns the number of scalar coordinates consumed by [cmd].
  /// 返回路径指令 [cmd] 所消耗的标量坐标个数。
  ///
  /// - [cmd]: Path command type. 路径指令类型。
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
  /// 检查 [other] 是否与当前路径同构（指令序列与坐标长度完全一致）。
  ///
  /// - [other]: Another precompiled path to compare. 待比较的另一条预编译路径。
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

  /// Populates [outPath] from [commands] and [activeCoords] (defaulting to [coords]).
  /// 使用 [commands] 与 [activeCoords]（默认 [coords]，形变时为插值缓冲）填充目标 [outPath]。
  ///
  /// - [outPath]: Destination Flutter [ui.Path] to populate. 目标 [ui.Path]。
  /// - [activeCoords]: Optional coordinate buffer overriding [coords]. 可选覆盖坐标缓冲。
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
