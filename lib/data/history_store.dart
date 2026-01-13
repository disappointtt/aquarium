import 'package:flutter/foundation.dart';

import '../models/history_models.dart';

class HistoryStore extends ChangeNotifier {
  HistoryStore._();

  static final HistoryStore instance = HistoryStore._();

  final List<HistoryEvent> _events = [];

  List<HistoryEvent> get events => List.unmodifiable(_events);

  void addEvent(HistoryEvent event) {
    _events.insert(0, event);
    if (_events.length > 200) {
      _events.removeLast();
    }
    notifyListeners();
  }
}
