import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/app/app_navigator_key.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/features/settings/custom_app_skin_screen.dart';
import 'package:vaultexplorer/features/skin_editor/skin_edit_session.dart';
import 'package:vaultexplorer/features/skin_editor/skin_element_inspector.dart';
import 'package:vaultexplorer/features/skin_editor/skin_picker_panel.dart';
import 'package:vaultexplorer/features/skin_editor/skin_target.dart';

/// Wraps the whole app (put it in `MaterialApp.builder`) and, while a skin
/// editing session is running, floats the skin editor's controls above every
/// page, dialog and sheet.
///
/// Outside a session it adds nothing but a keyed wrapper around [child].
class SkinEditorHost extends ConsumerStatefulWidget {
  final Widget child;

  const SkinEditorHost({super.key, required this.child});

  @override
  ConsumerState<SkinEditorHost> createState() => _SkinEditorHostState();
}

class _SkinEditorHostState extends ConsumerState<SkinEditorHost>
    with WidgetsBindingObserver {
  /// Marks the app's own subtree, so taps can be hit-tested against the app
  /// without ever hitting the editor's controls.
  final GlobalKey _appKey = GlobalKey(debugLabel: 'skinEditorApp');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The draft only lives in memory until the session is closed, so save it
    // whenever the app leaves the foreground; a killed process then loses
    // nothing.
    final leaving =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (!leaving) return;
    if (ref.read(skinEditSessionProvider) == null) return;
    unawaited(ref.read(skinEditSessionProvider.notifier).persist());
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(skinEditSessionProvider.select((s) => s != null));
    return Stack(
      children: [
        Positioned.fill(
          child: KeyedSubtree(key: _appKey, child: widget.child),
        ),
        if (active) Positioned.fill(child: _SkinEditorLayer(appKey: _appKey)),
      ],
    );
  }
}

/// Gives the controls their own [Overlay] (text fields and tooltips need one,
/// and the app's Navigator, which normally provides it, is below this).
/// `Overlay.wrap` puts the controls in it without any entry to manage; touches
/// outside the controls fall through to the app underneath.
class _SkinEditorLayer extends StatelessWidget {
  final GlobalKey appKey;

  const _SkinEditorLayer({required this.appKey});

  @override
  Widget build(BuildContext context) =>
      Overlay.wrap(child: _SkinEditorContent(appKey: appKey));
}

class _SkinEditorContent extends ConsumerStatefulWidget {
  final GlobalKey appKey;

  const _SkinEditorContent({required this.appKey});

  @override
  ConsumerState<_SkinEditorContent> createState() =>
      _SkinEditorContentState();
}

