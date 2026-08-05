import 'package:flutter/services.dart';

class AppSecureStorage {
  const AppSecureStorage._();

  static const AppSecureStorage instance = AppSecureStorage._();

  static const _channel = MethodChannel('com.aeidolon.vaultexplorer/engine');

  Future<String?> read({required String key}) async {
    return await _channel.invokeMethod<String>('readSecure', {'key': key});
  }

  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      await delete(key: key);
      return;
    }
    await _channel.invokeMethod<bool>('writeSecure', {'key': key, 'value': value});
  }

  Future<void> delete({required String key}) async {
    await _channel.invokeMethod<bool>('deleteSecure', {'key': key});
  }

  Future<void> deleteAll() async {
    await _channel.invokeMethod<bool>('deleteAllSecure');
  }

  Future<Map<String, String>> readAll() async {
    final result = await _channel.invokeMapMethod<String, String>('readAllSecure');
    return result ?? <String, String>{};
  }

  Future<bool> containsKey({required String key}) async {
    final result = await _channel.invokeMethod<bool>('containsKeySecure', {'key': key});
    return result ?? false;
  }
}
