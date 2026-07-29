import 'filesystem_type.dart';
import 'name_validation.dart';

/// The outcome of [PathComponents.validateAndBuild]: either a joined path
/// string built only from components that all passed validation, or the
/// full list of issues found (which may span multiple components).
sealed class PathBuildResult {
  const PathBuildResult();
}

class PathBuildSuccess extends PathBuildResult {
  final String path;
  const PathBuildSuccess(this.path);
}

class PathBuildFailure extends PathBuildResult {
  /// Every issue found, across every component and the full-path length
  /// check — not just the first. Order matches [PathComponents.parentSegments]
  /// followed by the final name, so a UI can map issues back to "this is
  /// wrong about the third folder in the path" if it ever needs to.
  final List<NameValidationIssue> issues;
  const PathBuildFailure(this.issues);
}

/// A filesystem path decomposed into the pieces that must never be
/// conflated: the already-existing parent directory (as separate path
/// segments — each already exists on the volume, having been accepted by
/// the real filesystem whenever it was created), the new leaf [name] being
/// created or renamed to, and its [EntryType].
///
/// This is the *only* sanctioned way to produce a joined path string for a
/// create/rename call in the call sites this change touches
/// (browser_dialogs.dart, vault_item_edit_screen.dart) — see
/// docs/architecture.md ADR-002, ownership rule #5. The plain string
/// interpolation this replaces (`'$currentDirPath/$name'`) could join an
/// unvalidated [name] straight into a path with no check at all; this type
/// makes that impossible by construction, since [PathBuildSuccess.path]
/// only exists once [validateAndBuild] has validated [name] and the
/// resulting total path length.
class PathComponents {
  final List<String> parentSegments;
  final String name;
  final EntryType type;
  final FilesystemType fsType;

  const PathComponents({
    required this.parentSegments,
    required this.name,
    required this.type,
    required this.fsType,
  });

  /// Validates the leaf [name] and the resulting total path length, then
  /// joins [parentSegments] and [name] with `/`. Returns [PathBuildFailure]
  /// with the complete list of problems if anything fails — never a
  /// partially-corrected path.
  ///
  /// [parentSegments] are deliberately *not* re-validated character-by-
  /// character here: they already exist on the volume, having been legal
  /// under whichever rules applied when each was created (which may
  /// predate this validator, or belong to a filesystem the app can only
  /// approximate — see [FilesystemType.unknownConservative]). Re-checking
  /// them against [fsType] now could spuriously block an otherwise-valid
  /// operation on a folder whose own name is fine on the real volume but
  /// happens not to fit this conservative approximation of it. Only [name]
  /// — the one thing actually being typed right now — is validated.
  PathBuildResult validateAndBuild() {
    final nameResult = validateEntryName(name, fsType, entryType: type);
    if (nameResult.issues.isNotEmpty) return PathBuildFailure(nameResult.issues);

    final allSegments = [...parentSegments, name];
    final path = allSegments.join('/');

    final rules = FilesystemRules.of(fsType);
    if (path.length > rules.maxPathLength) {
      return PathBuildFailure([
        NameValidationIssue(
          reason: NameValidationReason.componentTooLong,
          message: 'The full path is ${path.length} characters long; '
              '${fsType.label} allows at most ${rules.maxPathLength}.',
        ),
      ]);
    }

    return PathBuildSuccess(path);
  }
}
