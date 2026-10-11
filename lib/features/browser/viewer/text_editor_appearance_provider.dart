// Manually-defined provider (no @riverpod/build_runner codegen), matching
// the pattern already used by e.g. ExternalStorageLocationsNotifier: a
// plain Notifier subclass plus a NotifierProvider constructed from it.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/services/text_editor_appearance_service.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_theme.dart';

class TextEditorAppearanceNotifier extends Notifier<TextEditorAppearancePrefs> {
  static const _service = TextEditorAppearanceService();

  @override
  TextEditorAppearancePrefs build() {
    _init();
    return const TextEditorAppearancePrefs();
  }

  Future<void> _init() async {
    state = await _service.load();
  }

  void setBackground(EditorBackgroundOption option) {
    state = state.copyWith(background: option);
    _service.save(state);
  }

  void setSyntaxTheme(EditorSyntaxThemeOption option) {
    state = state.copyWith(syntaxTheme: option);
    _service.save(state);
  }

  void setRelativeLineNumbers(bool enabled) {
    state = state.copyWith(relativeLineNumbers: enabled);
    _service.save(state);
  }

  void setAutoSave(bool enabled) {
    state = state.copyWith(autoSave: enabled);
    _service.save(state);
  }

  void setShowLineNumbers(bool enabled) {
    state = state.copyWith(showLineNumbers: enabled);
    _service.save(state);
  }

  void setShowStatusBar(bool enabled) {
    state = state.copyWith(showStatusBar: enabled);
    _service.save(state);
  }

  void setShowTabBar(bool enabled) {
    state = state.copyWith(showTabBar: enabled);
    _service.save(state);
  }

  void setAutoHideTabBar(bool enabled) {
    state = state.copyWith(autoHideTabBar: enabled);
    _service.save(state);
  }

  void setShowAccessoryBar(bool enabled) {
    state = state.copyWith(showAccessoryBar: enabled);
    _service.save(state);
  }

  void setShowAccessorySymbols(bool enabled) {
    state = state.copyWith(showAccessorySymbols: enabled);
    _service.save(state);
  }

  void setShowAccessoryActions(bool enabled) {
    state = state.copyWith(showAccessoryActions: enabled);
    _service.save(state);
  }

  void setShowAccessoryScrubber(bool enabled) {
    state = state.copyWith(showAccessoryScrubber: enabled);
    _service.save(state);
  }

  void setFontSize(double size, {bool persist = true}) {
    if (state.fontSize != size) {
      state = state.copyWith(fontSize: size);
    }
    if (persist) _service.save(state);
  }

  void setAccessorySymbols(List<String> symbols) {
    state = state.copyWith(accessorySymbols: symbols);
    _service.save(state);
  }

  void setAccessoryActions(List<String> actions) {
    state = state.copyWith(accessoryActions: actions);
    _service.save(state);
  }

  void setCustomColor(
    String role,
    Color? color, {
    EditorBackgroundOption? background,
    EditorSyntaxThemeOption? syntaxTheme,
  }) {
    final next = Map<String, int>.from(state.customColors);
    if (color == null) {
      next.remove(role);
    } else {
      next[role] = color.toARGB32();
    }
    state = state.copyWith(
      background: background,
      syntaxTheme: syntaxTheme,
      customColors: next,
    );
    _service.save(state);
  }

  void resetCustomColors() {
    state = state.copyWith(customColors: const {});
    _service.save(state);
  }
}

final textEditorAppearanceProvider =
    NotifierProvider<TextEditorAppearanceNotifier, TextEditorAppearancePrefs>(
      TextEditorAppearanceNotifier.new,
    );
