// Settings screen for choosing TextEditorScreen's appearance, themes,
// typography, keyboard shortcuts, and auto-save behavior.
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/services/text_editor_appearance_service.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_appearance_provider.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_language.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_theme.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/core/theme/app_skin_tokens.dart';
import 'package:vaultexplorer/features/settings/widgets/skin_color_picker_sheet.dart';

Future<void> showEditorAppearanceSheet(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (context) => const EditorAppearanceScreen()),
  );
}

class EditorAppearanceScreen extends ConsumerStatefulWidget {
  const EditorAppearanceScreen({super.key});

  @override
  ConsumerState<EditorAppearanceScreen> createState() =>
      _EditorAppearanceScreenState();
}

class _EditorAppearanceScreenState
    extends ConsumerState<EditorAppearanceScreen> {
  late final CodeLineEditingController _previewCodeController =
      CodeLineEditingController.fromText(
        '// Live theme & font preview\n'
        'void main() {\n'
        '  const vault = "VaultExplorer";\n'
        '  final count = 42;\n'
        '  print("Ready: \$vault (\$count)");\n'
        '}',
      );

  @override
  void dispose() {
    _previewCodeController.dispose();
    super.dispose();
  }

  String _backgroundLabel(
    BuildContext context,
    EditorBackgroundOption option,
  ) => switch (option) {
    EditorBackgroundOption.matchSyntaxTheme =>
      context.l10n.textEditorBackgroundMatchTheme,
    EditorBackgroundOption.amoledBlack =>
      context.l10n.textEditorBackgroundAmoledBlack,
    EditorBackgroundOption.darkSlate =>
      context.l10n.textEditorBackgroundDarkSlate,
    EditorBackgroundOption.classicLight =>
      context.l10n.textEditorBackgroundClassicLight,
    EditorBackgroundOption.sepia => context.l10n.textEditorBackgroundSepia,
  };

  String _syntaxThemeLabel(
    BuildContext context,
    EditorSyntaxThemeOption option,
  ) => switch (option) {
    EditorSyntaxThemeOption.auto => context.l10n.textEditorSyntaxThemeAuto,
    EditorSyntaxThemeOption.oneDark =>
      context.l10n.textEditorSyntaxThemeOneDark,
    EditorSyntaxThemeOption.dracula =>
      context.l10n.textEditorSyntaxThemeDracula,
    EditorSyntaxThemeOption.githubLight =>
      context.l10n.textEditorSyntaxThemeGithubLight,
    EditorSyntaxThemeOption.monokai =>
      context.l10n.textEditorSyntaxThemeMonokai,
    EditorSyntaxThemeOption.nord => context.l10n.textEditorSyntaxThemeNord,
  };

  Widget _buildPreviewCard(
    BuildContext context,
    TextEditorAppearancePrefs prefs,
    ColorScheme cs,
    Brightness appBrightness,
  ) {
    final appSkinTokens = Theme.of(context).extension<AppSkinTokens>();
    final followsAppSkin = appSkinTokens?.editorFollowsAppSkin == true;
    final customColors = followsAppSkin
        ? null
        : prefs.customColors.isNotEmpty
            ? prefs.customColors.map((k, v) => MapEntry(k, Color(v)))
            : null;

    final syntaxStyle = applyAppSkinEditorTokens(
      resolveEditorSyntaxStyle(
        'preview.dart',
        appBrightness,
        cs,
        background: prefs.background,
        syntaxTheme: prefs.syntaxTheme,
        customColors: customColors,
      ),
      appSkinTokens,
    );

    // Resolve cursor / selection / gutter from custom overrides or defaults.
    final bgLuminance = syntaxStyle.backgroundColor.computeLuminance();
    final contrast =
        (cs.primary.computeLuminance() - bgLuminance).abs();
    final customCursor = followsAppSkin
        ? appSkinTokens!.editorCursor
        : prefs.customColor('cursor');
    final safeAccent = customCursor ??
        (contrast > 0.25
            ? cs.primary
            : (bgLuminance < 0.5 ? Colors.white : Colors.black));
    final customSelection = followsAppSkin
        ? appSkinTokens!.editorSelection
        : prefs.customColor('selection');
    final selectionColor =
        customSelection ?? safeAccent.withValues(alpha: 0.28);
    final customGutter = followsAppSkin
        ? appSkinTokens!.editorGutter
        : prefs.customColor('gutter');
    final gutterColor =
        customGutter ?? syntaxStyle.textColor.withValues(alpha: 0.45);

    return Container(
      height: 145,
      decoration: BoxDecoration(
        color: syntaxStyle.backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CodeEditor(
        key: ValueKey(
          'preview_${prefs.background.name}_${prefs.syntaxTheme.name}_${prefs.fontSize}_${prefs.showLineNumbers}_${prefs.relativeLineNumbers}_${appBrightness.name}_${prefs.customColors.hashCode}',
        ),
        controller: _previewCodeController,
        readOnly: true,
        showCursorWhenReadOnly: false,
        wordWrap: false,
        autofocus: false,
        chunkAnalyzer: const NonCodeChunkAnalyzer(),
        style: CodeEditorStyle(
          fontFamily: 'JetBrains Mono',
          fontFamilyFallback: const ['monospace'],
          fontSize: prefs.fontSize,
          fontHeight: 1.45,
          backgroundColor: syntaxStyle.backgroundColor,
          textColor: syntaxStyle.textColor,
          codeTheme: syntaxStyle.codeTheme,
          cursorColor: safeAccent,
          selectionColor: selectionColor,
        ),
        indicatorBuilder: prefs.showLineNumbers
            ? (context, editingController, chunkController, notifier) {
                return DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                  textStyle: TextStyle(
                    color: gutterColor,
                    fontFamily: 'JetBrains Mono',
                    fontFamilyFallback: const ['monospace'],
                    fontSize: prefs.fontSize,
                    height: 1.45,
                  ),
                  focusedTextStyle: TextStyle(
                    color: safeAccent,
                    fontFamily: 'JetBrains Mono',
                    fontFamilyFallback: const ['monospace'],
                    fontSize: prefs.fontSize,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                  customLineIndex2Text: prefs.relativeLineNumbers
                      ? (lineIndex) {
                          const simulatedCurrentLine = 1;
                          return lineIndex == simulatedCurrentLine
                              ? '${lineIndex + 1}'
                              : '${(lineIndex - simulatedCurrentLine).abs()}';
                        }
                      : null,
                );
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(textEditorAppearanceProvider);
    final appSkinSettings = ref.watch(appSkinSettingsProvider);
    final appSkinTokens = Theme.of(context).extension<AppSkinTokens>();
    final shownPrefs =
        appSkinSettings.editorFollowsAppSkin && appSkinTokens != null
        ? prefs.copyWith(
            background: EditorBackgroundOption.values.firstWhere(
              (option) => option.name == appSkinTokens.editorBackgroundOption,
              orElse: () => EditorBackgroundOption.matchSyntaxTheme,
            ),
            syntaxTheme: EditorSyntaxThemeOption.values.firstWhere(
              (option) => option.name == appSkinTokens.editorSyntaxThemeOption,
              orElse: () => EditorSyntaxThemeOption.auto,
            ),
          )
        : prefs;
    final notifier = ref.read(textEditorAppearanceProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appBrightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.textEditorThemeSheetTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: context.l10n.textEditorResetToDefault,
            onPressed: () {
              notifier.setBackground(EditorBackgroundOption.matchSyntaxTheme);
              notifier.setSyntaxTheme(EditorSyntaxThemeOption.auto);
              notifier.setFontSize(14.0);
              notifier.setShowLineNumbers(true);
              notifier.setRelativeLineNumbers(false);
              notifier.setShowStatusBar(true);
              notifier.setShowTabBar(true);
              notifier.setAutoHideTabBar(true);
              notifier.setShowAccessoryBar(true);
              notifier.setShowAccessorySymbols(true);
              notifier.setShowAccessoryActions(true);
              notifier.setShowAccessoryScrubber(false);
              notifier.setAccessorySymbols(
                TextEditorAppearancePrefs.defaultSymbols,
              );
              notifier.setAccessoryActions(
                TextEditorAppearancePrefs.defaultActions,
              );
              notifier.setAutoSave(false);
              notifier.resetCustomColors();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                const SectionHeader('Editor styling'),
                SectionCard(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      value: appSkinSettings.editorFollowsAppSkin,
                      onChanged: (value) => ref
                          .read(appSkinSettingsProvider.notifier)
                          .setEditorFollowsAppSkin(value),
                      title: Text(
                        'Follow app skin',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        appSkinSettings.editorFollowsAppSkin
                            ? 'The editor uses the selected skin’s color template.'
                            : 'Choose an independent editor background and syntax theme below.',
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      secondary: Icon(Icons.code_rounded, color: cs.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // ==========================================
                // 1. LIVE PREVIEW (Original style)
                // ==========================================
                SectionHeader(context.l10n.textEditorLivePreviewTitle),
                _buildPreviewCard(context, shownPrefs, cs, appBrightness),
                const SizedBox(height: 16),

                // ==========================================
                // 2. THEMES & COLORS (Single Card, no dividers between titles & pills)
                // ==========================================
                SectionHeader(context.l10n.textEditorBackgroundSectionTitle),
                SectionCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Background Subtitle
                          Text(
                            context.l10n.textEditorBackgroundSectionTitle,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Background Pills
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final option
                                  in EditorBackgroundOption.values)
                                _BackgroundChip(
                                  label: _backgroundLabel(context, option),
                                  color:
                                      option.overrideColor ??
                                      cs.surfaceContainerHighest,
                                  textColor: option.overrideColor != null
                                      ? option.fallbackTextColor
                                      : cs.onSurface,
                                  selected: shownPrefs.background == option,
                                  isAuto:
                                      option ==
                                      EditorBackgroundOption.matchSyntaxTheme,
                                  onTap: () {
                                    if (appSkinSettings.editorFollowsAppSkin) {
                                      unawaited(
                                        ref
                                            .read(
                                              appSkinSettingsProvider.notifier,
                                            )
                                            .setEditorFollowsAppSkin(false),
                                      );
                                    }
                                    notifier.setBackground(option);
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          // Syntax Theme Subtitle
                          Text(
                            context.l10n.textEditorSyntaxThemeSectionTitle,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Syntax Theme Pills
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final option
                                  in EditorSyntaxThemeOption.values)
                                _BackgroundChip(
                                  label: _syntaxThemeLabel(context, option),
                                  color:
                                      option
                                          .themeMap(appBrightness)['root']
                                          ?.backgroundColor ??
                                      cs.surfaceContainerHighest,
                                  textColor:
                                      option
                                          .themeMap(appBrightness)['root']
                                          ?.color ??
                                      cs.onSurface,
                                  selected: shownPrefs.syntaxTheme == option,
                                  isAuto:
                                      option == EditorSyntaxThemeOption.auto,
                                  onTap: () {
                                    if (appSkinSettings.editorFollowsAppSkin) {
                                      unawaited(
                                        ref
                                            .read(
                                              appSkinSettingsProvider.notifier,
                                            )
                                            .setEditorFollowsAppSkin(false),
                                      );
                                    }
                                    notifier.setSyntaxTheme(option);
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ==========================================
                // 3. APPEARANCE & INTERFACE (No divider between Font label & Slider)
                // ==========================================
                SectionHeader(context.l10n.sectionAppearanceInterface),
                SectionCard(
                  children: [
                    // Font Size and Slider unified without divider
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.format_size_rounded,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  context.l10n.textEditorFontSizeLabel(
                                    prefs.fontSize.round(),
                                  ),
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${prefs.fontSize.round()} pt',
                                  style: TextStyle(
                                    color: cs.onPrimaryContainer,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Slider(
                            value: prefs.fontSize,
                            min: 10,
                            max: 24,
                            divisions: 14,
                            label: '${prefs.fontSize.round()} pt',
                            onChanged: notifier.setFontSize,
                          ),
                        ],
                      ),
                    ),

                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      value: prefs.showTabBar,
                      onChanged: notifier.setShowTabBar,
                      title: Text(
                        context.l10n.textEditorShowTabBarLabel,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        context.l10n.textEditorShowTabBarDescription,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      secondary: Icon(Icons.tab_rounded, color: cs.primary),
                    ),
                    if (prefs.showTabBar)
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        value: prefs.autoHideTabBar,
                        onChanged: notifier.setAutoHideTabBar,
                        title: Text(
                          context.l10n.textEditorAutoHideTabBarLabel,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.textEditorAutoHideTabBarDescription,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        secondary: Icon(
                          Icons.unfold_less_rounded,
                          color: cs.primary,
                        ),
                      ),

                    // Show Line Numbers Switch
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      value: prefs.showLineNumbers,
                      onChanged: notifier.setShowLineNumbers,
                      title: Text(
                        context.l10n.textEditorShowLineNumbersLabel,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        context.l10n.textEditorShowLineNumbersDescription,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      secondary: Icon(
                        Icons.format_list_numbered_rounded,
                        color: cs.primary,
                      ),
                    ),

                    // Relative Line Numbers
                    if (prefs.showLineNumbers)
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        value: prefs.relativeLineNumbers,
                        onChanged: notifier.setRelativeLineNumbers,
                        title: Text(
                          context.l10n.textEditorRelativeLineNumbersLabel,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.textEditorRelativeLineNumbersDescription,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        secondary: Icon(
                          Icons.swap_vert_rounded,
                          color: cs.primary,
                        ),
                      ),

                    // Show Status Bar Switch
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      value: prefs.showStatusBar,
                      onChanged: notifier.setShowStatusBar,
                      title: Text(
                        context.l10n.textEditorShowStatusBarLabel,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        context.l10n.textEditorShowStatusBarDescription,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      secondary: Icon(Icons.dock_rounded, color: cs.primary),
                    ),

                    // Accessory Bar Master Switch
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      value: prefs.showAccessoryBar,
                      onChanged: notifier.setShowAccessoryBar,
                      title: Text(
                        context.l10n.textEditorShowAccessoryBarLabel,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        context.l10n.textEditorShowAccessoryBarDescription,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      secondary: Icon(
                        Icons.keyboard_outlined,
                        color: cs.primary,
                      ),
                    ),

                    if (prefs.showAccessoryBar) ...[
                      // Show Symbols Row Switch
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        value: prefs.showAccessorySymbols,
                        onChanged: notifier.setShowAccessorySymbols,
                        title: Text(
                          context.l10n.textEditorShowSymbolsBarLabel,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.textEditorShowSymbolsBarDescription,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        secondary: Icon(Icons.tag_rounded, color: cs.primary),
                      ),

                      // Customize Symbols Tile
                      if (prefs.showAccessorySymbols)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          leading: Icon(
                            Icons.edit_note_rounded,
                            color: cs.primary,
                          ),
                          title: Text(
                            context.l10n.textEditorCustomizeKeyBarLabel,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            context.l10n.textEditorCustomizeKeyBarDescription,
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _showCustomizeKeyBarDialog(context),
                        ),

                      // Show Actions Row Switch
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        value: prefs.showAccessoryActions,
                        onChanged: notifier.setShowAccessoryActions,
                        title: Text(
                          context.l10n.textEditorShowActionsBarLabel,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.textEditorShowActionsBarDescription,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        secondary: Icon(
                          Icons.smart_button_rounded,
                          color: cs.primary,
                        ),
                      ),

                      // Customize & Reorder Actions Tile
                      if (prefs.showAccessoryActions)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          leading: Icon(Icons.tune_rounded, color: cs.primary),
                          title: Text(
                            context.l10n.textEditorCustomizeActionsLabel,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            context.l10n.textEditorCustomizeActionsDescription,
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _showCustomizeActionsDialog(context),
                        ),

                      // Show Scrubber Switch
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        value: prefs.showAccessoryScrubber,
                        onChanged: notifier.setShowAccessoryScrubber,
                        title: Text(
                          context.l10n.textEditorShowCaretScrubberLabel,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.textEditorShowCaretScrubberDescription,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        secondary: Icon(
                          Icons.linear_scale_rounded,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // ==========================================
                // 4. VAULT & FILE HANDLING
                // ==========================================
                SectionHeader(context.l10n.sectionVaultFileHandling),
                SectionCard(
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      value: prefs.autoSave,
                      onChanged: notifier.setAutoSave,
                      title: Text(
                        context.l10n.textEditorAutoSaveLabel,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        context.l10n.textEditorAutoSaveDescription,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      secondary: Icon(
                        Icons.save_as_outlined,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCustomizeActionsDialog(BuildContext context) {
    final prefs = ref.read(textEditorAppearanceProvider);
    final notifier = ref.read(textEditorAppearanceProvider.notifier);

    showDialog(
      context: context,
      builder: (ctx) => _CustomizeActionsDialog(
        currentActions: prefs.accessoryActions,
        onSave: notifier.setAccessoryActions,
      ),
    );
  }

  void _showCustomizeKeyBarDialog(BuildContext context) {
    final prefs = ref.read(textEditorAppearanceProvider);
    final notifier = ref.read(textEditorAppearanceProvider.notifier);
    final controller = TextEditingController(
      text: prefs.accessorySymbols.join(' '),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.textEditorCustomizeKeyBarTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: ctx.l10n.textEditorCustomizeKeyBarHint,
                helperText: ctx.l10n.textEditorCustomizeKeyBarDescription,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                controller.text = TextEditorAppearancePrefs.defaultSymbols.join(
                  ' ',
                );
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(ctx.l10n.textEditorResetToDefault),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final symbols = controller.text
                  .trim()
                  .split(RegExp(r'\s+'))
                  .where((s) => s.isNotEmpty)
                  .toList();
              if (symbols.isNotEmpty) {
                notifier.setAccessorySymbols(symbols);
              }
              Navigator.of(ctx).pop();
            },
            child: Text(ctx.l10n.done),
          ),
        ],
      ),
    );
  }
}

class _CustomizeActionsDialog extends StatefulWidget {
  final List<String> currentActions;
  final ValueChanged<List<String>> onSave;

  const _CustomizeActionsDialog({
    required this.currentActions,
    required this.onSave,
  });

  @override
  State<_CustomizeActionsDialog> createState() =>
      _CustomizeActionsDialogState();
}

class _CustomizeActionsDialogState extends State<_CustomizeActionsDialog> {
  late List<String> _order;
  late Set<String> _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = Set<String>.from(widget.currentActions);
    final rest = TextEditorAppearancePrefs.allAvailableActions.where(
      (a) => !_enabled.contains(a),
    );
    _order = [...widget.currentActions, ...rest];
  }

  (IconData, String) _actionInfo(BuildContext context, String key) {
    return switch (key) {
      'undo' => (Icons.undo_rounded, context.l10n.actionUndo),
      'redo' => (Icons.redo_rounded, context.l10n.actionRedo),
      'cursorLeft' => (
        Icons.keyboard_arrow_left_rounded,
        context.l10n.actionCursorLeft,
      ),
      'cursorRight' => (
        Icons.keyboard_arrow_right_rounded,
        context.l10n.actionCursorRight,
      ),
      'selectWord' => (
        Icons.highlight_alt_rounded,
        context.l10n.actionSelectWord,
      ),
      'selectAll' => (Icons.select_all_rounded, context.l10n.actionSelectAll),
      'copy' => (Icons.content_copy_rounded, context.l10n.actionCopy),
      'cut' => (Icons.content_cut_rounded, context.l10n.actionCut),
      'paste' => (Icons.content_paste_rounded, context.l10n.actionPaste),
      'find' => (Icons.search_rounded, context.l10n.actionFind),
      'wordWrap' => (Icons.wrap_text_rounded, context.l10n.actionWordWrap),
      'goToLine' => (
        Icons.format_list_numbered_rounded,
        context.l10n.actionGoToLine,
      ),
      'goToStart' => (
        Icons.vertical_align_top_rounded,
        context.l10n.actionGoToStart,
      ),
      'goToEnd' => (
        Icons.vertical_align_bottom_rounded,
        context.l10n.actionGoToEnd,
      ),
      'indent' => (
        Icons.format_indent_increase_rounded,
        context.l10n.actionIndent,
      ),
      'outdent' => (
        Icons.format_indent_decrease_rounded,
        context.l10n.actionOutdent,
      ),
      'format' => (Icons.auto_fix_high_rounded, context.l10n.actionFormat),
      'readOnly' => (Icons.lock_outline_rounded, context.l10n.actionReadOnly),
      _ => (Icons.code_rounded, key),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(context.l10n.textEditorCustomizeActionsTitle),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: ReorderableListView.builder(
          shrinkWrap: true,
          itemCount: _order.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = _order.removeAt(oldIndex);
              _order.insert(newIndex, item);
            });
          },
          itemBuilder: (context, index) {
            final key = _order[index];
            final isChecked = _enabled.contains(key);
            final (icon, label) = _actionInfo(context, key);

            return ListTile(
              key: ValueKey(key),
              leading: Icon(icon, color: isChecked ? cs.primary : cs.outline),
              title: Text(
                label,
                style: TextStyle(
                  fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                  color: isChecked ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: isChecked,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _enabled.add(key);
                        } else {
                          _enabled.remove(key);
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle_rounded),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _enabled = Set<String>.from(
                TextEditorAppearancePrefs.defaultActions,
              );
              final rest = TextEditorAppearancePrefs.allAvailableActions.where(
                (a) => !_enabled.contains(a),
              );
              _order = [...TextEditorAppearancePrefs.defaultActions, ...rest];
            });
          },
          child: Text(context.l10n.textEditorResetToDefault),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final finalActions = _order
                .where((a) => _enabled.contains(a))
                .toList();
            widget.onSave(finalActions);
            Navigator.of(context).pop();
          },
          child: Text(context.l10n.done),
        ),
      ],
    );
  }
}

class _BackgroundChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final bool selected;
  final bool isAuto;
  final VoidCallback onTap;

  const _BackgroundChip({
    required this.label,
    required this.color,
    required this.textColor,
    required this.selected,
    required this.onTap,
    this.isAuto = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = selected
        ? cs.primary
        : cs.outlineVariant.withValues(alpha: 0.35);

    return Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor, width: selected ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAuto) ...[
                Icon(Icons.auto_awesome_rounded, size: 14, color: textColor),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 12,
                    color: cs.onPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
