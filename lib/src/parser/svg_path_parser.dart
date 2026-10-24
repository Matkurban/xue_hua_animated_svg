import 'dart:typed_data';

import '../model/svg_node.dart';

/// Precompiles SVG `d` path strings into strongly-typed [PrecompiledSvgPath]
/// command + coordinate buffers during the XML AST build phase.
///
/// Normalizes shorthand commands (`H`, `V`, `S`, `T`) into canonical absolute
/// commands (`M`, `L`, `C`, `Q`, `A`, `Z`) so that paths using shorthand curves
/// or horizontal/vertical segments remain isomorphic for Path Morphing.
abstract final class SvgPathParser {
  /// Parses an SVG path data string `d` into a [PrecompiledSvgPath].
  static PrecompiledSvgPath parse(String d) {
    final commands = <SvgPathCmdType>[];
    final coords = <double>[];

    if (d.isEmpty) {
      return PrecompiledSvgPath(commands: commands, coords: Float64List(0));
    }

    final scanner = _PathNumberScanner(d);
    double currentX = 0.0;
    double currentY = 0.0;
    double subpathStartX = 0.0;
    double subpathStartY = 0.0;
    double lastCubicCtrlX = 0.0;
    double lastCubicCtrlY = 0.0;
    double lastQuadCtrlX = 0.0;
    double lastQuadCtrlY = 0.0;
    int prevCmdChar = 0;

    int cmd = 0;
    while (!scanner.isDone) {
      scanner.skipSeparators();
      if (scanner.isDone) break;

      final nextCmd = scanner.peekCommandChar();
      if (nextCmd != 0) {
        cmd = scanner.readCommandChar();
      } else if (cmd == 0) {
        break;
      }

      switch (cmd) {
        case 0x4D: // 'M'
        case 0x6D: // 'm'
          final isRel = cmd == 0x6D;
          final x = scanner.readDouble() + (isRel ? currentX : 0.0);
          final y = scanner.readDouble() + (isRel ? currentY : 0.0);
          commands.add(SvgPathCmdType.moveTo);
          coords.add(x);
          coords.add(y);
          currentX = x;
          currentY = y;
          subpathStartX = x;
          subpathStartY = y;
          lastCubicCtrlX = x;
          lastCubicCtrlY = y;
          lastQuadCtrlX = x;
          lastQuadCtrlY = y;
          prevCmdChar = cmd;
          // Subsequent coordinate pairs after M/m are implicit L/l
          cmd = isRel ? 0x6C : 0x4C;

        case 0x4C: // 'L'
        case 0x6C: // 'l'
          final isRel = cmd == 0x6C;
          final x = scanner.readDouble() + (isRel ? currentX : 0.0);
          final y = scanner.readDouble() + (isRel ? currentY : 0.0);
          commands.add(SvgPathCmdType.lineTo);
          coords.add(x);
          coords.add(y);
          currentX = x;
          currentY = y;
          lastCubicCtrlX = x;
          lastCubicCtrlY = y;
          lastQuadCtrlX = x;
          lastQuadCtrlY = y;
          prevCmdChar = cmd;

        case 0x48: // 'H'
        case 0x68: // 'h'
          final isRel = cmd == 0x68;
          final x = scanner.readDouble() + (isRel ? currentX : 0.0);
          commands.add(SvgPathCmdType.lineTo);
          coords.add(x);
          coords.add(currentY);
          currentX = x;
          lastCubicCtrlX = currentX;
          lastCubicCtrlY = currentY;
          lastQuadCtrlX = currentX;
          lastQuadCtrlY = currentY;
          prevCmdChar = cmd;

        case 0x56: // 'V'
        case 0x76: // 'v'
          final isRel = cmd == 0x76;
          final y = scanner.readDouble() + (isRel ? currentY : 0.0);
          commands.add(SvgPathCmdType.lineTo);
          coords.add(currentX);
          coords.add(y);
          currentY = y;
          lastCubicCtrlX = currentX;
          lastCubicCtrlY = currentY;
          lastQuadCtrlX = currentX;
          lastQuadCtrlY = currentY;
          prevCmdChar = cmd;

        case 0x43: // 'C'
        case 0x63: // 'c'
          final isRel = cmd == 0x63;
          final ox = isRel ? currentX : 0.0;
          final oy = isRel ? currentY : 0.0;
          final x1 = scanner.readDouble() + ox;
          final y1 = scanner.readDouble() + oy;
          final x2 = scanner.readDouble() + ox;
          final y2 = scanner.readDouble() + oy;
          final x = scanner.readDouble() + ox;
          final y = scanner.readDouble() + oy;
          commands.add(SvgPathCmdType.cubicTo);
          coords.add(x1);
          coords.add(y1);
          coords.add(x2);
          coords.add(y2);
          coords.add(x);
          coords.add(y);
          lastCubicCtrlX = x2;
          lastCubicCtrlY = y2;
          currentX = x;
          currentY = y;
          lastQuadCtrlX = x;
          lastQuadCtrlY = y;
          prevCmdChar = cmd;

        case 0x53: // 'S'
        case 0x73: // 's'
          final isRel = cmd == 0x73;
          final ox = isRel ? currentX : 0.0;
          final oy = isRel ? currentY : 0.0;
          final bool hadPrevCubic =
              prevCmdChar == 0x43 ||
              prevCmdChar == 0x63 ||
              prevCmdChar == 0x53 ||
              prevCmdChar == 0x73;
          final x1 = hadPrevCubic
              ? (2.0 * currentX - lastCubicCtrlX)
              : currentX;
          final y1 = hadPrevCubic
              ? (2.0 * currentY - lastCubicCtrlY)
              : currentY;
          final x2 = scanner.readDouble() + ox;
          final y2 = scanner.readDouble() + oy;
          final x = scanner.readDouble() + ox;
          final y = scanner.readDouble() + oy;
          commands.add(SvgPathCmdType.cubicTo);
          coords.add(x1);
          coords.add(y1);
          coords.add(x2);
          coords.add(y2);
          coords.add(x);
          coords.add(y);
          lastCubicCtrlX = x2;
          lastCubicCtrlY = y2;
          currentX = x;
          currentY = y;
          lastQuadCtrlX = x;
          lastQuadCtrlY = y;
          prevCmdChar = cmd;

        case 0x51: // 'Q'
        case 0x71: // 'q'
          final isRel = cmd == 0x71;
          final ox = isRel ? currentX : 0.0;
          final oy = isRel ? currentY : 0.0;
          final x1 = scanner.readDouble() + ox;
          final y1 = scanner.readDouble() + oy;
          final x = scanner.readDouble() + ox;
          final y = scanner.readDouble() + oy;
          commands.add(SvgPathCmdType.quadTo);
          coords.add(x1);
          coords.add(y1);
          coords.add(x);
          coords.add(y);
          lastQuadCtrlX = x1;
          lastQuadCtrlY = y1;
          currentX = x;
          currentY = y;
          lastCubicCtrlX = x;
          lastCubicCtrlY = y;
          prevCmdChar = cmd;

        case 0x54: // 'T'
        case 0x74: // 't'
          final isRel = cmd == 0x74;
          final ox = isRel ? currentX : 0.0;
          final oy = isRel ? currentY : 0.0;
          final bool hadPrevQuad =
              prevCmdChar == 0x51 ||
              prevCmdChar == 0x71 ||
              prevCmdChar == 0x54 ||
              prevCmdChar == 0x74;
          final x1 = hadPrevQuad ? (2.0 * currentX - lastQuadCtrlX) : currentX;
          final y1 = hadPrevQuad ? (2.0 * currentY - lastQuadCtrlY) : currentY;
          final x = scanner.readDouble() + ox;
          final y = scanner.readDouble() + oy;
          commands.add(SvgPathCmdType.quadTo);
          coords.add(x1);
          coords.add(y1);
          coords.add(x);
          coords.add(y);
          lastQuadCtrlX = x1;
          lastQuadCtrlY = y1;
          currentX = x;
          currentY = y;
          lastCubicCtrlX = x;
          lastCubicCtrlY = y;
          prevCmdChar = cmd;

        case 0x41: // 'A'
        case 0x61: // 'a'
          final isRel = cmd == 0x61;
          final rx = scanner.readDouble();
          final ry = scanner.readDouble();
          final xAxisRotation = scanner.readDouble();
          final largeArcFlag = scanner.readArcFlag();
          final sweepFlag = scanner.readArcFlag();
          final x = scanner.readDouble() + (isRel ? currentX : 0.0);
          final y = scanner.readDouble() + (isRel ? currentY : 0.0);
          commands.add(SvgPathCmdType.arcTo);
          coords.add(rx);
          coords.add(ry);
          coords.add(xAxisRotation);
          coords.add(largeArcFlag);
          coords.add(sweepFlag);
          coords.add(x);
          coords.add(y);
          currentX = x;
          currentY = y;
          lastCubicCtrlX = x;
          lastCubicCtrlY = y;
          lastQuadCtrlX = x;
          lastQuadCtrlY = y;
          prevCmdChar = cmd;

        case 0x5A: // 'Z'
        case 0x7A: // 'z'
          commands.add(SvgPathCmdType.close);
          currentX = subpathStartX;
          currentY = subpathStartY;
          lastCubicCtrlX = currentX;
          lastCubicCtrlY = currentY;
          lastQuadCtrlX = currentX;
          lastQuadCtrlY = currentY;
          prevCmdChar = cmd;
          cmd = 0;

        default:
          // Unsupported command character: advance to avoid infinite loop
          scanner.advance();
          cmd = 0;
      }
    }

    return PrecompiledSvgPath(
      commands: commands,
      coords: Float64List.fromList(coords),
    );
  }
}

