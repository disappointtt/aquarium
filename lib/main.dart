import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/app_shell.dart';

// Ключи для SharedPreferences
const _kPrefThemeMode = 'theme_mode';
const _kPrefDemoMode = 'demo_mode';
const _kPrefEspIp = 'esp_ip';
const _kPrefAquariums = 'aquariums';
const _kPrefActiveAquariumId = 'active_aquarium_id';

class AquariumProfile {
  const AquariumProfile({
    required this.id,
    required this.name,
    required this.espIp,
  });

  final String id;
  final String name;
  final String espIp;

  AquariumProfile copyWith({String? name, String? espIp}) {
    return AquariumProfile(
      id: id,
      name: name ?? this.name,
      espIp: espIp ?? this.espIp,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'espIp': espIp};
  }

  static AquariumProfile fallback(String espIp) {
    return AquariumProfile(
      id: 'default-aquarium',
      name: 'Tropical Tank',
      espIp: espIp,
    );
  }

  static AquariumProfile? tryFromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final espIp = json['espIp']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty || espIp.isEmpty) return null;
    return AquariumProfile(id: id, name: name, espIp: espIp);
  }
}

/// Глобальное состояние приложения (тема, демо-режим, профиль пользователя).
class AppState extends ChangeNotifier {
  AppState({
    required this.themeMode,
    required this.isDemo,
    required String espIp,
    List<AquariumProfile>? aquariums,
    String? activeAquariumId,
  }) {
    this.aquariums = _normalizeAquariums(espIp, aquariums);
    this.activeAquariumId = _normalizeActiveId(
      this.aquariums,
      activeAquariumId,
    );
  }

  ThemeMode themeMode;
  bool isDemo;
  late final List<AquariumProfile> aquariums;
  late String activeAquariumId;

  AquariumProfile get activeAquarium {
    return aquariums.firstWhere(
      (aquarium) => aquarium.id == activeAquariumId,
      orElse: () => aquariums.first,
    );
  }

  String get espIp => activeAquarium.espIp;

  static List<AquariumProfile> _normalizeAquariums(
    String fallbackIp,
    List<AquariumProfile>? aquariums,
  ) {
    if (aquariums == null || aquariums.isEmpty) {
      return [AquariumProfile.fallback(fallbackIp)];
    }
    return List<AquariumProfile>.from(aquariums);
  }

  static String _normalizeActiveId(
    List<AquariumProfile> aquariums,
    String? activeAquariumId,
  ) {
    final requestedId = activeAquariumId?.trim();
    if (requestedId != null &&
        aquariums.any((aquarium) => aquarium.id == requestedId)) {
      return requestedId;
    }
    return aquariums.first.id;
  }

  Future<void> _saveAquariums() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPrefAquariums,
      jsonEncode(aquariums.map((aquarium) => aquarium.toJson()).toList()),
    );
    await prefs.setString(_kPrefActiveAquariumId, activeAquariumId);
    await prefs.setString(_kPrefEspIp, espIp);
  }

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
    final index = aquariums.indexWhere(
      (aquarium) => aquarium.id == activeAquariumId,
    );
    if (index == -1) return;
    aquariums[index] = aquariums[index].copyWith(espIp: ip);
    notifyListeners();
    await _saveAquariums();
  }

  Future<void> selectAquarium(String id) async {
    if (!aquariums.any((aquarium) => aquarium.id == id)) return;
    if (activeAquariumId == id) return;
    activeAquariumId = id;
    notifyListeners();
    await _saveAquariums();
  }

  Future<String> addAquarium({
    required String name,
    required String espIp,
  }) async {
    final aquarium = AquariumProfile(
      id: 'aquarium-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Новый аквариум' : name.trim(),
      espIp: espIp.trim().isEmpty ? '192.168.0.105' : espIp.trim(),
    );
    aquariums.add(aquarium);
    activeAquariumId = aquarium.id;
    notifyListeners();
    await _saveAquariums();
    return aquarium.id;
  }

  Future<void> updateAquarium({
    required String id,
    required String name,
    required String espIp,
  }) async {
    final index = aquariums.indexWhere((aquarium) => aquarium.id == id);
    if (index == -1) return;
    aquariums[index] = aquariums[index].copyWith(
      name: name.trim().isEmpty ? aquariums[index].name : name.trim(),
      espIp: espIp.trim().isEmpty ? aquariums[index].espIp : espIp.trim(),
    );
    notifyListeners();
    await _saveAquariums();
  }

  Future<void> removeAquarium(String id) async {
    if (aquariums.length <= 1) return;
    aquariums.removeWhere((aquarium) => aquarium.id == id);
    if (!aquariums.any((aquarium) => aquarium.id == activeAquariumId)) {
      activeAquariumId = aquariums.first.id;
    }
    notifyListeners();
    await _saveAquariums();
  }
}

List<AquariumProfile> _loadAquariums(String? raw, String fallbackIp) {
  if (raw == null || raw.trim().isEmpty) {
    return [AquariumProfile.fallback(fallbackIp)];
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [AquariumProfile.fallback(fallbackIp)];
    final aquariums = <AquariumProfile>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        final aquarium = AquariumProfile.tryFromJson(item);
        if (aquarium != null) aquariums.add(aquarium);
      }
    }
    return aquariums.isEmpty
        ? [AquariumProfile.fallback(fallbackIp)]
        : aquariums;
  } catch (_) {
    return [AquariumProfile.fallback(fallbackIp)];
  }
}

/// Inherited-обёртка для доступа к AppState из любого экрана.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState notifier, required Widget child})
    : super(notifier: notifier, child: child);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in context');
    return scope!.notifier!;
  }

  static AppState read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<AppScope>();
    final scope = element?.widget as AppScope?;
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
  final espIp = prefs.getString(_kPrefEspIp) ?? '192.168.0.105';
  final aquariums = _loadAquariums(prefs.getString(_kPrefAquariums), espIp);
  final activeAquariumId = prefs.getString(_kPrefActiveAquariumId);

  final themeMode = switch (themeName) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };

  final appState = AppState(
    themeMode: themeMode,
    isDemo: demo,
    espIp: espIp,
    aquariums: aquariums,
    activeAquariumId: activeAquariumId,
  );

  runApp(AppScope(notifier: appState, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ColorScheme _colorScheme(Brightness brightness) {
    // Спокойный «водный» синий как базовый акцент.
    final seed = const Color(0xFF0E7C7B);
    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      primaryContainer: brightness == Brightness.light
          ? const Color(0xFFE5F7F5)
          : const Color(0xFF12343B),
      surface: brightness == Brightness.light
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF0F1F24),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = _colorScheme(brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: const TextTheme(
        titleMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        titleSmall: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.3,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF5FAFA)
          : const Color(0xFF081316),
      cardColor: scheme.surface,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        fillColor: scheme.primaryContainer.withOpacity(0.35),
        filled: true,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shadowColor: Colors.black.withOpacity(0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            fontWeight: states.contains(MaterialState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.read(context);
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
