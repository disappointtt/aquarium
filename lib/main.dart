import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/app_shell.dart';
import 'services/notification_service.dart';

// Ключи для SharedPreferences
const _kPrefThemeMode = 'theme_mode';
const _kPrefDemoMode = 'demo_mode';
const _kPrefEspIp = 'esp_ip';
const _kPrefAlertsEnabled = 'alerts_enabled';
const _kPrefTempMin = 'alert_temp_min';
const _kPrefTempMax = 'alert_temp_max';
const _kPrefWaterMin = 'alert_water_min';
const _kPrefOfflineTimeout = 'alert_offline_timeout';
const _kPrefAlertCooldown = 'alert_cooldown';

/// Глобальное состояние приложения (тема, демо-режим, профиль пользователя).
class AppState extends ChangeNotifier {
  AppState({
    required this.themeMode,
    required this.isDemo,
    required this.espIp,
    required this.alertsEnabled,
    required this.tempMin,
    required this.tempMax,
    required this.waterMin,
    required this.offlineTimeoutMinutes,
    required this.alertCooldownMinutes,
  });

  ThemeMode themeMode;
  bool isDemo;
  String espIp;
  bool alertsEnabled;
  double tempMin;
  double tempMax;
  double waterMin;
  int offlineTimeoutMinutes;
  int alertCooldownMinutes;

  Duration get offlineTimeout => Duration(minutes: offlineTimeoutMinutes);
  Duration get alertCooldown => Duration(minutes: alertCooldownMinutes);

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

  Future<void> setEspIp(String ip) async {
    espIp = ip;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_kPrefEspIp, ip);
  }

  Future<void> setAlertsEnabled(bool enabled) async {
    alertsEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool(_kPrefAlertsEnabled, enabled);
  }

  Future<void> setAlertThresholds({
    required double tempMin,
    required double tempMax,
    required double waterMin,
    required int offlineTimeoutMinutes,
    required int alertCooldownMinutes,
  }) async {
    this.tempMin = tempMin;
    this.tempMax = tempMax;
    this.waterMin = waterMin;
    this.offlineTimeoutMinutes = offlineTimeoutMinutes;
    this.alertCooldownMinutes = alertCooldownMinutes;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble(_kPrefTempMin, tempMin);
    prefs.setDouble(_kPrefTempMax, tempMax);
    prefs.setDouble(_kPrefWaterMin, waterMin);
    prefs.setInt(_kPrefOfflineTimeout, offlineTimeoutMinutes);
    prefs.setInt(_kPrefAlertCooldown, alertCooldownMinutes);
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
  await NotificationService.init();

  final themeName = prefs.getString(_kPrefThemeMode);
  final bool demo = prefs.getBool(_kPrefDemoMode) ?? false;
  final espIp = prefs.getString(_kPrefEspIp) ?? '192.168.0.105';
  final alertsEnabled = prefs.getBool(_kPrefAlertsEnabled) ?? true;
  final tempMin = prefs.getDouble(_kPrefTempMin) ?? 24.0;
  final tempMax = prefs.getDouble(_kPrefTempMax) ?? 28.0;
  final waterMin = prefs.getDouble(_kPrefWaterMin) ?? 30.0;
  final offlineTimeoutMinutes = prefs.getInt(_kPrefOfflineTimeout) ?? 5;
  final alertCooldownMinutes = prefs.getInt(_kPrefAlertCooldown) ?? 10;

  final themeMode = switch (themeName) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };

  final appState = AppState(
    themeMode: themeMode,
    isDemo: demo,
    espIp: espIp,
    alertsEnabled: alertsEnabled,
    tempMin: tempMin,
    tempMax: tempMax,
    waterMin: waterMin,
    offlineTimeoutMinutes: offlineTimeoutMinutes,
    alertCooldownMinutes: alertCooldownMinutes,
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
    final seed = const Color(0xFF2E6BD6);
    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      primaryContainer: brightness == Brightness.light
          ? const Color(0xFFE6F0FF)
          : const Color(0xFF0D1B2A),
      surface: brightness == Brightness.light
          ? const Color(0xFFF3F6FB)
          : const Color(0xFF0B1320),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = _colorScheme(brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardColor: scheme.surface,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shadowColor: Colors.black.withOpacity(0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: MaterialStateProperty.resolveWith(
          (states) => TextStyle(
            fontWeight: states.contains(MaterialState.selected) ? FontWeight.w700 : FontWeight.w600,
          ),
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
          home: const AppShell(),
        );
      },
    );
  }
}
