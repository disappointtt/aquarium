import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _ipController = TextEditingController();
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _loadIp();
  }

  Future<void> _loadIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('esp_ip') ?? '192.168.0.105';
    setState(() {
      _ipController.text = savedIp;
    });
  }

  Future<void> _saveIp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp_ip', _ipController.text);
    if (mounted) Navigator.pop(context, _ipController.text);
  }

  Future<void> _testConnection() async {
    final appState = AppScope.of(context);
    if (appState.isDemo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Демо-режим: подключение считается успешным')),
      );
      return;
    }

    setState(() => _isTesting = true);
    try {
      final resp = await http
          .get(Uri.parse('http://${_ipController.text}/getState'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ESP отвечает (HTTP 200)')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ответ ESP: HTTP ${resp.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: ${e.toString()}')),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appState = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Настройки")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Подключение к ESP',
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                children: [
                  TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: "IP адрес ESP",
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saveIp,
                          icon: const Icon(Icons.save_alt_rounded),
                          label: const Text("Сохранить"),
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
                          label: const Text("Тест подключения"),
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
            'Внешний вид',
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Тема'),
                    subtitle: const Text('Светлая, тёмная или системная'),
                    trailing: DropdownButton<ThemeMode>(
                      value: appState.themeMode,
                      items: const [
                        DropdownMenuItem(
                          value: ThemeMode.system,
                          child: Text('Системная'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.light,
                          child: Text('Светлая'),
                        ),
                        DropdownMenuItem(
                          value: ThemeMode.dark,
                          child: Text('Тёмная'),
                        ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) _changeTheme(mode);
                      },
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Демо-режим'),
                    subtitle: const Text('Показывать фейковые данные без запросов к ESP'),
                    value: appState.isDemo,
                    onChanged: _changeDemo,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'О проекте',
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Smart Aquarium'),
                  SizedBox(height: 6),
                  Text('Версия: 1.0.0'),
                  SizedBox(height: 6),
                  Text('Автор: Дипломный проект'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
