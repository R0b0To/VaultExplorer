part of 'advanced_rename_screen.dart';

/// The "Search & Replace" card in the Advanced Rename form: find/replace
/// text fields (with an insert-variable menu on the replace field) and the
/// regex/match-case/match-all filter chips. Extracted from what was a
/// 300+ line `_buildFindReplaceCard` method on `_AdvancedRenameScreenState`
/// -- pure presentation reading [AdvancedRenameFormState] plus the two
/// controllers, no other coupling to the screen's state.
class _FindReplaceCard extends ConsumerWidget {
  const _FindReplaceCard({
    required this.cs,
    required this.textTheme,
    required this.searchController,
    required this.replaceController,
    required this.onInsertVariable,
  });

  final ColorScheme cs;
  final TextTheme textTheme;
  final TextEditingController searchController;
  final TextEditingController replaceController;
  final ValueChanged<String> onInsertVariable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(advancedRenameFormProvider);
    final l10n = context.l10n;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide.none,
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.find_replace_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.advancedRenameSearchReplaceTitle,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: l10n.advancedRenameFindTextLabel,
                hintText: l10n.advancedRenameFindTextHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.primary,
                    width: 1.5,
                  ),
                ),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => searchController.clear(),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: replaceController,
              decoration: InputDecoration(
                labelText: l10n.advancedRenameReplaceWithLabel,
                hintText: l10n.advancedRenameReplaceWithHint,
                prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.primary,
                    width: 1.5,
                  ),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: l10n.advancedRenameInsertVariableTooltip,
                      icon: Icon(
                        Icons.data_object_rounded,
                        size: 20,
                        color: cs.primary,
                      ),
                      onSelected: onInsertVariable,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          enabled: false,
                          child: Text(
                            l10n.advancedRenameDateTimeTokens,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'$YYYY-$MM-$DD',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.calendar_today_rounded,
                              size: 18,
                            ),
                            title: Text(
                              l10n.advancedRenameStandardDate(
                                r'$YYYY-$MM-$DD',
                              ),
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'$YYYY',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.date_range_rounded,
                              size: 18,
                            ),
                            title: Text(
                              l10n.advancedRenameYearFourDigit(r'$YYYY'),
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'$MM',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.calendar_view_month_rounded,
                              size: 18,
                            ),
                            title: Text(l10n.advancedRenameMonth(r'$MM')),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'$DD',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.today_rounded,
                              size: 18,
                            ),
                            title: Text(l10n.advancedRenameDayOfMonth(r'$DD')),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'$hh-$mm-$ss',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.access_time_rounded,
                              size: 18,
                            ),
                            title: Text(
                              l10n.advancedRenameTime(r'$hh-$mm-$ss'),
                            ),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          enabled: false,
                          child: Text(
                            l10n.advancedRenameDynamicIdentifiers,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'${ruuidv4}',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.fingerprint_rounded,
                              size: 18,
                            ),
                            title: Text(
                              l10n.advancedRenameUniqueUuid(r'${ruuidv4}'),
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'${rstringalnum=8}',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.password_rounded,
                              size: 18,
                            ),
                            title: Text(l10n.advancedRenameRandomAlphanumeric),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'${rstringdigit=6}',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.numbers_rounded,
                              size: 18,
                            ),
                            title: Text(l10n.advancedRenameRandomDigits),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          enabled: false,
                          child: Text(
                            l10n.advancedRenameEmbeddedCounter,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'${padding=3;start=1}',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.format_list_numbered_rounded,
                              size: 18,
                            ),
                            title: Text(
                              l10n.advancedRenamePaddedCounter(
                                r'${padding=3;start=1}',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (replaceController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => replaceController.clear(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: Text(
                    l10n.advancedRenameRegex,
                    style: const TextStyle(fontSize: 12),
                  ),
                  avatar: const Icon(Icons.code_rounded, size: 16),
                  selected: state.useRegex,
                  showCheckmark: false,
                  backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  selectedColor: cs.primaryContainer,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (v) => ref
                      .read(advancedRenameFormProvider.notifier)
                      .setUseRegex(v),
                ),
                FilterChip(
                  label: Text(
                    l10n.advancedRenameMatchCase,
                    style: const TextStyle(fontSize: 12),
                  ),
                  avatar: const Icon(Icons.format_size_rounded, size: 16),
                  selected: state.matchCase,
                  showCheckmark: false,
                  backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  selectedColor: cs.primaryContainer,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (v) => ref
                      .read(advancedRenameFormProvider.notifier)
                      .setMatchCase(v),
                ),
                FilterChip(
                  label: Text(
                    l10n.advancedRenameAllOccurrences,
                    style: const TextStyle(fontSize: 12),
                  ),
                  avatar: const Icon(Icons.select_all_rounded, size: 16),
                  selected: state.matchAll,
                  showCheckmark: false,
                  backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  selectedColor: cs.primaryContainer,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (v) => ref
                      .read(advancedRenameFormProvider.notifier)
                      .setMatchAll(v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Scope & Formatting" card: which parts of the filename the rename
/// applies to (name/extension/both) and the case-transformation dropdown.
/// Extracted from `_AdvancedRenameScreenState._buildScopeAndCaseCard` --
/// pure presentation reading [AdvancedRenameFormState], no other coupling
/// to the screen's state.
class _ScopeAndCaseCard extends ConsumerWidget {
  const _ScopeAndCaseCard({required this.cs, required this.textTheme});

  final ColorScheme cs;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(advancedRenameFormProvider);
    final l10n = context.l10n;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide.none,
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Header ---
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.advancedRenameScopeFormatting,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // --- Scope / Target Selection (Responsive Wrap) ---
            Text(
              l10n.advancedRenameApplyChangesTo,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  avatar: Icon(
                    Icons.insert_drive_file_outlined,
                    size: 16,
                    color: state.applyTarget == RenameApplyTarget.nameOnly
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                  label: Text(
                    l10n.advancedRenameFilename,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: state.applyTarget == RenameApplyTarget.nameOnly,
                  showCheckmark: false,
                  backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  selectedColor: cs.primaryContainer,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (_) => ref
                      .read(advancedRenameFormProvider.notifier)
                      .setApplyTarget(RenameApplyTarget.nameOnly),
                ),
                ChoiceChip(
                  avatar: Icon(
                    Icons.extension_outlined,
                    size: 16,
                    color: state.applyTarget == RenameApplyTarget.extensionOnly
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                  label: Text(
                    l10n.advancedRenameExtension,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: state.applyTarget == RenameApplyTarget.extensionOnly,
                  showCheckmark: false,
                  backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  selectedColor: cs.primaryContainer,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (_) => ref
                      .read(advancedRenameFormProvider.notifier)
                      .setApplyTarget(RenameApplyTarget.extensionOnly),
                ),
                ChoiceChip(
                  avatar: Icon(
                    Icons.all_inclusive_rounded,
                    size: 16,
                    color: state.applyTarget == RenameApplyTarget.nameAndExtension
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                  label: Text(
                    l10n.advancedRenameBoth,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: state.applyTarget == RenameApplyTarget.nameAndExtension,
                  showCheckmark: false,
                  backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  selectedColor: cs.primaryContainer,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: (_) => ref
                      .read(advancedRenameFormProvider.notifier)
                      .setApplyTarget(RenameApplyTarget.nameAndExtension),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // --- Case Transformation Selection ---
            Text(
              l10n.advancedRenameCaseTransformation,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<CaseTransformation>(
                  value: state.caseTransform,
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down_rounded, color: cs.onSurfaceVariant),
                  borderRadius: BorderRadius.circular(12),
                  dropdownColor: cs.surfaceContainer,
                  items: [
                    DropdownMenuItem(
                      value: CaseTransformation.none,
                      child: Row(
                        children: [
                          Icon(Icons.block_rounded, size: 18, color: cs.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Text(l10n.advancedRenameNoChange),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: CaseTransformation.lower,
                      child: Row(
                        children: [
                          Icon(Icons.text_fields_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: 10),
                          Text(l10n.advancedRenameLowercase),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: CaseTransformation.upper,
                      child: Row(
                        children: [
                          Icon(Icons.text_fields_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: 10),
                          Text(l10n.advancedRenameUppercase),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: CaseTransformation.title,
                      child: Row(
                        children: [
                          Icon(Icons.title_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: 10),
                          Text(l10n.advancedRenameTitleCase),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: CaseTransformation.capitalize,
                      child: Row(
                        children: [
                          Icon(Icons.text_format_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: 10),
                          Text(l10n.advancedRenameCapitalize),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(advancedRenameFormProvider.notifier)
                          .setCaseTransform(v);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Numbering" card: start number, zero-padding width, and separator
/// text fields for the `${padding=N;start=M}` counter token. Extracted
/// from `_AdvancedRenameScreenState._buildCounterCard` -- pure
/// presentation reading [AdvancedRenameFormState] plus the three
/// controllers, no other coupling to the screen's state.
class _CounterCard extends ConsumerWidget {
  const _CounterCard({
    required this.cs,
    required this.textTheme,
    required this.startNumberController,
    required this.paddingController,
    required this.separatorController,
  });

  final ColorScheme cs;
  final TextTheme textTheme;
  final TextEditingController startNumberController;
  final TextEditingController paddingController;
  final TextEditingController separatorController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(advancedRenameFormProvider);
    final l10n = context.l10n;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide.none,
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.format_list_numbered_rounded,
                  size: 18,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.advancedRenameSequentialCounter,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        l10n.advancedRenameCounterDescription,
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: state.enableCounter,
                  onChanged: (v) => ref
                      .read(advancedRenameFormProvider.notifier)
                      .setEnableCounter(v),
                ),
              ],
            ),
            if (state.enableCounter) ...[
              const SizedBox(height: 16),
              SegmentedButton<CounterPosition>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: CounterPosition.suffix,
                    label: Text(l10n.advancedRenameSuffix),
                    icon: const Icon(Icons.arrow_right_alt_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: CounterPosition.prefix,
                    label: Text(l10n.advancedRenamePrefix),
                    icon: const Icon(
                      Icons.keyboard_backspace_rounded,
                      size: 16,
                    ),
                  ),
                ],
                selected: {state.counterPosition},
                style: SegmentedButton.styleFrom(
                  side: BorderSide.none,
                  backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  selectedBackgroundColor: cs.primaryContainer,
                ),
                onSelectionChanged: (set) => ref
                    .read(advancedRenameFormProvider.notifier)
                    .setCounterPosition(set.first),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: startNumberController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.advancedRenameStartAt,
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: cs.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: paddingController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.advancedRenameDigits,
                        hintText: l10n.advancedRenameDigitsHint,
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: cs.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: separatorController,
                      decoration: InputDecoration(
                        labelText: l10n.advancedRenameSeparator,
                        hintText: l10n.advancedRenameSeparatorHint,
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: cs.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The preview list's header: "N of M changed" count plus a select-all/
/// deselect-all button. Extracted from
/// `_AdvancedRenameScreenState._buildPreviewHeader` -- pure presentation,
/// no state coupling beyond the entries list and selection notifier calls.
class _PreviewHeader extends ConsumerWidget {
  const _PreviewHeader({
    required this.cs,
    required this.textTheme,
    required this.allSelected,
    required this.changedCount,
    required this.oldEntries,
  });

  final ColorScheme cs;
  final TextTheme textTheme;
  final bool allSelected;
  final int changedCount;
  final List<RawEntry> oldEntries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(Icons.preview_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  l10n.advancedRenameLivePreview,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.advancedRenameChangedCount(
                    changedCount,
                    oldEntries.length,
                  ),
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          icon: Icon(
            allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
            size: 16,
          ),
          onPressed: () {
            if (allSelected) {
              ref.read(advancedRenameFormProvider.notifier).deselectAll();
            } else {
              ref
                  .read(advancedRenameFormProvider.notifier)
                  .selectAll(oldEntries);
            }
          },
          label: Text(
            allSelected
                ? l10n.advancedRenameDeselect
                : l10n.advancedRenameSelectAll,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// A single row in the rename preview list: checkbox, old name -> new
/// name, and an error/changed indicator. Extracted from
/// `_AdvancedRenameScreenState._buildCandidateTile` -- pure presentation
/// reading the passed-in [_AdvancedRenameCandidate] and
/// [AdvancedRenameFormState], plus a toggle-selection notifier call.
class _CandidateTile extends ConsumerWidget {
  const _CandidateTile({
    required this.c,
    required this.cs,
    required this.textTheme,
    required this.state,
  });

  final _AdvancedRenameCandidate c;
  final ColorScheme cs;
  final TextTheme textTheme;
  final AdvancedRenameFormState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChecked = state.selectedEntries.contains(c.entry);
    final hasError = !c.isValid && isChecked;
    final isChanged = c.hasChanged && isChecked;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () =>
          ref.read(advancedRenameFormProvider.notifier).toggleEntry(c.entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: isChecked,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              onChanged: (_) => ref
                  .read(advancedRenameFormProvider.notifier)
                  .toggleEntry(c.entry),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 10),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: c.entry.isDir
                      ? cs.secondaryContainer.withValues(alpha: 0.4)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  c.entry.isDir
                      ? Icons.folder_rounded
                      : iconForFile(c.originalName),
                  size: 18,
                  color: c.entry.isDir
                      ? cs.secondary
                      : colorForFile(c.originalName),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.originalName,
                    style: textTheme.bodyMedium?.copyWith(
                      color: isChanged
                          ? cs.onSurfaceVariant.withValues(alpha: 0.6)
                          : cs.onSurface,
                      decoration: isChanged ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isChanged) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.subdirectory_arrow_right_rounded,
                          size: 14,
                          color: hasError ? cs.error : cs.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            c.newName,
                            style: textTheme.bodyMedium?.copyWith(
                              color: hasError ? cs.error : cs.primary,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (hasError && c.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 12,
                              color: cs.error,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                c.errorMessage!,
                                style: textTheme.labelSmall?.copyWith(
                                  color: cs.error,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (isChanged && !hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: cs.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The scrollable preview list, with a compact fallback layout when the
/// viewport is squeezed (e.g. software keyboard in landscape). Extracted
/// from `_AdvancedRenameScreenState._buildPreviewList` -- pure
/// presentation composing [_PreviewHeader] and [_CandidateTile].
class _PreviewList extends StatelessWidget {
  const _PreviewList({
    required this.candidates,
    required this.cs,
    required this.textTheme,
    required this.state,
    required this.oldEntries,
  });

  final List<_AdvancedRenameCandidate> candidates;
  final ColorScheme cs;
  final TextTheme textTheme;
  final AdvancedRenameFormState state;
  final List<RawEntry> oldEntries;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final allSelected =
        state.selectedEntries.length == oldEntries.length;
    final changedCount = candidates
        .where((c) => state.selectedEntries.contains(c.entry) && c.hasChanged)
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 140) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              children: [
                _PreviewHeader(
                  cs: cs,
                  textTheme: textTheme,
                  allSelected: allSelected,
                  changedCount: changedCount,
                  oldEntries: oldEntries,
                ),
                const SizedBox(height: 8),
                if (candidates.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        l10n.advancedRenameNoFilesSelected,
                        style: textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  ...candidates.map(
                    (c) => _CandidateTile(c: c, cs: cs, textTheme: textTheme, state: state),
                  ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PreviewHeader(
              cs: cs,
              textTheme: textTheme,
              allSelected: allSelected,
              changedCount: changedCount,
              oldEntries: oldEntries,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: candidates.isEmpty
                    ? Center(
                        child: Text(
                          l10n.advancedRenameNoFilesSelected,
                          style: textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 8,
                        ),
                        itemCount: candidates.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, i) => _CandidateTile(
                          c: candidates[i],
                          cs: cs,
                          textTheme: textTheme,
                          state: state,
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The bottom action bar: progress indicator while executing, a status
/// summary, and Cancel/Apply buttons. Extracted from
/// `_AdvancedRenameScreenState._buildBottomBar` -- pure presentation; the
/// actual rename execution stays on the State (it's async and mutates
/// vault contents), reached here only via [onApply].
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.validRenameCount,
    required this.hasErrors,
    required this.cs,
    required this.textTheme,
    required this.state,
    required this.oldEntriesCount,
    required this.onApply,
  });

  final int validRenameCount;
  final bool hasErrors;
  final ColorScheme cs;
  final TextTheme textTheme;
  final AdvancedRenameFormState state;
  final int oldEntriesCount;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: cs.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.isExecuting) ...[
              LinearProgressIndicator(
                value: state.executionProgress,
                minHeight: 4,
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasErrors
                            ? l10n.advancedRenameNameConflictDetected
                            : l10n.advancedRenameReadyOfTotal(
                                validRenameCount,
                                oldEntriesCount,
                              ),
                        style: textTheme.bodySmall?.copyWith(
                          color: hasErrors ? cs.error : cs.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        hasErrors
                            ? l10n.advancedRenameCheckPreviewToFix
                            : (state.selectedEntries.isEmpty
                                ? l10n.advancedRenameNoFilesSelected
                                : l10n.advancedRenameReadyToRename),
                        style: textTheme.labelSmall?.copyWith(
                          color: hasErrors ? cs.error : cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: state.isExecuting
                      ? null
                      : () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: state.isExecuting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.done_all_rounded, size: 18),
                  label: Text(l10n.advancedRenameApply(validRenameCount)),
                  onPressed:
                      (state.isExecuting || validRenameCount == 0 || hasErrors)
                          ? null
                          : onApply,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}