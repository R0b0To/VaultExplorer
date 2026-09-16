import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Shows a thumb-friendly bottom sheet letting the user quickly select a custom
/// duration using tactile drum wheels and quick-jump chips.
///
/// Returns the chosen duration in minutes, or `null` if cancelled.
Future<int?> showDurationPickerDialog(
  BuildContext context, {
  required String title,
  required int initialMinutes,
  int minMinutes = 1,
  int maxMinutes = 1440, // 24 hours
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
    ),
    builder: (sheetContext) => _DurationPickerSheet(
      title: title,
      initialMinutes: initialMinutes,
      minMinutes: minMinutes,
      maxMinutes: maxMinutes,
    ),
  );
}

class _DurationPickerSheet extends StatefulWidget {
  final String title;
  final int initialMinutes;
  final int minMinutes;
  final int maxMinutes;

  const _DurationPickerSheet({
    required this.title,
    required this.initialMinutes,
    required this.minMinutes,
    required this.maxMinutes,
  });

  @override
  State<_DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<_DurationPickerSheet> {
  late int _hours;
  late int _minutes;

  late FixedExtentScrollController _hoursCtrl;
  late FixedExtentScrollController _minutesCtrl;

  static const double _itemExtent = 44.0;

  @override
  void initState() {
    super.initState();
    final clamped = widget.initialMinutes.clamp(widget.minMinutes, widget.maxMinutes);
    _hours = clamped ~/ 60;
    _minutes = clamped % 60;

    _hoursCtrl = FixedExtentScrollController(initialItem: _hours);
    _minutesCtrl = FixedExtentScrollController(initialItem: _minutes);
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  int get _totalMinutes => (_hours * 60) + _minutes;
  bool get _isValid => _totalMinutes >= widget.minMinutes && _totalMinutes <= widget.maxMinutes;

  void _applyQuickMinutes(int targetMinutes) {
    HapticFeedback.mediumImpact();
    final clamped = targetMinutes.clamp(widget.minMinutes, widget.maxMinutes);
    final targetH = clamped ~/ 60;
    final targetM = clamped % 60;

    setState(() {
      _hours = targetH;
      _minutes = targetM;
    });

    _hoursCtrl.animateToItem(
      targetH,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
    _minutesCtrl.animateToItem(
      targetM,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  String _formatPreview() {
    if (_hours == 0 && _minutes == 0) return context.l10n.nMinutes(0);
    if (_hours == 0) return context.l10n.nMinutes(_minutes);
    if (_minutes == 0) return context.l10n.nHours(_hours);
    return '${context.l10n.nHours(_hours)} ${context.l10n.nMinutes(_minutes)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isValid ? cs.primaryContainer : cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatPreview(),
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _isValid ? cs.onPrimaryContainer : cs.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Quick selection chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _QuickChip(label: '6h', onTap: () => _applyQuickMinutes(360)),
                const SizedBox(width: 8),
                _QuickChip(label: '12h', onTap: () => _applyQuickMinutes(720)),
                const SizedBox(width: 8),
                _QuickChip(label: '24h', onTap: () => _applyQuickMinutes(1440)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Dual Scroll Wheel Picker
          Container(
            height: 170,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Highlight indicator bar across both wheels
                IgnorePointer(
                  child: Container(
                    height: _itemExtent,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.3),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
                // The wheels
                Row(
                  children: [
                    // Hours Wheel (0 .. 24)
                    Expanded(
                      child: CupertinoPicker.builder(
                        scrollController: _hoursCtrl,
                        itemExtent: _itemExtent,
                        selectionOverlay: const SizedBox.shrink(),
                        onSelectedItemChanged: (index) {
                          HapticFeedback.selectionClick();
                          setState(() => _hours = index);
                        },
                        childCount: (widget.maxMinutes ~/ 60) + 1,
                        itemBuilder: (context, index) {
                          final isSelected = index == _hours;
                          return Center(
                            child: Text(
                              context.l10n.nHours(index),
                              style: isSelected
                                  ? textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: cs.primary,
                                    )
                                  : textTheme.bodyLarge?.copyWith(
                                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Minutes Wheel (0 .. 59)
                    Expanded(
                      child: CupertinoPicker.builder(
                        scrollController: _minutesCtrl,
                        itemExtent: _itemExtent,
                        selectionOverlay: const SizedBox.shrink(),
                        onSelectedItemChanged: (index) {
                          HapticFeedback.selectionClick();
                          setState(() => _minutes = index);
                        },
                        childCount: 60,
                        itemBuilder: (context, index) {
                          final isSelected = index == _minutes;
                          return Center(
                            child: Text(
                              context.l10n.nMinutes(index),
                              style: isSelected
                                  ? textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: cs.primary,
                                    )
                                  : textTheme.bodyLarge?.copyWith(
                                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isValid ? () => Navigator.of(context).pop(_totalMinutes) : null,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(context.l10n.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}