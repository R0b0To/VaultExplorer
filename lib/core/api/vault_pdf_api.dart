import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

typedef OpenPdfResult = ({int handle, int pageCount});

typedef PdfPageSize = ({int width, int height});

typedef JetpackPdfSession = ({String contentUri, String? token});

class VaultPdfApi {
  final MethodChannel _channel;
  const VaultPdfApi(this._channel);

  Future<OpenPdfResult> openPdf(
    MountedContainer container,
    String fileName,
  ) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      ChannelMethods.openPdf,
      {'filePath': container.uri, 'fileName': fileName},
    );
    if (result == null) {
      throw StateError('openPdf returned no result');
    }
    return (
      handle: result['handle'] as int,
      pageCount: result['pageCount'] as int,
    );
  }

  Future<OpenPdfResult> openLocalPdf(String uri) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      ChannelMethods.openPdf,
      {'localUri': uri},
    );
    if (result == null) {
      throw StateError('openPdf (local) returned no result');
    }
    return (
      handle: result['handle'] as int,
      pageCount: result['pageCount'] as int,
    );
  }

  Future<PdfPageSize> getPdfPageSize(int handle, int pageIndex) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      ChannelMethods.getPdfPageSize,
      {'handle': handle, 'pageIndex': pageIndex},
    );
    if (result == null) {
      throw StateError('getPdfPageSize returned no result');
    }
    return (width: result['width'] as int, height: result['height'] as int);
  }

  Future<Uint8List> renderPdfPage(
    int handle,
    int pageIndex,
    int width,
    int height,
  ) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.renderPdfPage,
      {
        'handle': handle,
        'pageIndex': pageIndex,
        'width': width,
        'height': height,
      },
    );
    if (result == null) {
      throw StateError('renderPdfPage returned no result');
    }
    return result;
  }

  Future<void> closePdf(int handle) async {
    await _channel.invokeMethod(ChannelMethods.closePdf, {'handle': handle});
  }

  Future<bool> isJetpackPdfViewerSupported() async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.isJetpackPdfViewerSupported,
    );
    return result ?? false;
  }

  Future<JetpackPdfSession> registerVaultJetpackPdfSession(
    MountedContainer container,
    String fileName,
  ) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      ChannelMethods.registerJetpackPdfSession,
      {'filePath': container.uri, 'fileName': fileName},
    );
    if (result == null) {
      throw StateError('registerJetpackPdfSession returned no result');
    }
    return (
      contentUri: result['contentUri'] as String,
      token: result['token'] as String?,
    );
  }

  Future<JetpackPdfSession> registerLocalJetpackPdfSession(String uri) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      ChannelMethods.registerJetpackPdfSession,
      {'localUri': uri},
    );
    if (result == null) {
      throw StateError('registerJetpackPdfSession (local) returned no result');
    }
    return (contentUri: result['contentUri'] as String, token: null);
  }

  Future<void> revokeJetpackPdfSession(String? token) async {
    if (token == null) return;
    await _channel.invokeMethod(ChannelMethods.revokeJetpackPdfSession, {
      'token': token,
    });
  }

  Future<bool> printPdf({
  MountedContainer? container,
  String? fileName,
  String? localUri,
}) async {
  try {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.printPdf,
      {
        if (container != null) 'filePath': container.uri,
        'fileName': ?fileName,
        'localUri': ?localUri,
      },
    );
    return result ?? false;
  } catch (e) {
    return false;
  }
}
}
