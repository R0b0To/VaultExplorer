part of 'hash_verifier_sheet.dart';

/// One row inside the Compute tab's file list: filename, remove button,
/// and (once computed) each requested algorithm's hex digest with a copy
/// button.
class _SourceRow extends StatelessWidget {
  final CryptoSourceItem source;
  final HashComputeResult? result;
  final Set<HashAlgorithm> algorithms;
  final bool enabled;
  final VoidCallback onRemove;
  final void Function(String hex) onCopy;

  const _SourceRow({
    required this.source,
    required this.result,
    required this.algorithms,
    required this.enabled,
    required this.onRemove,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                source.isFromVault ? Icons.lock_rounded : iconForFile(source.displayName),
                size: 16,
                color: source.isFromVault ? cs.primary : colorForFile(source.displayName),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source.displayName,
                  style: textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (result?.hasError == true)
                Icon(Icons.error_outline_rounded, size: 16, color: cs.error)
              else if (result != null)
                Icon(Icons.check_circle_outline_rounded, size: 16, color: cs.primary),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                onPressed: enabled ? onRemove : null,
              ),
            ],
          ),
          if (result != null) ...[
            if (result!.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 2),
                child: Text(
                  result!.error!,
                  style: textTheme.labelSmall?.copyWith(color: cs.error),
                ),
              )
            else
              for (final algo in algorithms)
                if (result!.digests[algo] != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            algo.label,
                            style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            result!.digests[algo]!,
                            style: textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => onCopy(result!.digests[algo]!),
                        ),
                      ],
                    ),
                  ),
          ],
        ],
      ),
    );
  }
}

/// One row inside the Verify tab's results list.
class _VerifyRowTile extends StatelessWidget {
  final VerifyRow row;

  const _VerifyRowTile({required this.row});

  (IconData, Color) _visual(BuildContext context) {
    final cs = context.colors;
    final semantic = context.semanticColors;
    return switch (row.status) {
      VerifyStatus.match => (Icons.check_circle_rounded, semantic.success),
      VerifyStatus.mismatch => (Icons.cancel_rounded, cs.error),
      VerifyStatus.error => (Icons.error_rounded, cs.error),
      VerifyStatus.missing => (Icons.help_outline_rounded, cs.onSurfaceVariant),
      VerifyStatus.pending => (Icons.radio_button_unchecked_rounded, cs.onSurfaceVariant),
      VerifyStatus.computing => (Icons.hourglass_top_rounded, cs.primary),
    };
  }

  String _statusLabel(BuildContext context) => switch (row.status) {
        VerifyStatus.match => context.l10n.hashVerifierStatusMatch,
        VerifyStatus.mismatch => context.l10n.hashVerifierStatusMismatch,
        VerifyStatus.error => row.errorMessage ?? context.l10n.hashVerifierStatusMismatch,
        VerifyStatus.missing => context.l10n.hashVerifierStatusMissing,
        VerifyStatus.pending || VerifyStatus.computing => context.l10n.hashVerifierStatusPending,
      };

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final (icon, color) = _visual(context);
    final showDetail = row.status == VerifyStatus.mismatch || row.status == VerifyStatus.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              row.status == VerifyStatus.computing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: color),
                    )
                  : Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.entry.fileName,
                      style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${row.entry.algorithm.label} • ${_statusLabel(context)}',
                      style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showDetail && row.computedHex != null) ...[
            const SizedBox(height: 6),
            Text(
              '${context.l10n.hashVerifierExpectedLabel}: ${row.entry.expectedHex}',
              style: textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
            ),
            Text(
              '${context.l10n.hashVerifierActualLabel}: ${row.computedHex}',
              style: textTheme.labelSmall?.copyWith(fontFamily: 'monospace', color: cs.error),
            ),
          ],
        ],
      ),
    );
  }
}