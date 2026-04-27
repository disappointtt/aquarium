import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquarium_app/main.dart';

void main() {
  testWidgets('Aquarium app starts on the home screen', (tester) async {
    final appState = AppState(
      themeMode: ThemeMode.light,
      isDemo: true,
      espIp: '192.168.0.103',
    );

    await tester.pumpWidget(AppScope(notifier: appState, child: const MyApp()));

    expect(find.text('Tropical Tank'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Температура'), findsOneWidget);
    expect(find.text('Уровень воды'), findsOneWidget);
  });
}
