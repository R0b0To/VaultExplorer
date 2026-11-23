import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/layout/section_card.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/composite/presentation/composite_create_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/container_repair_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/container_splitter_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/duplicate_finder_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/hash_verifier_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/header_backup_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/keyfile_passphrase_generator_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/password_interchange/password_interchange_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/single_file_crypto_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/veracrypt_volume_tools_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_screen.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';

class ToolsScreen extends StatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;
  final ValueListenable<MountedContainer?>? localStorageContainer;
  final ValueChanged<int>? onNavigateTab;

  /// Opens a vault in the file browser. Lets tools such as the Storage
  /// Analyzer offer "show in file browser"; tools hide that action when this
  /// is null (e.g. when ToolsScreen is pushed from the drawer).
  final ValueChanged<MountedContainer>? onOpenInBrowser;

  const ToolsScreen({
    super.key,
    required this.mountedContainers,
    this.localStorageContainer,
    this.onNavigateTab,
    this.onOpenInBrowser,
  });

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  /// Side padding of the desktop grid; matches the Dashboard's card grid.
  static const double _kGridPadding = 24;
  static const double _kGridGap = 12;
  static const double _kMinTileWidth = 320;
  static const int _kMaxColumns = 3;

  /// Widest the grid grows before it stops adding width (it stays
  /// left-aligned under the title rather than floating in the centre).
  static const double _kMaxContentWidth = 1480;

  /// Widest the single-column (phone / narrow window) list grows.
  static const double _kStackedMaxWidth = 720;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    // In the docked layout Tools is a page in the content area beside the
    // sidebar, not a pushed route, so there is nothing to go back out of.
    final docked = DockedSidebarScope.of(context);
    final wide = context.screen.useWideLayout;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: docked
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Text(
          context.l10n.toolsScreenTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        // Same compact top-right search box as Dashboard / File Manager /
        // Settings. Narrow windows put it above the list instead.
        actions: wide
            ? [
                Center(
                  child: SizedBox(
                    width: 300,
                    child: _buildSearchField(context),
                  ),
                ),
                const SizedBox(width: 16),
              ]
            : null,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = math.min(
              constraints.maxWidth - _kGridPadding * 2,
              _kMaxContentWidth,
            );
            final columns = ScreenInfo.cardColumnsFor(
              contentWidth,
              minTileWidth: _kMinTileWidth,
              maxColumns: _kMaxColumns,
            );
            final multiColumn = columns >= 2;
            final sections = _sections(context, gridOrder: multiColumn);

            if (sections.isEmpty) {
              return Column(
                children: [
                  if (!wide) _buildBodySearch(context),
                  Expanded(
                    child: Center(
                      child: Text(
                        context.l10n.noResultsTitle,
                        style: context.typography.bodyLarge?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return multiColumn
                ? _buildGridBody(context, sections, columns, contentWidth)
                : _buildStackedBody(context, sections, showSearch: !wide);
          },
        ),
      ),
    );
  }

  // ── SEARCH ─────────────────────────────────────────────────────────────────

  Widget _buildBodySearch(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: _buildSearchField(context),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final cs = context.colors;
    final radius = BorderRadius.circular(28);
    const noBorder = BorderSide.none;

    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      textInputAction: TextInputAction.search,
      onChanged: _onQueryChanged,
      decoration: InputDecoration(
        isDense: true,
        hintText: context.l10n.toolsSearchHint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchController,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: context.l10n.settingsSearchClear,
              onPressed: () {
                _searchController.clear();
                _onQueryChanged('');
                _searchFocus.requestFocus();
              },
            );
          },
        ),
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        border: OutlineInputBorder(borderRadius: radius, borderSide: noBorder),
        enabledBorder:
            OutlineInputBorder(borderRadius: radius, borderSide: noBorder),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: cs.primary, width: 1.5),
        ),
      ),
    );
  }

  // ── SECTIONS ───────────────────────────────────────────────────────────────

  /// The tool sections, filtered by the search query. [gridOrder] lists the
  /// big sections first so the small ones pack into one shared row of the
  /// desktop grid; the single column keeps the original order.
  List<_ToolSection> _sections(
    BuildContext context, {
    required bool gridOrder,
  }) {
    final l10n = context.l10n;
    final cs = context.colors;

    final crypto = _ToolSection(l10n.toolsSectionFileCryptography, [
      _buildKeyfileGeneratorRow(context, cs),
      _buildSingleFileCryptoRow(context, cs),
      _buildHashVerifierRow(context, cs),
    ]);
    final backup = _ToolSection(l10n.toolsSectionBackupSync, [
      _buildVaultSyncRow(context, cs),
    ]);
    final password = _ToolSection(l10n.toolsSectionPasswordManager, [
      _buildPasswordInterchangeRow(context, cs),
    ]);
    final storage = _ToolSection(l10n.toolsSectionStorageDiagnostics, [
      _buildStorageAnalyzerRow(context, cs),
      _buildDuplicateFinderRow(context, cs),
    ]);
    final container = _ToolSection(l10n.toolsSectionContainerUtilities, [
      _buildContainerSplitterRow(context, cs),
      _buildCompositeContainerRow(context, cs),
      _buildContainerRepairRow(context, cs),
      _buildHeaderBackupRow(context, cs),
      _buildExpandVolumeRow(context, cs),
      _buildHiddenInExistingRow(context, cs),
    ]);

    final all = gridOrder
        ? [crypto, container, storage, backup, password]
        : [crypto, backup, password, storage, container];

    if (_query.isEmpty) return all;
    return [
      for (final section in all)
        if (section.matching(_query).isNotEmpty)
          _ToolSection(section.title, section.matching(_query)),
    ];
  }

  // ── SINGLE-COLUMN BODY (PHONES / NARROW WINDOWS) ──────────────────────────

  Widget _buildStackedBody(
    BuildContext context,
    List<_ToolSection> sections, {
    required bool showSearch,
  }) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kStackedMaxWidth),
        child: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            if (showSearch)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _buildSearchField(context),
              ),
            for (final section in sections) ...[
              SectionHeader(section.title),
              SectionCard(children: section.rows),
              const SizedBox(height: AppSpacing.lg),
            ],
          ],
        ),
      ),
    );
  }

  // ── DESKTOP BODY (FULL-WIDTH, LEFT-ALIGNED RESPONSIVE GRID) ───────────────

  Widget _buildGridBody(
    BuildContext context,
    List<_ToolSection> sections,
    int columns,
    double contentWidth,
  ) {
    final cellWidth =
        (contentWidth - _kGridGap * (columns - 1)) / columns;
    double spanWidth(int span) => cellWidth * span + _kGridGap * (span - 1);

    // A section with one or two tools is a compact stack that takes a single
    // column; a bigger one spreads across up to every column. Consecutive
    // sections share a row while their columns add up to the grid width.
    final bands = <List<({_ToolSection section, int span})>>[];
    var band = <({_ToolSection section, int span})>[];
    var used = 0;
    for (final section in sections) {
      final span =
          section.rows.length <= 2 ? 1 : math.min(columns, section.rows.length);
      if (used + span > columns && band.isNotEmpty) {
        bands.add(band);
        band = [];
        used = 0;
      }
      band.add((section: section, span: span));
      used += span;
    }
    if (band.isNotEmpty) bands.add(band);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        _kGridPadding,
        8,
        _kGridPadding,
        32,
      ),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: contentWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final b in bands) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < b.length; i++) ...[
                      if (i > 0) const SizedBox(width: _kGridGap),
                      SizedBox(
                        width: spanWidth(b[i].span),
                        child: _buildSectionBlock(
                          context,
                          b[i].section,
                          b[i].span,
                          cellWidth,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionBlock(
    BuildContext context,
    _ToolSection section,
    int span,
    double cellWidth,
  ) {
    final rows = section.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(section.title),
        if (span == 1)
          // One or two tools in a single column: the segmented card.
          SectionCard(
            children: [for (final r in rows) r.copyWith(compact: true)],
          )
        else
          for (var start = 0; start < rows.length; start += span) ...[
            if (start > 0) const SizedBox(height: _kGridGap),
            // IntrinsicHeight keeps every card in a line equally tall, even
            // when one subtitle wraps to two lines and its neighbour doesn't.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = start;
                      i < math.min(start + span, rows.length);
                      i++) ...[
                    if (i > start) const SizedBox(width: _kGridGap),
                    SizedBox(
                      width: cellWidth,
                      child: _ToolCard(row: rows[i].copyWith(compact: true)),
                    ),
                  ],
                ],
              ),
            ),
          ],
      ],
    );
  }

  // ── TOOL BUILDERS ──────────────────────────────────────────────────────────

  _ToolRow _buildKeyfileGeneratorRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.key_rounded,
      title: context.l10n.keyfilePassphraseGeneratorTitle,
      subtitle: context.l10n.keyfilePassphraseGeneratorSubtitle,
      iconColor: cs.primary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(area: SkinArea.tools, child: KeyfilePassphraseGeneratorScreen(
            mountedContainers: widget.mountedContainers,
          )),
        ),
      ),
    );
  }

  _ToolRow _buildSingleFileCryptoRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.enhanced_encryption_rounded,
      title: context.l10n.toolSingleFileCryptoTitle,
      subtitle: context.l10n.toolSingleFileCryptoSubtitle,
      iconColor: cs.secondary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(area: SkinArea.tools, child: SingleFileCryptoSheet(
            mountedContainers: widget.mountedContainers,
          )),
        ),
      ),
    );
  }

  _ToolRow _buildHashVerifierRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.verified_rounded,
      title: context.l10n.toolHashVerifierTitle,
      subtitle: context.l10n.toolHashVerifierSubtitle,
      iconColor: cs.secondary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(area: SkinArea.tools, child: HashVerifierSheet(
            mountedContainers: widget.mountedContainers,
          )),
        ),
      ),
    );
  }

  _ToolRow _buildVaultSyncRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.sync_alt_rounded,
      title: context.l10n.toolVaultSyncTitle,
      subtitle: context.l10n.toolVaultSyncSubtitle,
      iconColor: cs.tertiary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(area: SkinArea.tools, child: VaultSyncScreen(
            mountedContainers: widget.mountedContainers,
          )),
        ),
      ),
    );
  }

  _ToolRow _buildPasswordInterchangeRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.import_export_rounded,
      title: context.l10n.toolPasswordInterchangeTitle,
      subtitle: context.l10n.toolPasswordInterchangeSubtitle,
      iconColor: cs.tertiary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(area: SkinArea.tools, child: PasswordInterchangeScreen(
            mountedContainers: widget.mountedContainers,
          )),
        ),
      ),
    );
  }

  _ToolRow _buildStorageAnalyzerRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.pie_chart_rounded,
      title: context.l10n.toolStorageAnalyzerTitle,
      subtitle: context.l10n.toolStorageAnalyzerSubtitle,
      iconColor: cs.tertiary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(area: SkinArea.tools, child: StorageAnalyzerScreen(
            mountedContainers: widget.mountedContainers,
            localStorageContainer: widget.localStorageContainer,
            onOpenInBrowser: widget.onOpenInBrowser,
          )),
        ),
      ),
    );
  }

  _ToolRow _buildDuplicateFinderRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.difference_rounded,
      title: context.l10n.toolDuplicateFinderTitle,
      subtitle: context.l10n.toolDuplicateFinderSubtitle,
      iconColor: cs.primary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(area: SkinArea.tools, child: DuplicateFinderScreen(
            mountedContainers: widget.mountedContainers,
          )),
        ),
      ),
    );
  }

  _ToolRow _buildContainerSplitterRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.content_cut_rounded,
      title: context.l10n.toolContainerSplitterTitle,
      subtitle: context.l10n.toolContainerSplitterSubtitle,
      iconColor: cs.primary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(area: SkinArea.tools, child: const ContainerSplitterSheet()),
        ),
      ),
    );
  }

  _ToolRow _buildCompositeContainerRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.layers_rounded,
      title: context.l10n.toolCompositeContainerTitle,
      subtitle: context.l10n.toolCompositeContainerSubtitle,
      badgeText: context.l10n.badgeExperimental,
      iconColor: cs.primary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(area: SkinArea.tools, child: CompositeCreateSheet(
            onCreated: () => widget.onNavigateTab?.call(0),
          )),
        ),
      ),
    );
  }

  _ToolRow _buildContainerRepairRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.build_rounded,
      title: context.l10n.toolContainerRepairTitle,
      subtitle: context.l10n.toolContainerRepairSubtitle,
      iconColor: cs.tertiary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(area: SkinArea.tools, child: ContainerRepairSheet(
            mountedContainers: widget.mountedContainers,
          )),
        ),
      ),
    );
  }

  _ToolRow _buildExpandVolumeRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.unfold_more_rounded,
      title: context.l10n.vcToolsExpandAction,
      subtitle: context.l10n.toolExpandVolumeSubtitle,
      iconColor: cs.secondary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(
            area: SkinArea.tools,
            child: const VeraCryptVolumeToolsScreen(tool: VeraCryptVolumeTool.expand),
          ),
        ),
      ),
    );
  }

  _ToolRow _buildHiddenInExistingRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.visibility_off_rounded,
      title: context.l10n.toolHiddenInExistingTitle,
      subtitle: context.l10n.toolHiddenInExistingSubtitle,
      iconColor: cs.secondary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(
            area: SkinArea.tools,
            child: const VeraCryptVolumeToolsScreen(tool: VeraCryptVolumeTool.addHidden),
          ),
        ),
      ),
    );
  }

  _ToolRow _buildHeaderBackupRow(BuildContext context, ColorScheme cs) {
    return _ToolRow(
      icon: Icons.settings_backup_restore_rounded,
      title: context.l10n.toolHeaderBackupTitle,
      subtitle: context.l10n.toolHeaderBackupSubtitle,
      iconColor: cs.secondary,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(area: SkinArea.tools, child: const HeaderBackupSheet()),
        ),
      ),
    );
  }
}

