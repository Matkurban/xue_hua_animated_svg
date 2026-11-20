import 'package:flutter/foundation.dart';

/// Playback controller for `AnimatedSvgPicture`.
/// `AnimatedSvgPicture` 的播放控制器。
///
/// Extends [ChangeNotifier] so it can be passed directly as `repaint:` to
/// `CustomPainter`, driving 60fps/120fps canvas repaints without rebuilding
/// the Flutter widget tree.
/// 继承自 [ChangeNotifier]，可直接作为 `CustomPainter` 的 `repaint` 监听源，
/// 在不重建 Flutter 组件树的前提下驱动 60fps/120fps 画布重绘。
class AnimatedSvgController extends ChangeNotifier {
  bool _isPlaying;
  double _speed;
  int _elapsedMicroseconds = 0;
  Duration? _lastTickerTimestamp;

  /// Representative cycle duration populated when bound to a compiled SVG scene.
  /// 绑定到已编译 SVG 场景后的代表性周期时长。
  Duration _cycleDuration = const Duration(seconds: 1);

  /// Finite total duration of the bound SVG scene (`null` if infinite).
  /// 已绑定 SVG 场景的有限总时长（若包含无限循环动画则为 `null`）。
  Duration? _finiteDuration;

  /// Creates an [AnimatedSvgController].
  /// 创建一个 [AnimatedSvgController] 实例。
  ///
  /// - [autoPlay]: Whether playback starts automatically (`true` by default).
  ///   是否自动开始播放（默认 `true`）。
  /// - [speed]: Initial playback speed multiplier; non-positive values fall back to `1.0`.
  ///   初始倍速系数；非正数时回退为 `1.0`。
  AnimatedSvgController({bool autoPlay = true, double speed = 1.0})
    : _isPlaying = autoPlay,
      _speed = speed <= 0.0 ? 1.0 : speed;

  /// Whether the animation is currently playing.
  /// 动画当前是否正在播放。
  bool get isPlaying => _isPlaying;

  /// Playback speed multiplier (`1.0` = normal speed, `2.0` = 2x speed, `0.5` = half speed).
  /// 播放速度倍率（`1.0` 为原速，`2.0` 为 2 倍速，`0.5` 为 0.5 倍速）。
  double get speed => _speed;

  /// Current virtual timeline position.
  /// 当前虚拟时间轴位置。
  Duration get elapsed => Duration(microseconds: _elapsedMicroseconds);

  /// Current elapsed time in microseconds (used directly by `SvgTimelineEngine`).
  /// 当前已经过的微秒数（供 `SvgTimelineEngine` 直接采样）。
  int get elapsedMicroseconds => _elapsedMicroseconds;

  /// Representative cycle duration of the attached SVG document.
  /// 已绑定 SVG 文档的代表性单周期时长。
  Duration get cycleDuration => _cycleDuration;

  /// Normalized cycle progress in `[0.0 .. 1.0]` for timeline scrubbers.
  /// 归一化周期进度（范围 `[0.0 .. 1.0]`），适用于进度条展示。
  double get cycleProgress {
    final cycleUs = _cycleDuration.inMicroseconds;
    if (cycleUs <= 0) return 0.0;
    return ((_elapsedMicroseconds % cycleUs) / cycleUs).clamp(0.0, 1.0);
  }

  /// Internal binding hook called by `AnimatedSvgPicture` when a scene is compiled.
  /// 当场景编译完成时由 `AnimatedSvgPicture` 调用的内部时长绑定钩子。
  ///
  /// - [cycleDuration]: Representative cycle duration of the scene. 场景的代表性周期时长。
  /// - [finiteDuration]: Total finite duration, or `null` for infinite timelines.
  ///   有限总时长，无限循环时间轴为 `null`。
  void attachSceneDurations({
    required Duration cycleDuration,
    required Duration? finiteDuration,
  }) {
    _cycleDuration = cycleDuration;
    _finiteDuration = finiteDuration;
  }

  /// Starts or resumes animation playback.
  /// 开始或恢复动画播放。
  void play() {
    if (_isPlaying) return;
    _isPlaying = true;
    _lastTickerTimestamp = null;
    notifyListeners();
  }

  /// Pauses animation playback at the current frame.
  /// 将动画暂停在当前帧。
  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    _lastTickerTimestamp = null;
    notifyListeners();
  }

  /// Jumps directly to [position] on the animation timeline and triggers a repaint.
  /// 直接跳转到动画时间轴上的 [position] 位置并触发重绘。
  ///
  /// - [position]: Target timeline timestamp (clamped to `Duration.zero` if negative).
  ///   目标时间轴位置（若为负值则钳制到 `Duration.zero`）。
  void seek(Duration position) {
    final targetUs = position.inMicroseconds < 0 ? 0 : position.inMicroseconds;
    if (_elapsedMicroseconds == targetUs) return;
    _elapsedMicroseconds = targetUs;
    _lastTickerTimestamp = null;
    notifyListeners();
  }

  /// Resets the timeline position to `Duration.zero` and triggers a repaint.
  /// 将时间轴重置到 `Duration.zero` 并触发重绘。
  void reset() {
    _elapsedMicroseconds = 0;
    _lastTickerTimestamp = null;
    notifyListeners();
  }

  /// Updates the playback speed multiplier (must be `> 0.0`).
  /// 更新播放速度倍率（必须大于 `0.0`）。
  ///
  /// - [newSpeed]: Positive playback speed factor. 正数播放速度倍率。
  void setSpeed(double newSpeed) {
    assert(newSpeed > 0.0, 'Speed multiplier must be positive.');
    if (newSpeed <= 0.0 || _speed == newSpeed) return;
    _speed = newSpeed;
    notifyListeners();
  }

  /// Advances the virtual timeline from a Flutter `Ticker` callback.
  /// 根据 Flutter `Ticker` 回调推进虚拟时间轴。
  ///
  /// - [tickerElapsed]: Monotonic elapsed duration reported by the active `Ticker`.
  ///   当前活跃 `Ticker` 报告的单调递增时长。
  void onTick(Duration tickerElapsed) {
    if (!_isPlaying) {
      _lastTickerTimestamp = null;
      return;
    }

    final prev = _lastTickerTimestamp;
    _lastTickerTimestamp = tickerElapsed;
    if (prev == null) return;

    final deltaUs = tickerElapsed.inMicroseconds - prev.inMicroseconds;
    if (deltaUs <= 0) return;

    _elapsedMicroseconds += (deltaUs * _speed).round();

    final finiteLimit = _finiteDuration;
    if (finiteLimit != null &&
        _elapsedMicroseconds >= finiteLimit.inMicroseconds) {
      _elapsedMicroseconds = finiteLimit.inMicroseconds;
      _isPlaying = false;
      _lastTickerTimestamp = null;
    }

    notifyListeners();
  }
}
