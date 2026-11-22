import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const double kDesktopTitleBarCaptionButtonWidth = 46;
const double kDesktopTitleBarCaptionWidth =
    kDesktopTitleBarCaptionButtonWidth * 3;
const double kDesktopTitleBarDragWidth = 24;
const double kDesktopTitleBarTrailingWidth =
    kDesktopTitleBarCaptionWidth + kDesktopTitleBarDragWidth;

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

  @override
  void initState() {
    super.initState();
    _refreshMaximized();
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
      color: cs.surfaceContainer,
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
            Expanded(child: widget.tabs),
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
