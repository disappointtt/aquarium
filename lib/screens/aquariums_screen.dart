import 'package:flutter/material.dart';

import '../widgets/ui_components.dart';

class AquariumsScreen extends StatelessWidget {
  const AquariumsScreen({super.key});

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.water_rounded, color: scheme.onPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Аквариумы',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '1 активный аквариум',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _header(context),
            const SizedBox(height: 18),
            InfoCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 164,
                    decoration: BoxDecoration(
                      color: const Color(0xFF12343B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: 74,
                            margin: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2EC4B6).withOpacity(0.75),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        Center(
                          child: Icon(
                            Icons.bubble_chart_rounded,
                            size: 72,
                            color: Colors.white.withOpacity(0.74),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Tropical Tank',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'ESP 192.168.1.44 · Online · 90% воды',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Открыть'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Настроить'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader(title: 'Будущие возможности'),
            const SizedBox(height: 8),
            InfoCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: const [
                  _RoadmapRow(
                    icon: Icons.dashboard_customize_rounded,
                    title: 'Несколько аквариумов',
                    subtitle: 'Отдельные ESP, профили и статусы.',
                  ),
                  _RoadmapRow(
                    icon: Icons.hub_rounded,
                    title: 'Группы устройств',
                    subtitle: 'Фильтры, свет, помпы и компрессоры.',
                  ),
                  _RoadmapRow(
                    icon: Icons.notifications_active_rounded,
                    title: 'Общие алерты',
                    subtitle: 'Сводка проблем по всем аквариумам.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoadmapRow extends StatelessWidget {
  const _RoadmapRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
