/// Step jump behavior for W3C CSS Easing Functions Level 1 `steps(N, <pos>)`.
/// W3C CSS Easing Functions Level 1 中 `steps(N, <pos>)` 的阶梯跳变位置模式。
enum SvgStepPosition {
  /// Jumps upward immediately at `t = 0` (`jump-start` / `start`).
  /// 在 `t = 0` 处立即向上跳变（`jump-start` / `start`）。
  jumpStart,

  /// Holds the initial value until the first interval ends (`jump-end` / `end`).
  /// 保持初始值直至首个区间结束再跳变（`jump-end` / `end`）。
  jumpEnd,

  /// No jump at either endpoint; `N` steps produce `N - 1` jumps (`jump-none`).
  /// 起止端点均不跳变，`N` 步产生 `N - 1` 次跳变（`jump-none`）。
  jumpNone,

  /// Jumps at both `t = 0` and `t = 1`; `N` steps produce `N + 1` jumps (`jump-both`).
  /// 起止端点均发生跳变，`N` 步产生 `N + 1` 次跳变（`jump-both`）。
  jumpBoth,
}

/// Precompiled CSS `steps(N, <step-position>)` / `step-start` / `step-end`
/// easing curve (W3C CSS Easing Functions Level 1 §2.3).
/// 预编译的 CSS `steps(N, <step-position>)` / `step-start` / `step-end` 阶梯缓动曲线。
class SvgStepEasing {
  /// Number of discrete step intervals (`>= 1`).
  /// 离散步进区间总数（`>= 1`）。
  final int steps;

  /// Endpoint jump behavior for the step curve.
  /// 阶梯曲线的端点跳变模式。
  final SvgStepPosition position;

  /// Creates an [SvgStepEasing] curve with [steps] intervals and jump [position].
  /// 创建一个包含 [steps] 个区间、跳变模式为 [position] 的 [SvgStepEasing] 缓动曲线。
  ///
  /// - [steps]: Number of discrete step intervals. 离散步数。
  /// - [position]: Endpoint jump behavior (defaults to [SvgStepPosition.jumpEnd]).
  ///   跳变位置模式（默认 [SvgStepPosition.jumpEnd]）。
  const SvgStepEasing(this.steps, [this.position = SvgStepPosition.jumpEnd]);

  /// Shorthand for `steps(1, jump-start)` (`step-start`).
  /// `step-start` 简写，等价于 `steps(1, jump-start)`。
  static const SvgStepEasing stepStart = SvgStepEasing(
    1,
    SvgStepPosition.jumpStart,
  );

  /// Shorthand for `steps(1, jump-end)` (`step-end`).
  /// `step-end` 简写，等价于 `steps(1, jump-end)`。
  static const SvgStepEasing stepEnd = SvgStepEasing(
    1,
    SvgStepPosition.jumpEnd,
  );

  /// Evaluates the quantized step output for input progress [t] in `[0.0, 1.0]`.
  /// 计算输入进度 [t]（`[0.0, 1.0]`）对应的量化阶梯输出值。
  ///
  /// - [t]: Normalized input progress in `[0.0, 1.0]`. 归一化输入进度。
  double transform(double t) {
    if (steps <= 0) return t.clamp(0.0, 1.0);
    if (t < 0.0) return 0.0;
    if (t >= 1.0) return 1.0;

    int currentStep = (t * steps).floor();
    if (position == SvgStepPosition.jumpStart ||
        position == SvgStepPosition.jumpBoth) {
      currentStep += 1;
    }

    final int jumps;
    switch (position) {
      case SvgStepPosition.jumpStart:
      case SvgStepPosition.jumpEnd:
        jumps = steps;
      case SvgStepPosition.jumpNone:
        jumps = steps > 1 ? steps - 1 : 1;
      case SvgStepPosition.jumpBoth:
        jumps = steps + 1;
    }

    if (currentStep < 0) currentStep = 0;
    if (currentStep > jumps) currentStep = jumps;
    return (currentStep / jumps).clamp(0.0, 1.0);
  }

  /// Parses `step-start`, `step-end`, or `steps(N[, <step-position>])`.
  /// 解析 `step-start`、`step-end` 或 `steps(N[, <step-position>])` 字符串。
  ///
  /// - [raw]: Raw CSS timing function string. 原始 CSS 缓动函数字符串。
  static SvgStepEasing? parse(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'step-start') return stepStart;
    if (s == 'step-end') return stepEnd;
    if (!s.startsWith('steps(') || !s.endsWith(')')) return null;

    final inner = s.substring(6, s.length - 1).trim();
    if (inner.isEmpty) return null;
    final parts = inner.split(',').map((e) => e.trim()).toList();
    final n = int.tryParse(parts[0]);
    if (n == null || n < 1) return null;

    var pos = SvgStepPosition.jumpEnd;
    if (parts.length >= 2) {
      switch (parts[1]) {
        case 'jump-start':
        case 'start':
          pos = SvgStepPosition.jumpStart;
        case 'jump-end':
        case 'end':
          pos = SvgStepPosition.jumpEnd;
        case 'jump-none':
          if (n < 2) return null;
          pos = SvgStepPosition.jumpNone;
        case 'jump-both':
          pos = SvgStepPosition.jumpBoth;
        default:
          return null;
      }
    }
    return SvgStepEasing(n, pos);
  }
}
