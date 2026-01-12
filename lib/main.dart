import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';

// Ключи для SharedPreferences
const _kPrefThemeMode = 'theme_mode';
const _kPrefDemoMode = 'demo_mode';

/// Глобальное состояние приложения (тема, демо-режим, профиль пользователя).
class AppState extends ChangeNotifier {
  AppState({
    required this.themeMode,
    required this.isDemo,
  });

  ThemeMode themeMode;
  bool isDemo;

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_kPrefThemeMode, mode.name);
  }

  Future<void> setDemoMode(bool enabled) async {
    isDemo = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool(_kPrefDemoMode, enabled);
  }
}

/// Inherited-обёртка для доступа к AppState из любого экрана.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required AppState notifier,
    required Widget child,
  }) : super(notifier: notifier, child: child);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in context');
    return scope!.notifier!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => notifier != oldWidget.notifier;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  final themeName = prefs.getString(_kPrefThemeMode);
  final bool demo = prefs.getBool(_kPrefDemoMode) ?? false;

  final themeMode = switch (themeName) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };

  final appState = AppState(
    themeMode: themeMode,
    isDemo: demo,
  );

  runApp(AppScope(
    notifier: appState,
    child: const MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ColorScheme _colorScheme(Brightness brightness) {
    // Спокойный «водный» синий как базовый акцент.
    final seed = const Color(0xFF2E8BC0);
    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      primaryContainer: brightness == Brightness.light
          ? const Color(0xFFE3F2FB)
          : const Color(0xFF0D1B2A),
      surface: brightness == Brightness.light
          ? const Color(0xFFF7FBFF)
          : const Color(0xFF0B1320),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = _colorScheme(brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        fillColor: scheme.primaryContainer.withOpacity(0.35),
        filled: true,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.primaryContainer.withOpacity(0.45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return MaterialApp(
          title: 'Умный аквариум',
          debugShowCheckedModeBanner: false,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          themeMode: appState.themeMode,
          home: const HomeScreen(),
        );
      },
    );
  }
}
