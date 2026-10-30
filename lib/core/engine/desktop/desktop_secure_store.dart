// Desktop backing store for the app's secret store (saved vault records, remembered credentials,
// unlock-attempt counters, ...): the readSecure / writeSecure / deleteSecure / deleteAllSecure /
// readAllSecure / containsKeySecure methods of the engine channel.
//
// On Android those are AES-GCM encrypted with an Android Keystore key. Here the OS keyring does
// that job (flutter_secure_storage: libsecret -- GNOME Keyring / KWallet -- on Linux, DPAPI on
// Windows). If no keyring is available the calls fail SOFT, the way the Android handler does when
// Keystore encryption fails: writes answer `false`, reads answer `null`, and callers whose
// security depends on persistence (the lockout counters) already have their own fallback for that.
//
// All operations run through one queue, so a read (or containsKey) issued after a write always
// observes it -- the same ordering guarantee the Android handler documents.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DesktopSecureStore {
  DesktopSecureStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  Future<void> _tail = Future<void>.value();
  bool _warned = false;

  Future<T> _serial<T>(Future<T> Function() op, T onError) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await op());
      } on Object catch (e) {
        if (!_warned) {
          _warned = true;
          debugPrint('[desktop-secure-store] OS keyring unavailable or failed: $e\n'
              'Saved vaults and credentials will not persist. On Linux install libsecret and run a '
              'keyring service (gnome-keyring or KWallet).');
        }
        completer.complete(onError);
      }
    });
    return completer.future;
  }

  Future<String?> read(String key) => _serial<String?>(() => _storage.read(key: key), null);

  Future<bool> write(String key, String value) => _serial<bool>(() async {
        await _storage.write(key: key, value: value);
        return true;
      }, false);

  Future<bool> delete(String key) => _serial<bool>(() async {
        await _storage.delete(key: key);
        return true;
      }, false);

  Future<bool> deleteAll() => _serial<bool>(() async {
        await _storage.deleteAll();
        return true;
      }, false);

  Future<bool> containsKey(String key) => _serial<bool>(() => _storage.containsKey(key: key), false);

  /// Every entry, optionally narrowed to keys starting with one of [prefixes] and not starting with
  /// any of [excludePrefixes] (same semantics as the Android handler).
  Future<Map<String, String>> readAll({List<String>? prefixes, List<String>? excludePrefixes}) =>
      _serial<Map<String, String>>(() async {
        final all = await _storage.readAll();
        final out = <String, String>{};
        all.forEach((key, value) {
          if (prefixes != null && !prefixes.any(key.startsWith)) return;
          if (excludePrefixes != null && excludePrefixes.any(key.startsWith)) return;
          out[key] = value;
        });
        return out;
      }, <String, String>{});
}
