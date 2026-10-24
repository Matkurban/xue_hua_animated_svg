import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../controller/animated_svg_controller.dart';
import '../io/svg_file_reader.dart';
import '../parser/svg_xml_parser.dart';

String? _svgFilePathOrNull(Object? file) {
  if (file == null) return null;
  try {
    return svgFilePath(file);
  } catch (_) {
    return null;
  }
}

/// High-performance, zero-native-dependency animated SVG rendering widget.
///
/// Precompiles the SVG XML into a strongly-typed AST scene graph once, caches
/// static subtrees into `ui.Picture` layers, and drives 60fps/120fps animations
/// directly inside [AnimatedSvgPainter] via `CustomPainter(repaint: controller)`
/// without rebuilding the widget tree or allocating objects on the Dart heap.
///
/// Load sources:
/// - [AnimatedSvgPicture.string] / [AnimatedSvgPicture.compiled] — sync
/// - [AnimatedSvgPicture.asset] / [AnimatedSvgPicture.network] — async
/// - [AnimatedSvgPicture.file] — async; requires `dart:io` (unsupported on web)
class AnimatedSvgPicture extends StatefulWidget {
  /// Raw SVG XML string to precompile and render.
  final String? svgString;

  /// Optional asset path to load from [bundle] or [rootBundle].
  final String? assetName;

  /// Optional asset bundle used when loading [assetName].
  final AssetBundle? bundle;

  /// Optional package name used when loading [assetName] from a package dependency.
  final String? package;

  /// Optional local `dart:io` File used by [AnimatedSvgPicture.file].
  ///
  /// Typed as [Object] so the library analyzes on web; pass a `dart:io` File
  /// at the call site. Unsupported on web (see [readSvgFileAsString]).
  final Object? file;

  /// Optional network URL used by [AnimatedSvgPicture.network].
  final String? networkUrl;

  /// Optional HTTP headers for [AnimatedSvgPicture.network].
  final Map<String, String>? headers;

  /// Optional HTTP client for [AnimatedSvgPicture.network] (tests / custom clients).
  final http.Client? httpClient;

  /// Optional precompiled [CompiledSvgScene] if compiled ahead of time.
  final CompiledSvgScene? compiledScene;

  /// Optional external playback controller (`play`, `pause`, `seek`, `reset`, `setSpeed`).
  final AnimatedSvgController? controller;

  /// Desired width of the widget (defaults to the SVG's intrinsic width or parent constraints).
  final double? width;

  /// Desired height of the widget (defaults to the SVG's intrinsic height or parent constraints).
  final double? height;

  /// Whether to automatically start playing when no external [controller] is provided.
  final bool autoPlay;

  /// Initial playback speed multiplier when no external [controller] is provided.
  final double speed;

  /// Whether to clip the canvas to the widget's bounds.
  final Clip clipBehavior;

  /// How to inscribe the SVG's intrinsic size into the widget layout box.
  ///
  /// Defaults to [BoxFit.contain], matching `flutter_svg` / `SvgPicture`.
  /// Leftover space uses [Alignment.center] (not exposed as a parameter).
  ///
  /// Widget [fit] maps the intrinsic paint box into the layout size. The SVG's
  /// own `preserveAspectRatio` still applies when painting viewBox → intrinsic.
  final BoxFit fit;

  /// Optional whole-picture tint applied after painting (Flutter [ColorFilter]).
  ///
  /// Same role as `SvgPicture.colorFilter` — a post-process layer tint
  /// (commonly `ColorFilter.mode(color, BlendMode.srcIn)`). This is **not**
  /// SVG `<filter>` / `fe*` support (still Out-of-Scope).
  final ColorFilter? colorFilter;

  /// Creates an [AnimatedSvgPicture] from an SVG XML string.
  const AnimatedSvgPicture.string(
    String svgXml, {
    super.key,
    this.controller,
    this.width,
    this.height,
    this.autoPlay = true,
    this.speed = 1.0,
    this.clipBehavior = Clip.hardEdge,
    this.fit = BoxFit.contain,
    this.colorFilter,
  }) : svgString = svgXml,
       assetName = null,
       bundle = null,
       package = null,
       file = null,
       networkUrl = null,
       headers = null,
       httpClient = null,
       compiledScene = null;

  /// Creates an [AnimatedSvgPicture] from a Flutter asset bundle path (e.g., `'assets/svgs/elephant.svg'`).
  const AnimatedSvgPicture.asset(
    String assetPath, {
    super.key,
    this.bundle,
    this.package,
    this.controller,
    this.width,
    this.height,
    this.autoPlay = true,
    this.speed = 1.0,
    this.clipBehavior = Clip.hardEdge,
    this.fit = BoxFit.contain,
    this.colorFilter,
  }) : assetName = assetPath,
       svgString = null,
       file = null,
       networkUrl = null,
       headers = null,
       httpClient = null,
       compiledScene = null;

