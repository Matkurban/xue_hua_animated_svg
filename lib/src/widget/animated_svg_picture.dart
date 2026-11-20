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
/// 高性能、零原生依赖的动态 SVG 渲染组件。
///
/// Precompiles the SVG XML into a strongly-typed AST scene graph once, caches
/// static subtrees into `ui.Picture` layers, and drives 60fps/120fps animations
/// directly inside [AnimatedSvgPainter] via `CustomPainter(repaint: controller)`
/// without rebuilding the widget tree or allocating objects on the Dart heap.
/// 一次性将 SVG XML 预编译为强类型 AST 场景图，对静态子树自动启用 `ui.Picture` 缓存，
/// 并通过 [AnimatedSvgPainter] 以 60fps/120fps 直接重绘画布，不重建组件树且零堆分配。
///
/// Load sources / 加载来源:
/// - [AnimatedSvgPicture.string] / [AnimatedSvgPicture.compiled] — sync（同步）
/// - [AnimatedSvgPicture.asset] / [AnimatedSvgPicture.network] — async（异步）
/// - [AnimatedSvgPicture.file] — async; requires `dart:io` (unsupported on web)（异步，需 `dart:io`，Web 不支持）
class AnimatedSvgPicture extends StatefulWidget {
  /// Raw SVG XML string to precompile and render.
  /// 待预编译并渲染的原始 SVG XML 字符串。
  final String? svgString;

  /// Optional asset path to load from [bundle] or [rootBundle].
  /// 可选的 Flutter 资源路径，从 [bundle] 或 [rootBundle] 加载。
  final String? assetName;

  /// Optional asset bundle used when loading [assetName].
  /// 加载 [assetName] 时使用的自定义 [AssetBundle]。
  final AssetBundle? bundle;

  /// Optional package name used when loading [assetName] from a package dependency.
  /// 从依赖包加载 [assetName] 时的包名。
  final String? package;

  /// Optional local `dart:io` `File` used by [AnimatedSvgPicture.file].
  /// [AnimatedSvgPicture.file] 使用的本地 `dart:io` `File` 对象。
  ///
  /// Typed as [Object] so the library analyzes on web; pass a `dart:io` `File`
  /// at the call site. Unsupported on web (see [readSvgFileAsString]).
  /// 为兼容 Web 静态分析而声明为 [Object]，调用方需传入 `dart:io` 的 `File`。
  final Object? file;

  /// Optional network URL used by [AnimatedSvgPicture.network].
  /// [AnimatedSvgPicture.network] 使用的网络地址。
  final String? networkUrl;

  /// Optional HTTP headers for [AnimatedSvgPicture.network].
  /// [AnimatedSvgPicture.network] 请求的可选 HTTP 头。
  final Map<String, String>? headers;

  /// Optional HTTP client for [AnimatedSvgPicture.network] (tests / custom clients).
  /// [AnimatedSvgPicture.network] 使用的可选自定义 [http.Client]（便于测试或复用连接）。
  final http.Client? httpClient;

  /// Optional precompiled [CompiledSvgScene] if compiled ahead of time.
  /// 可选的提前预编译好的 [CompiledSvgScene] 场景。
  final CompiledSvgScene? compiledScene;

  /// Optional external playback controller (`play`, `pause`, `seek`, `reset`, `setSpeed`).
  /// 可选的外部播放控制器（支持播放、暂停、跳转、重置与倍速）。
  final AnimatedSvgController? controller;

  /// Desired width of the widget (defaults to the SVG's intrinsic width or parent constraints).
  /// 组件目标宽度（默认使用 SVG 固有宽度或父级约束）。
  final double? width;

  /// Desired height of the widget (defaults to the SVG's intrinsic height or parent constraints).
  /// 组件目标高度（默认使用 SVG 固有高度或父级约束）。
  final double? height;

  /// Whether to automatically start playing when no external [controller] is provided.
  /// 未传入外部 [controller] 时是否自动开始播放。
  final bool autoPlay;

  /// Initial playback speed multiplier when no external [controller] is provided.
  /// 未传入外部 [controller] 时的初始播放倍速。
  final double speed;

  /// Whether to clip the canvas to the widget's bounds.
  /// 是否按组件边界裁剪画布。
  final Clip clipBehavior;

  /// How to inscribe the SVG's intrinsic size into the widget layout box.
  /// 如何将 SVG 固有尺寸适配到组件布局框内。
  ///
  /// Defaults to [BoxFit.contain].
  /// 默认值为 [BoxFit.contain]。
  ///
  /// Widget [fit] maps the intrinsic paint box into the layout size. The SVG's
  /// own `preserveAspectRatio` still applies when painting viewBox → intrinsic.
  /// 组件 [fit] 负责固有尺寸到布局尺寸的映射；SVG 自身的 `preserveAspectRatio` 仍作用于 viewBox 到固有尺寸。
  final BoxFit fit;

