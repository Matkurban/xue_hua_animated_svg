import '../animation/svg_animation_timing.dart';
import 'svg_css_value_parser.dart';

/// Syncbase anchor edge on a referenced SMIL animation (`id.begin` or `id.end`).
/// SMIL Syncbase 同步引用锚点边缘（目标动画的开始或结束时刻）。
enum SvgSyncbaseEdge {
  /// References the start time of the target animation (`id.begin`).
  /// 引用目标动画的开始时刻（`id.begin`）。
  begin,

  /// References the active end time of the target animation (`id.end`).
  /// 引用目标动画的结束时刻（`id.end`）。
  end,
}

/// Parsed SMIL syncbase timing token (e.g., `anim1.end+0.5s`, `anim2.begin-200ms`).
/// 解析后的 SMIL Syncbase 同步时间标记（如 `anim1.end+0.5s`、`anim2.begin-200ms`）。
class SvgSmilSyncbaseRef {
  /// XML `id` of the referenced SMIL animation element.
  /// 被引用 SMIL 动画元素的 XML `id`。
  final String targetAnimId;

  /// Referenced edge (`begin` or `end`) on [targetAnimId].
  /// 引用的锚点边缘（`begin` 或 `end`）。
  final SvgSyncbaseEdge edge;

  /// Signed clock offset in microseconds added to the referenced edge.
  /// 叠加在引用锚点上的带符号微秒偏移量。
  final int offsetUs;

  /// Creates an [SvgSmilSyncbaseRef].
  /// 创建一个 [SvgSmilSyncbaseRef] 同步引用描述。
  ///
  /// - [targetAnimId]: Referenced animation element `id`. 目标动画元素 `id`。
  /// - [edge]: Anchor edge (`begin` or `end`). 锚点边缘。
  /// - [offsetUs]: Signed microsecond offset (defaults to `0`). 带符号微秒偏移（默认 `0`）。
  const SvgSmilSyncbaseRef({
    required this.targetAnimId,
    required this.edge,
    this.offsetUs = 0,
  });

  static final RegExp _pattern = RegExp(
    r'^([A-Za-z_][\w-]*)\.(begin|end)(?:\s*([+-])\s*(.+))?$',
    caseSensitive: false,
  );

  /// Parses a single semicolon-delimited `begin` token [raw] into a syncbase
  /// reference, or returns `null` if it is a plain clock value or unsupported token.
  /// 将单个分号分隔的 `begin` 项 [raw] 解析为 Syncbase 引用；若为普通时钟值或不支持格式则返回 `null`。
  ///
  /// - [raw]: Raw `begin` list token string. 原始 `begin` 列表项字符串。
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

    return SvgSmilSyncbaseRef(targetAnimId: id, edge: edge, offsetUs: offsetUs);
  }
}

class _PendingSyncbaseEntry {
  final SvgAnimationTiming timing;
  final List<SvgSmilSyncbaseRef> refs;

  const _PendingSyncbaseEntry({required this.timing, required this.refs});
}

/// Deterministically resolves SMIL syncbase timing chains (`begin="a1.end+0.5s"`)
/// across all compiled animation elements in a document at compile time.
/// 在编译期确定性地解析整份文档中的 SMIL Syncbase 链式同步时间依赖（如 `begin="a1.end+0.5s"`）。
class SvgSmilSyncbaseResolver {
  final Map<String, SvgAnimationTiming> _timingsById =
      <String, SvgAnimationTiming>{};
  final List<_PendingSyncbaseEntry> _pending = <_PendingSyncbaseEntry>[];

  /// Registers a compiled SMIL animation [timing] by its optional XML [id].
  /// 按可选 XML [id] 注册已编译的 SMIL 动画时间轴 [timing]。
  ///
  /// - [id]: Optional XML `id` of the animation element. 动画元素的可选 XML `id`。
  /// - [timing]: Compiled timing configuration. 已编译的时间轴配置。
  void registerTiming(String? id, SvgAnimationTiming timing) {
    if (id != null && id.isNotEmpty) {
      _timingsById[id] = timing;
    }
  }

  /// Queues unresolved syncbase `begin` references [refs] for [timing].
  /// 将 [timing] 对应的待解析 Syncbase 引用列表 [refs] 加入队列。
  ///
  /// - [timing]: Dependent animation timing object. 依赖方的动画时间轴对象。
  /// - [refs]: Parsed syncbase references to resolve. 待解析的同步引用列表。
  void addPendingRefs(
    SvgAnimationTiming timing,
    List<SvgSmilSyncbaseRef> refs,
  ) {
    if (refs.isEmpty) return;
    _pending.add(_PendingSyncbaseEntry(timing: timing, refs: refs));
  }

  /// Resolves all queued syncbase references with cycle protection and appends
  /// concrete microsecond offsets to each dependent timing's `beginOffsetsUs`.
  /// 带环路保护地解析全部待处理 Syncbase 引用，并将计算出的微秒起始偏移追加至各依赖轨道。
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