class _PathNumberScanner {
  final String _src;
  final int _len;
  int _pos = 0;

  _PathNumberScanner(this._src) : _len = _src.length;

  bool get isDone => _pos >= _len;

  void advance() {
    if (_pos < _len) _pos++;
  }

  void skipSeparators() {
    while (_pos < _len) {
      final c = _src.codeUnitAt(_pos);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2C) {
        _pos++;
      } else {
        break;
      }
    }
  }

  int peekCommandChar() {
    if (_pos >= _len) return 0;
    final c = _src.codeUnitAt(_pos);
    if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)) {
      return c;
    }
    return 0;
  }

  int readCommandChar() {
    final c = peekCommandChar();
    if (c != 0) _pos++;
    return c;
  }

  /// Reads an SVG arc flag (`0` or `1`), which in compact SVG syntax can be
  /// concatenated without whitespace (e.g., `a25,25 -30 0150,-25`).
  double readArcFlag() {
    skipSeparators();
    if (_pos >= _len) return 0.0;
    final c = _src.codeUnitAt(_pos);
    if (c == 0x30) {
      _pos++;
      return 0.0;
    }
    if (c == 0x31) {
      _pos++;
      return 1.0;
    }
    return readDouble();
  }

  double readDouble() {
    skipSeparators();
    if (_pos >= _len) return 0.0;

    final start = _pos;
    int c = _src.codeUnitAt(_pos);
    if (c == 0x2B || c == 0x2D) {
      // '+' or '-'
      _pos++;
    }

    bool hasDot = false;
    while (_pos < _len) {
      c = _src.codeUnitAt(_pos);
      if (c >= 0x30 && c <= 0x39) {
        _pos++;
      } else if (c == 0x2E && !hasDot) {
        hasDot = true;
        _pos++;
      } else if (c == 0x65 || c == 0x45) {
        // Scientific notation 'e' or 'E'
        _pos++;
        if (_pos < _len) {
          final sign = _src.codeUnitAt(_pos);
          if (sign == 0x2B || sign == 0x2D) {
            _pos++;
          }
        }
        while (_pos < _len) {
          final d = _src.codeUnitAt(_pos);
          if (d >= 0x30 && d <= 0x39) {
            _pos++;
          } else {
            break;
          }
        }
        break;
      } else {
        break;
      }
    }

    if (_pos == start) return 0.0;
    return double.tryParse(_src.substring(start, _pos)) ?? 0.0;
  }
}
