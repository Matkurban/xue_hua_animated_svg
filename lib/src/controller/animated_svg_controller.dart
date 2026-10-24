import 'package:flutter/foundation.dart';

/// Playback controller for [AnimatedSvgPicture].
///
/// Extends [ChangeNotifier] so it can be passed directly as `repaint:` to
/// `CustomPainter`, driving 60fps/120fps canvas repaints without rebuilding
/// the Flutter widget tree.
class AnimatedSvgController extends ChangeNotifier {
  bool _isPlaying;
  double _speed;
  int _elapsedMicroseconds = 0;
  Duration? _lastTickerTimestamp;

  /// Representative cycle duration populated when bound to a compiled SVG scene.
  Duration _cycleDuration = const Duration(seconds: 1);

  /// Finite total duration of the bound SVG scene (`null` if infinite).
  Duration? _finiteDuration;

  AnimatedSvgController({bool autoPlay = true, double speed = 1.0})
    : _isPlaying = autoPlay,
      _speed = speed <= 0.0 ? 1.0 : speed;

  /// Whether the animation is currently playing.
  bool get isPlaying => _isPlaying;

  /// Playback speed multiplier (`1.0` = normal speed, `2.0` = 2x speed, `0.5` = half speed).
  double get speed => _speed;

  /// Current virtual timeline position.
  Duration get elapsed => Duration(microseconds: _elapsedMicroseconds);

  /// Current elapsed time in microseconds (used directly by `SvgTimelineEngine`).
  int get elapsedMicroseconds => _elapsedMicroseconds;

  /// Representative cycle duration of the attached SVG document.
  Duration get cycleDuration => _cycleDuration;

  /// Normalized cycle progress in `[0.0 .. 1.0]` for timeline scrubbers.
  double get cycleProgress {
    final cycleUs = _cycleDuration.inMicroseconds;
    if (cycleUs <= 0) return 0.0;
    return ((_elapsedMicroseconds % cycleUs) / cycleUs).clamp(0.0, 1.0);
  }

  /// Internal binding hook called by `AnimatedSvgPicture` when a scene is compiled.
  void attachSceneDurations({
    required Duration cycleDuration,
    required Duration? finiteDuration,
  }) {
    _cycleDuration = cycleDuration;
    _finiteDuration = finiteDuration;
  }

  /// Starts or resumes animation playback.
  void play() {
    if (_isPlaying) return;
    _isPlaying = true;
    _lastTickerTimestamp = null;
    notifyListeners();
  }

  /// Pauses animation playback at the current frame.
  void pause() {
    if (!_isPlaying) return;
    _isPlaying = false;
    _lastTickerTimestamp = null;
    notifyListeners();
  }

  /// Jumps directly to [position] on the animation timeline and triggers a repaint.
  void seek(Duration position) {
    final targetUs = position.inMicroseconds < 0 ? 0 : position.inMicroseconds;
    if (_elapsedMicroseconds == targetUs) return;
    _elapsedMicroseconds = targetUs;
    _lastTickerTimestamp = null;
    notifyListeners();
  }

  /// Resets the timeline position to `Duration.zero` and triggers a repaint.
  void reset() {
    _elapsedMicroseconds = 0;
    _lastTickerTimestamp = null;
    notifyListeners();
  }

  /// Updates the playback speed multiplier (must be `> 0.0`).
  void setSpeed(double newSpeed) {
    assert(newSpeed > 0.0, 'Speed multiplier must be positive.');
    if (newSpeed <= 0.0 || _speed == newSpeed) return;
    _speed = newSpeed;
    notifyListeners();
  }

  /// Advances the virtual timeline from a Flutter `Ticker` callback.
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
