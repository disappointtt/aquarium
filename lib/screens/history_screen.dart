import 'package:flutter/material.dart';

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
    final yesterday = DateUtils.dateOnly(
      DateTime.now().subtract(const Duration(days: 1)),
    );
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
    return _historyStore.filterByType(
      _mapFilterToCategory(_historyFilter),
      desc: desc,
    );
  }

  Widget _eventTile(HistoryEvent event) {
    return HistoryItemTile(event: event, subtitle: _eventSubtitle(event));
  }

  String _filterLabel(HistoryFilter filter) {
    return switch (filter) {
      HistoryFilter.all => 'Все',
      HistoryFilter.commands => 'Команды',
      HistoryFilter.alerts => 'Опасности',
      HistoryFilter.readings => 'Показания',
    };
  }

  String _sortLabel(HistorySort sort) {
    return switch (sort) {
      HistorySort.desc => 'Новые',
      HistorySort.asc => 'Старые',
    };
  }

  ButtonStyle _segmentStyle(BuildContext context) {
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(42)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8),
      ),
      textStyle: WidgetStatePropertyAll(
        Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800) ??
            const TextStyle(fontWeight: FontWeight.w800),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
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
          child: Icon(Icons.history_rounded, color: scheme.onPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'История',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Команды, показания и опасности',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
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
              child: _header(context),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InfoCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<HistoryFilter>(
                        style: _segmentStyle(context),
                        showSelectedIcon: false,
                        segments: HistoryFilter.values
                            .map(
                              (filter) => ButtonSegment(
                                value: filter,
                                label: Text(
                                  _filterLabel(filter),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
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
                    const SizedBox(height: 10),
                    Text(
                      'Сортировка',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<HistorySort>(
                        style: _segmentStyle(context),
                        showSelectedIcon: false,
                        segments: HistorySort.values
                            .map(
                              (sort) => ButtonSegment(
                                value: sort,
                                label: Text(
                                  _sortLabel(sort),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                            .toList(),
                        selected: {_historySort},
                        onSelectionChanged: (selection) {
                          setState(() {
                            _historySort = selection.first;
                          });
                        },
                      ),
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
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
                            style: Theme.of(context).textTheme.labelMedium
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
