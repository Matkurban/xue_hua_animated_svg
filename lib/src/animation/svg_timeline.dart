import '../model/svg_gradient.dart';
import '../model/svg_node.dart';
import 'svg_animation_timing.dart';

export 'svg_animation_timing.dart';
export 'svg_property_tracks.dart';
export 'svg_transform_tracks.dart';

/// High-performance precompiled Timeline Engine driving all SMIL and CSS animations
/// in an [SvgDocument] with zero heap allocations per frame.
class SvgTimelineEngine {
  final List<SvgElement> animatedElements;
  final List<SvgGradientNode> animatedGradients;
  final List<SvgAnimationTrack> tracks;

  /// Finite duration of the timeline, or `null` if any track repeats indefinitely.
  final Duration? finiteDuration;

  /// Representative cycle duration used for UI progress bars / looping controllers.
  final Duration cycleDuration;

  SvgTimelineEngine({
    required this.animatedElements,
    required this.animatedGradients,
    required this.tracks,
    required this.finiteDuration,
    required this.cycleDuration,
  });

  bool get hasAnimations => tracks.isNotEmpty;

  /// Evaluates all animation tracks at [elapsedUs] in-place.
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