class _SkinEditorContentState extends ConsumerState<_SkinEditorContent> {
  /// The controls never take the skin's colors: a color that makes its own
  /// editor unreadable could not be fixed.
  static final ThemeData _controlsTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6487D9),
      brightness: Brightness.dark,
    ),
  );

  static const double _pillWidth = 52;
  static const double _pillHeight = 132;

  SkinPickResult? _pick;
  int? _layerIndex;
  SkinTarget? _target;
  Rect? _highlight;
  bool _showAll = false;
  bool _collapsed = false;

  bool _pillOnRight = true;
  double? _pillTop;
  double _lastDragX = 0;

  SkinEditSessionNotifier get _notifier =>
      ref.read(skinEditSessionProvider.notifier);

  void _clearPick() {
    _pick = null;
    _layerIndex = null;
    _target = null;
    _highlight = null;
    _showAll = false;
  }

  void _inspect(
    Offset position,
    ThemeData base,
    CustomAppSkin skin,
    bool dark,
  ) {
    final appContext = widget.appKey.currentContext;
    if (appContext == null) return;
    final result = inspectSkinElementAt(
      appContext: appContext,
      globalPosition: position,
      base: base,
      skin: skin,
      dark: dark,
    );
    setState(() {
      _pick = result;
      _collapsed = false;
      _showAll = false;
      if (result.layers.isEmpty) {
        _layerIndex = null;
        _target = null;
        _highlight = null;
      } else {
        _applyLayer(result, 0);
      }
    });
  }

  void _applyLayer(SkinPickResult pick, int index) {
    final layer = pick.layers[index];
    _layerIndex = index;
    _target = layer.candidates.first;
    _highlight = layer.rect;
  }

  void _selectLayer(int index) {
    final pick = _pick;
    if (pick == null || index >= pick.layers.length) return;
    setState(() {
      _showAll = false;
      _applyLayer(pick, index);
    });
  }

  void _selectTarget(SkinTarget target) => setState(() {
    final pick = _pick;
    final layerIndex = _layerIndex;
    final stillOnLayer =
        pick != null &&
        layerIndex != null &&
        pick.layers[layerIndex].candidates.contains(target);
    _target = target;
    _showAll = false;
    if (!stillOnLayer) {
      // Chosen from the full list, not from what was tapped.
      _layerIndex = null;
      _highlight = null;
    }
  });

  void _togglePicking() {
    final picking = ref.read(skinEditSessionProvider)?.picking ?? false;
    setState(_clearPick);
    _notifier.setPicking(!picking);
  }

  Future<void> _close() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final message = context.l10n.skinEditSaved;
    await _notifier.commit();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _openControls() {
    setState(_clearPick);
    _notifier.setPicking(false);
    appNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => const SkinAreaScope(
          area: SkinArea.settings,
          child: CustomAppSkinScreen(),
        ),
      ),
    );
  }

  void _setDark(bool dark) {
    setState(_clearPick);
    _notifier.setForcedBrightness(dark ? Brightness.dark : Brightness.light);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(skinEditSessionProvider);
    if (session == null) return const SizedBox.shrink();

    // The app's own theme (this context is below MaterialApp's Theme), which
    // is what each color is compared against.
    final base = Theme.of(context);
    final dark = base.brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final size = media.size;
    final safe = media.padding;
    final keyboard = media.viewInsets.bottom;
    final picking = session.picking;

    final minTop = safe.top + 8;
    final maxTop = math.max(minTop, size.height - safe.bottom - _pillHeight - 8);
    final pillTop = (_pillTop ?? size.height * 0.3)
        .clamp(minTop, maxTop)
        .toDouble();

    final highlight = _highlight;
    final dockTop = highlight != null && highlight.center.dy > size.height * 0.5;
    final sideInset = 8 + _pillWidth + 8;
    final panelMaxHeight = math.max(
      180.0,
      math.min(
        size.height * 0.6,
        size.height - keyboard - safe.top - safe.bottom - 24,
      ),
    );

    return Theme(
      data: _controlsTheme,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // While picking, the app underneath does not receive touches: a tap
          // selects what is there instead of pressing it. Switching picking
          // off hands every touch back to the app.
          if (picking)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _inspect(
                  details.globalPosition,
                  base,
                  session.draft,
                  dark,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          if (picking && highlight != null)
            Positioned.fromRect(
              rect: highlight,
              child: const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x1FFFC107),
                    border: Border.fromBorderSide(
                      BorderSide(color: Color(0xFFFFC107), width: 2),
                    ),
                  ),
                ),
              ),
            ),
          if (picking)
            Positioned(
              left: safe.left + (_pillOnRight ? 8 : sideInset),
              right: safe.right + (_pillOnRight ? sideInset : 8),
              top: dockTop ? safe.top + 8 : null,
              bottom: dockTop ? null : math.max(keyboard, safe.bottom) + 8,
              child: Align(
                alignment: dockTop
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: SkinPickerPanel(
                    pick: _pick,
                    layerIndex: _layerIndex,
                    target: _target,
                    skin: session.draft,
                    base: base,
                    dark: dark,
                    undoDepth: session.undoDepth,
                    showAll: _showAll,
                    collapsed: _collapsed,
                    maxHeight: panelMaxHeight,
                    onSelectLayer: _selectLayer,
                    onSelectTarget: _selectTarget,
                    onColor: (color) {
                      final target = _target;
                      if (target != null) {
                        _notifier.setColor(target, color, dark: dark);
                      }
                    },
                    onReset: () {
                      final target = _target;
                      if (target != null) {
                        _notifier.setColor(target, null, dark: dark);
                      }
                    },
                    onToggleAll: () => setState(() => _showAll = !_showAll),
                    onToggleCollapsed: () =>
                        setState(() => _collapsed = !_collapsed),
                    onUndo: _notifier.undo,
                    onSetDark: _setDark,
                    onMoreOptions: _openControls,
                  ),
                ),
              ),
            ),
          Positioned(
            top: pillTop,
            left: _pillOnRight ? null : safe.left + 8,
            right: _pillOnRight ? safe.right + 8 : null,
            child: _Pill(
              width: _pillWidth,
              picking: picking,
              onTogglePicking: _togglePicking,
              onClose: _close,
              onDrag: (details) => setState(() {
                _pillTop = pillTop + details.delta.dy;
                _lastDragX = details.globalPosition.dx;
              }),
              onDragEnd: () => setState(() {
                // Snap to whichever edge it was let go nearest to.
                _pillOnRight = _lastDragX >= size.width / 2;
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// The two floating buttons: the eyedropper that turns picking on and off, and
/// the check that saves and closes the editor. The grip on top moves the pill
/// out of the way; it snaps to the left or right edge.
class _Pill extends StatelessWidget {
  final double width;
  final bool picking;
  final VoidCallback onTogglePicking;
  final VoidCallback onClose;
  final ValueChanged<DragUpdateDetails> onDrag;
  final VoidCallback onDragEnd;

  const _Pill({
    required this.width,
    required this.picking,
    required this.onTogglePicking,
    required this.onClose,
    required this.onDrag,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 8,
      shape: const StadiumBorder(),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: onDrag,
                onPanEnd: (_) => onDragEnd(),
                child: SizedBox(
                  width: width,
                  height: 26,
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (picking)
                IconButton.filled(
                  tooltip: l10n.skinEditPickStopTooltip,
                  onPressed: onTogglePicking,
                  icon: const Icon(Icons.colorize_rounded),
                )
              else
                IconButton.filledTonal(
                  tooltip: l10n.skinEditPickTooltip,
                  onPressed: onTogglePicking,
                  icon: const Icon(Icons.colorize_rounded),
                ),
              const SizedBox(height: 2),
              IconButton(
                tooltip: l10n.skinEditDoneTooltip,
                onPressed: onClose,
                icon: const Icon(Icons.check_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
