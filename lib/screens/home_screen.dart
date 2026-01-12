import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import 'settings_screen.dart';

class Reading {
  final DateTime time;
  final String temperature;
  final String humidity;

  Reading({required this.time, required this.temperature, required this.humidity});
}

enum AquariumPreset { day, night, feeding }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _espIp = "192.168.0.105";
  String _ledState = "unknown";
  String _temperature = "---";
  String _humidity = "---";
  String _status = 'Нажмите "Обновить", чтобы получить статус.';
  bool _hasError = false;
  bool _dangerTemp = false;
  AquariumPreset _preset = AquariumPreset.day;
  final List<Reading> _history = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _espIp = prefs.getString('esp_ip') ?? "192.168.0.105";
    });
  }

  Future<void> _saveSettings(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp_ip', ip);
    setState(() {
      _espIp = ip;
    });
  }

  void _pushHistory(String temp, String hum) {
    if (temp == '---' || hum == '---') return;
    _history.insert(
      0,
      Reading(time: DateTime.now(), temperature: temp, humidity: hum),
    );
    if (_history.length > 20) {
      _history.removeLast();
    }
  }

  Future<void> _getState() async {
    final appState = AppScope.of(context);
    setState(() {
      _status = "Получаем данные...";
      _hasError = false;
    });

    if (appState.isDemo) {
      final demoTemp = (24 + Random().nextDouble() * 3).toStringAsFixed(1);
      final demoHum = (40 + Random().nextDouble() * 30).toStringAsFixed(0);
      final demoLed = Random().nextBool() ? 'on' : 'off';
      _updateFromResponse(demoLed, demoTemp, demoHum, isDemo: true);
      return;
    }

    try {
      final client = http.Client();
      final response = await client
          .get(Uri.parse('http://$_espIp/getState'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final led = data['ledState']?.toString() ?? 'unknown';
        final temp = data['temperature']?.toString() ?? '---';
        final hum = data['humidity']?.toString() ?? '---';
        _updateFromResponse(led, temp, hum, isDemo: false);
      } else {
        setState(() {
          _status = "HTTP ошибка: ${response.statusCode}";
          _hasError = true;
        });
      }
      client.close();
    } catch (e) {
      setState(() {
        _status = "Ошибка: ${e.toString()}";
        _hasError = true;
      });
    }
  }

  Future<void> _toggleLight() async {
    final appState = AppScope.of(context);
    if (appState.isDemo) {
      setState(() {
        _ledState = _ledState == 'on' ? 'off' : 'on';
        _status = "Демо: свет переключён";
        _hasError = false;
      });
      return;
    }

    try {
      final client = http.Client();
      final response = await client
          .get(Uri.parse('http://$_espIp/toggle'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _getState();
      } else {
        setState(() {
          _status = "HTTP ошибка: ${response.statusCode}";
          _hasError = true;
        });
      }
      client.close();
    } catch (e) {
      setState(() {
        _status = "Ошибка: ${e.toString()}";
        _hasError = true;
      });
    }
  }

  void _updateFromResponse(String led, String temp, String hum, {required bool isDemo}) {
    setState(() {
      _ledState = led;
      _temperature = temp;
      _humidity = hum;
      _status = isDemo ? "Демо: данные обновлены" : "Данные обновлены.";
      _hasError = false;
      _dangerTemp = _isDangerTemp(temp);
      _pushHistory(temp, hum);
    });
  }

  bool _isDangerTemp(String temp) {
    final value = double.tryParse(temp);
    if (value == null) return false;
    return value < 20 || value > 30;
  }

  void _openSettings() async {
    final newIp = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
    if (newIp != null && newIp is String) {
      _saveSettings(newIp);
    }
  }

  Widget _buildInfoBanner({required IconData icon, required String text, required Color color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required IconData icon,
    Color? accent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: (accent ?? scheme.primary).withOpacity(0.15),
              foregroundColor: accent ?? scheme.primary,
              child: Icon(icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      )),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetButton(AquariumPreset preset, String label, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = preset == _preset;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _preset = preset;
            _status = "Режим: $label";
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? scheme.primary.withOpacity(0.15) : scheme.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isActive ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyList() {
    final scheme = Theme.of(context).colorScheme;
    if (_history.isEmpty) {
      return Text(
        'История пока пуста. Обновите данные.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      children: _history
          .map(
            (r) => ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 0),
              leading: Icon(Icons.timeline, color: scheme.primary),
              title: Text('${r.temperature} °C | ${r.humidity} %'),
              subtitle: Text(
                '${r.time.hour.toString().padLeft(2, '0')}:${r.time.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appState = AppScope.of(context);
    const greeting = 'Smart Aquarium';
    final isOnline = !_hasError && _status.toLowerCase().contains('обновл');

    return Scaffold(
      appBar: AppBar(
        title: Text(greeting),
        actions: [
          if (appState.isDemo)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Chip(
                label: const Text('Demo'),
                backgroundColor: scheme.primary.withOpacity(0.2),
                labelStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _getState,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Статус соединения
              Row(
                children: [
                  Icon(
                    isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: isOnline ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOnline ? 'Онлайн' : 'Оффлайн/неизвестно',
                    style: TextStyle(
                      color: isOnline ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'IP: $_espIp',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_hasError)
                _buildInfoBanner(
                  icon: Icons.warning_amber_rounded,
                  text: _status,
                  color: Colors.orange,
                )
              else if (_dangerTemp)
                _buildInfoBanner(
                  icon: Icons.thermostat,
                  text: 'Опасная температура! Сейчас: $_temperature °C',
                  color: Colors.red,
                )
              else
                _buildInfoBanner(
                  icon: Icons.info_outline,
                  text: _status,
                  color: scheme.primary,
                ),
              const SizedBox(height: 16),

              // Метрики
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 1,
                  childAspectRatio: 2.8,
                  mainAxisSpacing: 12,
                ),
                children: [
                  _metricCard(
                    title: 'Температура воды',
                    value: '$_temperature °C',
                    icon: Icons.thermostat_rounded,
                    accent: Colors.deepOrange,
                  ),
                  _metricCard(
                    title: 'Влажность',
                    value: '$_humidity %',
                    icon: Icons.water_drop_rounded,
                    accent: Colors.teal,
                  ),
                  _metricCard(
                    title: 'Свет',
                    value: _ledState.toUpperCase(),
                    icon: Icons.lightbulb_rounded,
                    accent: Colors.amber,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Пресеты
              Text(
                'Режим аквариума',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _presetButton(AquariumPreset.day, 'Дневной', Icons.wb_sunny_rounded),
                  const SizedBox(width: 10),
                  _presetButton(AquariumPreset.night, 'Ночной', Icons.nights_stay_rounded),
                  const SizedBox(width: 10),
                  _presetButton(AquariumPreset.feeding, 'Кормление', Icons.restaurant_rounded),
                ],
              ),
              const SizedBox(height: 16),

              // Быстрые действия
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _getState,
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Обновить данные'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _toggleLight,
                      icon: const Icon(Icons.lightbulb_outline),
                      label: const Text('Переключить свет'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // История
              Text(
                'История показаний',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _historyList(),
              const SizedBox(height: 24),

              // Переход в настройки
              OutlinedButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_suggest_rounded),
                label: const Text('Открыть настройки'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
