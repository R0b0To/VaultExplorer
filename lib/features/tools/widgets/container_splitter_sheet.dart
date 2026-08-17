import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';

enum _SplitJoinMode { split, join }

/// Container Utilities → Split & Join.
///
/// Two flows in one sheet, switched by a segmented control: split a
/// container file into `<name>.001`, `<name>.002`, ... chunks of a chosen
/// size, or rejoin a chunk sequence back into one file starting from its
/// first part. Both flows call through [ContainerToolService] — see that
/// interface's doc comment for why every call here is wrapped to catch
/// [UnimplementedError] gracefully instead of crashing the screen.
///
/// Pushed as a full page (not a modal bottom sheet) so the split ↔ join
/// mode switch reflows within a fixed-height [Scaffold] instead of
/// resizing a sheet around the user's thumb.
class ContainerSplitterSheet extends StatefulWidget {
  const ContainerSplitterSheet({super.key});

  @override
  State<ContainerSplitterSheet> createState() =>
      _ContainerSplitterSheetState();
}

class _ContainerSplitterSheetState extends State<ContainerSplitterSheet> {
  _SplitJoinMode _mode = _SplitJoinMode.split;
  bool _busy = false;
  String? _error;
  int? _progressDone;
  int? _progressTotal;

  // Split fields
  String? _sourceUri;
  String? _sourceName;
  String? _destPath;
  String? _destName;
  String? _destTreeUri;
  ChunkSizePreset _preset = ChunkSizePreset.cloud8mb;
  final _customSizeCtrl = TextEditingController();

  // Join fields
  String? _firstPartUri;
  String? _firstPartName;
  String? _joinDestPath;
  String? _joinDestName;
  String? _joinDestTreeUri;
  final _outputNameCtrl = TextEditingController();

