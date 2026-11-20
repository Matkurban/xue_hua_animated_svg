import '../animation/svg_animation_timing.dart';
import 'svg_css_value_parser.dart';

/// Syncbase anchor edge on a referenced SMIL animation (`id.begin` or `id.end`).
enum SvgSyncbaseEdge { begin, end }

/// Parsed SMIL syncbase timing token (e.g., `anim1.end+0.5s`, `anim2.begin-200ms`).
class SvgSmilSyncbaseRef {
  final String targetAnimId;
  final SvgSyncbaseEdge edge;
  final int offsetUs;

  const SvgSmilSyncbaseRef({
    required this.targetAnimId,
    required this.edge,
    this.offsetUs = 0,
  });

  static final RegExp _pattern = RegExp(
    r'^([A-Za-z_][\w-]*)\.(begin|end)(?:\s*([+-])\s*(.+))?$',
    caseSensitive: false,
  );

  /// Parses a single semicolon-delimited `begin` token into a syncbase reference,
  /// or returns `null` if it is a plain clock value or unsupported event token.
  static SvgSmilSyncbaseRef? parse(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final m = _pattern.firstMatch(s);
    if (m == null) return null;

    final id = m.group(1)!;
    final edgeStr = m.group(2)!.toLowerCase();
    final edge = edgeStr == 'begin'
        ? SvgSyncbaseEdge.begin
        : SvgSyncbaseEdge.end;

    int offsetUs = 0;
    final sign = m.group(3);
    final rawOffset = m.group(4);
    if (sign != null && rawOffset != null) {
      final parsed = SvgCssValueParser.parseClockMicroseconds(rawOffset);
      if (parsed == null) return null;
      offsetUs = sign == '-' ? -parsed : parsed;
    }

    return SvgSmilSyncbaseRef(
      targetAnimId: id,
      edge: edge,
      offsetUs: offsetUs,
    );
  }
}

class _PendingSyncbaseEntry {
  final SvgAnimationTiming timing;
  final List<SvgSmilSyncbaseRef> refs;

  const _PendingSyncbaseEntry({required this.timing, required this.refs});
}

/// Deterministically resolves SMIL syncbase timing chains (`begin="a1.end+0.5s"`)
/// across all compiled animation elements in a document at compile time.
class SvgSmilSyncbaseResolver {
  final Map<String, SvgAnimationTiming> _timingsById =
      <String, SvgAnimationTiming>{};
  final List<_PendingSyncbaseEntry> _pending = <_PendingSyncbaseEntry>[];

  /// Registers a compiled SMIL animation timing by its optional XML `id`.
  void registerTiming(String? id, SvgAnimationTiming timing) {
    if (id != null && id.isNotEmpty) {
      _timingsById[id] = timing;
    }
  }

  /// Queues unresolved syncbase `begin` references for [timing].
  void addPendingRefs(
    SvgAnimationTiming timing,
    List<SvgSmilSyncbaseRef> refs,
  ) {
    if (refs.isEmpty) return;
    _pending.add(_PendingSyncbaseEntry(timing: timing, refs: refs));
  }

  /// Resolves all queued syncbase references with cycle protection and appends
  /// concrete microsecond offsets to each dependent timing's `beginOffsetsUs`.
  void resolveAll() {
    if (_pending.isEmpty) return;
    final pendingByTiming = <SvgAnimationTiming, List<SvgSmilSyncbaseRef>>{
      for (final e in _pending) e.timing: e.refs,
    };
    final resolvedTimings = <SvgAnimationTiming>{};
    final visiting = <SvgAnimationTiming>{};

    void resolveTiming(SvgAnimationTiming timing) {
      if (resolvedTimings.contains(timing) || visiting.contains(timing)) return;
      final refs = pendingByTiming[timing];
      if (refs == null) {
        resolvedTimings.add(timing);
        return;
      }
      visiting.add(timing);
      for (final ref in refs) {
        final target = _timingsById[ref.targetAnimId];
        if (target == null) continue;
        resolveTiming(target);
        final anchorUs = _resolveAnchorUs(target, ref.edge);
        if (anchorUs != null) {
          timing.beginOffsetsUs.add(anchorUs + ref.offsetUs);
        }
      }
      visiting.remove(timing);
      resolvedTimings.add(timing);
    }

    for (final entry in _pending) {
      resolveTiming(entry.timing);
    }
  }

  int? _resolveAnchorUs(SvgAnimationTiming target, SvgSyncbaseEdge edge) {
    if (target.beginOffsetsUs.isEmpty) return null;
    int earliestBegin = target.beginOffsetsUs[0];
    for (int i = 1; i < target.beginOffsetsUs.length; i++) {
      if (target.beginOffsetsUs[i] < earliestBegin) {
        earliestBegin = target.beginOffsetsUs[i];
      }
    }
    if (edge == SvgSyncbaseEdge.begin) {
      return earliestBegin;
    }
    // End edge: explicit `endUs` or finite `begin + duration * repeatCount`
    if (target.endUs != null) {
      return target.endUs!;
    }
    if (target.repeatCount.isInfinite || target.durationUs <= 0) {
      return null;
    }
    return earliestBegin + (target.durationUs * target.repeatCount).round();
  }
}
