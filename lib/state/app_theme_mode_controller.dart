import 'account_habits.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ios_platform_capabilities.dart';

enum ScheduleTodayAccent { blue, teal, amber, violet }

class AppThemeModeController extends ChangeNotifier {
  AppThemeModeController({
    Future<SharedPreferences> Function()? preferencesLoader,
    Future<bool> Function()? liquidGlassSupportLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _liquidGlassSupportLoader =
           liquidGlassSupportLoader ??
           IosPlatformCapabilities.supportsLiquidGlass;

  static const preferenceKey = 'app.appearance.theme_mode';
  static const liquidGlassPreferenceKey =
      'app.appearance.ios_liquid_glass_enabled';
  static const scheduleTodayHighlightPreferenceKey =
      'app.appearance.schedule_today_highlight_enabled';
  static const scheduleTodayAccentPreferenceKey =
      'app.appearance.schedule_today_accent';

  final Future<SharedPreferences> Function() _preferencesLoader;
  final Future<bool> Function() _liquidGlassSupportLoader;

  ThemeMode _themeMode = ThemeMode.system;
  bool _liquidGlassEnabled = false;
  bool _liquidGlassSupported = false;
  bool _scheduleTodayHighlightEnabled = true;
  ScheduleTodayAccent _scheduleTodayAccent = ScheduleTodayAccent.blue;
  int _themeGeneration = 0;
  int _liquidGlassGeneration = 0;
  int _scheduleTodayHighlightGeneration = 0;
  int _scheduleTodayAccentGeneration = 0;
  Future<void> _pendingWrite = Future<void>.value();

  ThemeMode get themeMode => _themeMode;
  bool get liquidGlassEnabled => _liquidGlassEnabled;
  bool get liquidGlassSupported => _liquidGlassSupported;
  bool get scheduleTodayHighlightEnabled => _scheduleTodayHighlightEnabled;
  ScheduleTodayAccent get scheduleTodayAccent => _scheduleTodayAccent;

  Future<void> restore() async {
    final themeGeneration = _themeGeneration;
    final liquidGlassGeneration = _liquidGlassGeneration;
    final scheduleTodayHighlightGeneration = _scheduleTodayHighlightGeneration;
    final scheduleTodayAccentGeneration = _scheduleTodayAccentGeneration;
    final results = await Future.wait<Object>([
      _preferencesLoader(),
      _liquidGlassSupportLoader(),
    ]);
    final preferences = results[0] as SharedPreferences;
    final liquidGlassSupported = results[1] as bool;
    final restoredThemeMode = _themeModeFromName(
      AccountHabits.shared.managed
          ? AccountHabits.shared.read(preferenceKey, 'system')
          : preferences.getString(preferenceKey),
    );
    final restoredLiquidGlass =
        liquidGlassSupported &&
        ((AccountHabits.shared.managed
                ? AccountHabits.shared.read(liquidGlassPreferenceKey, true)
                : preferences.getBool(liquidGlassPreferenceKey)) ??
            true);
    final restoredScheduleTodayHighlight =
        (AccountHabits.shared.managed
            ? AccountHabits.shared.read(
                scheduleTodayHighlightPreferenceKey,
                true,
              )
            : preferences.getBool(scheduleTodayHighlightPreferenceKey)) ??
        true;
    final restoredScheduleTodayAccent = _scheduleTodayAccentFromName(
      AccountHabits.shared.managed
          ? AccountHabits.shared.read(scheduleTodayAccentPreferenceKey, 'blue')
          : preferences.getString(scheduleTodayAccentPreferenceKey),
    );
    var changed = false;
    if (themeGeneration == _themeGeneration &&
        restoredThemeMode != _themeMode) {
      _themeMode = restoredThemeMode;
      changed = true;
    }
    if (liquidGlassGeneration == _liquidGlassGeneration &&
        (restoredLiquidGlass != _liquidGlassEnabled ||
            liquidGlassSupported != _liquidGlassSupported)) {
      _liquidGlassSupported = liquidGlassSupported;
      _liquidGlassEnabled = restoredLiquidGlass;
      changed = true;
    }
    if (scheduleTodayHighlightGeneration == _scheduleTodayHighlightGeneration &&
        restoredScheduleTodayHighlight != _scheduleTodayHighlightEnabled) {
      _scheduleTodayHighlightEnabled = restoredScheduleTodayHighlight;
      changed = true;
    }
    if (scheduleTodayAccentGeneration == _scheduleTodayAccentGeneration &&
        restoredScheduleTodayAccent != _scheduleTodayAccent) {
      _scheduleTodayAccent = restoredScheduleTodayAccent;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode value) async {
    final habitLease = AccountHabits.shared.lease;
    _themeGeneration++;
    if (_themeMode != value) {
      _themeMode = value;
      notifyListeners();
    }
    _pendingWrite = _pendingWrite.catchError((_) {}).then((_) async {
      final preferences = await _preferencesLoader();
      if (AccountHabits.shared.managed) {
        await AccountHabits.shared.set(
          preferenceKey,
          value.name,
          lease: habitLease,
        );
      } else {
        await preferences.setString(preferenceKey, value.name);
      }
    });
    await _pendingWrite;
  }

  Future<bool> setLiquidGlassEnabled(bool value) async {
    final habitLease = AccountHabits.shared.lease;
    if (value && !_liquidGlassSupported) {
      return false;
    }
    _liquidGlassGeneration++;
    if (_liquidGlassEnabled != value) {
      _liquidGlassEnabled = value;
      notifyListeners();
    }
    _pendingWrite = _pendingWrite.catchError((_) {}).then((_) async {
      final preferences = await _preferencesLoader();
      if (AccountHabits.shared.managed) {
        await AccountHabits.shared.set(
          liquidGlassPreferenceKey,
          value,
          lease: habitLease,
        );
      } else {
        await preferences.setBool(liquidGlassPreferenceKey, value);
      }
    });
    await _pendingWrite;
    return true;
  }

  Future<void> setScheduleTodayHighlightEnabled(bool value) async {
    final habitLease = AccountHabits.shared.lease;
    _scheduleTodayHighlightGeneration++;
    if (_scheduleTodayHighlightEnabled != value) {
      _scheduleTodayHighlightEnabled = value;
      notifyListeners();
    }
    _pendingWrite = _pendingWrite.catchError((_) {}).then((_) async {
      final preferences = await _preferencesLoader();
      if (AccountHabits.shared.managed) {
        await AccountHabits.shared.set(
          scheduleTodayHighlightPreferenceKey,
          value,
          lease: habitLease,
        );
      } else {
        await preferences.setBool(scheduleTodayHighlightPreferenceKey, value);
      }
    });
    await _pendingWrite;
  }

  Future<void> setScheduleTodayAccent(ScheduleTodayAccent value) async {
    final habitLease = AccountHabits.shared.lease;
    _scheduleTodayAccentGeneration++;
    if (_scheduleTodayAccent != value) {
      _scheduleTodayAccent = value;
      notifyListeners();
    }
    _pendingWrite = _pendingWrite.catchError((_) {}).then((_) async {
      final preferences = await _preferencesLoader();
      if (AccountHabits.shared.managed) {
        await AccountHabits.shared.set(
          scheduleTodayAccentPreferenceKey,
          value.name,
          lease: habitLease,
        );
      } else {
        await preferences.setString(
          scheduleTodayAccentPreferenceKey,
          value.name,
        );
      }
    });
    await _pendingWrite;
  }

  static ThemeMode _themeModeFromName(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static ScheduleTodayAccent _scheduleTodayAccentFromName(String? value) {
    return ScheduleTodayAccent.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ScheduleTodayAccent.blue,
    );
  }
}
