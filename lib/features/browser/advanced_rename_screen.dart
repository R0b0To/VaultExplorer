import 'dart:math';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/entry_conflict.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/advanced_rename_controller.dart';

part 'advanced_rename_cards.dart';

class _AdvancedRenameCandidate {
  final RawEntry entry;
  final String originalName;
  final String newName;
  final bool isValid;
  final bool hasChanged;
  final String? errorMessage;

  const _AdvancedRenameCandidate({
    required this.entry,
    required this.originalName,
    required this.newName,
    required this.isValid,
    required this.hasChanged,
    this.errorMessage,
  });
}

class AdvancedRenameScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final List<RawEntry> oldEntries;
  final List<RawEntry> existingEntries;
  final String currentDirPath;
  final VoidCallback onSuccess;
  final void Function(String oldPath, String newPath)? onEntryRenamed;

  const AdvancedRenameScreen({
    super.key,
    required this.container,
    required this.oldEntries,
    required this.existingEntries,
    required this.currentDirPath,
    required this.onSuccess,
    this.onEntryRenamed,
  });

  @override
  ConsumerState<AdvancedRenameScreen> createState() =>
      _AdvancedRenameScreenState();
}

class _AdvancedRenameScreenState extends ConsumerState<AdvancedRenameScreen> {
  final _searchCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  final _startNumCtrl = TextEditingController(text: '1');
  final _paddingCtrl = TextEditingController(text: '2');
  final _separatorCtrl = TextEditingController(text: '_');

  late final FilesystemType _fsType;

