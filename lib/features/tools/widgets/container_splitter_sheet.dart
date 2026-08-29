// File: lib/features/tools/widgets/container_splitter_sheet.dart

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/container_tool_service.dart';

enum _SplitJoinMode { split, join }

class ContainerSplitterSheet extends StatefulWidget {
  const ContainerSplitterSheet({super.key});

  @override
  State<ContainerSplitterSheet> createState() => _ContainerSplitterSheetState();
}

class _ContainerSplitterSheetState extends State<ContainerSplitterSheet> {
  _SplitJoinMode _mode = _SplitJoinMode.split;
  bool _busy = false;
  String? _error;
  int? _progressDone;
  int? _progressTotal;

  String? _sourceUri;
  String? _sourceName;
  String? _destPath;
  String? _destName;
  String? _destTreeUri;
  ChunkSizePreset _preset = ChunkSizePreset.cloud8mb;
  final _customSizeCtrl = TextEditingController();

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
    final treeUri = _destTreeUri;
    final dest = _destPath ?? treeUri;
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
        destinationTreeUri: treeUri,
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
    final treeUri = _joinDestTreeUri;
    final destFolder = _joinDestPath ?? treeUri;
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
        destinationTreeUri: treeUri,
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

  Widget _buildModeSegmentedButton({required bool isCompact}) {
    return Container(
      padding: isCompact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      child: SegmentedButton<_SplitJoinMode>(
        showSelectedIcon: false,
        style: isCompact
            ? SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              )
            : null,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final isLandscape = context.screen.useWideLayout;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        elevation: 0,
        title: Text(
          context.l10n.toolContainerSplitterTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (isLandscape) ...[
            _buildModeSegmentedButton(isCompact: true),
            const SizedBox(width: 16),
          ],
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: isLandscape
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
              : AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isLandscape) ...[
                _buildModeSegmentedButton(isCompact: false),
                const SizedBox(height: AppSpacing.md),
              ],
              if (isLandscape)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _mode == _SplitJoinMode.split
                              ? _buildSplitLeftColumn(cs, textTheme, isCompact: true)
                              : _buildJoinLeftColumn(cs, textTheme, isCompact: true),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const VerticalDivider(width: 1),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _mode == _SplitJoinMode.split
                              ? _buildSplitRightColumn(cs, textTheme, isCompact: true)
                              : _buildJoinRightColumn(cs, textTheme, isCompact: true),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_mode == _SplitJoinMode.split) ...[
                      ..._buildSplitLeftColumn(cs, textTheme, isCompact: false),
                      const SizedBox(height: AppSpacing.md),
                      ..._buildSplitRightColumn(cs, textTheme, isCompact: false),
                    ] else ...[
                      ..._buildJoinLeftColumn(cs, textTheme, isCompact: false),
                      const SizedBox(height: AppSpacing.md),
                      ..._buildJoinRightColumn(cs, textTheme, isCompact: false),
                    ],
                  ],
                ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSplitLeftColumn(ColorScheme cs, TextTheme textTheme, {required bool isCompact}) {
    return [
      _PickerRow(
        icon: Icons.description_outlined,
        label: context.l10n.splitSourceFileLabel,
        valueLabel: _sourceName ?? context.l10n.noFileSelectedLabel,
        buttonLabel: context.l10n.chooseFileButton,
        isCompact: isCompact,
        onTap: _busy ? null : _pickSplitSource,
      ),
      const SizedBox(height: 10),
      _PickerRow(
        icon: Icons.folder_outlined,
        label: context.l10n.splitDestinationFolderLabel,
        valueLabel: _destName ?? context.l10n.noFolderSelectedLabel,
        buttonLabel: context.l10n.chooseFolderButton,
        isCompact: isCompact,
        onTap: _busy ? null : _pickSplitDestination,
      ),
    ];
  }

 List<Widget> _buildSplitRightColumn(ColorScheme cs, TextTheme textTheme, {required bool isCompact}) {
    return [
      Text(
        context.l10n.splitChunkSizeLabel,
        style: textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
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
        const SizedBox(height: 8),
        TextField(
          controller: _customSizeCtrl,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            isDense: isCompact,
            labelText: context.l10n.splitChunkSizeCustomLabel,
            prefixIcon: const Icon(Icons.straighten_rounded, size: 20),
          ),
        ),
      ],
      _buildProgressAndAction(
        cs,
        textTheme,
        buttonLabel: context.l10n.splitContainerButton,
        onPressed: _runSplit,
      ),
    ];
  }
  List<Widget> _buildJoinLeftColumn(ColorScheme cs, TextTheme textTheme, {required bool isCompact}) {
    return [
      _PickerRow(
        icon: Icons.description_outlined,
        label: context.l10n.joinFirstPartLabel,
        valueLabel: _firstPartName ?? context.l10n.noFileSelectedLabel,
        buttonLabel: context.l10n.chooseFileButton,
        isCompact: isCompact,
        onTap: _busy ? null : _pickFirstPart,
      ),
      const SizedBox(height: 10),
      _PickerRow(
        icon: Icons.folder_outlined,
        label: context.l10n.splitDestinationFolderLabel,
        valueLabel: _joinDestName ?? context.l10n.noFolderSelectedLabel,
        buttonLabel: context.l10n.chooseFolderButton,
        isCompact: isCompact,
        onTap: _busy ? null : _pickJoinDestination,
      ),
    ];
  }

  List<Widget> _buildJoinRightColumn(ColorScheme cs, TextTheme textTheme, {required bool isCompact}) {
    return [
      TextField(
        controller: _outputNameCtrl,
        enabled: !_busy,
        decoration: InputDecoration(
          isDense: isCompact,
          labelText: context.l10n.joinOutputFileNameLabel,
          prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded, size: 20),
        ),
      ),
      _buildProgressAndAction(
        cs,
        textTheme,
        buttonLabel: context.l10n.joinContainerButton,
        onPressed: _runJoin,
      ),
    ];
  }

  Widget _buildProgressAndAction(
    ColorScheme cs,
    TextTheme textTheme, {
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_progressTotal != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progressTotal! > 0 ? (_progressDone ?? 0) / _progressTotal! : null,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.splitJoinOperationProgress(
              formatBytes(_progressDone ?? 0),
              formatBytes(_progressTotal!),
            ),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          InlineErrorBanner(_error!),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
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
                  buttonLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
      ],
    );
  }

  Widget _presetChip(ChunkSizePreset preset, String label) {
    final selected = _preset == preset;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: _busy ? null : (_) => setState(() => _preset = preset),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueLabel;
  final String buttonLabel;
  final VoidCallback? onTap;
  final bool isCompact;

  const _PickerRow({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.buttonLabel,
    required this.onTap,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Container(
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppIconSize.small, color: cs.primary),
          const SizedBox(width: 8),
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
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
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