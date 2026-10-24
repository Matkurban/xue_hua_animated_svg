import 'package:example/data/svg_catalog.dart';
import 'package:example/pages/preview_page.dart';
import 'package:material_ui/material_ui.dart';

/// Home screen: scrollable catalog of animated SVG demos.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  IconData _iconFor(String name) {
    switch (name) {
      case 'pets':
        return Icons.pets;
      case 'cloud_download':
        return Icons.cloud_download;
      case 'radio_button_checked':
        return Icons.radio_button_checked;
      case 'crop_square':
        return Icons.crop_square;
      case 'rocket_launch':
        return Icons.rocket_launch;
      case 'sync':
        return Icons.sync;
      case 'change_history':
        return Icons.change_history;
      case 'timeline':
        return Icons.timeline;
      case 'stairs':
        return Icons.stairs;
      case 'auto_awesome':
      default:
        return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('动态 SVG 示例')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: SvgCatalog.items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = SvgCatalog.items[index];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PreviewPage(item: item),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      child: Icon(_iconFor(item.iconName)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.subtitle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final tag in item.tags)
                                Chip(
                                  label: Text(tag),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
