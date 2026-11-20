import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in main() with the instance loaded before the first frame.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

abstract final class PrefKeys {
  static const onboardingSeen = 'onboarding_seen';
  static const themeMode = 'theme_mode';
  static const userName = 'user_name';
  static const userEmail = 'user_email';
}

class OnboardingSeen extends Notifier<bool> {
  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(PrefKeys.onboardingSeen) ?? false;

  Future<void> markSeen() async {
    state = true;
    await ref.read(sharedPrefsProvider).setBool(PrefKeys.onboardingSeen, true);
  }
}

final onboardingSeenProvider = NotifierProvider<OnboardingSeen, bool>(OnboardingSeen.new);

class ThemeModeSetting extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final saved = ref.read(sharedPrefsProvider).getString(PrefKeys.themeMode);
    return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPrefsProvider).setString(PrefKeys.themeMode, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeSetting, ThemeMode>(ThemeModeSetting.new);

/// Choices a form remembers from the user's last save (an offer's "For",
/// courier, prompt days…) to start the next one with. Kept on this phone.
class LastUsed {
  const LastUsed(this._prefs, this._form);
  final SharedPreferences _prefs;
  final String _form;

  String? operator [](String key) => _prefs.getString('last.$_form.$key');

  Future<void> save(Map<String, Object?> values) async {
    for (final e in values.entries) {
      final v = e.value?.toString().trim();
      if (v == null || v.isEmpty) continue;
      await _prefs.setString('last.$_form.${e.key}', v);
    }
  }
}

final lastUsedProvider = Provider.family<LastUsed, String>((ref, form) => LastUsed(ref.read(sharedPrefsProvider), form));
