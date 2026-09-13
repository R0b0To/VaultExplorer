part of 'hash_verifier_sheet.dart';

/// The "Computed Hashes" results card: empty-state prompt, or the list of
/// computed digests plus an export-manifest control. Extracted from
/// `_HashVerifierSheetState._buildComputeResultsCard` -- pure
/// presentation reading [HashVerifierState], plus two callbacks for the
/// State-owned async actions (copying a digest, exporting a manifest).
class _ComputeResultsCard extends ConsumerWidget {
  const _ComputeResultsCard({
    required this.state,
    required this.cs,
    required this.textTheme,
    required this.isCompact,
    required this.onCopy,
    required this.onExportManifest,
  });

  final HashVerifierState state;
  final ColorScheme cs;
  final TextTheme textTheme;
  final bool isCompact;
  final Future<void> Function(String hex) onCopy;
  final Future<void> Function(List<HashComputeResult> results, HashAlgorithm algorithm) onExportManifest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.computeResults.isEmpty && !state.computeBusy) {
      return Container(
        padding: EdgeInsets.all(isCompact ? 14 : 20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            'Select files and tap "Compute Hashes" to view checksums and export a verification manifest.',
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.computeResults.isNotEmpty) ...[
          Text(
            'Computed Hashes (${state.computeResults.length})',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: isCompact ? 160 : 300),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final source in state.computeSources)
                      if (state.computeResults[source.id] != null)
                        _SourceRow(
                          source: source,
                          result: state.computeResults[source.id],
                          algorithms: state.algorithms,
                          enabled: !state.computeBusy,
                          onRemove: () => ref
                              .read(hashVerifierProvider.notifier)
                              .removeComputeSource(source),
                          onCopy: onCopy,
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.hashVerifierExportAlgorithmLabel,
                  style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: DropdownButton<HashAlgorithm>(
                  value: state.algorithms.contains(state.exportAlgorithm)
                      ? state.exportAlgorithm
                      : (state.algorithms.isEmpty ? null : state.algorithms.first),
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox(),
                  items: [
                    for (final algo in state.algorithms)
                      DropdownMenuItem(value: algo, child: Text(algo.label)),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(hashVerifierProvider.notifier).setExportAlgorithm(val);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: state.computeResults.values
                    .any((r) => r.digests.containsKey(state.exportAlgorithm))
                ? () => onExportManifest(
                      state.computeResults.values
                          .where((r) => r.digests.containsKey(state.exportAlgorithm))
                          .toList(),
                      state.exportAlgorithm,
                    )
                : null,
            icon: const Icon(Icons.save_alt_rounded, size: 16),
            label: Text(
              context.l10n.hashVerifierExportManifestButton,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ],
    );
  }
}

/// The horizontal row of algorithm filter chips (MD5/SHA-1/SHA-256/...)
/// shown inline above the Compute tab's file list. Extracted from
/// `_HashVerifierSheetState._buildAlgorithmsInlineSelector` -- pure
/// presentation reading [HashVerifierState].
class _AlgorithmsInlineSelector extends ConsumerWidget {
  const _AlgorithmsInlineSelector({
    required this.state,
    required this.cs,
    required this.textTheme,
  });

  final HashVerifierState state;
  final ColorScheme cs;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.hashVerifierAlgorithmsLabel,
        style: textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final algo in HashAlgorithm.values) ...[
              FilterChip(
                label: Text(algo.label, style: const TextStyle(fontSize: 12)),
                selected: state.algorithms.contains(algo),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                onSelected: state.computeBusy
                    ? null
                    : (selected) {
                        final newAlgos = Set<HashAlgorithm>.from(state.algorithms);
                        if (selected) {
                          newAlgos.add(algo);
                        } else {
                          newAlgos.remove(algo);
                        }
                        ref
                            .read(hashVerifierProvider.notifier)
                            .setAlgorithms(newAlgos);
                      },
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    ],
  );
}
}
