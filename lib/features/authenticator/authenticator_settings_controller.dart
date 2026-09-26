import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AuthenticatorSearchPlacement { bottom, top }

class AuthenticatorSettings {
  final bool enabled;
  final bool showNumbers;
  final AuthenticatorSearchPlacement searchPlacement;

  const AuthenticatorSettings({
    this.enabled = true,
    this.showNumbers = true,
    this.searchPlacement = AuthenticatorSearchPlacement.bottom,
  });

  AuthenticatorSettings copyWith({
    bool? enabled,
    bool? showNumbers,
    AuthenticatorSearchPlacement? searchPlacement,
  }) {
    return AuthenticatorSettings(
      enabled: enabled ?? this.enabled,
      showNumbers: showNumbers ?? this.showNumbers,
      searchPlacement: searchPlacement ?? this.searchPlacement,
    );
  }
}

class AuthenticatorSettingsNotifier extends Notifier<AuthenticatorSettings> {
  @override
  AuthenticatorSettings build() => const AuthenticatorSettings();

  void setEnabled(bool value) => state = state.copyWith(enabled: value);
  void setShowNumbers(bool value) => state = state.copyWith(showNumbers: value);
  void setSearchPlacement(AuthenticatorSearchPlacement placement) =>
      state = state.copyWith(searchPlacement: placement);
}

final authenticatorSettingsProvider =
    NotifierProvider<AuthenticatorSettingsNotifier, AuthenticatorSettings>(
  AuthenticatorSettingsNotifier.new,
);