  @override
  void initState() {
    super.initState();
    _fsType = resolveFilesystemType(widget.container);
    
    Future.microtask(() {
      if (mounted) {
        ref.read(advancedRenameFormProvider.notifier).initialize(widget.oldEntries);
      }
    });

    _searchCtrl.addListener(_onParamChanged);
    _replaceCtrl.addListener(_onParamChanged);
    _startNumCtrl.addListener(_onParamChanged);
    _paddingCtrl.addListener(_onParamChanged);
    _separatorCtrl.addListener(_onParamChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _replaceCtrl.dispose();
    _startNumCtrl.dispose();
    _paddingCtrl.dispose();
    _separatorCtrl.dispose();
    super.dispose();
  }

  void _onParamChanged() {
    if (mounted) setState(() {});
  }

  void _insertVariable(String token) {
    final text = _replaceCtrl.text;
    final sel = _replaceCtrl.selection;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    final newText = text.replaceRange(start, end, token);
    _replaceCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  DateTime _getEntryDateTime(RawEntry entry) {
    try {
      final dynamic d = entry;
      if (d.modified is DateTime) return d.modified as DateTime;
      if (d.mtime is DateTime) return d.mtime as DateTime;
      if (d.date is DateTime) return d.date as DateTime;
      if (d.updatedAt is DateTime) return d.updatedAt as DateTime;
      if (d.createdAt is DateTime) return d.createdAt as DateTime;
      if (d.modified is int) {
        return DateTime.fromMillisecondsSinceEpoch(d.modified as int);
      }
      if (d.mtime is int) {
        return DateTime.fromMillisecondsSinceEpoch(d.mtime as int);
      }
    } catch (_) {
      // Probing several dynamic field names for whichever timestamp this
      // entry type actually has; accessing a field it doesn't have throws
      // NoSuchMethodError, which falls through to DateTime.now() below.
    }
    return DateTime.now();
  }

  String _formatDateToken(DateTime dt, String token, AppLocalizations l10n) {
    final monthsFull = l10n.advancedRenameMonthsFull.split('|');
    final monthsAbbr = l10n.advancedRenameMonthsAbbr.split('|');
    final daysFull = l10n.advancedRenameDaysFull.split('|');
    final daysAbbr = l10n.advancedRenameDaysAbbr.split('|');

    switch (token) {
      case r'$YYYY':
        return dt.year.toString().padLeft(4, '0');
      case r'$YY':
        return (dt.year % 100).toString().padLeft(2, '0');
      case r'$Y':
        return (dt.year % 10).toString();
      case r'$MMMM':
        return monthsFull[dt.month - 1];
      case r'$MMM':
        return monthsAbbr[dt.month - 1];
      case r'$MM':
        return dt.month.toString().padLeft(2, '0');
      case r'$M':
        return dt.month.toString();
      case r'$DDDD':
        return daysFull[dt.weekday - 1];
      case r'$DDD':
        return daysAbbr[dt.weekday - 1];
      case r'$DD':
        return dt.day.toString().padLeft(2, '0');
      case r'$D':
        return dt.day.toString();
      case r'$hh':
        return dt.hour.toString().padLeft(2, '0');
      case r'$h':
        return dt.hour.toString();
      case r'$mm':
        return dt.minute.toString().padLeft(2, '0');
      case r'$m':
        return dt.minute.toString();
      case r'$ss':
        return dt.second.toString().padLeft(2, '0');
      case r'$s':
        return dt.second.toString();
      case r'$fff':
        return dt.millisecond.toString().padLeft(3, '0');
      default:
        return token;
    }
  }

  String _generateUuidV4(Random rnd) {
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _generateRandomString(
    Random rnd,
    int length, {
    bool alpha = true,
    bool digit = true,
  }) {
    const alphaChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const digitChars = '0123456789';
    String pool = '';
    if (alpha && digit) {
      pool = '$alphaChars$digitChars';
    } else if (alpha) {
      pool = alphaChars;
    } else if (digit) {
      pool = digitChars;
    }
    if (pool.isEmpty) pool = alphaChars;
    return List.generate(length, (_) => pool[rnd.nextInt(pool.length)]).join();
  }

  String _evaluateReplaceTemplate({
    required AppLocalizations l10n,
    required String template,
    required RawEntry entry,
    required int fileIndex,
    required Random random,
    Match? regexMatch,
  }) {
    if (template.isEmpty) return '';

    String result = template;

    if (regexMatch != null) {
      result = result.replaceAllMapped(RegExp(r'\$(\d+)'), (m) {
        final groupIdx = int.tryParse(m.group(1) ?? '') ?? 0;
        if (groupIdx > 0 && groupIdx <= regexMatch.groupCount) {
          return regexMatch.group(groupIdx) ?? '';
        }
        return m.group(0)!;
      });
    }

    final dt = _getEntryDateTime(entry);
    const dateTokens = [
      r'$YYYY',
      r'$YY',
      r'$Y',
      r'$MMMM',
      r'$MMM',
      r'$MM',
      r'$M',
      r'$DDDD',
      r'$DDD',
      r'$DD',
      r'$D',
      r'$hh',
      r'$h',
      r'$mm',
      r'$m',
      r'$ss',
      r'$s',
      r'$fff',
      r'${YYYY}',
      r'${YY}',
      r'${Y}',
      r'${MMMM}',
      r'${MMM}',
      r'${MM}',
      r'${M}',
      r'${DDDD}',
      r'${DDD}',
      r'${DD}',
      r'${D}',
      r'${hh}',
      r'${h}',
      r'${mm}',
      r'${m}',
      r'${ss}',
      r'${s}',
      r'${fff}',
    ];

    for (final token in dateTokens) {
      if (result.contains(token)) {
        final cleanToken = token.startsWith(r'${')
            ? '\$${token.substring(2, token.length - 1)}'
            : token;
        final formatted = _formatDateToken(dt, cleanToken, l10n);
        result = result.replaceAll(token, formatted);
      }
    }

    result = result.replaceAllMapped(RegExp(r'\$\{([^}]+)\}'), (match) {
      final expr = match.group(1)?.trim() ?? '';
      if (expr.isEmpty) {
        return fileIndex.toString();
      }

      final lower = expr.toLowerCase();

      if (lower == 'ruuidv4' ||
          lower == 'uuid' ||
          lower == 'uuidv4' ||
          lower == 'guid') {
        return _generateUuidV4(random);
      }

      if (lower.startsWith('rstringalnum') ||
          lower.startsWith('randalnum') ||
          lower.startsWith('rand=') ||
          lower.startsWith('rstringalnum=')) {
        final len = int.tryParse(expr.split('=').last.trim()) ?? 8;
        return _generateRandomString(
          random,
          len.clamp(1, 64),
          alpha: true,
          digit: true,
        );
      }
      if (lower.startsWith('rstringalpha') || lower.startsWith('randalpha')) {
        final len = int.tryParse(expr.split('=').last.trim()) ?? 8;
        return _generateRandomString(
          random,
          len.clamp(1, 64),
          alpha: true,
          digit: false,
        );
      }
      if (lower.startsWith('rstringdigit') ||
          lower.startsWith('randdigit') ||
          lower.startsWith('rdigit')) {
        final len = int.tryParse(expr.split('=').last.trim()) ?? 6;
        return _generateRandomString(
          random,
          len.clamp(1, 64),
          alpha: false,
          digit: true,
        );
      }

      if (lower == 'count' ||
          lower.contains('start=') ||
          lower.contains('increment=') ||
          lower.contains('padding=')) {
        int start = 0;
        int increment = 1;
        int padding = 1;

        final parts = expr.split(RegExp(r'[;,]'));
        for (final part in parts) {
          final kv = part.split('=');
          if (kv.length == 2) {
            final key = kv[0].trim().toLowerCase();
            final val = int.tryParse(kv[1].trim());
            if (val != null) {
              if (key == 'start') start = val;
              if (key == 'increment') increment = val;
              if (key == 'padding') padding = val.clamp(1, 10);
            }
          }
        }

        final countVal = start + (fileIndex * increment);
        return countVal.toString().padLeft(padding, '0');
      }

      return match.group(0)!;
    });

    return result;
  }

  String _applyCaseTransform(String input, CaseTransformation transform) {
    switch (transform) {
      case CaseTransformation.none:
        return input;
      case CaseTransformation.lower:
        return input.toLowerCase();
      case CaseTransformation.upper:
        return input.toUpperCase();
      case CaseTransformation.capitalize:
        if (input.isEmpty) return input;
        return input[0].toUpperCase() + input.substring(1).toLowerCase();
      case CaseTransformation.title:
        if (input.isEmpty) return input;
        return input.splitMapJoin(
          RegExp(r'\w+'),
          onMatch: (m) {
            final word = m.group(0)!;
            return word[0].toUpperCase() + word.substring(1).toLowerCase();
          },
          onNonMatch: (nm) => nm,
        );
    }
  }

  String _performSearchReplace({
    required AppLocalizations l10n,
    required String input,
    required RawEntry entry,
    required int fileIndex,
    required Random random,
  }) {
    final state = ref.watch(advancedRenameFormProvider);
    final search = _searchCtrl.text;
    final rawReplace = _replaceCtrl.text;
    if (search.isEmpty) return input;

    if (state.useRegex) {
      try {
        final regex = RegExp(search, caseSensitive: state.matchCase);
        if (state.matchAll) {
          return input.replaceAllMapped(regex, (m) {
            return _evaluateReplaceTemplate(
              l10n: l10n,
              template: rawReplace,
              entry: entry,
              fileIndex: fileIndex,
              random: random,
              regexMatch: m,
            );
          });
        } else {
          return input.replaceFirstMapped(regex, (m) {
            return _evaluateReplaceTemplate(
              l10n: l10n,
              template: rawReplace,
              entry: entry,
              fileIndex: fileIndex,
              random: random,
              regexMatch: m,
            );
          });
        }
      } catch (_) {
        return input;
      }
    } else {
      final evaluatedReplace = _evaluateReplaceTemplate(
        l10n: l10n,
        template: rawReplace,
        entry: entry,
        fileIndex: fileIndex,
        random: random,
      );
      if (state.matchCase) {
        return state.matchAll
            ? input.replaceAll(search, evaluatedReplace)
            : input.replaceFirst(search, evaluatedReplace);
      } else {
        final regex = RegExp(RegExp.escape(search), caseSensitive: false);
        return state.matchAll
            ? input.replaceAll(regex, evaluatedReplace)
            : input.replaceFirst(regex, evaluatedReplace);
      }
    }
  }

  List<_AdvancedRenameCandidate> _generateCandidates() {
    final state = ref.watch(advancedRenameFormProvider);
    final l10n = context.l10n;
    final candidates = <_AdvancedRenameCandidate>[];
    final startNum = int.tryParse(_startNumCtrl.text.trim()) ?? 1;
    final padding = int.tryParse(_paddingCtrl.text.trim())?.clamp(1, 8) ?? 2;
    final separator = _separatorCtrl.text;
    final isCaseSensitive =
        _fsType == FilesystemType.ext ||
        _fsType == FilesystemType.encryptedVault;

    int counterIndex = 0;
    final Map<String, String> unselectedOriginals = {
      for (final e in widget.oldEntries.where(
        (e) => !state.selectedEntries.contains(e),
      ))
        (isCaseSensitive ? e.name : e.name.toLowerCase()): e.name,
    };

    final Map<String, int> plannedNameCounts = {};

    for (int i = 0; i < widget.oldEntries.length; i++) {
      final entry = widget.oldEntries[i];
      final isSelected = state.selectedEntries.contains(entry);
      final original = entry.name;

      if (!isSelected) {
        candidates.add(
          _AdvancedRenameCandidate(
            entry: entry,
            originalName: original,
            newName: original,
            isValid: true,
            hasChanged: false,
          ),
        );
        continue;
      }

      final deterministicRandom = Random(original.hashCode ^ i ^ 0x5bd1e995);

      String stem = original;
      String ext = '';
      final dot = original.lastIndexOf('.');
      if (dot > 0 && !entry.isDir) {
        stem = original.substring(0, dot);
        ext = original.substring(dot + 1);
      }

      String newStem = stem;
      String newExt = ext;
      String newFullName = original;

      switch (state.applyTarget) {
        case RenameApplyTarget.nameOnly:
          newStem = _performSearchReplace(
            l10n: l10n,
            input: stem,
            entry: entry,
            fileIndex: counterIndex,
            random: deterministicRandom,
          );
          newStem = _applyCaseTransform(newStem, state.caseTransform);
          break;
        case RenameApplyTarget.extensionOnly:
          if (ext.isNotEmpty) {
            newExt = _performSearchReplace(
              l10n: l10n,
              input: ext,
              entry: entry,
              fileIndex: counterIndex,
              random: deterministicRandom,
            );
            newExt = _applyCaseTransform(newExt, state.caseTransform);
          }
          break;
        case RenameApplyTarget.nameAndExtension:
          newFullName = _performSearchReplace(
            l10n: l10n,
            input: original,
            entry: entry,
            fileIndex: counterIndex,
            random: deterministicRandom,
          );
          newFullName = _applyCaseTransform(newFullName, state.caseTransform);
          final newDot = newFullName.lastIndexOf('.');
          if (newDot > 0 && !entry.isDir) {
            newStem = newFullName.substring(0, newDot);
            newExt = newFullName.substring(newDot + 1);
          } else {
            newStem = newFullName;
            newExt = '';
          }
          break;
      }

      if (state.enableCounter) {
        final formattedNum = (startNum + counterIndex).toString().padLeft(
          padding,
          '0',
        );
        if (state.counterPosition == CounterPosition.suffix) {
          newStem = '$newStem$separator$formattedNum';
        } else {
          newStem = '$formattedNum$separator$newStem';
        }
      }

      counterIndex++;

      final resolvedName = (newExt.isNotEmpty && !entry.isDir)
          ? '$newStem.$newExt'
          : newStem;
      final key = isCaseSensitive ? resolvedName : resolvedName.toLowerCase();
      plannedNameCounts[key] = (plannedNameCounts[key] ?? 0) + 1;

      candidates.add(
        _AdvancedRenameCandidate(
          entry: entry,
          originalName: original,
          newName: resolvedName,
          isValid: true,
          hasChanged: resolvedName != original,
        ),
      );
    }

    final finalCandidates = <_AdvancedRenameCandidate>[];

    for (final c in candidates) {
      if (!state.selectedEntries.contains(c.entry)) {
        finalCandidates.add(c);
        continue;
      }

      String? error;
      final nameValidation = validateEntryName(
        c.newName,
        _fsType,
        entryType: c.entry.isDir ? EntryType.folder : EntryType.file,
        l10n: l10n,
      );
      if (nameValidation.issues.isNotEmpty) {
        error = nameValidation.issues.first.message;
      }

      if (error == null) {
        final key = isCaseSensitive ? c.newName : c.newName.toLowerCase();
        if ((plannedNameCounts[key] ?? 0) > 1) {
          error = l10n.advancedRenameNameCollisionWithinBatch;
        } else if (unselectedOriginals.containsKey(key)) {
          error = l10n.advancedRenameCollidesWithUnselectedFile;
        } else {
          final externalConflict = checkEntryConflict(
            candidateName: c.newName,
            candidateIsDir: c.entry.isDir,
            existingEntries: widget.existingEntries
                .where((e) => !widget.oldEntries.contains(e))
                .toList(),
            caseSensitive: FilesystemRules.of(_fsType).caseSensitive,
          );
          if (externalConflict.isConflict) {
            error = externalConflict.message(l10n, c.newName);
          }
        }
      }

      finalCandidates.add(
        _AdvancedRenameCandidate(
          entry: c.entry,
          originalName: c.originalName,
          newName: c.newName,
          isValid: error == null,
          hasChanged: c.hasChanged,
          errorMessage: error,
        ),
      );
    }

    return finalCandidates;
  }

  Future<void> _executeBatchRename(
    List<_AdvancedRenameCandidate> candidates,
  ) async {
    final l10n = context.l10n;
    final selected = ref.read(advancedRenameFormProvider).selectedEntries;
    final toRename = candidates
        .where((c) => selected.contains(c.entry) && c.hasChanged && c.isValid)
        .toList();
    if (toRename.isEmpty) return;

    final renames = [
      for (final c in toRename)
        (
          oldFull: widget.currentDirPath.isEmpty
              ? c.originalName
              : '${widget.currentDirPath}/${c.originalName}',
          newFull: widget.currentDirPath.isEmpty
              ? c.newName
              : '${widget.currentDirPath}/${c.newName}',
        ),
    ];

    final result = await ref
        .read(advancedRenameFormProvider.notifier)
        .executeBatchRename(
          renames: renames,
          container: widget.container,
          onEachRenamed: (oldFull, newFull) =>
              widget.onEntryRenamed?.call(oldFull, newFull),
        );

    if (!mounted) return;

    if (result.succeeded > 0) {
      widget.onSuccess();
    }

    if (result.failed > 0) {
      showAppSnackBar(
        context,
        message: l10n.advancedRenameRenamedItems(
          result.succeeded,
          result.failed,
        ),
        tone: AppBannerTone.warning,
      );
    } else {
      showAppSnackBar(
        context,
        message: l10n.advancedRenameSuccessfullyRenamed(result.succeeded),
        tone: AppBannerTone.success,
      );
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(advancedRenameFormProvider);
    final cs = context.colors;
    final textTheme = context.typography;
    final isLandscape = context.screen.useWideLayout;

    final candidates = _generateCandidates();
    final validRenameCount = candidates
        .where(
          (c) =>
              state.selectedEntries.contains(c.entry) &&
              c.hasChanged &&
              c.isValid,
        )
        .length;
    final hasErrors = candidates.any(
      (c) =>
          state.selectedEntries.contains(c.entry) &&
          c.hasChanged &&
          !c.isValid,
    );

    return isLandscape
        ? _buildLandscapeScaffold(
            candidates,
            validRenameCount,
            hasErrors,
            cs,
            textTheme,
            state,
          )
        : _buildPortraitScaffold(
            candidates,
            validRenameCount,
            hasErrors,
            cs,
            textTheme,
            state,
          );
  }

  Widget _buildLandscapeScaffold(
    List<_AdvancedRenameCandidate> candidates,
    int validRenameCount,
    bool hasErrors,
    ColorScheme cs,
    TextTheme textTheme,
    AdvancedRenameFormState state,
  ) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.advancedRenameBatchTitle,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              hasErrors
                  ? l10n.advancedRenameResolveConflicts
                  : (state.selectedEntries.isEmpty
                      ? l10n.advancedRenameNoFilesSelected
                      : l10n.advancedRenameReadyCount(
                          validRenameCount,
                          widget.oldEntries.length,
                        )),
              style: textTheme.labelSmall?.copyWith(
                color: hasErrors ? cs.error : cs.onSurfaceVariant,
                fontWeight: hasErrors ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          if (hasErrors)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
                  const SizedBox(width: 4),
                  Text(
                    l10n.advancedRenameErrorsDetected,
                    style: textTheme.labelMedium?.copyWith(
                      color: cs.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: state.isExecuting ? null : () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 38),
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
                  : () => _executeBatchRename(candidates),
            ),
          ),
        ],
        bottom: state.isExecuting
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3.0),
                child: LinearProgressIndicator(
                  value: state.executionProgress,
                  minHeight: 3.0,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: _buildControls(cs, textTheme),
                ),
              ),
              const SizedBox(width: 16),
              const VerticalDivider(width: 1),
              const SizedBox(width: 16),
              Expanded(
                flex: 6,
                child: _PreviewList(
                  candidates: candidates,
                  cs: cs,
                  textTheme: textTheme,
                  state: state,
                  oldEntries: widget.oldEntries,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitScaffold(
    List<_AdvancedRenameCandidate> candidates,
    int validRenameCount,
    bool hasErrors,
    ColorScheme cs,
    TextTheme textTheme,
    AdvancedRenameFormState state,
  ) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            l10n.advancedRenameBatchTitle,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          bottom: TabBar(
            indicatorColor: cs.primary,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            tabs: [
              Tab(
                icon: const Icon(Icons.tune_rounded, size: 20),
                text: l10n.advancedRenameRulesTab,
              ),
              Tab(
                icon: Badge(
                  isLabelVisible: hasErrors,
                  backgroundColor: cs.error,
                  smallSize: 8,
                  child: const Icon(Icons.visibility_rounded, size: 20),
                ),
                text: l10n.advancedRenamePreviewTab(validRenameCount),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildControls(cs, textTheme),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _PreviewList(
                  candidates: candidates,
                  cs: cs,
                  textTheme: textTheme,
                  state: state,
                  oldEntries: widget.oldEntries,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _BottomBar(
          validRenameCount: validRenameCount,
          hasErrors: hasErrors,
          cs: cs,
          textTheme: textTheme,
          state: state,
          oldEntriesCount: widget.oldEntries.length,
          onApply: () => _executeBatchRename(candidates),
        ),
      ),
    );
  }

  Widget _buildControls(ColorScheme cs, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FindReplaceCard(
          cs: cs,
          textTheme: textTheme,
          searchController: _searchCtrl,
          replaceController: _replaceCtrl,
          onInsertVariable: _insertVariable,
        ),
        const SizedBox(height: 14),
        _ScopeAndCaseCard(cs: cs, textTheme: textTheme),
        const SizedBox(height: 14),
        _CounterCard(
          cs: cs,
          textTheme: textTheme,
          startNumberController: _startNumCtrl,
          paddingController: _paddingCtrl,
          separatorController: _separatorCtrl,
        ),
      ],
    );
  }

}
