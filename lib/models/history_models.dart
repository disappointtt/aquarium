import 'package:flutter/material.dart';

enum HistoryFilter { all, commands, alerts, readings }

enum HistoryCategory { commands, alerts, readings }

enum HistoryLightingMode { manual, auto }

enum HistoryFlowDirection { left, stop, right }

enum HistoryConnectionState { online, offline }

class HistorySnapshot {
  final double? temperature;
  final String temperatureUnit;
  final int? waterLevelPercent;
  final bool? lightingRequested;
  final bool? lightingActual;
  final HistoryLightingMode? lightingMode;
  final HistoryFlowDirection? flowDirection;
  final HistoryConnectionState connectionState;
  final DateTime? lastSeen;

  const HistorySnapshot({
    required this.temperature,
    this.temperatureUnit = 'C',
    required this.waterLevelPercent,
    required this.lightingRequested,
    required this.lightingActual,
    required this.lightingMode,
    required this.flowDirection,
    required this.connectionState,
    required this.lastSeen,
  });
}

class HistoryEvent {
  final String id;
  final DateTime time;
  final String title;
  final String? message;
  final IconData icon;
  final HistoryCategory category;
  final bool ok;
  final HistorySnapshot? snapshot;

  const HistoryEvent({
    required this.id,
    required this.time,
    required this.title,
    this.message,
    required this.icon,
    required this.category,
    required this.ok,
    this.snapshot,
  });
}

String historyFilterLabel(HistoryFilter filter) {
  return switch (filter) {
    HistoryFilter.all => 'All',
    HistoryFilter.commands => 'Commands',
    HistoryFilter.alerts => 'Alerts',
    HistoryFilter.readings => 'Readings',
  };
}

String historyFilterShortLabel(HistoryFilter filter) {
  return switch (filter) {
    HistoryFilter.all => 'All',
    HistoryFilter.commands => 'Cmd',
    HistoryFilter.alerts => 'Alerts',
    HistoryFilter.readings => 'Reads',
  };
}