  /// Creates an [AnimatedSvgPicture] from a local `dart:io` File.
  ///
  /// Pass a `dart:io` [File] instance. Unsupported on web and other platforms
  /// without `dart:io`; use [AnimatedSvgPicture.network],
  /// [AnimatedSvgPicture.asset], or [AnimatedSvgPicture.string] instead.
  ///
  /// The parameter is typed as [Object] for multi-platform analysis; at runtime
  /// it must be a `dart:io` File.
  const AnimatedSvgPicture.file(
    Object this.file, {
    super.key,
    this.controller,
    this.width,
    this.height,
    this.autoPlay = true,
    this.speed = 1.0,
    this.clipBehavior = Clip.hardEdge,
    this.fit = BoxFit.contain,
    this.colorFilter,
  }) : svgString = null,
       assetName = null,
       bundle = null,
       package = null,
       networkUrl = null,
       headers = null,
       httpClient = null,
       compiledScene = null;

  /// Creates an [AnimatedSvgPicture] by downloading SVG XML from [url].
  ///
  /// Uses `package:http`. Non-2xx responses and network errors are logged with
  /// [debugPrint] and leave an empty [SizedBox] (same pattern as asset load failures).
  const AnimatedSvgPicture.network(
    String url, {
    super.key,
    this.headers,
    this.httpClient,
    this.controller,
    this.width,
    this.height,
    this.autoPlay = true,
    this.speed = 1.0,
    this.clipBehavior = Clip.hardEdge,
    this.fit = BoxFit.contain,
    this.colorFilter,
  }) : networkUrl = url,
       svgString = null,
       assetName = null,
       bundle = null,
       package = null,
       file = null,
       compiledScene = null;

  /// Creates an [AnimatedSvgPicture] from a precompiled [CompiledSvgScene].
  const AnimatedSvgPicture.compiled(
    CompiledSvgScene scene, {
    super.key,
    this.controller,
    this.width,
    this.height,
    this.autoPlay = true,
    this.speed = 1.0,
    this.clipBehavior = Clip.hardEdge,
    this.fit = BoxFit.contain,
    this.colorFilter,
  }) : compiledScene = scene,
       svgString = null,
       assetName = null,
       bundle = null,
       package = null,
       file = null,
       networkUrl = null,
       headers = null,
       httpClient = null;

  @override
  State<AnimatedSvgPicture> createState() => _AnimatedSvgPictureState();
}

