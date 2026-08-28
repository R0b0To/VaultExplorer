import 'dart:math';
import 'package:flutter/material.dart';
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
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

enum RenameApplyTarget { nameOnly, extensionOnly, nameAndExtension }
enum CaseTransformation { none, lower, upper, title, capitalize }
enum CounterPosition { suffix, prefix }

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

class AdvancedRenameScreen extends StatefulWidget {
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
  State<AdvancedRenameScreen> createState() => _AdvancedRenameScreenState();
}

class _AdvancedRenameScreenState extends State<AdvancedRenameScreen> {
  final _searchCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  final _startNumCtrl = TextEditingController(text: '1');
  final _paddingCtrl = TextEditingController(text: '2');
  final _separatorCtrl = TextEditingController(text: '_');

  late final FilesystemType _fsType;
  final Set<RawEntry> _selectedEntries = {};

  bool _useRegex = false;
  bool _matchCase = false;
  bool _matchAll = true;
  RenameApplyTarget _applyTarget = RenameApplyTarget.nameOnly;
  CaseTransformation _caseTransform = CaseTransformation.none;
  bool _enableCounter = false;
  CounterPosition _counterPosition = CounterPosition.suffix;

  bool _isExecuting = false;
  double _executionProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _fsType = resolveFilesystemType(widget.container);
    _selectedEntries.addAll(widget.oldEntries);
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
      if (d.modified is int) return DateTime.fromMillisecondsSinceEpoch(d.modified as int);
      if (d.mtime is int) return DateTime.fromMillisecondsSinceEpoch(d.mtime as int);
    } catch (_) {
      // Probing several dynamic field names for whichever timestamp this
      // entry type actually has; accessing a field it doesn't have throws
      // NoSuchMethodError, which just means falling through to
      // DateTime.now() below.
    }
    return DateTime.now();
  }

  String _formatDateToken(DateTime dt, String token, AppLocalizations l10n) {
    final monthsFull = l10n.advancedRenameMonthsFull.split('|');
    final monthsAbbr = l10n.advancedRenameMonthsAbbr.split('|');
    final daysFull = l10n.advancedRenameDaysFull.split('|');
    final daysAbbr = l10n.advancedRenameDaysAbbr.split('|');

    switch (token) {
      case r'$YYYY': return dt.year.toString().padLeft(4, '0');
      case r'$YY': return (dt.year % 100).toString().padLeft(2, '0');
      case r'$Y': return (dt.year % 10).toString();
      case r'$MMMM': return monthsFull[dt.month - 1];
      case r'$MMM': return monthsAbbr[dt.month - 1];
      case r'$MM': return dt.month.toString().padLeft(2, '0');
      case r'$M': return dt.month.toString();
      case r'$DDDD': return daysFull[dt.weekday - 1];
      case r'$DDD': return daysAbbr[dt.weekday - 1];
      case r'$DD': return dt.day.toString().padLeft(2, '0');
      case r'$D': return dt.day.toString();
      case r'$hh': return dt.hour.toString().padLeft(2, '0');
      case r'$h': return dt.hour.toString();
      case r'$mm': return dt.minute.toString().padLeft(2, '0');
      case r'$m': return dt.minute.toString();
      case r'$ss': return dt.second.toString().padLeft(2, '0');
      case r'$s': return dt.second.toString();
      case r'$fff': return dt.millisecond.toString().padLeft(3, '0');
      default: return token;
    }
  }

  String _generateUuidV4(Random rnd) {
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _generateRandomString(Random rnd, int length, {bool alpha = true, bool digit = true}) {
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
      r'$YYYY', r'$YY', r'$Y',
      r'$MMMM', r'$MMM', r'$MM', r'$M',
      r'$DDDD', r'$DDD', r'$DD', r'$D',
      r'$hh', r'$h', r'$mm', r'$m', r'$ss', r'$s', r'$fff',
      r'${YYYY}', r'${YY}', r'${Y}',
      r'${MMMM}', r'${MMM}', r'${MM}', r'${M}',
      r'${DDDD}', r'${DDD}', r'${DD}', r'${D}',
      r'${hh}', r'${h}', r'${mm}', r'${m}', r'${ss}', r'${s}', r'${fff}',
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

      if (lower == 'ruuidv4' || lower == 'uuid' || lower == 'uuidv4' || lower == 'guid') {
        return _generateUuidV4(random);
      }

      if (lower.startsWith('rstringalnum') ||
          lower.startsWith('randalnum') ||
          lower.startsWith('rand=') ||
          lower.startsWith('rstringalnum=')) {
        final len = int.tryParse(expr.split('=').last.trim()) ?? 8;
        return _generateRandomString(random, len.clamp(1, 64), alpha: true, digit: true);
      }
      if (lower.startsWith('rstringalpha') || lower.startsWith('randalpha')) {
        final len = int.tryParse(expr.split('=').last.trim()) ?? 8;
        return _generateRandomString(random, len.clamp(1, 64), alpha: true, digit: false);
      }
      if (lower.startsWith('rstringdigit') || lower.startsWith('randdigit') || lower.startsWith('rdigit')) {
        final len = int.tryParse(expr.split('=').last.trim()) ?? 6;
        return _generateRandomString(random, len.clamp(1, 64), alpha: false, digit: true);
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
    final search = _searchCtrl.text;
    final rawReplace = _replaceCtrl.text;
    if (search.isEmpty) return input;

    if (_useRegex) {
      try {
        final regex = RegExp(search, caseSensitive: _matchCase);
        if (_matchAll) {
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
      if (_matchCase) {
        return _matchAll ? input.replaceAll(search, evaluatedReplace) : input.replaceFirst(search, evaluatedReplace);
      } else {
        final regex = RegExp(RegExp.escape(search), caseSensitive: false);
        return _matchAll ? input.replaceAll(regex, evaluatedReplace) : input.replaceFirst(regex, evaluatedReplace);
      }
    }
  }

  List<_AdvancedRenameCandidate> _generateCandidates() {
    final l10n = context.l10n;
    final candidates = <_AdvancedRenameCandidate>[];
    final startNum = int.tryParse(_startNumCtrl.text.trim()) ?? 1;
    final padding = int.tryParse(_paddingCtrl.text.trim())?.clamp(1, 8) ?? 2;
    final separator = _separatorCtrl.text;
    final isCaseSensitive = _fsType == FilesystemType.ext || _fsType == FilesystemType.encryptedVault;

    int counterIndex = 0;
    final Map<String, String> unselectedOriginals = {
      for (final e in widget.oldEntries.where((e) => !_selectedEntries.contains(e)))
        (isCaseSensitive ? e.name : e.name.toLowerCase()): e.name,
    };

    final Map<String, int> plannedNameCounts = {};

    for (int i = 0; i < widget.oldEntries.length; i++) {
      final entry = widget.oldEntries[i];
      final isSelected = _selectedEntries.contains(entry);
      final original = entry.name;

      if (!isSelected) {
        candidates.add(_AdvancedRenameCandidate(
          entry: entry,
          originalName: original,
          newName: original,
          isValid: true,
          hasChanged: false,
        ));
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

      switch (_applyTarget) {
        case RenameApplyTarget.nameOnly:
          newStem = _performSearchReplace(
            l10n: l10n,
            input: stem,
            entry: entry,
            fileIndex: counterIndex,
            random: deterministicRandom,
          );
          newStem = _applyCaseTransform(newStem, _caseTransform);
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
            newExt = _applyCaseTransform(newExt, _caseTransform);
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
          newFullName = _applyCaseTransform(newFullName, _caseTransform);
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

      if (_enableCounter) {
        final formattedNum = (startNum + counterIndex).toString().padLeft(padding, '0');
        if (_counterPosition == CounterPosition.suffix) {
          newStem = '$newStem$separator$formattedNum';
        } else {
          newStem = '$formattedNum$separator$newStem';
        }
      }

      counterIndex++;

      final resolvedName = (newExt.isNotEmpty && !entry.isDir) ? '$newStem.$newExt' : newStem;
      final key = isCaseSensitive ? resolvedName : resolvedName.toLowerCase();
      plannedNameCounts[key] = (plannedNameCounts[key] ?? 0) + 1;

      candidates.add(_AdvancedRenameCandidate(
        entry: entry,
        originalName: original,
        newName: resolvedName,
        isValid: true,
        hasChanged: resolvedName != original,
      ));
    }

    final finalCandidates = <_AdvancedRenameCandidate>[];

    for (final c in candidates) {
      if (!_selectedEntries.contains(c.entry)) {
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

      finalCandidates.add(_AdvancedRenameCandidate(
        entry: c.entry,
        originalName: c.originalName,
        newName: c.newName,
        isValid: error == null,
        hasChanged: c.hasChanged,
        errorMessage: error,
      ));
    }

    return finalCandidates;
  }

  Future<void> _executeBatchRename(List<_AdvancedRenameCandidate> candidates) async {
    final l10n = context.l10n;
    final toRename = candidates
        .where((c) => _selectedEntries.contains(c.entry) && c.hasChanged && c.isValid)
        .toList();
    if (toRename.isEmpty) return;

    setState(() {
      _isExecuting = true;
      _executionProgress = 0.0;
    });

    int succeeded = 0;
    int failed = 0;

    for (int i = 0; i < toRename.length; i++) {
      final c = toRename[i];
      final oldFull = widget.currentDirPath.isEmpty
          ? c.originalName
          : '${widget.currentDirPath}/${c.originalName}';
      final newFull = widget.currentDirPath.isEmpty
          ? c.newName
          : '${widget.currentDirPath}/${c.newName}';

      try {
        final ok = await vaultExplorerApi.renameFile(widget.container, oldFull, newFull);
        if (ok) {
          succeeded++;
          widget.onEntryRenamed?.call(oldFull, newFull);
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }

      if (mounted) {
        setState(() {
          _executionProgress = (i + 1) / toRename.length;
        });
      }
    }

    if (!mounted) return;

    if (succeeded > 0) {
      widget.onSuccess();
    }

    if (failed > 0) {
      showAppSnackBar(
        context,
        message: l10n.advancedRenameRenamedItems(succeeded, failed),
        tone: AppBannerTone.warning,
      );
    } else {
      showAppSnackBar(
        context,
        message: l10n.advancedRenameSuccessfullyRenamed(succeeded),
        tone: AppBannerTone.success,
      );
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final isLandscape = context.screen.useWideLayout;

    final candidates = _generateCandidates();
    final validRenameCount = candidates
        .where((c) => _selectedEntries.contains(c.entry) && c.hasChanged && c.isValid)
        .length;
    final hasErrors = candidates
        .any((c) => _selectedEntries.contains(c.entry) && c.hasChanged && !c.isValid);

    return isLandscape
        ? _buildLandscapeScaffold(candidates, validRenameCount, hasErrors, cs, textTheme)
        : _buildPortraitScaffold(candidates, validRenameCount, hasErrors, cs, textTheme);
  }

  Widget _buildLandscapeScaffold(
    List<_AdvancedRenameCandidate> candidates,
    int validRenameCount,
    bool hasErrors,
    ColorScheme cs,
    TextTheme textTheme,
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
                  : (_selectedEntries.isEmpty
                      ? l10n.advancedRenameNoFilesSelected
                      : l10n.advancedRenameReadyCount(validRenameCount, widget.oldEntries.length)),
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
            onPressed: _isExecuting ? null : () => Navigator.pop(context),
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
              icon: _isExecuting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.done_all_rounded, size: 18),
              label: Text(l10n.advancedRenameApply(validRenameCount)),
              onPressed: (_isExecuting || validRenameCount == 0 || hasErrors)
                  ? null
                  : () => _executeBatchRename(candidates),
            ),
          ),
        ],
        bottom: _isExecuting
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3.0),
                child: LinearProgressIndicator(
                  value: _executionProgress,
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
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: _buildControls(cs, textTheme),
                ),
              ),
              const SizedBox(width: 16),
              const VerticalDivider(width: 1),
              const SizedBox(width: 16),
              Expanded(
                flex: 6,
                child: _buildPreviewList(candidates, cs, textTheme),
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
                child: _buildPreviewList(candidates, cs, textTheme),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomBar(candidates, validRenameCount, hasErrors, cs, textTheme),
      ),
    );
  }

  Widget _buildControls(ColorScheme cs, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFindReplaceCard(cs, textTheme),
        const SizedBox(height: 14),
        _buildScopeAndCaseCard(cs, textTheme),
        const SizedBox(height: 14),
        _buildCounterCard(cs, textTheme),
      ],
    );
  }

  Widget _buildFindReplaceCard(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
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
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: l10n.advancedRenameFindTextLabel,
                hintText: l10n.advancedRenameFindTextHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: cs.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
                ),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _replaceCtrl,
              decoration: InputDecoration(
                labelText: l10n.advancedRenameReplaceWithLabel,
                hintText: l10n.advancedRenameReplaceWithHint,
                prefixIcon: const Icon(Icons.edit_note_rounded, size: 20),
                filled: true,
                fillColor: cs.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: l10n.advancedRenameInsertVariableTooltip,
                      icon: Icon(Icons.data_object_rounded, size: 20, color: cs.primary),
                      onSelected: _insertVariable,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          enabled: false,
                          child: Text(
                            l10n.advancedRenameDateTimeTokens,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'$YYYY-$MM-$DD',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.calendar_today_rounded, size: 18),
                            title: Text(l10n.advancedRenameStandardDate(r'$YYYY-$MM-$DD')),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'$YYYY',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.date_range_rounded, size: 18),
                            title: Text(l10n.advancedRenameYearFourDigit(r'$YYYY')),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'$MM',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.calendar_view_month_rounded, size: 18),
                            title: Text(l10n.advancedRenameMonth(r'$MM')),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'$DD',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.today_rounded, size: 18),
                            title: Text(l10n.advancedRenameDayOfMonth(r'$DD')),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'$hh-$mm-$ss',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.access_time_rounded, size: 18),
                            title: Text(l10n.advancedRenameTime(r'$hh-$mm-$ss')),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          enabled: false,
                          child: Text(
                            l10n.advancedRenameDynamicIdentifiers,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'${ruuidv4}',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.fingerprint_rounded, size: 18),
                            title: Text(l10n.advancedRenameUniqueUuid(r'${ruuidv4}')),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'${rstringalnum=8}',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.password_rounded, size: 18),
                            title: Text(l10n.advancedRenameRandomAlphanumeric),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'${rstringdigit=6}',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.numbers_rounded, size: 18),
                            title: Text(l10n.advancedRenameRandomDigits),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          enabled: false,
                          child: Text(
                            l10n.advancedRenameEmbeddedCounter,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                        ),
                        PopupMenuItem(
                          value: r'${padding=3;start=1}',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.format_list_numbered_rounded, size: 18),
                            title: Text(l10n.advancedRenamePaddedCounter(r'${padding=3;start=1}')),
                          ),
                        ),
                      ],
                    ),
                    if (_replaceCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () => _replaceCtrl.clear(),
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
                  label: Text(l10n.advancedRenameRegex, style: const TextStyle(fontSize: 12)),
                  avatar: const Icon(Icons.code_rounded, size: 16),
                  selected: _useRegex,
                  showCheckmark: false,
                  onSelected: (v) => setState(() => _useRegex = v),
                ),
                FilterChip(
                  label: Text(l10n.advancedRenameMatchCase, style: const TextStyle(fontSize: 12)),
                  avatar: const Icon(Icons.format_size_rounded, size: 16),
                  selected: _matchCase,
                  showCheckmark: false,
                  onSelected: (v) => setState(() => _matchCase = v),
                ),
                FilterChip(
                  label: Text(l10n.advancedRenameAllOccurrences, style: const TextStyle(fontSize: 12)),
                  avatar: const Icon(Icons.select_all_rounded, size: 16),
                  selected: _matchAll,
                  showCheckmark: false,
                  onSelected: (v) => setState(() => _matchAll = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeAndCaseCard(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Text(
              l10n.advancedRenameApplyChangesTo,
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<RenameApplyTarget>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: RenameApplyTarget.nameOnly,
                  label: Text(l10n.advancedRenameFilename),
                  icon: const Icon(Icons.insert_drive_file_outlined, size: 16),
                ),
                ButtonSegment(
                  value: RenameApplyTarget.extensionOnly,
                  label: Text(l10n.advancedRenameExtension),
                  icon: const Icon(Icons.extension_outlined, size: 16),
                ),
                ButtonSegment(
                  value: RenameApplyTarget.nameAndExtension,
                  label: Text(l10n.advancedRenameBoth),
                  icon: const Icon(Icons.all_inclusive_rounded, size: 16),
                ),
              ],
              selected: {_applyTarget},
              onSelectionChanged: (set) => setState(() => _applyTarget = set.first),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.text_fields_rounded, size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      l10n.advancedRenameCaseTransformation,
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  child: DropdownButton<CaseTransformation>(
                    value: _caseTransform,
                    underline: const SizedBox(),
                    isDense: true,
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      DropdownMenuItem(value: CaseTransformation.none, child: Text(l10n.advancedRenameNoChange)),
                      DropdownMenuItem(value: CaseTransformation.lower, child: Text(l10n.advancedRenameLowercase)),
                      DropdownMenuItem(value: CaseTransformation.upper, child: Text(l10n.advancedRenameUppercase)),
                      DropdownMenuItem(value: CaseTransformation.title, child: Text(l10n.advancedRenameTitleCase)),
                      DropdownMenuItem(value: CaseTransformation.capitalize, child: Text(l10n.advancedRenameCapitalize)),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _caseTransform = v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounterCard(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.format_list_numbered_rounded, size: 18, color: cs.primary),
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
                        style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _enableCounter,
                  onChanged: (v) => setState(() => _enableCounter = v),
                ),
              ],
            ),
            if (_enableCounter) ...[
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
                    icon: const Icon(Icons.keyboard_backspace_rounded, size: 16),
                  ),
                ],
                selected: {_counterPosition},
                onSelectionChanged: (set) => setState(() => _counterPosition = set.first),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _startNumCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.advancedRenameStartAt,
                        filled: true,
                        fillColor: cs.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _paddingCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.advancedRenameDigits,
                        hintText: l10n.advancedRenameDigitsHint,
                        filled: true,
                        fillColor: cs.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _separatorCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.advancedRenameSeparator,
                        hintText: l10n.advancedRenameSeparatorHint,
                        filled: true,
                        fillColor: cs.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
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

  Widget _buildPreviewHeader(
    ColorScheme cs,
    TextTheme textTheme,
    bool allSelected,
    int changedCount,
  ) {
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
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.advancedRenameChangedCount(changedCount, widget.oldEntries.length),
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
            setState(() {
              if (allSelected) {
                _selectedEntries.clear();
              } else {
                _selectedEntries.addAll(widget.oldEntries);
              }
            });
          },
          label: Text(
            allSelected ? l10n.advancedRenameDeselect : l10n.advancedRenameSelectAll,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildCandidateTile(
    _AdvancedRenameCandidate c,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final isChecked = _selectedEntries.contains(c.entry);
    final hasError = !c.isValid && isChecked;
    final isChanged = c.hasChanged && isChecked;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() {
          if (isChecked) {
            _selectedEntries.remove(c.entry);
          } else {
            _selectedEntries.add(c.entry);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: isChecked,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedEntries.add(c.entry);
                  } else {
                    _selectedEntries.remove(c.entry);
                  }
                });
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 10),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (c.entry.isDir ? cs.secondaryContainer : cs.surfaceContainerHighest)
                      .withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  c.entry.isDir ? Icons.folder_rounded : iconForFile(c.originalName),
                  size: 18,
                  color: c.entry.isDir ? cs.secondary : colorForFile(c.originalName),
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline_rounded, size: 12, color: cs.error),
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
                child: Icon(Icons.check_circle_outline_rounded, size: 16, color: cs.primary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewList(
    List<_AdvancedRenameCandidate> candidates,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;
    final allSelected = _selectedEntries.length == widget.oldEntries.length;
    final changedCount = candidates.where((c) => _selectedEntries.contains(c.entry) && c.hasChanged).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Fallback gracefully when viewport height is heavily squeezed (e.g. software keyboard in landscape)
        if (constraints.maxHeight < 140) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              children: [
                _buildPreviewHeader(cs, textTheme, allSelected, changedCount),
                const Divider(height: 8),
                if (candidates.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        l10n.advancedRenameNoFilesSelected,
                        style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  ...candidates.map((c) => _buildCandidateTile(c, cs, textTheme)),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPreviewHeader(cs, textTheme, allSelected, changedCount),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: candidates.isEmpty
                    ? Center(
                        child: Text(
                          l10n.advancedRenameNoFilesSelected,
                          style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        itemCount: candidates.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          thickness: 0.5,
                          color: cs.outlineVariant.withValues(alpha: 0.3),
                        ),
                        itemBuilder: (context, i) => _buildCandidateTile(candidates[i], cs, textTheme),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(
    List<_AdvancedRenameCandidate> candidates,
    int validRenameCount,
    bool hasErrors,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isExecuting) ...[
              LinearProgressIndicator(value: _executionProgress, minHeight: 4),
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
                            : l10n.advancedRenameReadyOfTotal(validRenameCount, widget.oldEntries.length),
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
                            : (_selectedEntries.isEmpty ? l10n.advancedRenameNoFilesSelected : l10n.advancedRenameReadyToRename),
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
                  onPressed: _isExecuting ? null : () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: _isExecuting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.done_all_rounded, size: 18),
                  label: Text(l10n.advancedRenameApply(validRenameCount)),
                  onPressed: (_isExecuting || validRenameCount == 0 || hasErrors)
                      ? null
                      : () => _executeBatchRename(candidates),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}