// File: lib/features/tools/widgets/container_splitter_sheet.dart

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/container_splitter_controller.dart';

class ContainerSplitterSheet extends ConsumerStatefulWidget {
  const ContainerSplitterSheet({super.key});

  @override
  ConsumerState<ContainerSplitterSheet> createState() => _ContainerSplitterSheetState();
}

class _ContainerSplitterSheetState extends ConsumerState<ContainerSplitterSheet> {
  final _customSizeCtrl = TextEditingController();
  final _outputNameCtrl = TextEditingController();

  @override
  void dispose() {
    _customSizeCtrl.dispose();
    _outputNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickSplitSource() =>
      ref.read(containerSplitterProvider.notifier).pickSplitSource();

  Future<void> _pickSplitDestination() =>
      ref.read(containerSplitterProvider.notifier).pickSplitDestination();

  Future<void> _pickFirstPart() async {
    final stripped = await ref.read(containerSplitterProvider.notifier).pickFirstPart();
    if (!mounted || stripped == null) return;
    _outputNameCtrl.text = stripped;
  }

  Future<void> _pickJoinDestination() =>
      ref.read(containerSplitterProvider.notifier).pickJoinDestination();

  Future<void> _runSplit() async {
    final l10n = context.l10n;
    final ok = await ref
        .read(containerSplitterProvider.notifier)
        .runSplit(customSizeText: _customSizeCtrl.text, l10n: l10n);
    if (!mounted || !ok) return;
    Navigator.of(context).pop();
    showAppSnackBar(
      context,
      message: l10n.splitContainerSuccessMessage,
      tone: AppBannerTone.success,
    );
  }

  Future<void> _runJoin() async {
    final l10n = context.l10n;
    final ok = await ref
        .read(containerSplitterProvider.notifier)
        .runJoin(outputNameText: _outputNameCtrl.text, l10n: l10n);
    if (!mounted || !ok) return;
    Navigator.of(context).pop();
    showAppSnackBar(
      context,
      message: l10n.joinContainerSuccessMessage,
      tone: AppBannerTone.success,
    );
  }

  Widget _buildModeSegmentedButton(ContainerSplitterState state, {required bool isCompact}) {
    return Container(
      padding: isCompact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      child: SegmentedButton<SplitJoinMode>(
        showSelectedIcon: false,
        style: isCompact
            ? SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              )
            : null,
        segments: [
          ButtonSegment(
            value: SplitJoinMode.split,
            label: Text(
              context.l10n.splitJoinModeSplit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            icon: const Icon(Icons.content_cut_rounded, size: 18),
          ),
          ButtonSegment(
            value: SplitJoinMode.join,
            label: Text(
              context.l10n.splitJoinModeJoin,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            icon: const Icon(Icons.merge_type_rounded, size: 18),
          ),
        ],
        selected: {state.mode},
        onSelectionChanged: state.busy
            ? null
            : (sel) => ref.read(containerSplitterProvider.notifier).setMode(sel.first),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(containerSplitterProvider);
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
            _buildModeSegmentedButton(state, isCompact: true),
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
                _buildModeSegmentedButton(state, isCompact: false),
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
                          children: state.mode == SplitJoinMode.split
                              ? _buildSplitLeftColumn(state, cs, textTheme, isCompact: true)
                              : _buildJoinLeftColumn(state, cs, textTheme, isCompact: true),
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
                          children: state.mode == SplitJoinMode.split
                              ? _buildSplitRightColumn(state, cs, textTheme, isCompact: true)
                              : _buildJoinRightColumn(state, cs, textTheme, isCompact: true),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.mode == SplitJoinMode.split) ...[
                      ..._buildSplitLeftColumn(state, cs, textTheme, isCompact: false),
                      const SizedBox(height: AppSpacing.md),
                      ..._buildSplitRightColumn(state, cs, textTheme, isCompact: false),
                    ] else ...[
                      ..._buildJoinLeftColumn(state, cs, textTheme, isCompact: false),
                      const SizedBox(height: AppSpacing.md),
                      ..._buildJoinRightColumn(state, cs, textTheme, isCompact: false),
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

  List<Widget> _buildSplitLeftColumn(ContainerSplitterState state, ColorScheme cs, TextTheme textTheme, {required bool isCompact}) {
    return [
      _PickerRow(
        icon: Icons.description_outlined,
        label: context.l10n.splitSourceFileLabel,
        valueLabel: state.sourceName ?? context.l10n.noFileSelectedLabel,
        buttonLabel: context.l10n.chooseFileButton,
        isCompact: isCompact,
        onTap: state.busy ? null : _pickSplitSource,
      ),
      const SizedBox(height: 10),
      _PickerRow(
        icon: Icons.folder_outlined,
        label: context.l10n.splitDestinationFolderLabel,
        valueLabel: state.destName ?? context.l10n.noFolderSelectedLabel,
        buttonLabel: context.l10n.chooseFolderButton,
        isCompact: isCompact,
        onTap: state.busy ? null : _pickSplitDestination,
      ),
    ];
  }

 List<Widget> _buildSplitRightColumn(ContainerSplitterState state, ColorScheme cs, TextTheme textTheme, {required bool isCompact}) {
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
          _presetChip(state, ChunkSizePreset.fourMb, context.l10n.splitChunkSizeFourMb),
          _presetChip(state, ChunkSizePreset.cloud8mb, context.l10n.splitChunkSizeCloud8mb),
          _presetChip(state, ChunkSizePreset.cloud32mb, context.l10n.splitChunkSizeCloud32mb),
          _presetChip(state, ChunkSizePreset.cloud100mb, context.l10n.splitChunkSizeCloud),
          _presetChip(state, ChunkSizePreset.fat32_2gb, context.l10n.splitChunkSizeFat32),
          _presetChip(state, ChunkSizePreset.fourGb, context.l10n.splitChunkSizeFourGb),
          _presetChip(state, ChunkSizePreset.custom, context.l10n.splitChunkSizeCustom),
        ],
      ),
      if (state.preset == ChunkSizePreset.custom) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _customSizeCtrl,
          enabled: !state.busy,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            isDense: isCompact,
            labelText: context.l10n.splitChunkSizeCustomLabel,
            prefixIcon: const Icon(Icons.straighten_rounded, size: 20),
          ),
        ),
      ],
      _buildProgressAndAction(
        state,
        cs,
        textTheme,
        buttonLabel: context.l10n.splitContainerButton,
        onPressed: _runSplit,
      ),
    ];
  }
  List<Widget> _buildJoinLeftColumn(ContainerSplitterState state, ColorScheme cs, TextTheme textTheme, {required bool isCompact}) {
    return [
      _PickerRow(
        icon: Icons.description_outlined,
        label: context.l10n.joinFirstPartLabel,
        valueLabel: state.firstPartName ?? context.l10n.noFileSelectedLabel,
        buttonLabel: context.l10n.chooseFileButton,
        isCompact: isCompact,
        onTap: state.busy ? null : _pickFirstPart,
      ),
      const SizedBox(height: 10),
      _PickerRow(
        icon: Icons.folder_outlined,
        label: context.l10n.splitDestinationFolderLabel,
        valueLabel: state.joinDestName ?? context.l10n.noFolderSelectedLabel,
        buttonLabel: context.l10n.chooseFolderButton,
        isCompact: isCompact,
        onTap: state.busy ? null : _pickJoinDestination,
      ),
    ];
  }

  List<Widget> _buildJoinRightColumn(ContainerSplitterState state, ColorScheme cs, TextTheme textTheme, {required bool isCompact}) {
    return [
      TextField(
        controller: _outputNameCtrl,
        enabled: !state.busy,
        decoration: InputDecoration(
          isDense: isCompact,
          labelText: context.l10n.joinOutputFileNameLabel,
          prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded, size: 20),
        ),
      ),
      _buildProgressAndAction(
        state,
        cs,
        textTheme,
        buttonLabel: context.l10n.joinContainerButton,
        onPressed: _runJoin,
      ),
    ];
  }

  Widget _buildProgressAndAction(
    ContainerSplitterState state,
    ColorScheme cs,
    TextTheme textTheme, {
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.progressTotal != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: state.progressTotal! > 0 ? (state.progressDone ?? 0) / state.progressTotal! : null,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.splitJoinOperationProgress(
              formatBytes(state.progressDone ?? 0),
              formatBytes(state.progressTotal!),
            ),
            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 8),
          InlineErrorBanner(state.error!),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: state.busy ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: const StadiumBorder(),
          ),
          child: state.busy
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

  Widget _presetChip(ContainerSplitterState state, ChunkSizePreset preset, String label) {
    final selected = state.preset == preset;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onSelected: state.busy
          ? null
          : (_) => ref.read(containerSplitterProvider.notifier).setPreset(preset),
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