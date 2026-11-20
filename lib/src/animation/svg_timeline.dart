import '../model/svg_gradient.dart';
import '../model/svg_node.dart';
import 'svg_animation_timing.dart';

export 'svg_animation_timing.dart';
export 'svg_property_tracks.dart';
export 'svg_step_easing.dart';
export 'svg_transform_tracks.dart';

/// High-performance precompiled timeline engine driving all SMIL and CSS
/// animations in an `SvgDocument` with zero heap allocations per frame.
/// 高性能预编译时间轴引擎，每帧零堆分配驱动 `SvgDocument` 中的全部 SMIL 与 CSS 动画。
class SvgTimelineEngine {
  /// Elements that participate in at least one animation track and require frame resets.
  /// 参与至少一条动画轨道、每帧需要重置状态的 SVG 元素列表。
  final List<SvgElement> animatedElements;

  /// Gradients (or gradient stops) driven by animation tracks.
  /// 受动画轨道驱动的渐变节点列表。
  final List<SvgGradientNode> animatedGradients;

  /// All precompiled SMIL and CSS animation tracks evaluated in document order.
  /// 按文档顺序求值的全部预编译 SMIL 与 CSS 动画轨道。
  final List<SvgAnimationTrack> tracks;

  /// Finite duration of the timeline, or `null` if any track repeats indefinitely.
  /// 时间轴的有限总时长；若存在无限循环轨道则为 `null`。
  final Duration? finiteDuration;

  /// Representative cycle duration used for UI progress bars / looping controllers.
  /// 用于 UI 进度条与循环控制器的代表性单周期时长。
  final Duration cycleDuration;

  /// Creates an [SvgTimelineEngine].
  /// 创建一个 [SvgTimelineEngine] 实例。
  ///
  /// - [animatedElements]: Animated scene elements reset before each tick. 每帧重置的动画元素列表。
  /// - [animatedGradients]: Animated gradients reset before each tick. 每帧重置的动画渐变列表。
  /// - [tracks]: Ordered animation tracks to apply. 按序应用的动画轨道列表。
  /// - [finiteDuration]: Total finite duration, or `null` when infinite. 有限总时长或 `null`。
  /// - [cycleDuration]: Representative cycle duration. 代表性单周期时长。
  SvgTimelineEngine({
    required this.animatedElements,
    required this.animatedGradients,
    required this.tracks,
    required this.finiteDuration,
    required this.cycleDuration,
  });

  /// Whether this timeline contains at least one active animation track.
  /// 当前时间轴是否包含至少一条动画轨道。
  bool get hasAnimations => tracks.isNotEmpty;

  /// Evaluates all animation tracks at [elapsedUs] in-place.
  /// 在微秒时间点 [elapsedUs] 处原地求值所有动画轨道。
  ///
  /// - [elapsedUs]: Virtual timeline timestamp in microseconds. 虚拟时间轴微秒时间戳。
  void seekMicroseconds(int elapsedUs) {
    if (tracks.isEmpty) return;

    // 1. Reset animated elements and gradients to their precompiled base states
    for (int i = 0; i < animatedElements.length; i++) {
      animatedElements[i].resetFrameState();
    }
    for (int i = 0; i < animatedGradients.length; i++) {
      animatedGradients[i].resetToBase();
    }

    // 2. Apply all active animation tracks in document order (supporting additive="sum")
    for (int i = 0; i < tracks.length; i++) {
      tracks[i].applyAt(elapsedUs);
    }
  }
}
