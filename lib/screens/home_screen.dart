import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

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
  String _ledState = 'unknown';
  String _temperature = '---';
  String _humidity = '---';
  String _status = 'Waiting for data. Pull to refresh.';
  bool _hasError = false;
  bool _dangerTemp = false;
  DateTime? _lastOnlineAt;
  AquariumPreset _preset = AquariumPreset.day;
  final List<Reading> _history = [];

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
    final espIp = appState.espIp;
    setState(() {
      _status = 'Fetching latest readings...';
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
          .get(Uri.parse('http://$espIp/getState'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final led = data['ledState']?.toString() ?? 'unknown';
        final temp = data['temperature']?.toString() ?? '---';
        final hum = data['humidity']?.toString() ?? '---';
        _updateFromResponse(led, temp, hum, isDemo: false);
      } else {
        setState(() {
          _status = 'HTTP error: ${response.statusCode}';
          _hasError = true;
        });
      }
      client.close();
    } catch (e) {
      setState(() {
        _status = 'Request error: ${e.toString()}';
        _hasError = true;
      });
    }
  }

  Future<void> _toggleLight() async {
    final appState = AppScope.of(context);
    final espIp = appState.espIp;
    if (appState.isDemo) {
      setState(() {
        _ledState = _ledState == 'on' ? 'off' : 'on';
        _status = 'Light toggled (demo mode).';
        _hasError = false;
      });
      return;
    }

    try {
      final client = http.Client();
      final response = await client
          .get(Uri.parse('http://$espIp/toggle'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _getState();
      } else {
        setState(() {
          _status = 'HTTP error: ${response.statusCode}';
          _hasError = true;
        });
      }
      client.close();
    } catch (e) {
      setState(() {
        _status = 'Request error: ${e.toString()}';
        _hasError = true;
      });
    }
  }

  void _updateFromResponse(String led, String temp, String hum, {required bool isDemo}) {
    setState(() {
      _ledState = led;
      _temperature = temp;
      _humidity = hum;
      _status = isDemo ? 'Demo readings updated.' : 'Readings updated.';
      _hasError = false;
      _dangerTemp = _isDangerTemp(temp);
      _pushHistory(temp, hum);
      _lastOnlineAt = DateTime.now();
    });
  }

  bool _isDangerTemp(String temp) {
    final value = double.tryParse(temp);
    if (value == null) return false;
    return value < 20 || value > 30;
  }

  String _offlineReason(String status) {
    final lowered = status.toLowerCase();
    if (lowered.contains('network is unreachable') ||
        lowered.contains('no route to host') ||
        lowered.contains('network unreachable')) {
      return 'Not in Wi-Fi';
    }
    if (lowered.contains('failed host lookup') ||
        lowered.contains('connection refused') ||
        lowered.contains('http error') ||
        lowered.contains('host lookup')) {
      return 'Wrong IP';
    }
    return 'No response';
  }

  String _formatLastOnline() {
    final last = _lastOnlineAt;
    if (last == null) return 'Last online: never';
    final diff = DateTime.now().difference(last);
    if (diff.inMinutes < 1) return 'Last online: just now';
    if (diff.inHours < 1) return 'Last online: ${diff.inMinutes} min ago';
    if (diff.inHours < 24) return 'Last online: ${diff.inHours} hr ago';
    return 'Last online: ${diff.inDays} days ago';
  }

  void _copyIp(String ip) {
    Clipboard.setData(ClipboardData(text: ip));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('IP copied.')),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Widget _buildInfoBanner({required IconData icon, required String text, required Color color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
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

  Widget _surfaceCard({required Widget child}) {
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

  Widget _metricCard({
    required String title,
    required String value,
    required IconData icon,
    Color? accent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final accentColor = accent ?? scheme.primary;
    return _surfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w700,
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
            _status = 'Preset set to $label.';
          });
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? scheme.primary.withOpacity(0.12) : scheme.surface,
            borderRadius: BorderRadius.circular(18),
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
        'No history yet. Refresh to collect readings.',
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
              title: Text('${r.temperature} C | ${r.humidity} %'),
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
    final isOnline = !_hasError && _temperature != '---';
    final espIp = appState.espIp;
    final ledOn = _ledState.toLowerCase() == 'on';
    final presetLabel = switch (_preset) {
      AquariumPreset.day => 'Day',
      AquariumPreset.night => 'Night',
      AquariumPreset.feeding => 'Feeding',
    };

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _getState,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  const Spacer(),
                  Text(
                    'Aquarium',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (appState.isDemo)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Demo',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _surfaceCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 130,
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            colors: [
                              scheme.primary.withOpacity(0.4),
                              scheme.primary.withOpacity(0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          Icons.bubble_chart_rounded,
                          size: 80,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tropical Tank',
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Status: ${ledOn ? "Lights on" : "Lights off"}',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Preset: $presetLabel',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: isOnline ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      color: isOnline ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (!isOnline)
                    TextButton.icon(
                      onPressed: _getState,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Reconnect'),
                    ),
                ],
              ),
              if (!isOnline) ...[
                const SizedBox(height: 6),
                Text(
                  'Reason: ${_offlineReason(_status)}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatLastOnline(),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'IP: $espIp',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _copyIp(espIp),
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: 'Copy IP',
                  ),
                  TextButton(
                    onPressed: _openSettings,
                    child: const Text('Change IP'),
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
                  text: 'Temperature alert: $_temperature C',
                  color: Colors.red,
                )
              else
                _buildInfoBanner(
                  icon: Icons.info_outline,
                  text: _status,
                  color: scheme.primary,
                ),
              const SizedBox(height: 18),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _metricCard(
                    title: 'Temperature',
                    value: '$_temperature C',
                    icon: Icons.thermostat_rounded,
                    accent: Colors.deepOrange,
                  ),
                  _metricCard(
                    title: 'Water level',
                    value: '$_humidity %',
                    icon: Icons.water_drop_rounded,
                    accent: Colors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _surfaceCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.swap_horiz_rounded, color: scheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Flow direction',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Icon(Icons.arrow_left_rounded),
                                Icon(Icons.compress_rounded),
                                Icon(Icons.arrow_right_rounded),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _surfaceCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lightbulb_rounded, color: Colors.amber),
                                const SizedBox(width: 8),
                                Text(
                                  'Lighting',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text(
                                  ledOn ? 'ON' : 'OFF',
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Switch(
                                  value: ledOn,
                                  onChanged: (_) => _toggleLight(),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Presets',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _presetButton(AquariumPreset.day, 'Day', Icons.wb_sunny_rounded),
                  const SizedBox(width: 10),
                  _presetButton(AquariumPreset.night, 'Night', Icons.nights_stay_rounded),
                  const SizedBox(width: 10),
                  _presetButton(AquariumPreset.feeding, 'Feeding', Icons.restaurant_rounded),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Quick actions',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _getState,
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Refresh data'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _toggleLight,
                      icon: const Icon(Icons.lightbulb_outline),
                      label: const Text('Toggle light'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'History',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _historyList(),
            ],
          ),
        ),
      ),
    );
  }
}
