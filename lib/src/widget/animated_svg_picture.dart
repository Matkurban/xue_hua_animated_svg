import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../controller/animated_svg_controller.dart';
import '../io/svg_file_reader.dart';
import '../parser/svg_xml_parser.dart';
import 'animated_svg_painter.dart';

export 'animated_svg_painter.dart';
export 'animated_svg_showcase_presets.dart';

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
  /// Defaults to [BoxFit.contain].
  ///
  /// Widget [fit] maps the intrinsic paint box into the layout size. The SVG's
  /// own `preserveAspectRatio` still applies when painting viewBox → intrinsic.
  final BoxFit fit;

  /// How to align the fitted SVG within the widget layout box when [fit]
  /// leaves leftover space (or crops for [BoxFit.cover] / [BoxFit.none]).
  ///
  /// Defaults to [Alignment.center].
  /// [AlignmentDirectional] resolves against ambient [Directionality].
  final AlignmentGeometry alignment;

  /// Optional whole-picture tint applied after painting (Flutter [ColorFilter]).
  ///
  /// A post-process layer tint (commonly
  /// `ColorFilter.mode(color, BlendMode.srcIn)`). This is **not** SVG
  /// `<filter>` / `fe*` support (still Out-of-Scope).
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
    this.alignment = Alignment.center,
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
    this.alignment = Alignment.center,
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
    this.alignment = Alignment.center,
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
    this.alignment = Alignment.center,
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
    this.alignment = Alignment.center,
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

    final resolvedAlignment = widget.alignment.resolve(
      Directionality.maybeOf(context),
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
        alignment: resolvedAlignment,
      ),
    );
    final filter = widget.colorFilter;
    if (filter != null) {
      painted = ColorFiltered(colorFilter: filter, child: painted);
    }
    return painted;
  }
}
