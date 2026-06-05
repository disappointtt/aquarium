import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aquarium_app/main.dart';

void main() {
  testWidgets('Приложение открывает главный экран', (tester) async {
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

  testWidgets('Открытие аквариума выбирает профиль', (tester) async {
    final appState = AppState(
      themeMode: ThemeMode.light,
      isDemo: true,
      espIp: '192.168.0.103',
      aquariums: const [
        AquariumProfile(
          id: 'tropical',
          name: 'Tropical Tank',
          espIp: '192.168.0.103',
        ),
        AquariumProfile(id: 'reef', name: 'Риф', espIp: '192.168.0.104'),
      ],
      activeAquariumId: 'reef',
    );

    await tester.pumpWidget(AppScope(notifier: appState, child: const MyApp()));
    await tester.tap(find.text('Aquarium'));
    await tester.pump();

    expect(find.text('Аквариумы'), findsOneWidget);

    await tester.tap(find.text('Открыть').first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('Tropical Tank'), findsOneWidget);
    expect(find.text('Температура'), findsOneWidget);
  });

  testWidgets('Сохранение настроек обновляет профиль', (tester) async {
    final appState = AppState(
      themeMode: ThemeMode.light,
      isDemo: true,
      espIp: '192.168.0.103',
    );

    await tester.pumpWidget(AppScope(notifier: appState, child: const MyApp()));
    await tester.tap(find.text('Aquarium'));
    await tester.pump();

    await tester.tap(find.text('Настроить').first);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Настройка аквариума'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Office Tank');
    await tester.enterText(find.byType(TextField).at(1), '10.38.25.74');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Office Tank'), findsOneWidget);
    expect(appState.activeAquarium.espIp, '10.38.25.74');
  });
}
