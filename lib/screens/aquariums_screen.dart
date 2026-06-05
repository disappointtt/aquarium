import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../widgets/ui_components.dart';

class AquariumsScreen extends StatefulWidget {
  const AquariumsScreen({super.key, required this.onOpenHome});

  final VoidCallback onOpenHome;

  @override
  State<AquariumsScreen> createState() => _AquariumsScreenState();
}

class _AquariumsScreenState extends State<AquariumsScreen> {
  Widget _header(BuildContext context, int count) {
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
                '$count ${count == 1 ? "активный аквариум" : "аквариума"}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton.filled(
            tooltip: 'Добавить аквариум',
            onPressed: () => _showAquariumEditor(),
            icon: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }

  void _openAquarium(AquariumProfile aquarium) {
    unawaited(AppScope.read(context).selectAquarium(aquarium.id));
    if (!mounted) return;
    widget.onOpenHome();
  }

  Future<void> _waitForDialogDismissal() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _showAquariumEditor({AquariumProfile? aquarium}) async {
    final nameController = TextEditingController(text: aquarium?.name ?? '');
    final ipController = TextEditingController(text: aquarium?.espIp ?? '');
    final appState = AppScope.read(context);
    var isTesting = false;

    final draft = await showDialog<({String name, String ip})>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> testConnection() async {
              final ip = ipController.text.trim();
              if (ip.isEmpty) return;
              if (appState.isDemo) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Demo mode: connection test skipped.'),
                  ),
                );
                return;
              }

              setDialogState(() => isTesting = true);
              try {
                final response = await http
                    .get(Uri.parse('http://$ip/status'))
                    .timeout(const Duration(seconds: 6));
                if (!context.mounted) return;
                final message = response.statusCode == 200
                    ? 'ESP responded (HTTP 200).'
                    : 'ESP error: HTTP ${response.statusCode}';
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Request error: ${e.toString()}')),
                );
              } finally {
                if (context.mounted) {
                  setDialogState(() => isTesting = false);
                }
              }
            }

            Future<void> save() async {
              final name = nameController.text.trim();
              final ip = ipController.text.trim();
              if (ip.isEmpty) return;
              Navigator.of(dialogContext).pop((name: name, ip: ip));
            }

            return AlertDialog(
              title: Text(
                aquarium == null ? 'Новый аквариум' : 'Настройка аквариума',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Название'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ipController,
                      decoration: const InputDecoration(
                        labelText: 'ESP IP address',
                      ),
                      keyboardType: TextInputType.url,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Отмена'),
                ),
                OutlinedButton.icon(
                  onPressed: isTesting ? null : testConnection,
                  icon: isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_rounded),
                  label: const Text('Test'),
                ),
                FilledButton.icon(
                  onPressed: save,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    ipController.dispose();

    if (draft == null || !mounted) return;
    await _waitForDialogDismissal();
    if (!mounted) return;
    if (aquarium == null) {
      await appState.addAquarium(name: draft.name, espIp: draft.ip);
    } else {
      await appState.updateAquarium(
        id: aquarium.id,
        name: draft.name,
        espIp: draft.ip,
      );
    }
  }

  Future<void> _confirmDelete(AquariumProfile aquarium) async {
    final appState = AppScope.read(context);
    if (appState.aquariums.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нужен хотя бы один аквариум.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Удалить аквариум?'),
          content: Text(aquarium.name),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.delete_rounded),
              label: const Text('Удалить'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await _waitForDialogDismissal();
    if (!mounted) return;
    await appState.removeAquarium(aquarium.id);
  }

  Widget _tankPreview(BuildContext context, bool isActive) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF12343B)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 58,
              margin: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(
                  0xFF2EC4B6,
                ).withValues(alpha: isActive ? 0.75 : 0.46),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Center(
            child: Icon(
              Icons.bubble_chart_rounded,
              size: 58,
              color: (isActive ? Colors.white : scheme.primary).withValues(
                alpha: 0.74,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aquariumCard(AquariumProfile aquarium, bool isActive) {
    final scheme = Theme.of(context).colorScheme;
    final appState = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InfoCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tankPreview(context, isActive),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    aquarium.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive)
                  _statusChip(
                    icon: Icons.check_rounded,
                    label: 'Selected',
                    color: scheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'ESP ${aquarium.espIp}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _openAquarium(aquarium),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Открыть'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAquariumEditor(aquarium: aquarium),
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('Настроить'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton.outlined(
                    tooltip: 'Удалить',
                    onPressed: appState.aquariums.length > 1
                        ? () => _confirmDelete(aquarium)
                        : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    final aquariums = List<AquariumProfile>.from(appState.aquariums);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _header(context, aquariums.length),
            const SizedBox(height: 18),
            ...aquariums.map(
              (aquarium) => _aquariumCard(
                aquarium,
                aquarium.id == appState.activeAquariumId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
