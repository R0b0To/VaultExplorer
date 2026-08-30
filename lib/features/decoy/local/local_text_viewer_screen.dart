import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';

/// Plain-text viewer/editor for a real file on disk. Deliberately much
/// smaller than the vault's `TextEditorScreen`: there's no container to
/// decrypt from or commit back to, so this is just `File.readAsString` /
/// `File.writeAsString` behind a `TextField`.
class LocalTextViewerScreen extends StatefulWidget {
  final String filePath;

  const LocalTextViewerScreen({super.key, required this.filePath});

  @override
  State<LocalTextViewerScreen> createState() => _LocalTextViewerScreenState();
}

class _LocalTextViewerScreenState extends State<LocalTextViewerScreen> {
  static const int _maxPreviewBytes = 2 * 1024 * 1024; // 2 MB

  late final TextEditingController _controller;
  bool _loading = true;
  bool _tooLarge = false;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final file = File(widget.filePath);
    try {
      final length = await file.length();
      if (length > _maxPreviewBytes) {
        setState(() {
          _tooLarge = true;
          _loading = false;
        });
        return;
      }
      final text = await file.readAsString();
      if (!mounted) return;
      _controller.text = text;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tooLarge = true;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await File(widget.filePath).writeAsString(_controller.text);
      if (!mounted) return;
      setState(() {
        _dirty = false;
        _saving = false;
      });
      showAppSnackBar(context, message: context.l10n.filesTextSaved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnackBar(context, message: context.l10n.filesTextSaveFailed, tone: AppBannerTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.filePath.split('/').last;
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!_loading && !_tooLarge)
            IconButton(
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              tooltip: MaterialLocalizations.of(context).saveButtonLabel,
              onPressed: _dirty && !_saving ? _save : null,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tooLarge
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.l10n.filesTextTooLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                  onChanged: (_) {
                    if (!_dirty) setState(() => _dirty = true);
                  },
                ),
    );
  }
}
