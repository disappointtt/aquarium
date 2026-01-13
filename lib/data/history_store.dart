import 'package:flutter/foundation.dart';

import '../models/history_models.dart';

class HistoryStore extends ChangeNotifier {
  HistoryStore._();

  static final HistoryStore instance = HistoryStore._();

  final List<HistoryEvent> _events = [];

  List<HistoryEvent> get events => List.unmodifiable(_events);

  List<HistoryEvent> getRecent({int limit = 3}) {
    final items = List<HistoryEvent>.from(_events);
    items.sort((a, b) => b.time.compareTo(a.time));
    if (items.length <= limit) return items;
    return items.take(limit).toList();
  }

  List<HistoryEvent> getAllSorted({bool desc = true}) {
    final items = List<HistoryEvent>.from(_events);
    items.sort((a, b) => desc ? b.time.compareTo(a.time) : a.time.compareTo(b.time));
    return items;
  }

  List<HistoryEvent> filterByType(HistoryCategory category, {bool desc = true}) {
    final items = _events.where((event) => event.category == category).toList();
    items.sort((a, b) => desc ? b.time.compareTo(a.time) : a.time.compareTo(b.time));
    return items;
  }

  void addEvent(HistoryEvent event) {
    _events.insert(0, event);
    if (_events.length > 200) {
      _events.removeLast();
    }
    notifyListeners();
  }
}
