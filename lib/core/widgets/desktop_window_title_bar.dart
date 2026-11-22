import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const double kDesktopTitleBarHeight = 32;
const double kDesktopTitleBarCaptionButtonWidth = 46;
const double kDesktopTitleBarCaptionWidth =
    kDesktopTitleBarCaptionButtonWidth * 3;
const double kDesktopTitleBarDragWidth = 24;
const double kDesktopTitleBarTrailingWidth =
    kDesktopTitleBarCaptionWidth + kDesktopTitleBarDragWidth;

/// Background of a tab strip: a shade darker than [base], the colour of the
/// bar right under it, so the selected tab (drawn in [base]) reads as part of
/// that bar.
Color tabStripColorOver(ColorScheme cs, Color base) => Color.alphaBlend(
  (cs.brightness == Brightness.dark ? Colors.black : cs.onSurface).withValues(
    alpha: cs.brightness == Brightness.dark ? 0.28 : 0.07,
  ),
  base,
);

/// Background of the desktop tab strip and the title bar it lives in. The bar
/// right under the strip (the breadcrumb / navigation row, the dashboard
/// header) is `surfaceContainer`, and so is the selected tab.
Color desktopTabStripColor(ColorScheme cs) =>
    tabStripColorOver(cs, cs.surfaceContainer);

class DesktopWindowTitleBarScope extends InheritedWidget {
  final VoidCallback onDragStart;
  final VoidCallback onDoubleTap;

  const DesktopWindowTitleBarScope({
    super.key,
    required this.onDragStart,
    required this.onDoubleTap,
    required super.child,
  });

  static DesktopWindowTitleBarScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopWindowTitleBarScope>();

  @override
  bool updateShouldNotify(DesktopWindowTitleBarScope oldWidget) =>
      onDragStart != oldWidget.onDragStart ||
      onDoubleTap != oldWidget.onDoubleTap;
}

/// Lets a [DesktopCaptionFrame] know that the page it wraps already draws its
/// own [DesktopWindowTitleBar], so the frame must not add a second row.
class DesktopCaptionClaims extends ChangeNotifier {
  int _count = 0;
  bool _disposed = false;

  bool get claimed => _count > 0;

  void claim() {
    _count++;
    notifyListeners();
  }

  void release() {
    _count--;
    // Releasing happens while the tree is torn down, when layout must not be
    // invalidated yet, so the listeners hear about it after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class DesktopCaptionClaimsScope extends InheritedWidget {
  final DesktopCaptionClaims claims;

  const DesktopCaptionClaimsScope({
    super.key,
    required this.claims,
    required super.child,
  });

  static DesktopCaptionClaims? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<DesktopCaptionClaimsScope>()
      ?.claims;

  @override
  bool updateShouldNotify(DesktopCaptionClaimsScope oldWidget) =>
      claims != oldWidget.claims;
}

/// Windows caption controls hosted in Flutter so browser tabs can share the
/// top row with the system window actions.
class DesktopWindowTitleBar extends StatefulWidget {
  final Widget tabs;
  final Widget? leading;
  final double leadingWidth;
  final bool leadingDraggable;
  final double height;

  const DesktopWindowTitleBar({
    super.key,
    required this.tabs,
    this.leading,
    this.leadingWidth = 0,
    this.leadingDraggable = false,
    this.height = 34,
  });

  @override
  State<DesktopWindowTitleBar> createState() => _DesktopWindowTitleBarState();
}

class _DesktopWindowTitleBarState extends State<DesktopWindowTitleBar> {
  static const _channel = MethodChannel('vaultexplorer/window');
  bool _maximized = false;
  DesktopCaptionClaims? _claims;

  @override
  void initState() {
    super.initState();
    _claims = DesktopCaptionClaimsScope.maybeOf(context)?..claim();
    _refreshMaximized();
  }

  @override
  void dispose() {
    _claims?.release();
    super.dispose();
  }

  Future<void> _refreshMaximized() async {
    try {
      final value = await _channel.invokeMethod<bool>('isMaximized');
      if (mounted) setState(() => _maximized = value ?? false);
    } on MissingPluginException {
      // Non-Windows hosts keep their native title bar.
    } on PlatformException {
      // A transient runner shutdown should not interrupt the UI.
    }
  }

  Future<void> _invoke(String method) async {
    try {
      final value = await _channel.invokeMethod<bool>(method);
      if (method == 'toggleMaximize' && mounted && value != null) {
        setState(() => _maximized = value);
      }
    } on MissingPluginException {
      // Non-Windows hosts keep their native title bar.
    } on PlatformException {
      // A transient runner shutdown should not interrupt the UI.
    }
  }

  Future<void> _startDragging() async {
    await _invoke('startDragging');
    await _refreshMaximized();
  }

  Widget _captionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool close = false,
  }) => SizedBox(
    width: kDesktopTitleBarCaptionButtonWidth,
    height: widget.height,
    child: IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 15),
      style: IconButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        backgroundColor: Colors.transparent,
        hoverColor: close
            ? const Color(0xFFE81123)
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: .08),
        shape: const RoundedRectangleBorder(),
        padding: EdgeInsets.zero,
        minimumSize: Size(kDesktopTitleBarCaptionButtonWidth, widget.height),
        maximumSize: Size(kDesktopTitleBarCaptionButtonWidth, widget.height),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );

  Widget _dragRegion({required Widget child}) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onPanStart: (_) => _startDragging(),
    onDoubleTap: () => _invoke('toggleMaximize'),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: desktopTabStripColor(cs),
      child: SizedBox(
        height: widget.height,
        child: Row(
          children: [
            if (widget.leading != null)
              SizedBox(
                width: widget.leadingWidth,
                height: widget.height,
                child: widget.leadingDraggable
                    ? _dragRegion(child: widget.leading!)
                    : widget.leading!,
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Stretches the tabs leave empty (Tools and Settings show no
                  // tabs at all) still drag and maximize the window.
                  Positioned.fill(
                    child: _dragRegion(child: const SizedBox.expand()),
                  ),
                  DesktopWindowTitleBarScope(
                    onDragStart: _startDragging,
                    onDoubleTap: () => _invoke('toggleMaximize'),
                    child: widget.tabs,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: kDesktopTitleBarDragWidth,
              height: widget.height,
              child: _dragRegion(child: const SizedBox.expand()),
            ),
            _captionButton(
              icon: Icons.remove_rounded,
              tooltip: 'Minimize',
              onPressed: () => _invoke('minimize'),
            ),
            _captionButton(
              icon: _maximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              tooltip: _maximized ? 'Restore' : 'Maximize',
              onPressed: () => _invoke('toggleMaximize'),
            ),
            _captionButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              close: true,
              onPressed: () => _invoke('close'),
            ),
          ],
        ),
      ),
    );
  }
}
