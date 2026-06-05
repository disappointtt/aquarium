import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/ui_components.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _changeTheme(ThemeMode mode) async {
    final appState = AppScope.read(context);
    await appState.setThemeMode(mode);
  }

  Future<void> _changeDemo(bool value) async {
    final appState = AppScope.read(context);
    await appState.setDemoMode(value);
  }

  Widget _surfaceCard(BuildContext context, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

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
          child: Icon(Icons.settings_rounded, color: scheme.onPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Настройки',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Тема и режимы',
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
    final appState = AppScope.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _header(context),
            const SizedBox(height: 18),
            const SectionHeader(title: 'Appearance'),
            const SizedBox(height: 10),
            _surfaceCard(
              context,
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Theme'),
                      subtitle: const Text('Choose light, dark, or system.'),
                      trailing: DropdownButton<ThemeMode>(
                        value: appState.themeMode,
                        items: const [
                          DropdownMenuItem(
                            value: ThemeMode.system,
                            child: Text('System'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.light,
                            child: Text('Light'),
                          ),
                          DropdownMenuItem(
                            value: ThemeMode.dark,
                            child: Text('Dark'),
                          ),
                        ],
                        onChanged: (mode) {
                          if (mode != null) _changeTheme(mode);
                        },
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Demo mode'),
                      subtitle: const Text(
                        'Use simulated readings without ESP.',
                      ),
                      value: appState.isDemo,
                      onChanged: _changeDemo,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader(title: 'About'),
            const SizedBox(height: 10),
            _surfaceCard(
              context,
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Smart Aquarium'),
                    SizedBox(height: 6),
                    Text('Version: 1.0.0'),
                    SizedBox(height: 6),
                    Text('Built for ESP aquarium control.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
