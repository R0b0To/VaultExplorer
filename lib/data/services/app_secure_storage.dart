import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_channel.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

part 'app_secure_storage.g.dart';

@Riverpod(keepAlive: true)
AppSecureStorage appSecureStorage(Ref ref) => const AppSecureStorage();

class AppSecureStorage {
  final MethodChannel _channel;

  const AppSecureStorage([
    this._channel = kVaultEngineChannel,
  ]);

  static const AppSecureStorage instance = AppSecureStorage();

  Future<String?> read({required String key}) async {
    return await _channel.invokeMethod<String>(ChannelMethods.readSecure, {'key': key});
  }

  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      await delete(key: key);
      return;
    }
    await writeVerified(key: key, value: value);
  }

  /// Like [write], but reports whether the value was actually persisted.
  ///
  /// The native side answers `false` (not an exception) when Keystore
  /// encryption or the prefs commit fails, so a plain [write] can't tell a
  /// lost write from a successful one. Callers whose security depends on the
  /// value surviving (the unlock-attempt counters in
  /// `unlock_lockout_throttle.dart`) use this and keep their own fallback
  /// when it returns `false`. Still throws on a [PlatformException].
  Future<bool> writeVerified({required String key, required String value}) async {
    final ok = await _channel.invokeMethod<bool>(ChannelMethods.writeSecure, {'key': key, 'value': value});
    if (ok != true) {
      VeLog.w('AppSecureStorage', 'writeSecure did not persist a value (result=$ok)', ok ?? 'null');
    }
    return ok == true;
  }

  Future<void> delete({required String key}) async {
    await _channel.invokeMethod<bool>(ChannelMethods.deleteSecure, {'key': key});
  }

  Future<void> deleteAll() async {
    await _channel.invokeMethod<bool>(ChannelMethods.deleteAllSecure);
  }

  Future<Map<String, String>> readAll() async {
    final result = await _channel.invokeMapMethod<String, String>(ChannelMethods.readAllSecure);
    return result ?? <String, String>{};
  }

  /// Like [readAll], but the native side only decrypts entries whose key
  /// starts with one of [prefixes] and none of [excludePrefixes]. Entries a
  /// caller never asked for are not decrypted at all -- one Keystore
  /// operation saved per skipped entry, and, for callers that only need
  /// non-secret metadata, remembered passwords and PIN/pattern hashes never
  /// cross into Dart.
  Future<Map<String, String>> readAllWithPrefixes(
    List<String> prefixes, {
    List<String> excludePrefixes = const [],
  }) async {
    final result = await _channel.invokeMapMethod<String, String>(
      ChannelMethods.readAllSecure,
      {'prefixes': prefixes, 'excludePrefixes': excludePrefixes},
    );
    return result ?? <String, String>{};
  }

  Future<bool> containsKey({required String key}) async {
    final result = await _channel.invokeMethod<bool>(ChannelMethods.containsKeySecure, {'key': key});
    return result ?? false;
  }
}
