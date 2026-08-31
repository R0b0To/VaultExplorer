// AdvancedRenameScreen was a plain StatefulWidget holding the entire
// find/replace/case/counter form plus the per-entry selection Set and the
// batch-execution progress directly as State fields. No family needed --
// only one instance of this screen is ever pushed at a time (matches
// StorageAnalyzerScreen/ContainerSplitterSheet's "single instance" shape),
// and its constructor params (a MountedContainer, two RawEntry lists) don't
// make good family-key material anyway.
//
// `_generateCandidates()` and its helpers (_performSearchReplace,
// _evaluateReplaceTemplate, _applyCaseTransform, token/date/uuid/random
// generation) stay entirely in the widget, unmoved -- they're a pure,
// synchronous computation read fresh every build from a *mix* of
// Riverpod-owned toggle state and the five local TextEditingControllers'
// live `.text` (search/replace/start-number/padding/separator stay local,
// same ephemeral-controller reasoning as everywhere else), so there's
// nothing here that's cleanly "notifier state" on its own -- moving it
// would just mean the notifier reading back out of widget-owned
// controllers, which is backwards. Only the two genuinely async/shared
// concerns move here: the selection Set (mutated via `.add`/`.remove` in
// the original -- same in-place-Set-mutation hazard already fixed twice in
// FileBrowserScreen, fixed here too via immutable reconstruction) and the
// actual batch-rename execution (was a direct `vaultExplorerApi.renameFile`
// loop with per-item setState progress, upgraded to `vaultFileIoApiProvider`
// here, same Phase-2 upgrade applied throughout this migration).
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
 
part 'advanced_rename_controller.g.dart';
 
enum RenameApplyTarget { nameOnly, extensionOnly, nameAndExtension }
enum CaseTransformation { none, lower, upper, title, capitalize }
enum CounterPosition { suffix, prefix }
 
class AdvancedRenameFormState {
  final Set<RawEntry> selectedEntries;
  final bool useRegex;
  final bool matchCase;
  final bool matchAll;
  final RenameApplyTarget applyTarget;
  final CaseTransformation caseTransform;
  final bool enableCounter;
  final CounterPosition counterPosition;
  final bool isExecuting;
  final double executionProgress;
 
  const AdvancedRenameFormState({
    this.selectedEntries = const {},
    this.useRegex = false,
    this.matchCase = false,
    this.matchAll = true,
    this.applyTarget = RenameApplyTarget.nameOnly,
    this.caseTransform = CaseTransformation.none,
    this.enableCounter = false,
    this.counterPosition = CounterPosition.suffix,
    this.isExecuting = false,
    this.executionProgress = 0.0,
  });
 
  AdvancedRenameFormState _copy({
    Set<RawEntry>? selectedEntries,
    bool? useRegex,
    bool? matchCase,
    bool? matchAll,
    RenameApplyTarget? applyTarget,
    CaseTransformation? caseTransform,
    bool? enableCounter,
    CounterPosition? counterPosition,
    bool? isExecuting,
    double? executionProgress,
  }) => AdvancedRenameFormState(
    selectedEntries: selectedEntries ?? this.selectedEntries,
    useRegex: useRegex ?? this.useRegex,
    matchCase: matchCase ?? this.matchCase,
    matchAll: matchAll ?? this.matchAll,
    applyTarget: applyTarget ?? this.applyTarget,
    caseTransform: caseTransform ?? this.caseTransform,
    enableCounter: enableCounter ?? this.enableCounter,
    counterPosition: counterPosition ?? this.counterPosition,
    isExecuting: isExecuting ?? this.isExecuting,
    executionProgress: executionProgress ?? this.executionProgress,
  );
}
 
@riverpod
class AdvancedRenameForm extends _$AdvancedRenameForm {
  @override
  AdvancedRenameFormState build() => const AdvancedRenameFormState();
 
  /// Called once from the widget's initState -- a provider can't take a
  /// widget-supplied List as a construction param (not stable/hashable
  /// family-key material), so the initial selection is seeded here
  /// instead, same reasoning as SessionLockController's configure().
  void initialize(List<RawEntry> oldEntries) {
      state = AdvancedRenameFormState(selectedEntries: Set.of(oldEntries));
  }
 
  void setUseRegex(bool v) => state = state._copy(useRegex: v);
  void setMatchCase(bool v) => state = state._copy(matchCase: v);
  void setMatchAll(bool v) => state = state._copy(matchAll: v);
  void setApplyTarget(RenameApplyTarget v) =>
      state = state._copy(applyTarget: v);
  void setCaseTransform(CaseTransformation v) =>
      state = state._copy(caseTransform: v);
  void setEnableCounter(bool v) => state = state._copy(enableCounter: v);
  void setCounterPosition(CounterPosition v) =>
      state = state._copy(counterPosition: v);
 
  void selectAll(List<RawEntry> all) =>
      state = state._copy(selectedEntries: Set.of(all));
 
  void deselectAll() => state = state._copy(selectedEntries: const {});
 
  void toggleEntry(RawEntry entry) {
    final next = Set<RawEntry>.of(state.selectedEntries);
    if (!next.remove(entry)) next.add(entry);
    state = state._copy(selectedEntries: next);
  }
 
  /// Returns the final success/failure tally; the widget interprets that
  /// into a snackbar + pop, matching the original's post-loop handling.
  /// [onEachRenamed] is called synchronously inside the loop on each
  /// success, same timing as the original's `widget.onEntryRenamed?.call`
  /// -- a plain method param, not stored state, so it's fine for it to be
  /// a closure here (unlike a provider constructor param, a Notifier
  /// method doesn't need its arguments to be `==`-stable).
  Future<({int succeeded, int failed})> executeBatchRename({
    required List<({String oldFull, String newFull})> renames,
    required MountedContainer container,
    required void Function(String oldFull, String newFull) onEachRenamed,
  }) async {
    state = state._copy(isExecuting: true, executionProgress: 0.0);
    var succeeded = 0;
    var failed = 0;
 
    for (var i = 0; i < renames.length; i++) {
      final r = renames[i];
      try {
        final ok = await ref
            .read(vaultFileIoApiProvider)
            .renameFile(container, r.oldFull, r.newFull);
        if (ok) {
          succeeded++;
          onEachRenamed(r.oldFull, r.newFull);
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
      if (ref.mounted) {
        state = state._copy(executionProgress: (i + 1) / renames.length);
      }
    }
 
    if (ref.mounted) state = state._copy(isExecuting: false);
    return (succeeded: succeeded, failed: failed);
  }
}