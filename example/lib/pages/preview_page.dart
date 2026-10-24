import 'package:example/data/svg_catalog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

/// Preview page: renders one catalog item with playback controls.
class PreviewPage extends StatefulWidget {
  const PreviewPage({super.key, required this.item});

  final SvgCatalogItem item;

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late final AnimatedSvgController _controller;
  BoxFit _fit = BoxFit.contain;
  bool _tintEnabled = false;

  static const _tintFilter = ColorFilter.mode(
    Color(0xFF22C55E),
    BlendMode.srcIn,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimatedSvgController(autoPlay: true, speed: 1.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildPicture() {
    final item = widget.item;
    final filter = _tintEnabled ? _tintFilter : null;
    switch (item.kind) {
      case SvgCatalogSourceKind.asset:
        return AnimatedSvgPicture.asset(
          item.assetPath!,
          controller: _controller,
          width: 320,
          height: 200,
          fit: _fit,
          colorFilter: filter,
        );
      case SvgCatalogSourceKind.string:
        return AnimatedSvgPicture.string(
          item.svgString!,
          controller: _controller,
          width: 320,
          height: 200,
          fit: _fit,
          colorFilter: filter,
        );
      case SvgCatalogSourceKind.network:
        return AnimatedSvgPicture.network(
          item.networkUrl!,
          controller: _controller,
          width: 320,
          height: 200,
          fit: _fit,
          colorFilter: filter,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.item.subtitle,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Fit', style: Theme.of(context).textTheme.labelLarge),
                for (final fit in const [
                  BoxFit.contain,
                  BoxFit.cover,
                  BoxFit.fill,
                  BoxFit.fitWidth,
                  BoxFit.scaleDown,
                ])
                  ChoiceChip(
                    label: Text(fit.name),
                    selected: _fit == fit,
                    onSelected: (_) => setState(() => _fit = fit),
                  ),
                FilterChip(
                  label: const Text('colorFilter tint'),
                  selected: _tintEnabled,
                  onSelected: (v) => setState(() => _tintEnabled = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    // Wide box so BoxFit differences are visible.
                    width: 320,
                    height: 200,
                    child: ColoredBox(
                      color: colorScheme.surfaceContainerHighest,
                      child: _buildPicture(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '已播放 ${(_controller.elapsedMicroseconds / 1000000).toStringAsFixed(2)}s',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          Text(
                            '周期 ${(_controller.cycleDuration.inMicroseconds / 1000000).toStringAsFixed(2)}s · ${_controller.speed.toStringAsFixed(2)}x',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                      Slider(
                        value: _controller.cycleProgress,
                        onChanged: (v) {
                          final targetUs =
                              (_controller.cycleDuration.inMicroseconds * v)
                                  .round();
                          _controller.seek(Duration(microseconds: targetUs));
                        },
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              if (_controller.isPlaying) {
                                _controller.pause();
                              } else {
                                _controller.play();
                              }
                            },
                            icon: Icon(
                              _controller.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                            label: Text(_controller.isPlaying ? '暂停' : '播放'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _controller.reset,
                            icon: const Icon(Icons.replay),
                            label: const Text('重置'),
                          ),
                          for (final spd in const [0.5, 1.0, 2.0])
                            ChoiceChip(
                              label: Text('${spd}x'),
                              selected: _controller.speed == spd,
                              onSelected: (_) => _controller.setSpeed(spd),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