  @override
  void dispose() {
    _customSizeCtrl.dispose();
    _outputNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSplitSource() async {
    final picked = await vaultExplorerApi.pickContainer();
    if (picked == null || !mounted) return;
    setState(() {
      _sourceUri = picked.uri;
      _sourceName = picked.displayName;
      _error = null;
    });
  }

  Future<void> _pickSplitDestination() async {
    final picked = await vaultExplorerApi.pickExtractFolder();
    if (picked == null || !mounted) return;
    setState(() {
      _destPath = picked.path;
      _destName = picked.displayName;
      _destTreeUri = picked.treeUri;
      _error = null;
    });
  }

  Future<void> _pickFirstPart() async {
    final picked = await vaultExplorerApi.pickContainer();
    if (picked == null || !mounted) return;
    setState(() {
      _firstPartUri = picked.uri;
      _firstPartName = picked.displayName;
      // Default the output name to the first part's name with its
      // ".001"/".part1"-style suffix trimmed, as a starting point --
      // the field stays editable.
      _outputNameCtrl.text = _stripPartSuffix(picked.displayName);
      _error = null;
    });
  }

  Future<void> _pickJoinDestination() async {
    final picked = await vaultExplorerApi.pickExtractFolder();
    if (picked == null || !mounted) return;
    setState(() {
      _joinDestPath = picked.path;
      _joinDestName = picked.displayName;
      _joinDestTreeUri = picked.treeUri;
      _error = null;
    });
  }

  static String _stripPartSuffix(String name) {
    final dotMatch = RegExp(r'\.(\d{3}|part\d+)$', caseSensitive: false);
    return name.replaceFirst(dotMatch, '');
  }

  int? _resolvedChunkSizeBytes() {
    if (_preset != ChunkSizePreset.custom) {
      return _preset.megabytes! * 1000 * 1000;
    }
    final mb = int.tryParse(_customSizeCtrl.text.trim());
    if (mb == null || mb <= 0) return null;
    return mb * 1000 * 1000;
  }

  Future<void> _runSplit() async {
    final source = _sourceUri;
    final dest = _destPath;
    final chunkBytes = _resolvedChunkSizeBytes();

    if (source == null) {
      setState(() => _error = context.l10n.noFileSelectedLabel);
      return;
    }
    if (dest == null) {
      setState(() => _error = context.l10n.noFolderSelectedLabel);
      return;
    }
    if (chunkBytes == null) {
      setState(() => _error = context.l10n.splitChunkSizeCustomLabel);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _progressDone = 0;
      _progressTotal = null;
    });

    try {
      await ContainerToolService.instance.splitContainer(
        sourceUri: source,
        destinationPath: dest,
        destinationTreeUri: _destTreeUri,
        chunkSizeBytes: chunkBytes,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _progressDone = done;
            _progressTotal = total;
          });
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        message: context.l10n.splitContainerSuccessMessage,
        tone: AppBannerTone.success,
      );
    } on UnimplementedError {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.l10n.toolNotImplementedYetMessage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _runJoin() async {
    final firstPart = _firstPartUri;
    final destFolder = _joinDestPath;
    final outputName = _outputNameCtrl.text.trim();

    if (firstPart == null) {
      setState(() => _error = context.l10n.noFileSelectedLabel);
      return;
    }
    if (destFolder == null) {
      setState(() => _error = context.l10n.noFolderSelectedLabel);
      return;
    }
    if (outputName.isEmpty) {
      setState(() => _error = context.l10n.joinOutputFileNameLabel);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _progressDone = 0;
      _progressTotal = null;
    });

    try {
      await ContainerToolService.instance.joinContainer(
        firstPartUri: firstPart,
        destinationPath: '$destFolder/$outputName',
        destinationTreeUri: _joinDestTreeUri,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _progressDone = done;
            _progressTotal = total;
          });
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        message: context.l10n.joinContainerSuccessMessage,
        tone: AppBannerTone.success,
      );
    } on UnimplementedError {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.l10n.toolNotImplementedYetMessage;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.toolContainerSplitterTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_SplitJoinMode>(
              segments: [
                ButtonSegment(
                  value: _SplitJoinMode.split,
                  label: Text(
                    context.l10n.splitJoinModeSplit,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                  icon: const Icon(Icons.content_cut_rounded, size: 18),
                ),
                ButtonSegment(
                  value: _SplitJoinMode.join,
                  label: Text(
                    context.l10n.splitJoinModeJoin,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                  icon: const Icon(Icons.merge_type_rounded, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (sel) => setState(() {
                        _mode = sel.first;
                        _error = null;
                      }),
            ),
            const SizedBox(height: AppSpacing.lg),
            // IndexedStack keeps both field sets mounted and sizes itself
            // to the taller of the two, so switching Split <-> Join never
            // changes this region's height -- nothing below it (progress,
            // error, the action button) has to shift. AnimatedSize only
            // has to smooth the smaller in-mode reveal of the "custom
            // chunk size" field.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: IndexedStack(
                alignment: Alignment.topCenter,
                index: _mode == _SplitJoinMode.split ? 0 : 1,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _buildSplitFields(cs, textTheme),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _buildJoinFields(cs, textTheme),
                  ),
                ],
              ),
            ),
            if (_progressTotal != null) ...[
              const SizedBox(height: AppSpacing.md),
              LinearProgressIndicator(
                value: _progressTotal! > 0
                    ? (_progressDone ?? 0) / _progressTotal!
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.splitJoinOperationProgress(
                  formatBytes(_progressDone ?? 0),
                  formatBytes(_progressTotal!),
                ),
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              InlineErrorBanner(_error!),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _busy
                  ? null
                  : (_mode == _SplitJoinMode.split ? _runSplit : _runJoin),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
              child: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                      ),
                    )
                  : Text(
                      _mode == _SplitJoinMode.split
                          ? context.l10n.splitContainerButton
                          : context.l10n.joinContainerButton,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSplitFields(ColorScheme cs, TextTheme textTheme) {
    return [
      _PickerRow(
        icon: Icons.description_outlined,
        label: context.l10n.splitSourceFileLabel,
        valueLabel: _sourceName ?? context.l10n.noFileSelectedLabel,
        buttonLabel: context.l10n.chooseFileButton,
        onTap: _busy ? null : _pickSplitSource,
      ),
      const SizedBox(height: AppSpacing.sm),
      _PickerRow(
        icon: Icons.folder_outlined,
        label: context.l10n.splitDestinationFolderLabel,
        valueLabel: _destName ?? context.l10n.noFolderSelectedLabel,
        buttonLabel: context.l10n.chooseFolderButton,
        onTap: _busy ? null : _pickSplitDestination,
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        context.l10n.splitChunkSizeLabel,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _presetChip(ChunkSizePreset.fourMb, context.l10n.splitChunkSizeFourMb),
          _presetChip(ChunkSizePreset.cloud8mb, context.l10n.splitChunkSizeCloud8mb),
          _presetChip(ChunkSizePreset.cloud32mb, context.l10n.splitChunkSizeCloud32mb),
          _presetChip(ChunkSizePreset.cloud100mb, context.l10n.splitChunkSizeCloud),
          _presetChip(ChunkSizePreset.fat32_2gb, context.l10n.splitChunkSizeFat32),
          _presetChip(ChunkSizePreset.fourGb, context.l10n.splitChunkSizeFourGb),
          _presetChip(ChunkSizePreset.custom, context.l10n.splitChunkSizeCustom),
        ],
      ),
      if (_preset == ChunkSizePreset.custom) ...[
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _customSizeCtrl,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.l10n.splitChunkSizeCustomLabel,
            prefixIcon: const Icon(Icons.straighten_rounded, size: 20),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildJoinFields(ColorScheme cs, TextTheme textTheme) {
    return [
      _PickerRow(
        icon: Icons.description_outlined,
        label: context.l10n.joinFirstPartLabel,
        valueLabel: _firstPartName ?? context.l10n.noFileSelectedLabel,
        buttonLabel: context.l10n.chooseFileButton,
        onTap: _busy ? null : _pickFirstPart,
      ),
      const SizedBox(height: AppSpacing.sm),
      _PickerRow(
        icon: Icons.folder_outlined,
        label: context.l10n.splitDestinationFolderLabel,
        valueLabel: _joinDestName ?? context.l10n.noFolderSelectedLabel,
        buttonLabel: context.l10n.chooseFolderButton,
        onTap: _busy ? null : _pickJoinDestination,
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _outputNameCtrl,
        enabled: !_busy,
        decoration: InputDecoration(
          labelText: context.l10n.joinOutputFileNameLabel,
          prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded, size: 20),
        ),
      ),
    ];
  }

  Widget _presetChip(ChunkSizePreset preset, String label) {
    final selected = _preset == preset;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      // The default checkmark is inserted/removed from the chip's layout
      // on selection, changing each chip's width and shifting every chip
      // after it within the Wrap. Selection is already communicated via
      // the chip's background/label color change, so drop the checkmark
      // rather than reserve space for it.
      showCheckmark: false,
      onSelected: _busy ? null : (_) => setState(() => _preset = preset),
    );
  }
}

/// A labeled row with a value readout and a small trailing button to open
/// a file/folder picker -- shared shape for every picker field in this
/// screen (split source, split destination, join first part, join
/// destination).
class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueLabel;
  final String buttonLabel;
  final VoidCallback? onTap;

  const _PickerRow({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppIconSize.small, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  valueLabel,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: TextButton(
              onPressed: onTap,
              child: Text(
                buttonLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}