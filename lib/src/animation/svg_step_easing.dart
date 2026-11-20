/// Step jump behavior for W3C CSS Easing Functions Level 1 `steps(N, <pos>)`.
enum SvgStepPosition { jumpStart, jumpEnd, jumpNone, jumpBoth }

/// Precompiled CSS `steps(N, <step-position>)` / `step-start` / `step-end`
/// easing curve (W3C CSS Easing Functions Level 1 §2.3).
class SvgStepEasing {
  final int steps;
  final SvgStepPosition position;

  const SvgStepEasing(this.steps, [this.position = SvgStepPosition.jumpEnd]);

  static const SvgStepEasing stepStart = SvgStepEasing(
    1,
    SvgStepPosition.jumpStart,
  );
  static const SvgStepEasing stepEnd = SvgStepEasing(
    1,
    SvgStepPosition.jumpEnd,
  );

  /// Evaluates the quantized step output for input progress [t] in `[0.0, 1.0]`.
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
