import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../data/history_store.dart';
import '../main.dart';
import '../models/history_models.dart';
import '../widgets/ui_components.dart';
import 'settings_screen.dart';

class Reading {
  final DateTime time;
  final String temperature;
  final String humidity;

  Reading({required this.time, required this.temperature, required this.humidity});
}

enum AquariumPreset { day, night, feeding }

enum FlowDirection { left, stop, right }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenHistory});

  final VoidCallback? onOpenHistory;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _ledState = 'unknown';
  String? _requestedLedState;
  String _temperature = '---';
  String _humidity = '---';
  String _status = 'Waiting for data. Pull to refresh.';
  bool _hasError = false;
  bool _dangerTemp = false;
  bool _isLoading = false;
  bool _isLightingAuto = false;
  String _lightingStatus = 'Ready.';
  DateTime? _lastOnlineAt;
  DateTime? _lastUpdatedAt;
  AquariumPreset _preset = AquariumPreset.day;
  FlowDirection _flowDirection = FlowDirection.stop;
  String _flowStatus = 'Ready.';
  final List<Reading> _history = [];
  final HistoryStore _historyStore = HistoryStore.instance;
  bool _wasOnline = false;

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

  void _addEvent(HistoryEvent event) {
    _historyStore.addEvent(event);
  }

  Future<void> _getState() async {
    final appState = AppScope.of(context);
    final espIp = appState.espIp;
    setState(() {
      _status = 'Fetching latest readings...';
      _hasError = false;
      _isLoading = true;
    });

    if (appState.isDemo) {
      final demoTemp = (24 + Random().nextDouble() * 3).toStringAsFixed(1);
      final demoHum = (40 + Random().nextDouble() * 30).toStringAsFixed(0);
      final demoLed = Random().nextBool() ? 'on' : 'off';
      _updateFromResponse(demoLed, demoTemp, demoHum, isDemo: true);
      _recordRefresh(ok: true, message: 'Demo data updated');
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
        _recordRefresh(ok: true, message: 'Readings updated');
      } else {
        setState(() {
          _status = 'HTTP error: ${response.statusCode}';
          _hasError = true;
        });
        _markConnection(false);
        _recordRefresh(ok: false, message: 'HTTP ${response.statusCode}');
      }
      client.close();
    } catch (e) {
      setState(() {
        _status = 'Request error: ${e.toString()}';
        _hasError = true;
      });
      _markConnection(false);
      _recordRefresh(ok: false, message: 'Request error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleLight() async {
    final appState = AppScope.of(context);
    final espIp = appState.espIp;
    final nextState = _ledState.toLowerCase() == 'on' ? 'off' : 'on';
    setState(() {
      _requestedLedState = nextState;
      _lightingStatus = 'Sending...';
    });
    if (appState.isDemo) {
      setState(() {
        _ledState = nextState;
        _status = 'Light toggled (demo mode).';
        _hasError = false;
        _requestedLedState = null;
        _lightingStatus = 'Applied.';
      });
      _addEvent(
        HistoryEvent(
          id: _newEventId(),
          time: DateTime.now(),
          title: 'Light ${nextState.toUpperCase()}',
          message: 'Demo mode',
          icon: Icons.lightbulb_rounded,
          category: HistoryCategory.commands,
          ok: true,
        ),
      );
      return;
    }

    try {
      final client = http.Client();
      final response = await client
          .get(Uri.parse('http://$espIp/toggle'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _getState();
        if (mounted) {
          setState(() {
            _requestedLedState = null;
            _lightingStatus = 'Applied.';
          });
        }
        _addEvent(
          HistoryEvent(
            id: _newEventId(),
            time: DateTime.now(),
            title: 'Light ${nextState.toUpperCase()}',
            message: 'Applied',
            icon: Icons.lightbulb_rounded,
            category: HistoryCategory.commands,
            ok: true,
          ),
        );
      } else {
        setState(() {
          _status = 'HTTP error: ${response.statusCode}';
          _hasError = true;
          _lightingStatus = 'Failed to apply.';
        });
        _addEvent(
          HistoryEvent(
            id: _newEventId(),
            time: DateTime.now(),
            title: 'Light change failed',
            message: 'HTTP ${response.statusCode}',
            icon: Icons.lightbulb_outline,
            category: HistoryCategory.alerts,
            ok: false,
          ),
        );
      }
      client.close();
    } catch (e) {
      setState(() {
        _status = 'Request error: ${e.toString()}';
        _hasError = true;
        _lightingStatus = 'Failed to apply.';
      });
      _addEvent(
        HistoryEvent(
          id: _newEventId(),
          time: DateTime.now(),
          title: 'Light change failed',
          message: 'Request error',
          icon: Icons.lightbulb_outline,
          category: HistoryCategory.alerts,
          ok: false,
        ),
      );
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
      _lastUpdatedAt = DateTime.now();
      _isLoading = false;
    });
    _markConnection(true);
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

  String _formatUpdatedTime() {
    final updated = _lastUpdatedAt;
    if (updated == null) return 'Updated —';
    final hh = updated.hour.toString().padLeft(2, '0');
    final mm = updated.minute.toString().padLeft(2, '0');
    return 'Updated $hh:$mm';
  }

  String _formatEventTime(DateTime time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _newEventId({DateTime? time, String? tag}) {
    final base = (time ?? DateTime.now()).microsecondsSinceEpoch;
    return tag == null ? '$base' : '$base-$tag';
  }

  HistoryFlowDirection _mapFlowDirection(FlowDirection direction) {
    return switch (direction) {
      FlowDirection.left => HistoryFlowDirection.left,
      FlowDirection.stop => HistoryFlowDirection.stop,
      FlowDirection.right => HistoryFlowDirection.right,
    };
  }

  String _historyFlowLabel(HistoryFlowDirection direction) {
    return switch (direction) {
      HistoryFlowDirection.left => 'Left',
      HistoryFlowDirection.stop => 'Stop',
      HistoryFlowDirection.right => 'Right',
    };
  }

  HistorySnapshot _buildSnapshot({required bool ok}) {
    final tempValue = ok ? double.tryParse(_temperature) : null;
    final humidityValue = ok ? double.tryParse(_humidity) : null;
    int? waterLevelPercent;
    if (humidityValue != null) {
      waterLevelPercent = humidityValue <= 1 ? (humidityValue * 100).round() : humidityValue.round();
    }
    final actualLight = ok ? _ledState.toLowerCase() == 'on' : null;
    final requestedLight = ok
        ? (_requestedLedState == null ? actualLight : _requestedLedState == 'on')
        : null;
    final lightingMode = ok ? (_isLightingAuto ? HistoryLightingMode.auto : HistoryLightingMode.manual) : null;
    final flowDirection = ok ? _mapFlowDirection(_flowDirection) : null;
    final connectionState = ok ? HistoryConnectionState.online : HistoryConnectionState.offline;
    return HistorySnapshot(
      temperature: tempValue,
      waterLevelPercent: waterLevelPercent,
      lightingRequested: requestedLight,
      lightingActual: actualLight,
      lightingMode: lightingMode,
      flowDirection: flowDirection,
      connectionState: connectionState,
      lastSeen: _lastOnlineAt,
    );
  }

  String _snapshotSubtitle(HistorySnapshot snapshot) {
    final temp = snapshot.temperature != null
        ? '${snapshot.temperature!.toStringAsFixed(1)}${snapshot.temperatureUnit}'
        : '-';
    final water = snapshot.waterLevelPercent != null ? '${snapshot.waterLevelPercent}%' : '-';
    String light;
    if (snapshot.lightingActual == null) {
      light = '-';
    } else {
      light = snapshot.lightingActual! ? 'ON' : 'OFF';
      if (snapshot.lightingMode != null) {
        final mode = snapshot.lightingMode == HistoryLightingMode.auto ? 'Auto' : 'Manual';
        light = '$light ($mode)';
      }
    }
    final flow = snapshot.flowDirection != null ? _historyFlowLabel(snapshot.flowDirection!) : '-';
    return 'Temp: $temp | Water: $water | Light: $light | Flow: $flow';
  }

  String _eventSubtitle(HistoryEvent event) {
    if (event.snapshot != null) {
      return '${_formatEventTime(event.time)} - ${_snapshotSubtitle(event.snapshot!)}';
    }
    if (event.message != null) {
      return '${_formatEventTime(event.time)} - ${event.message}';
    }
    return _formatEventTime(event.time);
  }

  void _recordRefresh({required bool ok, String? message}) {
    final timestamp = DateTime.now();
    _addEvent(
      HistoryEvent(
        id: _newEventId(time: timestamp, tag: 'refresh'),
        time: timestamp,
        title: 'Refresh',
        message: message,
        icon: ok ? Icons.sync_rounded : Icons.sync_problem_rounded,
        category: HistoryCategory.commands,
        ok: ok,
      ),
    );
    _addEvent(
      HistoryEvent(
        id: _newEventId(time: timestamp, tag: 'snapshot'),
        time: timestamp,
        title: 'Readings',
        message: ok ? null : 'No data',
        icon: Icons.sensors_rounded,
        category: HistoryCategory.readings,
        ok: ok,
        snapshot: _buildSnapshot(ok: ok),
      ),
    );
  }


  void _markConnection(bool isOnlineNow) {
    if (isOnlineNow == _wasOnline) return;
    _wasOnline = isOnlineNow;
    _addEvent(
      HistoryEvent(
        id: _newEventId(),
        time: DateTime.now(),
        title: isOnlineNow ? 'Online' : 'Offline',
        message: isOnlineNow ? 'Connection restored' : 'No connection',
        icon: isOnlineNow ? Icons.wifi_rounded : Icons.wifi_off_rounded,
        category: HistoryCategory.alerts,
        ok: isOnlineNow,
      ),
    );
  }

  String? _trendText({required String currentValue, required bool isTemperature}) {
    final current = double.tryParse(currentValue);
    if (current == null) return null;
    if (_history.length < 2) return null;
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    Reading? past;
    for (final reading in _history) {
      if (reading.time.isBefore(cutoff) || reading.time.isAtSameMomentAs(cutoff)) {
        past = reading;
        break;
      }
    }
    if (past == null) return null;
    final pastValue = double.tryParse(isTemperature ? past.temperature : past.humidity);
    if (pastValue == null) return null;
    final diff = current - pastValue;
    if (diff.abs() < 0.05) return '—';
    final arrow = diff > 0 ? '▲' : '▼';
    final formatted = isTemperature ? diff.abs().toStringAsFixed(1) : diff.abs().toStringAsFixed(0);
    final unit = isTemperature ? '°C' : '%';
    final sign = diff > 0 ? '+' : '-';
    return '$arrow $sign$formatted$unit';
  }

  Widget _metricValueWidget({
    required bool isLoading,
    required bool hasData,
    required bool isOnline,
    required TextStyle style,
    required String valueText,
    required String offlineText,
  }) {
    if (isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 16,
            width: 90,
            decoration: BoxDecoration(
              color: style.color?.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 12,
            width: 60,
            decoration: BoxDecoration(
              color: style.color?.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ],
      );
    }
    if (!hasData && !isOnline) {
      return Text(
        offlineText,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text(
      valueText,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }


  Widget _kvRow({required String label, required String value, TextStyle? style}) {
    final textStyle = style ?? Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Text(
          '$label:',
          style: textStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
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

  void _editPreset(AquariumPreset preset) {
    final label = switch (preset) {
      AquariumPreset.day => 'Day',
      AquariumPreset.night => 'Night',
      AquariumPreset.feeding => 'Feeding',
    };
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit preset'),
        content: Text('Configure $label preset settings here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _applyPreset(AquariumPreset preset, {required bool isOnline}) {
    setState(() {
      _preset = preset;
      _status = isOnline
          ? 'Preset applied: ${_presetLabel(preset)}.'
          : 'Preset queued: ${_presetLabel(preset)}.';
      _hasError = false;
    });
    _addEvent(
      HistoryEvent(
        id: _newEventId(),
        time: DateTime.now(),
        title: 'Preset ${_presetLabel(preset)}',
        message: isOnline ? 'Applied' : 'Queued',
        icon: Icons.auto_awesome_rounded,
        category: HistoryCategory.commands,
        ok: true,
      ),
    );
  }

  String _presetLabel(AquariumPreset preset) {
    return switch (preset) {
      AquariumPreset.day => 'Day',
      AquariumPreset.night => 'Night',
      AquariumPreset.feeding => 'Feeding',
    };
  }

  Future<void> _syncTime() async {
    setState(() {
      _status = 'Syncing time...';
      _hasError = false;
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _status = 'Time synced.';
    });
    _addEvent(
      HistoryEvent(
        id: _newEventId(),
        time: DateTime.now(),
        title: 'Sync time',
        message: 'Applied',
        icon: Icons.schedule_rounded,
        category: HistoryCategory.commands,
        ok: true,
      ),
    );
  }

  void _emergencyOff({required bool isOnline}) {
    setState(() {
      _flowDirection = FlowDirection.stop;
      _requestedLedState = 'off';
      _lightingStatus = isOnline ? 'Sending...' : 'Queued.';
      _status = isOnline ? 'Emergency OFF sent.' : 'Emergency OFF queued.';
    });
    _addEvent(
      HistoryEvent(
        id: _newEventId(),
        time: DateTime.now(),
        title: 'Emergency OFF',
        message: isOnline ? 'Sent' : 'Queued',
        icon: Icons.power_settings_new_rounded,
        category: HistoryCategory.commands,
        ok: true,
      ),
    );
  }

  String _flowLabel(FlowDirection direction) {
    return switch (direction) {
      FlowDirection.left => 'Left',
      FlowDirection.stop => 'Stop',
      FlowDirection.right => 'Right',
    };
  }

  Future<void> _setFlowDirection(FlowDirection direction) async {
    setState(() {
      _flowDirection = direction;
      _flowStatus = 'Sending...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _flowStatus = 'Applied.';
    });
    _addEvent(
      HistoryEvent(
        id: _newEventId(),
        time: DateTime.now(),
        title: 'Flow ${_flowLabel(direction)}',
        message: 'Applied',
        icon: Icons.swap_horiz_rounded,
        category: HistoryCategory.commands,
        ok: true,
      ),
    );
  }

  Widget _flowButton({
    required FlowDirection direction,
    required IconData icon,
    required bool isEnabled,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = _flowDirection == direction;
    final activeColor = scheme.primary;
    final baseColor = scheme.onSurfaceVariant;
    final content = InkWell(
      onTap: isEnabled ? () => _setFlowDirection(direction) : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        constraints: const BoxConstraints(minHeight: 72),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.12) : scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? activeColor : scheme.outlineVariant,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isActive ? activeColor : baseColor,
            ),
            const SizedBox(height: 6),
            Text(
              _flowLabel(direction),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isActive ? activeColor : baseColor,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
    return Expanded(
      child: isEnabled ? content : Tooltip(message: 'Not available', child: content),
    );
  }

  Widget _buildInfoBanner({required IconData icon, required String text, required Color color}) {
    return InfoCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorDetails(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error details'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return InfoCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.orange),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _showErrorDetails(message),
                child: const Text('Details'),
              ),
              FilledButton(
                onPressed: _getState,
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _surfaceCard({required Widget child}) {
    return InfoCard(padding: EdgeInsets.zero, child: child);
  }

  Widget _metricCard({
    required String title,
    required Widget value,
    required IconData icon,
    String? subtitle,
    String? updated,
    String? trend,
    Color? accent,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final accentColor = accent ?? scheme.primary;
    return _surfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            value,
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (updated != null || trend != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (updated != null)
                    Expanded(
                      child: Text(
                        updated,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (trend != null)
                    Text(
                      trend,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: scheme.primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _presetButton(AquariumPreset preset, String label, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = preset == _preset;
    final isOnline = !_hasError && _temperature != '---';
    final subtitle = switch (preset) {
      AquariumPreset.day => 'Light on · Flow right',
      AquariumPreset.night => 'Light off · Flow left',
      AquariumPreset.feeding => 'Light on · Flow stop',
    };
    final schedule = switch (preset) {
      AquariumPreset.day => '09:00–21:00',
      AquariumPreset.night => '21:00–09:00',
      AquariumPreset.feeding => 'On demand',
    };
    return Expanded(
      child: InkWell(
        onTap: () {
          _applyPreset(preset, isOnline: isOnline);
        },
        onLongPress: () => _editPreset(preset),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: isActive ? scheme.primary : scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 14,
                    color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.swap_horiz_rounded,
                    size: 14,
                    color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Schedule: $schedule',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (!isOnline) ...[
                const SizedBox(height: 6),
                Text(
                  'Will apply when online',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyList() {
    return AnimatedBuilder(
      animation: _historyStore,
      builder: (context, _) {
        final items = _historyStore.getRecent(limit: 3);
        if (items.isEmpty) {
          return Text(
            'No events yet. Try Refresh or apply a preset.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
        }
        return Column(
          children: items
              .map(
                (event) => HistoryItemTile(
                  event: event,
                  subtitle: _eventSubtitle(event),
                ),
              )
              .toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appState = AppScope.of(context);
    final isOnline = !_hasError && _temperature != '---';
    final espIp = appState.espIp;
    final ledOn = _ledState.toLowerCase() == 'on';
    final requestedLedOn = _requestedLedState == null
        ? (ledOn ? 'On' : 'Off')
        : (_requestedLedState == 'on' ? 'On' : 'Off');
    final isFlowEnabled = isOnline && !_isLoading;
    final tempTrend = _trendText(currentValue: _temperature, isTemperature: true);
    final humTrend = _trendText(currentValue: _humidity, isTemperature: false);
    final humidityValue = double.tryParse(_humidity);
    final isWaterLevelDiscrete = humidityValue != null && (humidityValue == 0 || humidityValue == 1);
    final waterLevelLabel = isWaterLevelDiscrete
        ? (humidityValue == 0 ? 'Low' : 'OK')
        : (_humidity == '---' ? '---' : '$_humidity %');
    final waterLevelSubtitle = isWaterLevelDiscrete
        ? (humidityValue == null ? null : '· ${(humidityValue * 100).toStringAsFixed(0)}%')
        : null;
    final presetLabel = _presetLabel(_preset);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _getState,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Aquarium',
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (appState.isDemo)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Demo',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: scheme.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Status: ${ledOn ? "Lights on" : "Lights off"}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Preset: $presetLabel',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: isOnline ? Colors.green : Colors.orange),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatLastOnline(),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'IP: $espIp',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                      maxLines: 1,
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
                _buildErrorBanner(_status)
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
                    value: _metricValueWidget(
                      isLoading: _isLoading,
                      hasData: _temperature != '---',
                      isOnline: isOnline,
                      valueText: '$_temperature C',
                      offlineText: 'Нет данных (offline)',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    updated: _formatUpdatedTime(),
                    trend: tempTrend != null ? '$tempTrend за 1ч' : null,
                    icon: Icons.thermostat_rounded,
                    accent: Colors.deepOrange,
                  ),
                  _metricCard(
                    title: 'Water level',
                    value: _metricValueWidget(
                      isLoading: _isLoading,
                      hasData: _humidity != '---',
                      isOnline: isOnline,
                      valueText: waterLevelLabel,
                      offlineText: 'Нет данных (offline)',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: waterLevelSubtitle,
                    updated: _formatUpdatedTime(),
                    trend: !isWaterLevelDiscrete && humTrend != null ? '$humTrend за 1ч' : null,
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
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.swap_horiz_rounded, color: scheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Flow direction',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: scheme.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _flowLabel(_flowDirection),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _flowButton(
                                  direction: FlowDirection.left,
                                  icon: Icons.arrow_left_rounded,
                                  isEnabled: isFlowEnabled,
                                ),
                                const SizedBox(width: 8),
                                _flowButton(
                                  direction: FlowDirection.stop,
                                  icon: Icons.stop_circle_outlined,
                                  isEnabled: isFlowEnabled,
                                ),
                                const SizedBox(width: 8),
                                _flowButton(
                                  direction: FlowDirection.right,
                                  icon: Icons.arrow_right_rounded,
                                  isEnabled: isFlowEnabled,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _flowStatus,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InfoCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.lightbulb_rounded, color: Colors.amber),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Lighting',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 120,
                                child: ToggleButtons(
                                  textStyle: Theme.of(context).textTheme.labelMedium,
                                  isSelected: [_isLightingAuto == false, _isLightingAuto == true],
                                  onPressed: (index) {
                                    setState(() {
                                      _isLightingAuto = index == 1;
                                    });
                                  },
                                  constraints: const BoxConstraints(minHeight: 32, minWidth: 52),
                                  children: const [
                                    Text('Man', maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('Auto', maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _kvRow(
                                      label: 'Requested',
                                      value: requestedLedOn,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 4),
                                    _kvRow(
                                      label: 'Actual',
                                      value: ledOn ? 'On' : 'Off',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Switch(
                                value: ledOn,
                                onChanged: (_) => _toggleLight(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _lightingStatus,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SectionHeader(title: 'Presets'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _presetButton(AquariumPreset.day, 'Day', Icons.wb_sunny_rounded),
                  const SizedBox(width: 8),
                  _presetButton(AquariumPreset.night, 'Night', Icons.nights_stay_rounded),
                  const SizedBox(width: 8),
                  _presetButton(AquariumPreset.feeding, 'Feeding', Icons.restaurant_rounded),
                ],
              ),
              const SizedBox(height: 16),
              const SectionHeader(title: 'Quick actions'),
              const SizedBox(height: 8),
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            FilledButton.icon(
                              onPressed: _getState,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.sync_rounded),
                              label: const Text('Refresh data'),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatUpdatedTime(),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _getState,
                          icon: const Icon(Icons.wifi_tethering_rounded),
                          label: const Text('Reconnect'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _applyPreset(_preset, isOnline: isOnline),
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: Text('Apply $presetLabel'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _syncTime,
                          icon: const Icon(Icons.schedule_rounded),
                          label: const Text('Sync time'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _emergencyOff(isOnline: isOnline),
                      icon: const Icon(Icons.power_settings_new_rounded),
                      label: const Text('Emergency OFF'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SectionHeader(
                title: 'History',
                trailing: TextButton.icon(
                  onPressed: widget.onOpenHistory,
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('Open history', maxLines: 1, overflow: TextOverflow.ellipsis),
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
