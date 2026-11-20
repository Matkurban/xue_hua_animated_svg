import 'dart:math' as math;

/// Pure-Dart evaluator for W3C CSS Values & Units Level 4 math functions:
/// `calc()`, `min()`, `max()`, and `clamp()`.
/// 纯 Dart 实现的 W3C CSS Values & Units Level 4 数学函数求值器（`calc`/`min`/`max`/`clamp`）。
abstract final class SvgCssMath {
  /// Returns `true` if [raw] starts with a supported CSS math function.
  /// 判断 [raw] 是否以受支持的 CSS 数学函数开头。
  ///
  /// - [raw]: Raw CSS value string. 原始 CSS 属性值字符串。
  static bool isMathFunction(String raw) {
    final s = raw.trim().toLowerCase();
    return s.startsWith('calc(') ||
        s.startsWith('min(') ||
        s.startsWith('max(') ||
        s.startsWith('clamp(');
  }

  /// Evaluates a CSS math expression [raw] into pixels or a unitless `double`,
  /// resolving `%` against [referenceExtent] (or `[0..1]` if omitted).
  /// 计算 CSS 数学表达式 [raw] 的数值结果，百分比按 [referenceExtent] 解析（未传入时归一化到 `[0..1]`）。
  ///
  /// - [raw]: CSS math expression string. CSS 数学表达式字符串。
  /// - [referenceExtent]: Optional reference extent for resolving `%` units.
  ///   可选百分比参考基准尺寸。
  static double? evaluate(String raw, {double? referenceExtent}) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      final parser = _CssMathParser(s, referenceExtent: referenceExtent);
      final val = parser.parseExpression();
      parser.skipWs();
      if (!parser.isDone || val.isNaN || val.isInfinite) return null;
      return val;
    } catch (_) {
      return null;
    }
  }
}

class _CssMathParser {
  final String _src;
  final int _len;
  final double? referenceExtent;
  int _pos = 0;

  _CssMathParser(this._src, {this.referenceExtent}) : _len = _src.length;

  bool get isDone => _pos >= _len;

  void skipWs() {
    while (_pos < _len) {
      final c = _src.codeUnitAt(_pos);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        _pos++;
      } else {
        break;
      }
    }
  }

  double parseExpression() {
    double left = _parseTerm();
    while (true) {
      skipWs();
      if (isDone) break;
      final c = _src.codeUnitAt(_pos);
      if (c == 0x2B) {
        // '+'
        _pos++;
        left += _parseTerm();
      } else if (c == 0x2D) {
        // '-'
        _pos++;
        left -= _parseTerm();
      } else {
        break;
      }
    }
    return left;
  }

  double _parseTerm() {
    double left = _parseFactor();
    while (true) {
      skipWs();
      if (isDone) break;
      final c = _src.codeUnitAt(_pos);
      if (c == 0x2A) {
        // '*'
        _pos++;
        left *= _parseFactor();
      } else if (c == 0x2F) {
        // '/'
        _pos++;
        final rhs = _parseFactor();
        if (rhs == 0.0) throw StateError('Division by zero');
        left /= rhs;
      } else {
        break;
      }
    }
    return left;
  }

  double _parseFactor() {
    skipWs();
    if (isDone) throw StateError('Unexpected end of expression');

    final c = _src.codeUnitAt(_pos);
    if (c == 0x2B) {
      _pos++;
      return _parseFactor();
    }
    if (c == 0x2D) {
      _pos++;
      return -_parseFactor();
    }
    if (c == 0x28) {
      // '('
      _pos++;
      final val = parseExpression();
      skipWs();
      if (isDone || _src.codeUnitAt(_pos) != 0x29) {
        throw StateError('Missing closing paren');
      }
      _pos++;
      return val;
    }

    // Named CSS math functions: calc(), min(), max(), clamp()
    if (_isAlpha(c)) {
      final start = _pos;
      while (_pos < _len && _isAlpha(_src.codeUnitAt(_pos))) {
        _pos++;
      }
      final fn = _src.substring(start, _pos).toLowerCase();
      skipWs();
      if (isDone || _src.codeUnitAt(_pos) != 0x28) {
        throw StateError('Expected ( after $fn');
      }
      _pos++; // '('
      final args = <double>[];
      while (true) {
        args.add(parseExpression());
        skipWs();
        if (isDone) throw StateError('Unclosed $fn(');
        final sep = _src.codeUnitAt(_pos);
        if (sep == 0x2C) {
          _pos++;
          continue;
        }
        if (sep == 0x29) {
          _pos++;
          break;
        }
        throw StateError('Unexpected char in $fn()');
      }
      switch (fn) {
        case 'calc':
          return args.first;
        case 'min':
          return args.reduce(math.min);
        case 'max':
          return args.reduce(math.max);
        case 'clamp':
          if (args.length != 3) throw StateError('clamp requires 3 args');
          return math.max(args[0], math.min(args[1], args[2]));
        default:
          throw StateError('Unsupported function $fn');
      }
    }

    return _parseNumberWithUnit();
  }

  double _parseNumberWithUnit() {
    final start = _pos;
    bool hasDot = false;
    while (_pos < _len) {
      final c = _src.codeUnitAt(_pos);
      if (c >= 0x30 && c <= 0x39) {
        _pos++;
      } else if (c == 0x2E && !hasDot) {
        hasDot = true;
        _pos++;
      } else {
        break;
      }
    }
    if (_pos == start) throw StateError('Expected number');
    final numVal = double.parse(_src.substring(start, _pos));

    final unitStart = _pos;
    if (_pos < _len && _src.codeUnitAt(_pos) == 0x25) {
      _pos++;
      final ratio = numVal / 100.0;
      return referenceExtent != null ? ratio * referenceExtent! : ratio;
    }
    while (_pos < _len && _isAlpha(_src.codeUnitAt(_pos))) {
      _pos++;
    }
    final unit = _src.substring(unitStart, _pos).toLowerCase();
    switch (unit) {
      case '':
      case 'px':
      case 'deg':
        return numVal;
      case 'pt':
        return numVal * (96.0 / 72.0);
      case 'pc':
        return numVal * 16.0;
      case 'mm':
        return numVal * (96.0 / 25.4);
      case 'cm':
        return numVal * (96.0 / 2.54);
      case 'in':
        return numVal * 96.0;
      case 'rad':
        return numVal * (180.0 / math.pi);
      case 'turn':
        return numVal * 360.0;
      case 'grad':
        return numVal * 0.9;
      default:
        return numVal;
    }
  }

  static bool _isAlpha(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
}
