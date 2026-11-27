// The rules the desktop import follows, as pure functions (no engine, no I/O), so they can be tested without a
// native library and compared with Android's `ImportExportHandlers.kt` case for case.
//
// Dart owns import policy (docs/architecture.md, invariant 12): the case sensitivity of the destination is decided
// here and sent with each pick, and the native side does not re-derive it. Android implements the same rules in
// Kotlin (`uniqueNameAgainst`, `fitsWithinSafetyMargin`, the child-collision walk in `importEntryRecursive`); the
// shared known-answer table in test/fixtures/import_policy.tsv is read by the Dart tests and by the Kotlin tests,
// so the two cannot drift apart unnoticed.
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

/// Share of the free space held back for filesystem overhead (ImportExportHandlers.SPACE_SAFETY_MARGIN).
const double kSpaceSafetyMargin = 0.01;

/// True if [totalBytes] fits in [available] once [kSpaceSafetyMargin] is held back
/// (ImportExportHandlers.fitsWithinSafetyMargin; both truncate the margin-adjusted space toward zero).
bool fitsWithinSafetyMargin(int totalBytes, int available) =>
    totalBytes <= (available * (1.0 - kSpaceSafetyMargin)).toInt();

/// The form of [name] used to compare names on a destination with the given case sensitivity.
String foldName(String name, bool caseSensitive) => caseSensitive ? name : name.toLowerCase();

/// "name" -> "name (1)" -> "name (2)" ..., keeping the extension (ImportExportHandlers.uniqueNameAgainst).
/// [existingFolded] holds names already folded with [foldName]. A leading dot is not an extension separator, and
/// neither is a trailing one.
String uniqueNameAgainst(Set<String> existingFolded, String desiredName, {bool caseSensitive = false}) {
  if (!existingFolded.contains(foldName(desiredName, caseSensitive))) return desiredName;
  final dot = desiredName.lastIndexOf('.');
  final hasExt = dot > 0 && dot < desiredName.length - 1;
  final base = hasExt ? desiredName.substring(0, dot) : desiredName;
  final ext = hasExt ? desiredName.substring(dot) : '';
  for (var n = 1;; n++) {
    final candidate = '$base ($n)$ext';
    if (!existingFolded.contains(foldName(candidate, caseSensitive))) return candidate;
  }
}

final AppLocalizationsEn _english = AppLocalizationsEn();

/// Why [name] cannot be created under the rule set [fsType], one English sentence per problem; empty when it
/// can. [fsType] is `encryptedVault` for a folder vault and `unknownConservative` for a disk-image container
/// (Android's `FilesystemNameValidator.kindFor`); `null` skips the check.
List<String> importNameIssues(String name, FilesystemType? fsType, {required bool isDir}) {
  if (fsType == null) return const <String>[];
  final result = validateEntryName(
    name,
    fsType,
    entryType: isDir ? EntryType.folder : EntryType.file,
    l10n: _english,
  );
  return [for (final issue in result.issues) issue.message];
}

/// One child of a folder being imported.
class ImportChild {
  const ImportChild(this.name, {required this.isDir});
  final String name;
  final bool isDir;
}

/// What to do with one child: import it as [destName], or skip it for [skipReasons].
class ChildImportPlan {
  const ChildImportPlan.importAs(this.sourceName, String this.destName) : skipReasons = const <String>[];
  const ChildImportPlan.skip(this.sourceName, this.skipReasons) : destName = null;

  final String sourceName;

  /// The name to create it under; null when the child is skipped.
  final String? destName;
  final List<String> skipReasons;

  bool get isSkipped => destName == null;
}

/// Plans the children of one imported folder, in order (the walk in ImportExportHandlers.importEntryRecursive):
///
///  * a child whose name the destination cannot hold is skipped, with the reasons;
///  * on a destination that treats "Notes" and "notes" as one name ([caseSensitive] false), a child whose name
///    collides with an earlier sibling is imported under a unique name ("notes (1)") instead of silently
///    replacing it. The unique name avoids every source sibling and everything in [existingFolded] (names the
///    folder already holds, folded to lower case).
List<ChildImportPlan> planChildImports(
  List<ImportChild> children, {
  required FilesystemType? fsType,
  required bool caseSensitive,
  Set<String> existingFolded = const <String>{},
}) {
  final plans = <ChildImportPlan>[];
  final claimed = <String>{};
  Set<String>? taken;
  for (final child in children) {
    final issues = importNameIssues(child.name, fsType, isDir: child.isDir);
    if (issues.isNotEmpty) {
      plans.add(ChildImportPlan.skip(child.name, issues));
      continue;
    }
    var destName = child.name;
    if (!caseSensitive && !claimed.add(child.name.toLowerCase())) {
      final names = taken ??= <String>{
        for (final c in children) c.name.toLowerCase(),
        ...existingFolded,
      };
      destName = uniqueNameAgainst(names, child.name, caseSensitive: false);
      names.add(destName.toLowerCase());
      claimed.add(destName.toLowerCase());
    }
    plans.add(ChildImportPlan.importAs(child.name, destName));
  }
  return plans;
}

/// True when both digests are the same length and hold the same bytes.
bool digestsEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
