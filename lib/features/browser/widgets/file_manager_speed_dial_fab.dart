import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';

class FileManagerSpeedDialFab extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onToggle;
  final VoidCallback onClose;
  final List<FileManagerAction> actions;
  final Map<FileManagerAction, WidgetBuilder> builders;
  final double bottomOffset;

  const FileManagerSpeedDialFab({
    super.key,
    required this.isOpen,
    required this.onToggle,
    required this.onClose,
    required this.actions,
    required this.builders,
    this.bottomOffset = 16.0,
  });

  @override
  State<FileManagerSpeedDialFab> createState() => _FileManagerSpeedDialFabState();
}

class _FileManagerSpeedDialFabState extends State<FileManagerSpeedDialFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: AppMotion.short2,
      value: widget.isOpen ? 1.0 : 0.0,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant FileManagerSpeedDialFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _animController.forward();
      } else {
        _animController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final screenHeight = mediaQuery.size.height;
    final rightInset = mediaQuery.padding.right;

    final availableActions = widget.actions
        .where((a) => widget.builders.containsKey(a))
        .toList();

    if (availableActions.isEmpty) return const SizedBox.shrink();

    // Available vertical space for the unfolded items above the FAB
    final maxActionsHeight = math.max(
      120.0,
      screenHeight - widget.bottomOffset - 56.0 - 24.0 - mediaQuery.padding.top,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Black translucent backdrop with tap-outside dismiss
        IgnorePointer(
          ignoring: !widget.isOpen,
          child: FadeTransition(
            opacity: _expandAnimation,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.84),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),

        // 2. Action items and main toggle FAB
        Positioned(
          right: 16.0 + rightInset,
          bottom: widget.bottomOffset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Expanded Action Items
              IgnorePointer(
                ignoring: !widget.isOpen,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxActionsHeight),
                  child: SingleChildScrollView(
                    reverse: true,
                    physics: const BouncingScrollPhysics(),
                    child: _buildActionsLayout(
                      availableActions: availableActions,
                      isLandscape: isLandscape,
                      cs: cs,
                      l10n: l10n,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Main Toggle FAB
              FloatingActionButton(
                heroTag: 'file_manager_speed_dial_main_fab',
                elevation: 4,
                backgroundColor: widget.isOpen
                    ? cs.surfaceContainerHighest
                    : cs.primaryContainer,
                foregroundColor: widget.isOpen
                    ? cs.onSurface
                    : cs.onPrimaryContainer,
                onPressed: widget.onToggle,
                child: AnimatedRotation(
                  turns: widget.isOpen ? 0.125 : 0.0,
                  duration: AppMotion.short2,
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    widget.isOpen ? Icons.add_rounded : Icons.tune_rounded,
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionsLayout({
    required List<FileManagerAction> availableActions,
    required bool isLandscape,
    required ColorScheme cs,
    required dynamic l10n,
  }) {
    if (isLandscape && availableActions.length > 3) {
      // 2-column layout in landscape to conserve vertical height
      final List<Widget> rows = [];
      for (int i = 0; i < availableActions.length; i += 2) {
        final actionRight = availableActions[i];
        final hasLeft = i + 1 < availableActions.length;
        final actionLeft = hasLeft ? availableActions[i + 1] : null;

        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (actionLeft != null) ...[
                  _buildActionItem(
                    action: actionLeft,
                    cs: cs,
                    label: actionLeft.getLocalizedLabel(l10n),
                  ),
                  const SizedBox(width: 14),
                ],
                _buildActionItem(
                  action: actionRight,
                  cs: cs,
                  label: actionRight.getLocalizedLabel(l10n),
                ),
              ],
            ),
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: rows,
      );
    } else {
      // Standard 1-column layout in portrait
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < availableActions.length; i++) ...[
            _buildActionItem(
              action: availableActions[i],
              cs: cs,
              label: availableActions[i].getLocalizedLabel(l10n),
            ),
            if (i < availableActions.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }
  }

  Widget _buildActionItem({
    required FileManagerAction action,
    required ColorScheme cs,
    required String label,
  }) {
    final builder = widget.builders[action]!;

    return ScaleTransition(
      scale: _expandAnimation,
      alignment: Alignment.bottomRight,
      child: FadeTransition(
        opacity: _expandAnimation,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // High-contrast Label Pill
            Material(
              color: cs.surfaceContainerHighest,
              elevation: 4,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: widget.onClose,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Mini Action Button FAB
            Material(
              color: cs.primaryContainer,
              shape: const CircleBorder(),
              elevation: 4,
              shadowColor: Colors.black45,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      iconTheme: IconThemeData(
                        color: cs.onPrimaryContainer,
                        size: 22,
                      ),
                      iconButtonTheme: IconButtonThemeData(
                        style: IconButton.styleFrom(
                          foregroundColor: cs.onPrimaryContainer,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(48, 48),
                        ),
                      ),
                    ),
                    child: Builder(
                      builder: (ctx) => builder(ctx),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}