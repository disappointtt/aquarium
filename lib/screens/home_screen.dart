// ignore_for_file: deprecated_member_use, unused_element, unused_field, prefer_final_fields

import 'dart:async';
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

  Reading({
    required this.time,
    required this.temperature,
    required this.humidity,
  });
}

enum AquariumPreset { day, night, feeding }

enum FlowDirection { left, stop, right }

class AquariumAlert {
  final String key;
  final String title;
  final String message;
  final IconData icon;

  const AquariumAlert({
    required this.key,
    required this.title,
    required this.message,
    required this.icon,
  });
}

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
  bool _isLoading = false;
  bool _isLightingAuto = false;
  String _lightingStatus = 'Idle';
  DateTime? _lastOnlineAt;
  DateTime? _lastUpdatedAt;
  AquariumPreset _preset = AquariumPreset.day;
  FlowDirection _flowDirection = FlowDirection.stop;
  String _flowStatus = 'Idle';
  String _compressorState = 'unknown';
  String _compressorStatus = 'Idle';
  String _systemMode = '---';
  String _pumpState = '---';
  String _espTime = '--:--:--';
  String _timeSynced = '---';
  String _historyInfo = '---';
  String _cleanState = '---';
  String _tempSlope = '--';
  String _levelSlope = '--';
  String _daysToLowTemp = '--';
  String _daysToLowLevel = '--';
  final List<Reading> _history = [];
  final HistoryStore _historyStore = HistoryStore.instance;
  bool _wasOnline = false;
  Timer? _alertRepeatTimer;
  DateTime? _lightOffSince;
  final Map<String, DateTime> _lastAlertTimes = {};
  final Map<String, AquariumAlert> _activeAlerts = {};

  static const Duration _alertRepeatInterval = Duration(minutes: 2);
  static const Duration _lightOffAlertDelay = Duration(minutes: 3);

  String _apiBase(String ip) => 'http://$ip';

  String _onOffFromFlag(dynamic value) {
    if (value == null) return 'unknown';
    final text = value.toString().toLowerCase();
    return text == '1' || text == 'true' || text == 'on' ? 'on' : 'off';
  }

  String _dashIfNull(dynamic value, {int? fractionDigits}) {
    if (value == null) return '---';
    if (value is num && fractionDigits != null) {
      return value.toStringAsFixed(fractionDigits);
    }
    return value.toString();
  }

  bool _isDiscreteWaterLevel(double? value) {
    return value != null && (value == 0 || value == 1);
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
      _compressorState = Random().nextBool() ? 'on' : 'off';
      _systemMode = 'IDLE';
      _pumpState = 'OFF';
      _espTime = TimeOfDay.now().format(context);
      _timeSynced = 'OK';
      _historyInfo = '${_history.length} / 120';
      _cleanState = 'Ready';
      _tempSlope = '0.000';
      _levelSlope = '0.000';
      _daysToLowTemp = '--';
      _daysToLowLevel = '--';
      _updateFromResponse(demoLed, demoTemp, demoHum, isDemo: true);
      _recordRefresh(ok: true, message: 'Demo data updated');
      return;
    }

    try {
      final client = http.Client();
      final response = await client
          .get(Uri.parse('${_apiBase(espIp)}/status'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final led = _onOffFromFlag(data['led']);
        final temp = _dashIfNull(data['temp'], fractionDigits: 1);
        final hum = _dashIfNull(data['levelPercent'], fractionDigits: 1);
        _updateSystemStatus(data);
        _updateFromResponse(led, temp, hum, isDemo: false);
        await _getAnalytics();
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
      _lightingStatus = 'Sending';
    });
    if (appState.isDemo) {
      setState(() {
        _ledState = nextState;
        _status = 'Light toggled (demo mode).';
        _hasError = false;
        _requestedLedState = null;
        _lightingStatus = 'Done';
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
          .get(Uri.parse('${_apiBase(espIp)}/led?state=$nextState'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _getState();
        if (mounted) {
          setState(() {
            _requestedLedState = null;
            _lightingStatus = 'Done';
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
          _lightingStatus = 'Failed';
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
        _lightingStatus = 'Failed';
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

  void _updateFromResponse(
    String led,
    String temp,
    String hum, {
    required bool isDemo,
  }) {
    setState(() {
      _ledState = led;
      _temperature = temp;
      _humidity = hum;
      _status = isDemo ? 'Demo readings updated.' : 'Readings updated.';
      _hasError = false;
      _pushHistory(temp, hum);
      _lastOnlineAt = DateTime.now();
      _lastUpdatedAt = DateTime.now();
      _isLoading = false;
    });
    _markConnection(true);
    _evaluateAlerts();
  }

  void _updateSystemStatus(Map<String, dynamic> data) {
    final mode = data['mode']?.toString() ?? '---';
    final pump = _onOffFromFlag(data['pump']);
    final compressor = _onOffFromFlag(data['compressor']);
    final canClean = _onOffFromFlag(data['canClean']) == 'on';
    final progress = _dashIfNull(data['cleanProgress']);
    _compressorState = compressor;
    _systemMode = mode;
    _pumpState = pump == 'on' ? 'ON' : 'OFF';
    _espTime = data['time']?.toString() ?? '--:--:--';
    _timeSynced = _onOffFromFlag(data['timeSynced']) == 'on' ? 'OK' : 'NO';
    _historyInfo = '${data['historyCount'] ?? 0} / 120';
    _cleanState = mode == 'CLEANING'
        ? '$progress%'
        : (canClean ? 'Ready' : 'Blocked');
    _flowDirection = data['motor'] == 1 ? _flowDirection : FlowDirection.stop;
  }

  Future<void> _getAnalytics() async {
    if (AppScope.of(context).isDemo) return;
    try {
      final espIp = AppScope.of(context).espIp;
      final response = await http
          .get(Uri.parse('${_apiBase(espIp)}/analytics'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return;
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _tempSlope = _dashIfNull(data['tempSlope'], fractionDigits: 3);
        _levelSlope = _dashIfNull(data['levelSlope'], fractionDigits: 3);
        _daysToLowTemp = _dashIfNull(data['daysToLowTemp'], fractionDigits: 1);
        _daysToLowLevel = _dashIfNull(
          data['daysToLowLevel'],
          fractionDigits: 1,
        );
      });
    } catch (_) {
      // Analytics is secondary; keep sensor status visible if this endpoint fails.
    }
  }

  void _evaluateAlerts() {
    if (!mounted || _hasError) return;
    final now = DateTime.now();
    final tempValue = double.tryParse(_temperature);
    final levelValue = double.tryParse(_humidity);
    final waterLevelPercent = levelValue == null
        ? null
        : (levelValue <= 1 ? levelValue * 100 : levelValue);
    final ledOff = _ledState.toLowerCase() == 'off';

    if (ledOff) {
      _lightOffSince ??= now;
    } else {
      _lightOffSince = null;
    }

    final alerts = <AquariumAlert>[];
    if (waterLevelPercent != null && waterLevelPercent < 80) {
      alerts.add(
        AquariumAlert(
          key: 'water-low',
          title: 'Низкий уровень воды',
          message:
              'Уровень воды ниже 80%: ${waterLevelPercent.toStringAsFixed(0)}%',
          icon: Icons.water_drop_outlined,
        ),
      );
    }
    if (waterLevelPercent != null && waterLevelPercent > 95) {
      alerts.add(
        AquariumAlert(
          key: 'water-high',
          title: 'Высокий уровень воды',
          message:
              'Уровень воды выше 95%: ${waterLevelPercent.toStringAsFixed(0)}%',
          icon: Icons.water_rounded,
        ),
      );
    }
    if (tempValue != null && tempValue < 15) {
      alerts.add(
        AquariumAlert(
          key: 'temp-low',
          title: 'Вода слишком холодная',
          message: 'Температура ниже 15 C: ${tempValue.toStringAsFixed(1)} C',
          icon: Icons.ac_unit_rounded,
        ),
      );
    }
    if (tempValue != null && tempValue > 20) {
      alerts.add(
        AquariumAlert(
          key: 'temp-high',
          title: 'Вода слишком горячая',
          message: 'Температура выше 20 C: ${tempValue.toStringAsFixed(1)} C',
          icon: Icons.local_fire_department_rounded,
        ),
      );
    }
    final lightOffSince = _lightOffSince;
    if (ledOff &&
        lightOffSince != null &&
        now.difference(lightOffSince) >= _lightOffAlertDelay) {
      alerts.add(
        AquariumAlert(
          key: 'light-off-long',
          title: 'Свет долго выключен',
          message: 'Свет выключен дольше 3 минут',
          icon: Icons.lightbulb_outline_rounded,
        ),
      );
    }

    final activeKeys = alerts.map((alert) => alert.key).toSet();
    _lastAlertTimes.removeWhere((key, _) => !activeKeys.contains(key));

    setState(() {
      _activeAlerts
        ..clear()
        ..addEntries(alerts.map((alert) => MapEntry(alert.key, alert)));
    });

    for (final alert in alerts) {
      _sendAlertIfDue(alert, now: now);
    }
  }

  void _sendAlertIfDue(AquariumAlert alert, {required DateTime now}) {
    final lastSentAt = _lastAlertTimes[alert.key];
    if (lastSentAt != null &&
        now.difference(lastSentAt) < _alertRepeatInterval) {
      return;
    }
    _lastAlertTimes[alert.key] = now;
    _addEvent(
      HistoryEvent(
        id: _newEventId(time: now, tag: alert.key),
        time: now,
        title: alert.title,
        message: alert.message,
        icon: alert.icon,
        category: HistoryCategory.alerts,
        ok: false,
        snapshot: _buildSnapshot(ok: true),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(alert.message),
        duration: const Duration(seconds: 4),
      ),
    );
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
      waterLevelPercent = humidityValue <= 1
          ? (humidityValue * 100).round()
          : humidityValue.round();
    }
    final actualLight = ok ? _ledState.toLowerCase() == 'on' : null;
    final requestedLight = ok
        ? (_requestedLedState == null
              ? actualLight
              : _requestedLedState == 'on')
        : null;
    final lightingMode = ok
        ? (_isLightingAuto
              ? HistoryLightingMode.auto
              : HistoryLightingMode.manual)
        : null;
    final flowDirection = ok ? _mapFlowDirection(_flowDirection) : null;
    final connectionState = ok
        ? HistoryConnectionState.online
        : HistoryConnectionState.offline;
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
    final water = snapshot.waterLevelPercent != null
        ? '${snapshot.waterLevelPercent}%'
        : '-';
    String light;
    if (snapshot.lightingActual == null) {
      light = '-';
    } else {
      light = snapshot.lightingActual! ? 'ON' : 'OFF';
      if (snapshot.lightingMode != null) {
        final mode = snapshot.lightingMode == HistoryLightingMode.auto
            ? 'Auto'
            : 'Manual';
        light = '$light ($mode)';
      }
    }
    final flow = snapshot.flowDirection != null
        ? _historyFlowLabel(snapshot.flowDirection!)
        : '-';
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

  String? _trendText({
    required String currentValue,
    required bool isTemperature,
  }) {
    final current = double.tryParse(currentValue);
    if (current == null) return null;
    if (_history.length < 2) return null;
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    Reading? past;
    for (final reading in _history) {
      if (reading.time.isBefore(cutoff) ||
          reading.time.isAtSameMomentAs(cutoff)) {
        past = reading;
        break;
      }
    }
    if (past == null) return null;
    final pastValue = double.tryParse(
      isTemperature ? past.temperature : past.humidity,
    );
    if (pastValue == null) return null;
    final diff = current - pastValue;
    if (diff.abs() < 0.05) return '—';
    final arrow = diff > 0 ? '▲' : '▼';
    final formatted = isTemperature
        ? diff.abs().toStringAsFixed(1)
        : diff.abs().toStringAsFixed(0);
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

  Widget _kvRow({
    required String label,
    required String value,
    TextStyle? style,
  }) {
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

  Widget _kvSplitRow({
    required String label,
    required String value,
    TextStyle? style,
  }) {
    final textStyle = style ?? Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label:',
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: textStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _statusRow(String status) {
    final scheme = Theme.of(context).colorScheme;
    final normalized = status.toLowerCase();
    var icon = Icons.circle_outlined;
    var color = scheme.onSurfaceVariant;
    if (normalized.contains('fail')) {
      icon = Icons.error_rounded;
      color = Colors.red;
    } else if (normalized.contains('send') || normalized.contains('queue')) {
      icon = Icons.schedule_rounded;
      color = Colors.orange;
    } else if (normalized.contains('done') || normalized.contains('applied')) {
      icon = Icons.check_circle_rounded;
      color = Colors.green;
    }
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            status,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _copyIp(String ip) {
    Clipboard.setData(ClipboardData(text: ip));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('IP copied.')));
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
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
      _lightingStatus = isOnline ? 'Sending' : 'Queued';
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
    final appState = AppScope.of(context);
    setState(() {
      _flowDirection = direction;
      _flowStatus = 'Sending';
    });
    if (!appState.isDemo) {
      try {
        final state = direction == FlowDirection.stop ? 'off' : 'on';
        final dir = direction == FlowDirection.left ? 'back' : 'forward';
        final url = direction == FlowDirection.stop
            ? '${_apiBase(appState.espIp)}/motor?state=$state'
            : '${_apiBase(appState.espIp)}/motor?state=$state&dir=$dir';
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        final data = json.decode(response.body) as Map<String, dynamic>;
        _updateSystemStatus(data);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _flowStatus = 'Failed';
          _status = 'Request error: ${e.toString()}';
          _hasError = true;
        });
        return;
      }
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    if (!mounted) return;
    setState(() {
      _flowStatus = 'Done';
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

  Future<void> _setCompressor(bool enabled) async {
    final appState = AppScope.of(context);
    final nextState = enabled ? 'on' : 'off';
    setState(() {
      _compressorStatus = 'Sending';
    });
    if (appState.isDemo) {
      setState(() {
        _compressorState = nextState;
        _compressorStatus = 'Done';
      });
      return;
    }
    try {
      final response = await http
          .get(
            Uri.parse(
              '${_apiBase(appState.espIp)}/compressor?state=$nextState',
            ),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _updateSystemStatus(data);
        _compressorStatus = 'Done';
        _status = 'Compressor ${enabled ? "ON" : "OFF"} applied.';
        _hasError = false;
      });
      _addEvent(
        HistoryEvent(
          id: _newEventId(),
          time: DateTime.now(),
          title: 'Compressor ${enabled ? "ON" : "OFF"}',
          message: 'Applied',
          icon: Icons.air_rounded,
          category: HistoryCategory.commands,
          ok: true,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _compressorStatus = 'Failed';
        _status = 'Request error: ${e.toString()}';
        _hasError = true;
      });
    }
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
            Icon(icon, color: isActive ? activeColor : baseColor),
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
      child: isEnabled
          ? content
          : Tooltip(message: 'Not available', child: content),
    );
  }

  Widget _buildInfoBanner({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return InfoCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.orange),
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
              FilledButton(onPressed: _getState, child: const Text('Retry')),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (trend != null)
                    Text(
                      trend,
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: scheme.primary),
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
                  Icon(
                    icon,
                    color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isActive
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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

  Widget _appHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
  }) {
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
          child: Icon(icon, color: scheme.onPrimary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactMetric({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InfoCard(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: 94,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withOpacity(0.36),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.labelMedium,
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

  Widget _primaryActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    return SizedBox(
      height: 42,
      child: danger
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18),
              label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
    );
  }

  Widget _compactPresetButton(
    AquariumPreset preset,
    String label,
    IconData icon,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = preset == _preset;
    final isOnline = !_hasError && _temperature != '---';
    return Expanded(
      child: InkWell(
        onTap: () => _applyPreset(preset, isOnline: isOnline),
        onLongPress: () => _editPreset(preset),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 78,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isActive ? scheme.primary.withOpacity(0.12) : scheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const Spacer(),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (!isOnline) ...[
                const SizedBox(height: 2),
                Text(
                  'queued',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeRedesign({
    required bool isOnline,
    required String espIp,
    required bool ledOn,
    required String requestedLedOn,
    required bool isFlowEnabled,
    required String waterLevelLabel,
    required String presetLabel,
    required AquariumAlert? activeAlert,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final appState = AppScope.of(context);
    final connectionColor = isOnline ? Colors.green : Colors.orange;
    final alertColor = activeAlert == null ? scheme.primary : Colors.red;
    final alertIcon = activeAlert?.icon ?? Icons.info_outline_rounded;
    final alertText = _hasError
        ? _offlineReason(_status)
        : (activeAlert?.message ?? _status);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _getState,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _appHeader(
                title: 'Аквариум',
                subtitle:
                    '${isOnline ? "Online" : "Offline"} · ${_formatUpdatedTime()}',
                icon: Icons.water_drop_rounded,
                trailing: appState.isDemo
                    ? _statusChip(
                        icon: Icons.science_rounded,
                        label: 'Demo',
                        color: scheme.primary,
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              InfoCard(
                padding: EdgeInsets.zero,
                child: Container(
                  height: 132,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12343B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2EC4B6).withOpacity(0.78),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Tropical Tank',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _statusChip(
                                icon: isOnline
                                    ? Icons.wifi_rounded
                                    : Icons.wifi_off_rounded,
                                label: isOnline ? 'Online' : 'Offline',
                                color: connectionColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${ledOn ? "Свет включен" : "Свет выключен"} · поток ${_flowLabel(_flowDirection).toLowerCase()} · $presetLabel',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFFBFE7E2)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Text(
                            waterLevelLabel,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildInfoBanner(
                icon: alertIcon,
                text: alertText,
                color: alertColor,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _compactMetric(
                      title: 'Температура',
                      value: _temperature == '---' ? '---' : '$_temperature C',
                      subtitle: _tempSlope == '--'
                          ? 'нет тренда'
                          : '$_tempSlope C/ч',
                      icon: Icons.thermostat_rounded,
                      color: Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _compactMetric(
                      title: 'Уровень воды',
                      value: waterLevelLabel,
                      subtitle: _levelSlope == '--'
                          ? 'нет тренда'
                          : '$_levelSlope %/ч',
                      icon: Icons.water_rounded,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SectionHeader(title: 'Статус системы'),
              const SizedBox(height: 8),
              InfoCard(
                padding: const EdgeInsets.all(12),
                child: GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 3.1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    _miniStat('Режим', _systemMode, Icons.tune_rounded),
                    _miniStat('Помпа', _pumpState, Icons.waterfall_chart),
                    _miniStat(
                      'Компрессор',
                      _compressorState == 'on' ? 'ON' : 'OFF',
                      Icons.air_rounded,
                    ),
                    _miniStat('ESP', _espTime, Icons.schedule_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SectionHeader(title: 'Управление'),
              const SizedBox(height: 8),
              InfoCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _miniStat(
                            'Свет',
                            '${ledOn ? "ON" : "OFF"} · $requestedLedOn',
                            Icons.lightbulb_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: ledOn,
                          onChanged: _isLightingAuto
                              ? null
                              : (_) => _toggleLight(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
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
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _primaryActionButton(
                            label: 'Компрессор ON',
                            icon: Icons.play_arrow_rounded,
                            onPressed: isOnline && !_isLoading
                                ? () => _setCompressor(true)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _primaryActionButton(
                            label: 'OFF',
                            icon: Icons.stop_rounded,
                            onPressed: isOnline && !_isLoading
                                ? () => _setCompressor(false)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SectionHeader(title: 'Пресеты'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _compactPresetButton(
                    AquariumPreset.day,
                    'Day',
                    Icons.wb_sunny_rounded,
                  ),
                  const SizedBox(width: 8),
                  _compactPresetButton(
                    AquariumPreset.night,
                    'Night',
                    Icons.nights_stay_rounded,
                  ),
                  const SizedBox(width: 8),
                  _compactPresetButton(
                    AquariumPreset.feeding,
                    'Feed',
                    Icons.restaurant_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SectionHeader(title: 'Быстрые команды'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _primaryActionButton(
                      label: 'Refresh',
                      icon: Icons.sync_rounded,
                      onPressed: _getState,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _primaryActionButton(
                      label: 'Sync time',
                      icon: Icons.schedule_rounded,
                      onPressed: _syncTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _primaryActionButton(
                label: 'Emergency OFF',
                icon: Icons.power_settings_new_rounded,
                onPressed: () => _emergencyOff(isOnline: isOnline),
                danger: true,
              ),
              const SizedBox(height: 16),
              SectionHeader(
                title: 'История',
                trailing: TextButton(
                  onPressed: widget.onOpenHistory,
                  child: const Text('Открыть'),
                ),
              ),
              const SizedBox(height: 8),
              _historyList(),
              const SizedBox(height: 4),
              Text(
                'IP: $espIp',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _alertRepeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _evaluateAlerts();
    });
  }

  @override
  void dispose() {
    _alertRepeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    final isOnline = !_hasError && _temperature != '---';
    final espIp = appState.espIp;
    final ledOn = _ledState.toLowerCase() == 'on';
    final requestedLedOn = _requestedLedState == null
        ? (ledOn ? 'On' : 'Off')
        : (_requestedLedState == 'on' ? 'On' : 'Off');
    final isFlowEnabled = isOnline && !_isLoading;
    final humidityValue = double.tryParse(_humidity);
    final isWaterLevelDiscrete = _isDiscreteWaterLevel(humidityValue);
    final waterLevelLabel = isWaterLevelDiscrete
        ? (humidityValue == 0 ? 'Low' : 'OK')
        : (_humidity == '---' ? '---' : '$_humidity %');
    final presetLabel = _presetLabel(_preset);
    final activeAlert = _activeAlerts.isEmpty
        ? null
        : _activeAlerts.values.first;

    return _homeRedesign(
      isOnline: isOnline,
      espIp: espIp,
      ledOn: ledOn,
      requestedLedOn: requestedLedOn,
      isFlowEnabled: isFlowEnabled,
      waterLevelLabel: waterLevelLabel,
      presetLabel: presetLabel,
      activeAlert: activeAlert,
    );
  }
}