// ── DATA ─────────────────────────────────────────────────────────────────────

class _ToolSection {
  final String title;
  final List<_ToolRow> rows;
  const _ToolSection(this.title, this.rows);

  /// The rows that match [query] (already lower-cased): by tool title, by
  /// subtitle, or all of them when the section's own title matches.
  List<_ToolRow> matching(String query) {
    if (title.toLowerCase().contains(query)) return rows;
    return [
      for (final r in rows)
        if (r.title.toLowerCase().contains(query) ||
            r.subtitle.toLowerCase().contains(query))
          r,
    ];
  }
}

/// A single tool as its own rounded card in the desktop grid.
class _ToolCard extends StatelessWidget {
  final _ToolRow row;
  const _ToolCard({required this.row});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: ListTileTheme(
        tileColor: Colors.transparent,
        child: row,
      ),
    );
  }
}

// ── REUSABLE TOOL ROW WITH REFINED M3 AFFORDANCE ─────────────────────────────

class _ToolRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final String? badgeText;

  /// Tighter vertical padding for the desktop grid.
  final bool compact;

  const _ToolRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.badgeText,
    this.compact = false,
  });

  _ToolRow copyWith({bool? compact}) => _ToolRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        iconColor: iconColor,
        badgeText: badgeText,
        compact: compact ?? this.compact,
      );

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final accent = iconColor ?? cs.primary;

    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 2 : 4,
      ),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: accent),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (badgeText != null) ...[
            const SizedBox(width: 8),
            _ExperimentalBadge(text: badgeText!),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.25,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
      ),
      onTap: onTap,
    );
  }
}

/// Small, muted amber pill: readable, but quieter than the old magenta chip so
/// it doesn't outshout the slate/indigo palette of the rest of the row.
class _ExperimentalBadge extends StatelessWidget {
  final String text;
  const _ExperimentalBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const amber = Color(0xFFD08A00);
    final foreground = dark ? const Color(0xFFFFCB6B) : const Color(0xFF7A4B00);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: dark ? 0.16 : 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: amber.withValues(alpha: 0.45), width: 1),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: context.typography.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.3,
          color: foreground,
        ),
      ),
    );
  }
}
