import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DisguiseMode {
  vault,
  decoy;

  static DisguiseMode fromWire(String? raw) =>
      raw == 'decoy' ? DisguiseMode.decoy : DisguiseMode.vault;

  String get wireValue => switch (this) {
    DisguiseMode.vault => 'vault',
    DisguiseMode.decoy => 'decoy',
  };
}

typedef PickedLocalPdf = ({String uri, String displayName});

const _channel = MethodChannel('com.aeidolon.vaultexplorer/disguise_channel');

void _logSwallowed(String method, Object error) {
  debugPrint('[DisguiseModeApi] $method failed: $error');
}

class DisguiseModeApi {
  const DisguiseModeApi();

  Future<DisguiseMode> getMode() async {
    try {
      final result = await _channel.invokeMethod<String>('getMode');
      return DisguiseMode.fromWire(result);
    } catch (e) {
      _logSwallowed('getMode', e);
      return DisguiseMode.vault;
    }
  }

  Future<void> setMode(DisguiseMode mode) async {
    await _channel.invokeMethod<void>('setMode', {'mode': mode.wireValue});
  }

  Future<PickedLocalPdf?> pickLocalPdfFile() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'pickLocalPdfFile',
      );
      if (result == null) return null;

      final uri = result['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;

      return (
        uri: uri,
        displayName: (result['displayName'] as String?) ?? 'Document.pdf',
      );
    } catch (e) {
      _logSwallowed('pickLocalPdfFile', e);
      return null;
    }
  }

  Future<PickedLocalPdf?> consumePendingOpenRequest() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'consumePendingOpenRequest',
      );
      if (result == null) return null;

      final uri = result['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;

      return (
        uri: uri,
        displayName: (result['displayName'] as String?) ?? 'Document.pdf',
      );
    } catch (e) {
      _logSwallowed('consumePendingOpenRequest', e);
      return null;
    }
  }

  Future<String?> cacheContentUri(String uri) async {
    try {
      return await _channel.invokeMethod<String>('cacheContentUri', {'uri': uri});
    } catch (e) {
      _logSwallowed('cacheContentUri', e);
      return null;
    }
  }

  void setExternalOpenRequestListener(void Function(PickedLocalPdf) onRequest) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'externalOpenRequest') return null;

      final args = call.arguments;
      if (args is! Map) return null;

      final uri = args['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;

      onRequest((
        uri: uri,
        displayName: (args['displayName'] as String?) ?? 'Document.pdf',
      ));
      return null;
    });
  }
}

DisguiseModeApi disguiseModeApi = const DisguiseModeApi();