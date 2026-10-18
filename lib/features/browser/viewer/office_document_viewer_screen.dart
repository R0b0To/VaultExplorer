import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/office_document_formats.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Must match OFFICE_VIEWER_VIEW_TYPE in
/// kotlin/.../officeviewer/OfficeViewerPlugin.kt
const String _kOfficeViewerViewType =
    'com.aeidolon.vaultexplorer/office_viewer';

/// Why a document could not be shown. Mirrors `OfficeError` on the native
/// side, which reports it as the `PlatformException` code.
enum OfficeViewerFailure { encrypted, tooLarge, unsupported }

OfficeViewerFailure officeViewerFailureFromCode(String? code) {
  switch (code) {
    case 'ENCRYPTED':
      return OfficeViewerFailure.encrypted;
    case 'TOO_LARGE':
      return OfficeViewerFailure.tooLarge;
    default:
      return OfficeViewerFailure.unsupported;
  }
}

/// In-app viewer for Word, PowerPoint, Excel and OpenDocument files.
///
/// The decrypted bytes are read into memory, converted natively (pure
/// Kotlin, no third-party code) into a script-free HTML "reading view", and
/// shown in a WebView that cannot reach the network, the vault or the file
/// system -- it only serves that one in-memory page and its images. Nothing is
/// written to plaintext disk. Page layout is not reproduced: this is for
/// reading the content, not for editing or pixel-accurate rendering.
class OfficeDocumentViewerScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;

  const OfficeDocumentViewerScreen({
    super.key,
    required this.container,
    required this.filePath,
  });

  @override
  ConsumerState<OfficeDocumentViewerScreen> createState() =>
      _OfficeDocumentViewerScreenState();
}

class _OfficeDocumentViewerScreenState
    extends ConsumerState<OfficeDocumentViewerScreen> {
  MethodChannel? _method;
  StreamSubscription<dynamic>? _eventSub;
  late final VaultEngineEvents _engineEvents;

  Uint8List? _bytes;
  bool _sent = false;
  bool _locked = false;
  bool _rendering = true;
  OfficeViewerFailure? _failure;
  String? _title;

  String get _fileName => widget.filePath.split('/').last;

  String get _extension {
    final dot = _fileName.lastIndexOf('.');
    return dot < 0 ? '' : _fileName.substring(dot + 1).toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _engineEvents = ref.read(vaultEngineEventsProvider);
    if (!widget.container.isLocalStorage) {
      _engineEvents.addContainerLockedListener(_onContainerLocked);
    }
    unawaited(_readFile());
  }

  void _onContainerLocked(int lockedVolId) {
    if (lockedVolId != widget.container.volId || !mounted) return;
    // Dropping the platform view releases the converted page and images.
    setState(() {
      _locked = true;
      _bytes = null;
    });
  }

  Future<void> _readFile() async {
    final io = ref.read(vaultFileIoApiProvider);
    try {
      final size = await io.getFileSize(widget.container, widget.filePath);
      if (size < 0) return _fail(OfficeViewerFailure.unsupported);
      if (size > OfficeDocumentFormats.maxBytes) {
        return _fail(OfficeViewerFailure.tooLarge);
      }
      final bytes = await io.readWholeFile(widget.container, widget.filePath);
      if (!mounted) return;
      if (bytes == null) return _fail(OfficeViewerFailure.unsupported);
      _bytes = bytes;
      _trySend();
    } catch (_) {
      _fail(OfficeViewerFailure.unsupported);
    }
  }

  void _fail(OfficeViewerFailure failure) {
    if (!mounted) return;
    setState(() {
      _failure = failure;
      _rendering = false;
      _bytes = null;
    });
  }

  void _onPlatformViewCreated(int id) {
    final events = EventChannel('$_kOfficeViewerViewType/events/$id');
    _eventSub = events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (_) {},
    );
    _method = MethodChannel('$_kOfficeViewerViewType/$id');
    _trySend();
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map || !mounted) return;
    switch (raw['event']) {
      case 'pageFinished':
        setState(() => _rendering = false);
      case 'error':
        _fail(OfficeViewerFailure.unsupported);
    }
  }

  /// Sends the bytes once both the file and the platform view are ready.
  void _trySend() {
    final method = _method;
    final bytes = _bytes;
    if (_sent || method == null || bytes == null || !mounted) return;
    _sent = true;
    unawaited(_send(method, bytes));
  }

  String _hex(Color c) {
    final v = c.toARGB32() & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }

  Future<void> _send(MethodChannel method, Uint8List bytes) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final notesLabel = context.l10n.officeViewerSpeakerNotes;
    try {
      final result = await method.invokeMapMethod<String, dynamic>(
        'loadDocument',
        {
          'bytes': bytes,
          'extension': _extension,
          'dark': theme.brightness == Brightness.dark,
          'background': _hex(cs.surface),
          'foreground': _hex(cs.onSurface),
          'muted': _hex(cs.onSurfaceVariant),
          'accent': _hex(cs.primary),
          'notesLabel': notesLabel,
        },
      );
      if (!mounted) return;
      // The bytes now live natively; drop the Dart copy.
      setState(() {
        _bytes = null;
        _title = result?['title'] as String?;
      });
    } on PlatformException catch (e) {
      _fail(officeViewerFailureFromCode(e.code));
    } on MissingPluginException {
      _fail(OfficeViewerFailure.unsupported);
    }
  }

  @override
  void dispose() {
    if (!widget.container.isLocalStorage) {
      _engineEvents.removeContainerLockedListener(_onContainerLocked);
    }
    _eventSub?.cancel();
    _bytes = null;
    super.dispose();
  }

  String _failureMessage(BuildContext context, OfficeViewerFailure f) {
    switch (f) {
      case OfficeViewerFailure.encrypted:
        return context.l10n.officeViewerEncrypted;
      case OfficeViewerFailure.tooLarge:
        return context.l10n.officeViewerTooLarge;
      case OfficeViewerFailure.unsupported:
        return context.l10n.officeViewerUnsupported;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final failure = _failure;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          (_title != null && _title!.isNotEmpty) ? _title! : _fileName,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: failure != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, color: cs.error, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      context.l10n.officeViewerErrorTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _failureMessage(context, failure),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: AndroidView(
                    viewType: _kOfficeViewerViewType,
                    creationParams: const <String, Object?>{},
                    creationParamsCodec: const StandardMessageCodec(),
                    onPlatformViewCreated: _onPlatformViewCreated,
                  ),
                ),
                if (_rendering)
                  Container(
                    color: cs.surface,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
              ],
            ),
    );
  }
}
