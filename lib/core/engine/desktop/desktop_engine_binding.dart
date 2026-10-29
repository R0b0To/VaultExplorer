// Plugs the desktop engine underneath the existing `MethodChannel` without touching any caller.
//
// Every VaultXxxApi class (and a few const global channels) talks to the engine MethodChannel,
// which sends its messages through `ServicesBinding.instance.defaultBinaryMessenger`. On Linux/Windows this custom binding swaps
// in a messenger that answers THAT ONE channel in-process (via [DesktopEngineHost]) and passes
// every other channel straight through to Flutter's real messenger.
//
// Use it in place of WidgetsFlutterBinding.ensureInitialized():
//
//   if (isDesktopEngineTarget) {
//     DesktopEngineBinding.ensureInitialized();
//   } else {
//     WidgetsFlutterBinding.ensureInitialized();
//   }
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' show PlatformMessageResponseCallback;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/core/api/vault_engine_channel.dart';

import 'desktop_engine_host.dart';
import 'engine_worker_pool.dart';

/// True where the app should use the in-process desktop engine instead of the Kotlin one.
/// Set `VE_DESKTOP_ENGINE=0` to opt out (e.g. to debug the channel layer with a fake).
bool get isDesktopEngineTarget =>
    !kIsWeb &&
    (Platform.isLinux || Platform.isWindows) &&
    Platform.environment['VE_DESKTOP_ENGINE'] != '0';

const StandardMethodCodec _codec = StandardMethodCodec();

/// Process-wide holder for the host + the Dart-side handler the channel registered.
class DesktopEngineRuntime {
  DesktopEngineRuntime._();
  static final DesktopEngineRuntime instance = DesktopEngineRuntime._();

  late final DesktopEngineHost host = DesktopEngineHost(
    pool: EngineWorkerPool(),
    emit: _emitToDart,
  );

  MessageHandler? _dartHandler;

  void setDartHandler(MessageHandler? handler) => _dartHandler = handler;

  void _emitToDart(String method, Object? arguments) {
    final handler = _dartHandler;
    if (handler == null) return;
    handler(_codec.encodeMethodCall(MethodCall(method, arguments)));
  }

  /// Decodes a channel message, runs it on the host and encodes the reply envelope.
  Future<ByteData?> handleEncoded(ByteData? message) async {
    if (message == null) return null;
    final call = _codec.decodeMethodCall(message);
    try {
      final result = await host.handle(call);
      return _codec.encodeSuccessEnvelope(result);
    } on MissingPluginException {
      return null; // surfaces as MissingPluginException on the Dart caller, like a real miss
    } on PlatformException catch (e) {
      return _codec.encodeErrorEnvelope(code: e.code, message: e.message, details: e.details);
    } on Object catch (e, st) {
      debugPrint('[desktop-engine] ${call.method} failed: $e\n$st');
      return _codec.encodeErrorEnvelope(code: 'C++_ERROR', message: '$e');
    }
  }
}

class _EngineInterceptingMessenger implements BinaryMessenger {
  _EngineInterceptingMessenger(this._inner);

  final BinaryMessenger _inner;

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) => _inner.handlePlatformMessage(channel, data, callback);

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel != kVaultEngineChannelName) return _inner.send(channel, message);
    return DesktopEngineRuntime.instance.handleEncoded(message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    if (channel == kVaultEngineChannelName) {
      DesktopEngineRuntime.instance.setDartHandler(handler);
      return;
    }
    _inner.setMessageHandler(channel, handler);
  }
}

/// WidgetsFlutterBinding with the engine channel answered in-process.
class DesktopEngineBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() => _EngineInterceptingMessenger(super.createBinaryMessenger());

  static DesktopEngineBinding? _instance;

  static WidgetsBinding ensureInitialized() {
    if (_instance == null) {
      // BindingBase registers itself as the singleton from its constructor; this must run
      // before anything else initialises a binding.
      DesktopEngineBinding();
    }
    return WidgetsBinding.instance;
  }

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }
}
