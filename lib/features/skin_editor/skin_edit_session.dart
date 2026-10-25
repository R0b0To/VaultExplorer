import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/features/skin_editor/skin_target.dart';

/// A live skin-editing session.
///
/// While a session exists the whole app is drawn from [draft] instead of the
/// saved skin, so every change is visible on every page immediately. Nothing
/// is written to settings per change; the draft is saved when the session is
/// closed (and when the app goes to the background, so a killed process does
/// not lose work).
@immutable
class SkinEditSession {
  /// The skin being edited, including every change made in this session.
  final CustomAppSkin draft;

  /// How many changes [SkinEditSessionNotifier.undo] can still take back.
  final int undoDepth;

  /// Whether taps select an element to recolor (true) or reach the app
  /// normally (false).
  final bool picking;

  /// When set, the app is shown in this brightness regardless of the system or
  /// app theme mode, so the light and dark palettes can each be edited. Only
  /// lasts for the session; the saved theme mode is never touched.
  final Brightness? forcedBrightness;

  const SkinEditSession({
    required this.draft,
    this.undoDepth = 0,
    this.picking = true,
    this.forcedBrightness,
  });

  SkinEditSession copyWith({
    CustomAppSkin? draft,
    int? undoDepth,
    bool? picking,
    Brightness? forcedBrightness,
    bool clearForcedBrightness = false,
  }) => SkinEditSession(
    draft: draft ?? this.draft,
    undoDepth: undoDepth ?? this.undoDepth,
    picking: picking ?? this.picking,
    forcedBrightness: clearForcedBrightness
        ? null
        : (forcedBrightness ?? this.forcedBrightness),
  );
}

final skinEditSessionProvider =
    NotifierProvider<SkinEditSessionNotifier, SkinEditSession?>(
      SkinEditSessionNotifier.new,
    );

class SkinEditSessionNotifier extends Notifier<SkinEditSession?> {
  static const _maxUndo = 60;

  /// Edits to the same color closer together than this are one undo step, so a
  /// whole drag around the color wheel is undone in one tap.
  static const _coalesceWindow = Duration(milliseconds: 800);

  final List<CustomAppSkin> _undo = [];
  String? _lastKey;
  DateTime? _lastEditAt;

  @override
  SkinEditSession? build() => null;

  bool get isActive => state != null;

  /// Makes [skin] the active custom skin and starts editing it. If another
  /// skin is already being edited its changes are saved first.
  Future<void> start(CustomAppSkin skin) async {
    if (state != null) await commit();
    await ref.read(appSkinSettingsProvider.notifier).activateCustomSkin(skin);
    if (!ref.mounted) return;
    beginDraft(skin);
  }

  /// Starts a session on [skin] without touching saved settings.
  void beginDraft(CustomAppSkin skin) {
    _undo.clear();
    _lastKey = null;
    _lastEditAt = null;
    state = SkinEditSession(draft: skin);
  }

  void setPicking(bool picking) {
    final session = state;
    if (session == null || session.picking == picking) return;
    state = session.copyWith(picking: picking);
  }

  void togglePicking() {
    final session = state;
    if (session != null) setPicking(!session.picking);
  }

  void setForcedBrightness(Brightness? brightness) {
    final session = state;
    if (session == null) return;
    state = brightness == null
        ? session.copyWith(clearForcedBrightness: true)
        : session.copyWith(forcedBrightness: brightness);
  }

  /// Sets [target] to [color] (or back to its default when null) in the
  /// palette selected by [dark].
  void setColor(SkinTarget target, Color? color, {required bool dark}) {
    final session = state;
    if (session == null) return;
    _replace(
      session,
      target.write(session.draft, color, dark: dark),
      coalesceKey: target.id,
    );
  }

  /// Replaces the whole draft. Used by the full controls page, whose edits
  /// are not color-by-color.
  void replaceDraft(CustomAppSkin skin, {String? coalesceKey}) {
    final session = state;
    if (session == null) return;
    _replace(session, skin, coalesceKey: coalesceKey);
  }

  void _replace(
    SkinEditSession session,
    CustomAppSkin next, {
    String? coalesceKey,
  }) {
    final now = DateTime.now();
    final lastEditAt = _lastEditAt;
    final coalesce =
        coalesceKey != null &&
        coalesceKey == _lastKey &&
        lastEditAt != null &&
        now.difference(lastEditAt) < _coalesceWindow;
    if (!coalesce) {
      _undo.add(session.draft);
      if (_undo.length > _maxUndo) _undo.removeAt(0);
    }
    _lastKey = coalesceKey;
    _lastEditAt = now;
    state = session.copyWith(draft: next, undoDepth: _undo.length);
  }

  /// Takes back the most recent change.
  void undo() {
    final session = state;
    if (session == null || _undo.isEmpty) return;
    final previous = _undo.removeLast();
    _lastKey = null;
    _lastEditAt = null;
    state = session.copyWith(draft: previous, undoDepth: _undo.length);
  }

  /// Saves the draft without ending the session.
  Future<void> persist() async {
    final session = state;
    if (session == null) return;
    await ref.read(appSkinSettingsProvider.notifier).saveCustomSkin(
      session.draft,
    );
  }

  /// Saves the draft and ends the session.
  Future<void> commit() async {
    final session = state;
    if (session == null) return;
    await persist();
    if (!ref.mounted) return;
    _undo.clear();
    _lastKey = null;
    _lastEditAt = null;
    state = null;
  }
}

/// Activates [skin], starts editing it and tells the person where the
/// controls are. The entry point for every "edit this skin" button.
Future<void> beginSkinEditing(
  BuildContext context,
  WidgetRef ref,
  CustomAppSkin skin,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final message = context.l10n.skinEditStarted;
  await ref.read(skinEditSessionProvider.notifier).start(skin);
  messenger?.showSnackBar(SnackBar(content: Text(message)));
}