class _AnimatedSvgPictureState extends State<AnimatedSvgPicture>
    with SingleTickerProviderStateMixin {
  CompiledSvgScene? _internalScene;
  AnimatedSvgController? _internalController;
  Ticker? _ticker;
  int _loadGeneration = 0;

  CompiledSvgScene? get _activeScene => widget.compiledScene ?? _internalScene;
  AnimatedSvgController get _activeController =>
      widget.controller ?? _internalController!;

  bool get _needsAsyncLoad =>
      widget.assetName != null ||
      widget.file != null ||
      widget.networkUrl != null;

  @override
  void initState() {
    super.initState();
    _compileSyncSceneIfNeeded();
    _setupController();
    _ticker = createTicker(_onTick);
    if (_needsAsyncLoad) {
      _loadAsyncScene();
    }
    _syncTickerState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.assetName != null && _internalScene == null) {
      _loadAsyncScene();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedSvgPicture oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged =
        widget.svgString != oldWidget.svgString ||
        widget.compiledScene != oldWidget.compiledScene ||
        widget.assetName != oldWidget.assetName ||
        widget.package != oldWidget.package ||
        widget.bundle != oldWidget.bundle ||
        _svgFilePathOrNull(widget.file) != _svgFilePathOrNull(oldWidget.file) ||
        widget.networkUrl != oldWidget.networkUrl ||
        !mapEquals(widget.headers, oldWidget.headers) ||
        widget.httpClient != oldWidget.httpClient;
    if (sourceChanged) {
      _internalScene?.dispose();
      _internalScene = null;
      if (_needsAsyncLoad) {
        _loadAsyncScene();
      } else {
        _compileSyncSceneIfNeeded();
        _bindControllerToScene();
      }
    }
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_syncTickerState);
      _internalController?.removeListener(_syncTickerState);
      _internalController?.dispose();
      _internalController = null;
      _setupController();
    }
    _syncTickerState();
  }

  void _compileSyncSceneIfNeeded() {
    if (widget.compiledScene == null && widget.svgString != null) {
      _internalScene = SvgParser.compile(widget.svgString!);
    }
  }

  Future<void> _loadAsyncScene() async {
    final gen = ++_loadGeneration;
    try {
      final xmlStr = await _readSvgXml();
      if (!mounted || gen != _loadGeneration || xmlStr == null) return;
      final compiled = SvgParser.compile(xmlStr);
      setState(() {
        _internalScene?.dispose();
        _internalScene = compiled;
        _bindControllerToScene();
        _syncTickerState();
      });
    } catch (e) {
      debugPrint('AnimatedSvgPicture async load failed: $e');
    }
  }

  Future<String?> _readSvgXml() async {
    final asset = widget.assetName;
    if (asset != null) {
      final effectiveBundle =
          widget.bundle ??
          (mounted ? DefaultAssetBundle.of(context) : rootBundle);
      final keyName = widget.package == null
          ? asset
          : 'packages/${widget.package}/$asset';
      try {
        return await effectiveBundle.loadString(keyName);
      } catch (e) {
        debugPrint('AnimatedSvgPicture.asset failed to load "$keyName": $e');
        return null;
      }
    }

    final file = widget.file;
    if (file != null) {
      try {
        return await readSvgFileAsString(file);
      } catch (e) {
        debugPrint(
          'AnimatedSvgPicture.file failed to load '
          '"${_svgFilePathOrNull(file) ?? file}": $e',
        );
        return null;
      }
    }

    final url = widget.networkUrl;
    if (url != null) {
      final client = widget.httpClient;
      final ownsClient = client == null;
      final effectiveClient = client ?? http.Client();
      try {
        final response = await effectiveClient.get(
          Uri.parse(url),
          headers: widget.headers,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          debugPrint(
            'AnimatedSvgPicture.network failed to load "$url": '
            'HTTP ${response.statusCode}',
          );
          return null;
        }
        return response.body;
      } catch (e) {
        debugPrint('AnimatedSvgPicture.network failed to load "$url": $e');
        return null;
      } finally {
        if (ownsClient) {
          effectiveClient.close();
        }
      }
    }

    return null;
  }

  void _setupController() {
    if (widget.controller == null) {
      _internalController = AnimatedSvgController(
        autoPlay: widget.autoPlay,
        speed: widget.speed,
      );
    }
    _bindControllerToScene();
    _activeController.addListener(_syncTickerState);
  }

  void _bindControllerToScene() {
    final scene = _activeScene;
    if (scene == null) return;
    _activeController.attachSceneDurations(
      cycleDuration: scene.timeline.cycleDuration,
      finiteDuration: scene.timeline.finiteDuration,
    );
  }

  void _onTick(Duration elapsed) {
    _activeController.onTick(elapsed);
  }

  void _syncTickerState() {
    final ticker = _ticker;
    final scene = _activeScene;
    if (ticker == null || scene == null) return;
    final shouldTick =
        _activeController.isPlaying && scene.timeline.hasAnimations;
    if (shouldTick && !ticker.isActive) {
      ticker.start();
    } else if (!shouldTick && ticker.isActive) {
      ticker.stop();
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _ticker?.dispose();
    widget.controller?.removeListener(_syncTickerState);
    _internalController?.removeListener(_syncTickerState);
    _internalController?.dispose();
    _internalScene?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _activeScene;
    if (scene == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final intrinsic = scene.document.intrinsicSize;
    final targetSize = ui.Size(
      widget.width ?? intrinsic.width,
      widget.height ?? intrinsic.height,
    );

    Widget painted = CustomPaint(
      size: targetSize,
      isComplex: true,
      willChange: scene.timeline.hasAnimations,
      painter: AnimatedSvgPainter(
        scene: scene,
        controller: _activeController,
        clipBehavior: widget.clipBehavior,
        fit: widget.fit,
      ),
    );
    final filter = widget.colorFilter;
    if (filter != null) {
      painted = ColorFiltered(colorFilter: filter, child: painted);
    }
    return painted;
  }
}

/// Zero-allocation [CustomPainter] that advances the precompiled [SvgTimelineEngine]
/// and paints the [SvgDocument] scene graph directly onto the [ui.Canvas].
class AnimatedSvgPainter extends CustomPainter {
  final CompiledSvgScene scene;
  final AnimatedSvgController controller;
  final Clip clipBehavior;
  final BoxFit fit;

  AnimatedSvgPainter({
    required this.scene,
    required this.controller,
    this.clipBehavior = Clip.hardEdge,
    this.fit = BoxFit.contain,
  }) : super(repaint: controller);

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (size.isEmpty) return;

    // 1. Evaluate all precompiled SMIL & CSS animation tracks in-place
    scene.timeline.seekMicroseconds(controller.elapsedMicroseconds);

    final intrinsic = scene.document.intrinsicSize;
    if (intrinsic.width <= 0.0 || intrinsic.height <= 0.0) {
      return;
    }

    // 2. Fit the SVG intrinsic box into the widget layout size (flutter_svg-aligned).
    //    Alignment inside leftover space is center (matches SvgPicture default).
    final fitted = applyBoxFit(fit, intrinsic, size);
    if (fitted.source.isEmpty || fitted.destination.isEmpty) {
      return;
    }
    const alignment = Alignment.center;
    final inputSubrect = alignment.inscribe(
      fitted.source,
      ui.Offset.zero & intrinsic,
    );
    final outputSubrect = alignment.inscribe(
      fitted.destination,
      ui.Offset.zero & size,
    );

    canvas.save();
    if (clipBehavior != Clip.none) {
      canvas.clipRect(ui.Offset.zero & size);
    }

    final scaleX = outputSubrect.width / inputSubrect.width;
    final scaleY = outputSubrect.height / inputSubrect.height;
    canvas.translate(outputSubrect.left, outputSubrect.top);
    canvas.scale(scaleX, scaleY);
    canvas.translate(-inputSubrect.left, -inputSubrect.top);

    // Paint into the intrinsic viewport; SVG preserveAspectRatio still applies
    // for viewBox → intrinsic. Widget [fit] then maps intrinsic → [size].
    scene.document.paint(canvas, intrinsic);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AnimatedSvgPainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.controller != controller ||
        oldDelegate.clipBehavior != clipBehavior ||
        oldDelegate.fit != fit;
  }
}

