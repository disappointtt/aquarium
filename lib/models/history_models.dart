import 'package:flutter/material.dart';

enum HistoryFilter { all, commands, alerts, readings }

enum HistoryCategory { commands, alerts, readings }

class HistoryEvent {
  final DateTime time;
  final String title;
  final String? detail;
  final IconData icon;
  final HistoryCategory category;
  final bool ok;

  const HistoryEvent({
    required this.time,
    required this.title,
    this.detail,
    required this.icon,
    required this.category,
    required this.ok,
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
