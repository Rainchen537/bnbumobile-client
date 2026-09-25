import 'account_habits.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguageMode { system, chinese, traditionalChinese, english }

class AppLanguageController extends ChangeNotifier {
  AppLanguageController({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const preferenceKey = 'app.appearance.language_mode';

  final Future<SharedPreferences> Function() _preferencesLoader;
  AppLanguageMode _mode = AppLanguageMode.system;
  bool _restored = false;

  AppLanguageMode get mode => _mode;
  bool get restored => _restored;

  Locale? get locale => switch (_mode) {
    AppLanguageMode.system => null,
    AppLanguageMode.chinese => const Locale('zh', 'CN'),
    AppLanguageMode.traditionalChinese => const Locale('zh', 'TW'),
    AppLanguageMode.english => const Locale('en'),
  };

  /// Resolves the app language from the device's primary language only.
  ///
  /// A non-Chinese primary language always receives English, even when a
  /// secondary preferred language happens to be Chinese. This keeps the app's
  /// default predictable for international users.
  static Locale resolveSystemLocale(Iterable<Locale>? preferredLocales) {
    final locales = preferredLocales?.toList(growable: false) ?? const [];
    if (locales.isEmpty) return const Locale('en');
    final primary = locales.first;
    if (primary.languageCode.toLowerCase() != 'zh') {
      return const Locale('en');
    }

    final script = primary.scriptCode?.toLowerCase();
    final country = primary.countryCode?.toUpperCase();
    final isTraditional =
        script == 'hant' ||
        country == 'TW' ||
        country == 'HK' ||
        country == 'MO';
    return isTraditional ? const Locale('zh', 'TW') : const Locale('zh', 'CN');
  }

  Locale resolveLocale(Iterable<Locale>? preferredLocales) {
    return locale ?? resolveSystemLocale(preferredLocales);
  }

  String resolveInterfaceLanguageTag(Iterable<Locale>? preferredLocales) {
    return interfaceLanguageTagForLocale(resolveLocale(preferredLocales));
  }

  static String interfaceLanguageTagForLocale(Locale resolved) {
    if (resolved.languageCode != 'zh') return 'en';
    return resolved.countryCode == 'TW' ? 'zh-Hant' : 'zh-Hans';
  }

  Future<void> restore({Iterable<Locale>? preferredLocales}) async {
    final preferences = await _preferencesLoader();
    final stored = AccountHabits.shared.managed
        ? AccountHabits.shared.read<String?>(preferenceKey, null)
        : preferences.getString(preferenceKey);
    final restoredMode = AppLanguageMode.values.firstWhere(
      (candidate) => candidate.name == stored,
      orElse: () => AppLanguageMode.system,
    );
    _mode = restoredMode == AppLanguageMode.system
        ? modeForLocale(resolveSystemLocale(preferredLocales))
        : restoredMode;
    if (restoredMode == AppLanguageMode.system &&
        !AccountHabits.shared.managed) {
      await preferences.setString(preferenceKey, _mode.name);
    }
    _restored = true;
    notifyListeners();
  }

  static AppLanguageMode modeForLocale(Locale locale) {
    if (locale.languageCode != 'zh') return AppLanguageMode.english;
    return locale.countryCode == 'TW'
        ? AppLanguageMode.traditionalChinese
        : AppLanguageMode.chinese;
  }

  Future<void> setMode(AppLanguageMode mode) async {
    final habitLease = AccountHabits.shared.lease;
    if (_mode == mode && _restored && !AccountHabits.shared.managed) return;
    _mode = mode;
    _restored = true;
    notifyListeners();
    final preferences = await _preferencesLoader();
    if (AccountHabits.shared.managed) {
      await AccountHabits.shared.set(
        preferenceKey,
        mode.name,
        lease: habitLease,
      );
    } else {
      await preferences.setString(preferenceKey, mode.name);
    }
  }
}