  /// How to align the fitted SVG within the widget layout box when [fit]
  /// leaves leftover space (or crops for [BoxFit.cover] / [BoxFit.none]).
  /// 当 [fit] 留有空白或发生裁剪时，SVG 在布局框内的对齐方式。
  ///
  /// Defaults to [Alignment.center].
  /// [AlignmentDirectional] resolves against ambient [Directionality].
  /// 默认为 [Alignment.center]；[AlignmentDirectional] 会结合环境 [Directionality] 解析。
  final AlignmentGeometry alignment;

  /// Optional whole-picture tint applied after painting (Flutter [ColorFilter]).
  /// 可选的整图后处理着色滤镜（Flutter [ColorFilter]）。
  ///
  /// Independent of W3C SVG `<filter>` graphs (commonly used with
  /// `ColorFilter.mode(color, BlendMode.srcIn)` for icon tinting).
  /// 与 W3C SVG `<filter>` 管线相互独立，常用于图标整体着色。
  final ColorFilter? colorFilter;

  /// Optional named `<view id="...">` identifier to override the active `viewBox`.
  /// 可选的命名 `<view id="...">` 标识，用于覆盖当前生效的 `viewBox`。
  final String? viewId;

  /// Creates an [AnimatedSvgPicture] from an SVG XML string.
  /// 从原始 SVG XML 字符串创建 [AnimatedSvgPicture]。
  ///
  /// - [svgXml]: Raw SVG XML document string. 原始 SVG XML 文档字符串。
  /// - [controller]: Optional external playback controller. 可选外部播放控制器。
  /// - [width]: Optional widget width. 可选组件宽度。
  /// - [height]: Optional widget height. 可选组件高度。
  /// - [autoPlay]: Auto-start playback when [controller] is omitted. 无外部控制器时是否自动播放。
  /// - [speed]: Initial playback speed when [controller] is omitted. 无外部控制器时的初始倍速。
  /// - [clipBehavior]: Canvas clipping behavior. 画布裁剪方式。
  /// - [fit]: BoxFit strategy for intrinsic-to-layout sizing. 固有尺寸到布局框的填充策略。
  /// - [alignment]: Alignment within layout bounds. 在布局框内的对齐方式。
  /// - [colorFilter]: Optional Flutter whole-picture tint. 可选整图后处理着色。
  /// - [viewId]: Optional `<view id="...">` to activate. 可选激活的 `<view>` 标识。
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
    this.viewId,
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
  /// 从 Flutter 资源包路径（如 `'assets/svgs/elephant.svg'`）创建 [AnimatedSvgPicture]。
  ///
  /// - [assetPath]: Asset key path in the bundle. 资源包中的资源路径。
  /// - [bundle]: Optional custom [AssetBundle]. 可选自定义资源包。
  /// - [package]: Optional package name owning the asset. 可选资源所属包名。
  /// - [controller]: Optional external playback controller. 可选外部播放控制器。
  /// - [width]: Optional widget width. 可选组件宽度。
  /// - [height]: Optional widget height. 可选组件高度。
  /// - [autoPlay]: Auto-start playback when [controller] is omitted. 无外部控制器时是否自动播放。
  /// - [speed]: Initial playback speed when [controller] is omitted. 无外部控制器时的初始倍速。
  /// - [clipBehavior]: Canvas clipping behavior. 画布裁剪方式。
  /// - [fit]: BoxFit strategy for intrinsic-to-layout sizing. 固有尺寸到布局框的填充策略。
  /// - [alignment]: Alignment within layout bounds. 在布局框内的对齐方式。
  /// - [colorFilter]: Optional Flutter whole-picture tint. 可选整图后处理着色。
  /// - [viewId]: Optional `<view id="...">` to activate. 可选激活的 `<view>` 标识。
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
    this.viewId,
  }) : assetName = assetPath,
       svgString = null,
       file = null,
       networkUrl = null,
       headers = null,
       httpClient = null,
       compiledScene = null;

  /// Creates an [AnimatedSvgPicture] from a local `dart:io` `File`.
  /// 从本地 `dart:io` `File` 创建 [AnimatedSvgPicture]。
  ///
  /// Pass a `dart:io` `File` instance. Unsupported on web and other platforms
  /// without `dart:io`; use [AnimatedSvgPicture.network],
  /// [AnimatedSvgPicture.asset], or [AnimatedSvgPicture.string] instead.
  /// 需传入 `dart:io` 的 `File` 实例；不支持 Web 等无 `dart:io` 平台。
  ///
  /// - [file]: Local `dart:io` `File` instance (typed as [Object] for web analysis).
  ///   本地 `dart:io` `File` 实例（为兼容 Web 分析声明为 [Object]）。
  /// - [controller]: Optional external playback controller. 可选外部播放控制器。
  /// - [width]: Optional widget width. 可选组件宽度。
  /// - [height]: Optional widget height. 可选组件高度。
  /// - [autoPlay]: Auto-start playback when [controller] is omitted. 无外部控制器时是否自动播放。
  /// - [speed]: Initial playback speed when [controller] is omitted. 无外部控制器时的初始倍速。
  /// - [clipBehavior]: Canvas clipping behavior. 画布裁剪方式。
  /// - [fit]: BoxFit strategy for intrinsic-to-layout sizing. 固有尺寸到布局框的填充策略。
  /// - [alignment]: Alignment within layout bounds. 在布局框内的对齐方式。
  /// - [colorFilter]: Optional Flutter whole-picture tint. 可选整图后处理着色。
  /// - [viewId]: Optional `<view id="...">` to activate. 可选激活的 `<view>` 标识。
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
    this.viewId,
  }) : svgString = null,
       assetName = null,
       bundle = null,
       package = null,
       networkUrl = null,
       headers = null,
       httpClient = null,
       compiledScene = null;

  /// Creates an [AnimatedSvgPicture] by downloading SVG XML from [url].
  /// 通过从网络地址 [url] 下载 SVG XML 创建 [AnimatedSvgPicture]。
  ///
  /// Uses `package:http`. Non-2xx responses and network errors are logged with
  /// [debugPrint] and leave an empty [SizedBox] (same pattern as asset load failures).
  /// 基于 `package:http` 加载；非 2xx 响应或网络异常会通过 [debugPrint] 记录日志并保留空白 [SizedBox]。
  ///
  /// - [url]: Remote HTTP/HTTPS URL of the SVG resource. 远程 SVG 资源地址。
  /// - [headers]: Optional HTTP request headers. 可选 HTTP 请求头。
  /// - [httpClient]: Optional custom [http.Client]. 可选自定义 [http.Client]。
  /// - [controller]: Optional external playback controller. 可选外部播放控制器。
  /// - [width]: Optional widget width. 可选组件宽度。
  /// - [height]: Optional widget height. 可选组件高度。
  /// - [autoPlay]: Auto-start playback when [controller] is omitted. 无外部控制器时是否自动播放。
  /// - [speed]: Initial playback speed when [controller] is omitted. 无外部控制器时的初始倍速。
  /// - [clipBehavior]: Canvas clipping behavior. 画布裁剪方式。
  /// - [fit]: BoxFit strategy for intrinsic-to-layout sizing. 固有尺寸到布局框的填充策略。
  /// - [alignment]: Alignment within layout bounds. 在布局框内的对齐方式。
  /// - [colorFilter]: Optional Flutter whole-picture tint. 可选整图后处理着色。
  /// - [viewId]: Optional `<view id="...">` to activate. 可选激活的 `<view>` 标识。
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
    this.viewId,
  }) : networkUrl = url,
       svgString = null,
       assetName = null,
       bundle = null,
       package = null,
       file = null,
       compiledScene = null;

  /// Creates an [AnimatedSvgPicture] from a precompiled [CompiledSvgScene].
  /// 从已提前预编译的 [CompiledSvgScene] 创建 [AnimatedSvgPicture]。
  ///
  /// - [scene]: Precompiled scene whose lifecycle is managed by the caller.
  ///   预编译场景对象（其生命周期由调用方自行管理与释放）。
  /// - [controller]: Optional external playback controller. 可选外部播放控制器。
  /// - [width]: Optional widget width. 可选组件宽度。
  /// - [height]: Optional widget height. 可选组件高度。
  /// - [autoPlay]: Auto-start playback when [controller] is omitted. 无外部控制器时是否自动播放。
  /// - [speed]: Initial playback speed when [controller] is omitted. 无外部控制器时的初始倍速。
  /// - [clipBehavior]: Canvas clipping behavior. 画布裁剪方式。
  /// - [fit]: BoxFit strategy for intrinsic-to-layout sizing. 固有尺寸到布局框的填充策略。
  /// - [alignment]: Alignment within layout bounds. 在布局框内的对齐方式。
  /// - [colorFilter]: Optional Flutter whole-picture tint. 可选整图后处理着色。
  /// - [viewId]: Optional `<view id="...">` to activate. 可选激活的 `<view>` 标识。
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
    this.viewId,
  }) : compiledScene = scene,
       svgString = null,
       assetName = null,
       bundle = null,
       package = null,
       file = null,
       networkUrl = null,
       headers = null,
       httpClient = null;

  /// Creates the mutable state managing scene compilation and the frame ticker.
  /// 创建管理场景编译与帧驱动 `Ticker` 的可变状态对象。
  @override
  State<AnimatedSvgPicture> createState() => _AnimatedSvgPictureState();
}

class _AnimatedSvgPictureState extends State<AnimatedSvgPicture>
    with SingleTickerProviderStateMixin {
  CompiledSvgScene? _internalScene;
  AnimatedSvgController? _internalController;
  final ValueNotifier<int> _assetRepaintNotifier = ValueNotifier<int>(0);
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
    scene.document.onAsyncAssetLoaded = () {
      if (mounted) {
        _assetRepaintNotifier.value++;
      }
    };
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
    _assetRepaintNotifier.dispose();
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
        viewId: widget.viewId,
        repaint: Listenable.merge([_activeController, _assetRepaintNotifier]),
      ),
    );
    final filter = widget.colorFilter;
    if (filter != null) {
      painted = ColorFiltered(colorFilter: filter, child: painted);
    }
    return painted;
  }
}
