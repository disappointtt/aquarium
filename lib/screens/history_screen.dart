import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/history_store.dart';
import '../models/history_models.dart';
import '../widgets/ui_components.dart';

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
    if (event.message != null) {
      return '${_formatEventTime(event.time)} - ${event.message}';
    }
    return _formatEventTime(event.time);
  }


  HistoryCategory _mapFilterToCategory(HistoryFilter filter) {
    return switch (filter) {
      HistoryFilter.commands => HistoryCategory.commands,
      HistoryFilter.alerts => HistoryCategory.alerts,
      HistoryFilter.readings => HistoryCategory.readings,
      HistoryFilter.all => HistoryCategory.readings,
    };
  }

  List<HistoryEvent> _filteredEvents() {
    final desc = _historySort == HistorySort.desc;
    if (_historyFilter == HistoryFilter.all) {
      return _historyStore.getAllSorted(desc: desc);
    }
    return _historyStore.filterByType(_mapFilterToCategory(_historyFilter), desc: desc);
  }

  void _exportEvents({required bool asJson}) {
    final items = _filteredEvents()
        .map((e) {
          final snapshot = e.snapshot;
          final lightingMode = snapshot?.lightingMode;
          final flowDirection = snapshot?.flowDirection;
          final connectionState = snapshot?.connectionState;
          return {
            'id': e.id,
            'time': e.time.toIso8601String(),
            'title': e.title,
            'message': e.message ?? '',
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
        'id,time,title,message,category,result,temperature,temperatureUnit,waterLevelPercent,lightingRequested,lightingActual,lightingMode,flowDirection,connectionState,lastSeen',
        ...items.map(
          (e) =>
              '"${e['id'] ?? ''}","${e['time'] ?? ''}","${e['title'] ?? ''}","${e['message'] ?? ''}","${e['category'] ?? ''}","${e['result'] ?? ''}","${e['temperature'] ?? ''}","${e['temperatureUnit'] ?? ''}","${e['waterLevelPercent'] ?? ''}","${e['lightingRequested'] ?? ''}","${e['lightingActual'] ?? ''}","${e['lightingMode'] ?? ''}","${e['flowDirection'] ?? ''}","${e['connectionState'] ?? ''}","${e['lastSeen'] ?? ''}"',
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
    return HistoryItemTile(
      event: event,
      subtitle: _eventSubtitle(event),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SectionHeader(
                title: 'History',
                titleStyle: Theme.of(context).textTheme.titleMedium,
                trailing: OutlinedButton.icon(
                  onPressed: _showExportDialog,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Export', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InfoCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<HistoryFilter>(
                        showSelectedIcon: false,
                        segments: HistoryFilter.values
                            .map(
                              (filter) => ButtonSegment(
                                value: filter,
                                label: Text(
                                  historyFilterShortLabel(filter),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Sort',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 12),
                        SegmentedButton<HistorySort>(
                          style: ButtonStyle(
                            fixedSize:
                                const MaterialStatePropertyAll(Size(72, 32)),
                            padding: const MaterialStatePropertyAll(
                              EdgeInsets.symmetric(horizontal: 0),
                            ),
                            textStyle: MaterialStatePropertyAll(
                              Theme.of(context).textTheme.labelMedium ??
                                  const TextStyle(),
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: HistorySort.desc,
                              label: Text('DESC', maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            ButtonSegment(
                              value: HistorySort.asc,
                              label: Text('ASC', maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AnimatedBuilder(
                animation: _historyStore,
                builder: (context, _) {
                  final events = _filteredEvents();
                  if (events.isEmpty) {
                    return Center(
                      child: Text(
                        'No events yet. Try Refresh or apply a preset.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }
                    items.add(_eventTile(event));
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
