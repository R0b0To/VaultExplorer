import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/features/decoy/local/local_text_viewer_controller.dart';

/// Plain-text viewer/editor for a real file on disk. Deliberately much
/// smaller than the vault's `TextEditorScreen`: there's no container to
/// decrypt from or commit back to, so this is just `File.readAsString` /
/// `File.writeAsString` behind a `TextField`.
class LocalTextViewerScreen extends ConsumerStatefulWidget {
  final String filePath;

  const LocalTextViewerScreen({super.key, required this.filePath});

  @override
  ConsumerState<LocalTextViewerScreen> createState() =>
      _LocalTextViewerScreenState();
}

class _LocalTextViewerScreenState
    extends ConsumerState<LocalTextViewerScreen> {
  late final TextEditingController _controller;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await ref
        .read(localTextViewerProvider(widget.filePath).notifier)
        .save(widget.filePath, _controller.text);
    if (!mounted) return;
    if (ok) {
      setState(() => _dirty = false);
      showAppSnackBar(context, message: context.l10n.filesTextSaved);
    } else {
      showAppSnackBar(
        context,
        message: context.l10n.filesTextSaveFailed,
        tone: AppBannerTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localTextViewerProvider(widget.filePath));
    ref.listen<LocalTextViewerState>(
      localTextViewerProvider(widget.filePath),
      (previous, next) {
        if (previous?.loadedText == null && next.loadedText != null) {
          _controller.text = next.loadedText!;
        }
      },
    );

    final name = widget.filePath.split('/').last;
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!state.loading && !state.tooLarge)
            IconButton(
              icon: state.saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              tooltip: MaterialLocalizations.of(context).saveButtonLabel,
              onPressed: _dirty && !state.saving ? _save : null,
            ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.tooLarge
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