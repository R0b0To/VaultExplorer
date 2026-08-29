import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_pill.dart';

/// Pending copy/move clipboard indicator.
class ClipboardActivityPill extends StatefulWidget {
  final bool isCutOperation;
  final int itemCount;
  final String? sourceLabel;
  final VoidCallback onCancel;
  final VoidCallback? onPaste;

  const ClipboardActivityPill({
    super.key,
    required this.isCutOperation,
    required this.itemCount,
    this.sourceLabel,
    required this.onCancel,
    this.onPaste,
  });

  @override
  State<ClipboardActivityPill> createState() => _ClipboardActivityPillState();
}

class _ClipboardActivityPillState extends State<ClipboardActivityPill> {
  Timer? _shrinkTimer;
  bool _shrunk = false;

  @override
  void initState() {
    super.initState();
    _startShrinkTimer();
  }

  @override
  void didUpdateWidget(ClipboardActivityPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount || oldWidget.isCutOperation != widget.isCutOperation) {
      setState(() => _shrunk = false);
      _startShrinkTimer();
    }
  }

  void _startShrinkTimer() {
    _shrinkTimer?.cancel();
    _shrinkTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _shrunk = true);
    });
  }

  @override
  void dispose() {
    _shrinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final verb = widget.isCutOperation
        ? context.l10n.clipboardVerbMoving
        : context.l10n.clipboardVerbCopying;
    final fromSuffix = widget.sourceLabel != null
        ? context.l10n.clipboardFromSourceSuffix(widget.sourceLabel!)
        : '';
    final title = '${context.l10n.clipboardPillTitle(verb, widget.itemCount)}$fromSuffix';

    return FloatingPill(
      color: cs.secondaryContainer,
      onTap: widget.onPaste,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_shrunk || widget.onPaste == null) ...[
              Icon(
                widget.isCutOperation ? Icons.cut_rounded : Icons.copy_rounded,
                size: AppIconSize.standard,
                color: cs.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: widget.onPaste != null
                    ? Text(
                        title,
                        style: textTheme.labelLarge?.copyWith(
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: textTheme.labelLarge?.copyWith(
                              color: cs.onSecondaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            context.l10n.clipboardOpenContainerToPaste,
                            style: textTheme.labelSmall?.copyWith(
                              color: cs.onSecondaryContainer.withValues(alpha: 0.8),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
              ),
              if (widget.onPaste != null) const SizedBox(width: 4),
            ],
            if (widget.onPaste != null)
              TextButton(
                onPressed: widget.onPaste,
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSecondaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                child: Text(context.l10n.paste),
              ),
            Container(
              width: 1,
              height: 20,
              color: cs.onSecondaryContainer.withValues(alpha: 0.2),
              margin: const EdgeInsets.symmetric(horizontal: 6),
            ),
            IconButton(
              icon: Icon(Icons.close_rounded, size: AppIconSize.standard, color: cs.onSecondaryContainer),
              tooltip: context.l10n.cancel,
              onPressed: widget.onCancel,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}
