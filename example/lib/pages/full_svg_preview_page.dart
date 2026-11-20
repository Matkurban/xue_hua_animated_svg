import 'package:example/data/full_svg_catalog.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

/// Immersive fullscreen viewer for a [FullSvgAssetItem] with no control panels.
class FullSvgPreviewPage extends StatefulWidget {
  const FullSvgPreviewPage({super.key, required this.item});

  final FullSvgAssetItem item;

  @override
  State<FullSvgPreviewPage> createState() => _FullSvgPreviewPageState();
}

class _FullSvgPreviewPageState extends State<FullSvgPreviewPage> {
  bool _showBackButton = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showBackButton = !_showBackButton),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSvgPicture.asset(
              widget.item.assetPath,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.contain,
            ),
            if (_showBackButton)
              Positioned(
                top: 12,
                left: 12,
                child: SafeArea(
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
