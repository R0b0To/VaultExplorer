import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String kJetpackPdfViewerViewType =
    'com.aeidolon.vaultexplorer/jetpack_pdf_viewer';

class JetpackPdfViewerView extends StatefulWidget {
  final String contentUri;
  final void Function()? onLoaded;
  final void Function(String message)? onError;
  final void Function()? onEditRequested;

  const JetpackPdfViewerView({
    super.key,
    required this.contentUri,
    this.onLoaded,
    this.onError,
    this.onEditRequested,
  });

  @override
  State<JetpackPdfViewerView> createState() => JetpackPdfViewerViewState();
}

class JetpackPdfViewerViewState extends State<JetpackPdfViewerView> {
  MethodChannel? _method;
  StreamSubscription<dynamic>? _eventSub;

  void _onPlatformViewCreated(int id) {
    final method = MethodChannel('$kJetpackPdfViewerViewType/$id');
    final events = EventChannel('$kJetpackPdfViewerViewType/events/$id');
    _eventSub = events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
    _method = method;
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    switch (raw['event']) {
      case 'loaded':
        widget.onLoaded?.call();
      case 'error':
        widget.onError?.call(
          (raw['message'] as String?) ?? 'Failed to load PDF',
        );
      case 'editRequested':
        widget.onEditRequested?.call();
    }
  }

  Future<bool> toggleSearch() async {
    final result = await _method?.invokeMethod<bool>('toggleSearch');
    return result ?? false;
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: kJetpackPdfViewerViewType,
      creationParams: {
        'contentUri': widget.contentUri,
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}