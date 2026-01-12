import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _ipController = TextEditingController();
  bool _isTesting = false;
  bool _didLoad = false;

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _ipController.text = AppScope.of(context).espIp;
    _didLoad = true;
  }

  Future<void> _saveIp() async {
    final appState = AppScope.of(context);
    final value = _ipController.text.trim();
    await appState.setEspIp(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('IP saved.')),
    );
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<void> _testConnection() async {
    final appState = AppScope.of(context);
    if (appState.isDemo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo mode: connection test skipped.')),
      );
      return;
    }

    setState(() => _isTesting = true);
    try {
      final resp = await http
          .get(Uri.parse('http://${_ipController.text.trim()}/getState'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ESP responded (HTTP 200).')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ESP error: HTTP ${resp.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    final appState = AppScope.of(context);
    await appState.setThemeMode(mode);
  }

  Future<void> _changeDemo(bool value) async {
    final appState = AppScope.of(context);
    await appState.setDemoMode(value);
  }

  Widget _surfaceCard(BuildContext context, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appState = AppScope.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Spacer(),
                Text(
                  'Settings',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'ESP connection',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            _surfaceCard(
              context,
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'ESP IP address',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saveIp,
                            icon: const Icon(Icons.save_alt_rounded),
                            label: const Text('Save'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isTesting ? null : _testConnection,
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.wifi_tethering_rounded),
                            label: const Text('Test'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Appearance',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
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
                      subtitle: const Text('Use simulated readings without ESP.'),
                      value: appState.isDemo,
                      onChanged: _changeDemo,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'About',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
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