/// Built-in composite SVG showcase presets demonstrating:
/// 1. **3D CSS Perspective Rotation + Shimmering Gradient + Stroke Dash Growth + Motion Path + Path Morphing**
/// 2. **Static Subtree Picture Caching vs Dynamic Animated Layers**
abstract final class AnimatedSvgShowcasePresets {
  /// Composite showcase SVG combining:
  /// - **3D Rotation (`@keyframes` with `perspective`, `rotateY`, `rotateZ` and `transform-origin: 50% 50%`)**
  /// - **Streaming Gradient (`<linearGradient>` with animated `<stop>` colors/offsets & `<animateTransform>`)**
  /// - **Stroke Dash Growth (`stroke-dasharray` + `stroke-dashoffset` with `pathLength="100"` & `keySplines` cubic bezier)**
  /// - **Isomorphic Path Morphing (`<animate attributeName="d" />`)**
  /// - **Tangent-Aligned `<animateMotion rotate="auto">` along `<mpath>`**
  /// - **Static Subtree (`isAnimated == false`) recorded once into `ui.Picture`**
  static const String cyberCoreCompositeSvg = '''
<svg viewBox="0 0 240 240" width="240" height="240" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <!-- Dynamic Streaming Linear Gradient -->
    <linearGradient id="cyberFlowGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#00F5D4">
        <animate attributeName="stop-color"
          values="#00F5D4;#7B2CBF;#FF007F;#00F5D4"
          dur="4s" repeatCount="indefinite" />
      </stop>
      <stop offset="50%" stop-color="#7B2CBF">
        <animate attributeName="offset"
          values="0.25;0.75;0.25"
          dur="3s" repeatCount="indefinite"
          calcMode="spline" keyTimes="0;0.5;1"
          keySplines="0.42 0 0.58 1;0.42 0 0.58 1" />
        <animate attributeName="stop-color"
          values="#7B2CBF;#00BBF9;#00F5D4;#7B2CBF"
          dur="4s" repeatCount="indefinite" />
      </stop>
      <stop offset="100%" stop-color="#FF007F">
        <animate attributeName="stop-color"
          values="#FF007F;#00F5D4;#7B2CBF;#FF007F"
          dur="4s" repeatCount="indefinite" />
      </stop>
      <animateTransform attributeName="gradientTransform"
        type="rotate" from="0 0.5 0.5" to="360 0.5 0.5"
        dur="6s" repeatCount="indefinite" />
    </linearGradient>

    <!-- Dynamic Radial Glow Gradient -->
    <radialGradient id="corePulseGrad" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#00F5D4" stop-opacity="0.85" />
      <stop offset="100%" stop-color="#7B2CBF" stop-opacity="0.0" />
      <animate attributeName="r" values="0.32;0.52;0.32" dur="2.4s" repeatCount="indefinite" />
    </radialGradient>

    <!-- Motion Orbit Path referenced via <mpath> -->
    <path id="orbitTrack" d="M 120 36 A 84 84 0 1 1 119.9 36 Z" fill="none" />
  </defs>

  <style>
    .ring-3d {
      transform-origin: 50% 50%;
      animation: flip3d 4s cubic-bezier(0.42, 0.0, 0.58, 1.0) infinite;
    }
    @keyframes flip3d {
      0% {
        transform: perspective(500px) rotateX(0deg) rotateY(0deg) rotateZ(0deg) scale(0.95);
      }
      50% {
        transform: perspective(500px) rotateX(28deg) rotateY(180deg) rotateZ(180deg) scale(1.06);
      }
      100% {
        transform: perspective(500px) rotateX(0deg) rotateY(360deg) rotateZ(360deg) scale(0.95);
      }
    }
  </style>

  <!-- 1. Static Background Grid Subtree (Automatically cached into ui.Picture) -->
  <g id="staticBackdrop" opacity="0.28">
    <circle cx="120" cy="120" r="108" fill="none" stroke="#3A506B" stroke-width="1" />
    <circle cx="120" cy="120" r="96" fill="none" stroke="#1C2541" stroke-width="1" />
    <line x1="12" y1="120" x2="228" y2="120" stroke="#3A506B" stroke-width="0.75" />
    <line x1="120" y1="12" x2="120" y2="228" stroke="#3A506B" stroke-width="0.75" />
    <polygon points="120,16 210,68 210,172 120,224 30,172 30,68"
      fill="none" stroke="#3A506B" stroke-width="1" />
  </g>

  <!-- 2. Radial Glow Pulse -->
  <circle cx="120" cy="120" r="78" fill="url(#corePulseGrad)" />

  <!-- 3. Stroke Dash Growth Outer Ring (pathLength="100" + Spline Easing) -->
  <circle id="growingStrokeRing" cx="120" cy="120" r="84"
    fill="none" stroke="url(#cyberFlowGrad)" stroke-width="6"
    stroke-linecap="round" pathLength="100"
    stroke-dasharray="75 25" stroke-dashoffset="100">
    <animate attributeName="stroke-dashoffset"
      values="100;0;-100"
      keyTimes="0;0.5;1"
      calcMode="spline"
      keySplines="0.4 0 0.2 1;0.4 0 0.2 1"
      dur="3.2s" repeatCount="indefinite" />
  </circle>

  <!-- 4. CSS 3D Rotating Geometric Ring with Streaming Gradient -->
  <g id="css3dGroup" class="ring-3d">
    <rect x="68" y="68" width="104" height="104" rx="22" ry="22"
      fill="none" stroke="url(#cyberFlowGrad)" stroke-width="4" />
    <circle cx="120" cy="120" r="42"
      fill="none" stroke="#00F5D4" stroke-width="2"
      stroke-dasharray="10 8" />
  </g>

  <!-- 5. Isomorphic Path Morphing Core Star <-> Octagon Crystal -->
  <path id="morphingCore"
    d="M 120 82 L 132 108 L 158 120 L 132 132 L 120 158 L 108 132 L 82 120 L 108 108 Z"
    fill="url(#cyberFlowGrad)" fill-opacity="0.85"
    stroke="#FFFFFF" stroke-width="1.5" stroke-linejoin="round">
    <animate attributeName="d"
      dur="2.8s" repeatCount="indefinite"
      calcMode="spline" keyTimes="0;0.5;1"
      keySplines="0.45 0.05 0.55 0.95;0.45 0.05 0.55 0.95"
      values="
        M 120 82 L 132 108 L 158 120 L 132 132 L 120 158 L 108 132 L 82 120 L 108 108 Z;
        M 120 92 L 142 98 L 148 120 L 142 142 L 120 148 L 98 142 L 92 120 L 98 98 Z;
        M 120 82 L 132 108 L 158 120 L 132 132 L 120 158 L 108 132 L 82 120 L 108 108 Z" />
    <animateTransform attributeName="transform"
      type="rotate" from="0 120 120" to="-360 120 120"
      dur="8s" repeatCount="indefinite" />
  </path>

  <!-- 6. Tangent-Aligned <animateMotion rotate="auto"> Spaceship/Probe on Orbit -->
  <g id="orbitingProbe">
    <path d="M -8 -5 L 10 0 L -8 5 L -4 0 Z" fill="#00F5D4" stroke="#FFFFFF" stroke-width="1" />
    <animateMotion dur="3.2s" repeatCount="indefinite" rotate="auto">
      <mpath href="#orbitTrack" />
    </animateMotion>
  </g>
</svg>
''';
}
