import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/history_store.dart';
import '../models/history_models.dart';

enum HistorySort { desc, asc }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final HistoryStore _historyStore = HistoryStore.instance;
  HistoryFilter _historyFilter = HistoryFilter.all;
  HistorySort _historySort = HistorySort.desc;

  String _formatEventTime(DateTime time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _dayLabel(DateTime date) {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateUtils.dateOnly(DateTime.now().subtract(const Duration(days: 1)));
    final day = DateUtils.dateOnly(date);
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    final dd = day.day.toString().padLeft(2, '0');
    final mm = day.month.toString().padLeft(2, '0');
    final yyyy = day.year.toString();
    return '$dd.$mm.$yyyy';
  }

  String _historyFlowLabel(HistoryFlowDirection direction) {
    return switch (direction) {
      HistoryFlowDirection.left => 'Left',
      HistoryFlowDirection.stop => 'Stop',
      HistoryFlowDirection.right => 'Right',
    };
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
    if (event.detail != null) {
      return '${_formatEventTime(event.time)} - ${event.detail}';
    }
    return _formatEventTime(event.time);
  }


  List<HistoryEvent> _filteredEvents(List<HistoryEvent> events) {
    final filtered = events.where((event) {
      return switch (_historyFilter) {
        HistoryFilter.all => true,
        HistoryFilter.commands => event.category == HistoryCategory.commands,
        HistoryFilter.alerts => event.category == HistoryCategory.alerts,
        HistoryFilter.readings => event.category == HistoryCategory.readings,
      };
    }).toList();
    filtered.sort((a, b) {
      final compare = a.time.compareTo(b.time);
      return _historySort == HistorySort.desc ? -compare : compare;
    });
    return filtered;
  }

  void _exportEvents({required bool asJson}) {
    final items = _filteredEvents(_historyStore.events)
        .map((e) {
          final snapshot = e.snapshot;
          final lightingMode = snapshot?.lightingMode;
          final flowDirection = snapshot?.flowDirection;
          final connectionState = snapshot?.connectionState;
          return {
            'time': e.time.toIso8601String(),
            'title': e.title,
            'detail': e.detail ?? '',
            'category': e.category.name,
            'result': e.ok ? 'OK' : 'Fail',
            'temperature': snapshot?.temperature,
            'temperatureUnit': snapshot?.temperatureUnit,
            'waterLevelPercent': snapshot?.waterLevelPercent,
            'lightingRequested': snapshot?.lightingRequested,
            'lightingActual': snapshot?.lightingActual,
            'lightingMode': lightingMode?.name,
            'flowDirection': flowDirection?.name,
            'connectionState': connectionState?.name,
            'lastSeen': snapshot?.lastSeen?.toIso8601String(),
          };
        })
        .toList();
    if (asJson) {
      final payload = jsonEncode(items);
      Clipboard.setData(ClipboardData(text: payload));
    } else {
      final rows = [
        'time,title,detail,category,result,temperature,temperatureUnit,waterLevelPercent,lightingRequested,lightingActual,lightingMode,flowDirection,connectionState,lastSeen',
        ...items.map(
          (e) =>
              '"${e['time'] ?? ''}","${e['title'] ?? ''}","${e['detail'] ?? ''}","${e['category'] ?? ''}","${e['result'] ?? ''}","${e['temperature'] ?? ''}","${e['temperatureUnit'] ?? ''}","${e['waterLevelPercent'] ?? ''}","${e['lightingRequested'] ?? ''}","${e['lightingActual'] ?? ''}","${e['lightingMode'] ?? ''}","${e['flowDirection'] ?? ''}","${e['connectionState'] ?? ''}","${e['lastSeen'] ?? ''}"',
        ),
      ];
      Clipboard.setData(ClipboardData(text: rows.join('\n')));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${asJson ? 'JSON' : 'CSV'} to clipboard.')),
    );
  }



  void _showExportDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export'),
        content: const Text('Copy events to clipboard.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _exportEvents(asJson: true);
            },
            child: const Text('JSON'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _exportEvents(asJson: false);
            },
            child: const Text('CSV'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _eventTile(HistoryEvent event) {
    final scheme = Theme.of(context).colorScheme;
    final color = event.ok ? Colors.green : Colors.red;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withOpacity(0.12),
        child: Icon(
          event.icon,
          color: color,
          size: 18,
        ),
      ),
      title: Text(event.title),
      subtitle: Text(
        _eventSubtitle(event),
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        event.ok ? 'OK' : 'Fail',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  const Spacer(),
                  Text(
                    'History',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _showExportDialog,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Export'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<HistoryFilter>(
                  segments: HistoryFilter.values
                      .map(
                        (filter) => ButtonSegment(
                          value: filter,
                          label: Text(historyFilterLabel(filter)),
                        ),
                      )
                      .toList(),
                  selected: {_historyFilter},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _historyFilter = selection.first;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Sort',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<HistorySort>(
                    segments: const [
                      ButtonSegment(
                        value: HistorySort.desc,
                        label: Text('DESC'),
                      ),
                      ButtonSegment(
                        value: HistorySort.asc,
                        label: Text('ASC'),
                      ),
                    ],
                    selected: {_historySort},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _historySort = selection.first;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedBuilder(
                animation: _historyStore,
                builder: (context, _) {
                  final events = _filteredEvents(_historyStore.events);
                  if (events.isEmpty) {
                    return Center(
                      child: Text(
                        'No events yet. Try Refresh or apply a preset.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    );
                  }
                  final items = <Widget>[];
                  DateTime? currentDay;
                  for (final event in events) {
                    final day = DateUtils.dateOnly(event.time);
                    if (currentDay == null || day != currentDay) {
                      currentDay = day;
                      items.add(
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Text(
                            _dayLabel(event.time),
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    }
                    items.add(_eventTile(event));
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    children: items,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
