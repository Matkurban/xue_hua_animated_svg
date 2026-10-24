import 'package:flutter/material.dart';
import 'package:xue_hua_animated_svg/xue_hua_animated_svg.dart';

void main() {
  runApp(const AnimatedSvgShowcaseApp());
}

enum DemoSvgSource { elephantAsset, cyberCoreComposite }

class AnimatedSvgShowcaseApp extends StatelessWidget {
  const AnimatedSvgShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Animated SVG Engine Showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00F5D4),
          brightness: Brightness.dark,
        ),
      ),
      home: const ShowcaseHomePage(),
    );
  }
}

class ShowcaseHomePage extends StatefulWidget {
  const ShowcaseHomePage({super.key});

  @override
  State<ShowcaseHomePage> createState() => _ShowcaseHomePageState();
}

class _ShowcaseHomePageState extends State<ShowcaseHomePage> {
  late final AnimatedSvgController _controller;
  DemoSvgSource _selectedSource = DemoSvgSource.elephantAsset;

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

  void _switchSource(DemoSvgSource source) {
    if (_selectedSource == source) return;
    setState(() {
      _selectedSource = source;
      _controller.reset();
      _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B132B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2541),
        title: const Text('Animated SVG Engine (120fps Pure Dart)'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SegmentedButton<DemoSvgSource>(
              segments: const [
                ButtonSegment<DemoSvgSource>(
                  value: DemoSvgSource.elephantAsset,
                  icon: Icon(Icons.pets),
                  label: Text('elephant.svg (Asset)'),
                ),
                ButtonSegment<DemoSvgSource>(
                  value: DemoSvgSource.cyberCoreComposite,
                  icon: Icon(Icons.auto_awesome),
                  label: Text('CyberCore (3D + Morph)'),
                ),
              ],
              selected: <DemoSvgSource>{_selectedSource},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  _switchSource(selection.first);
                }
              },
            ),
          ),
          Expanded(
            child: Center(
              child: Container(
                width: 340,
                height: 340,
                decoration: BoxDecoration(
                  color: const Color(0xFF111936),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF3A506B)),
                ),
                padding: const EdgeInsets.all(16),
                child: _selectedSource == DemoSvgSource.elephantAsset
                    ? AnimatedSvgPicture.asset(
                        'assets/svgs/elephant.svg',
                        controller: _controller,
                        width: 308,
                        height: 308,
                      )
                    : AnimatedSvgPicture.string(
                        AnimatedSvgShowcasePresets.cyberCoreCompositeSvg,
                        controller: _controller,
                        width: 308,
                        height: 308,
                      ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                decoration: const BoxDecoration(
                  color: Color(0xFF1C2541),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Elapsed: ${(_controller.elapsedMicroseconds / 1000000).toStringAsFixed(2)}s',
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        Text(
                          'Cycle: ${(_controller.cycleDuration.inMicroseconds / 1000000).toStringAsFixed(2)}s | Speed: ${_controller.speed.toStringAsFixed(2)}x',
                          style: const TextStyle(fontFamily: 'monospace'),
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
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
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
                          label: Text(_controller.isPlaying ? 'Pause' : 'Play'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _controller.reset,
                          icon: const Icon(Icons.replay),
                          label: const Text('Reset'),
                        ),
                        for (final spd in [0.5, 1.0, 2.0])
                          ChoiceChip(
                            label: Text('${spd}x'),
                            selected: _controller.speed == spd,
                            onSelected: (_) => _controller.setSpeed(spd),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
