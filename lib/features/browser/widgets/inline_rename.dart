import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/entry_conflict.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/filesystem/path_components.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_pins_bookmarks_controller.dart';

/// Which item of the folder view is being renamed in place, and what to do
/// with the new name. The tile showing that item draws a [InlineRenameField]
/// where its name label would be (see `FileNameLabel`).
class InlineRenameController extends ChangeNotifier {
  RawEntry? _entry;
  List<RawEntry> _existing = const [];
  FilesystemType _fsType = FilesystemType.values.first;
  Future<void> Function(RawEntry entry, String newName)? _onCommit;

  RawEntry? get entry => _entry;
  List<RawEntry> get existing => _existing;
  FilesystemType get fsType => _fsType;

  bool isRenaming(String name) => _entry?.name == name;

  void start(
    RawEntry entry, {
    required List<RawEntry> existing,
    required FilesystemType fsType,
    required Future<void> Function(RawEntry entry, String newName) onCommit,
  }) {
    _entry = entry;
    _existing = existing;
    _fsType = fsType;
    _onCommit = onCommit;
    notifyListeners();
  }

  void stop() {
    if (_entry == null) return;
    _entry = null;
    _onCommit = null;
    notifyListeners();
  }

  Future<void> commit(String newName) async {
    final entry = _entry;
    final callback = _onCommit;
    stop();
    if (entry != null && callback != null) await callback(entry, newName);
  }
}

/// Offers the [InlineRenameController] to the name labels below it.
class InlineRenameScope extends InheritedNotifier<InlineRenameController> {
  const InlineRenameScope({
    super.key,
    required InlineRenameController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, with the caller rebuilding when it changes; null outside
  /// a scope.
  static InlineRenameController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<InlineRenameScope>()
      ?.notifier;
}

/// The text field that stands in for an item's name while it is renamed:
/// Enter or a click elsewhere applies the name, Escape drops it, and a name
/// the filesystem would not take shows a red outline with the reason.
class InlineRenameField extends StatefulWidget {
  const InlineRenameField({super.key, required this.controller, this.style});

  final InlineRenameController controller;
  final TextStyle? style;

  @override
  State<InlineRenameField> createState() => _InlineRenameFieldState();
}

class _InlineRenameFieldState extends State<InlineRenameField> {
  late final RawEntry _entry = widget.controller.entry!;
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();
  final GlobalKey _fieldKey = GlobalKey();
  final DateTime _openedAt = DateTime.now();
  bool _done = false;
  bool _validated = false;
  List<String> _problems = const [];

  @override
  void initState() {
    super.initState();
    final name = _entry.name;
    final dot = _entry.isDir ? -1 : name.lastIndexOf('.');
    _text = TextEditingController.fromValue(
      TextEditingValue(
        text: name,
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: dot > 0 ? dot : name.length,
        ),
      ),
    );
    _focus.addListener(_onFocusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_done) _focus.requestFocus();
    });
    // A menu that was open a moment ago may hand focus back as it closes.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted && !_done && !_focus.hasFocus) _focus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_validated) {
      _validated = true;
      _problems = _check(_text.text);
    }
  }

  @override
  void dispose() {
    _done = true;
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  List<String> _check(String text) {
    final c = widget.controller;
    final type = _entry.isDir ? EntryType.folder : EntryType.file;
    final result = validateEntryName(
      text,
      c.fsType,
      entryType: type,
      l10n: context.l10n,
    );
    final conflict = text.isEmpty
        ? const EntryConflictResult(EntryConflictKind.none, null)
        : checkEntryConflict(
            candidateName: text,
            candidateIsDir: _entry.isDir,
            existingEntries: c.existing,
            caseSensitive: FilesystemRules.of(c.fsType).caseSensitive,
            excluding: _entry,
          );
    return [
      ...result.issues.map((i) => i.message),
      if (conflict.isConflict) conflict.message(context.l10n, text)!,
    ];
  }

  bool get _changed => _text.text != _entry.name;
  bool get _valid => _text.text.isNotEmpty && _problems.isEmpty;

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.controller.stop();
  }

  void _apply() {
    if (_done) return;
    if (!_changed) return _cancel();
    if (!_valid) return;
    _done = true;
    unawaited(widget.controller.commit(_text.text));
  }

  void _onFocusChanged() {
    if (_focus.hasFocus || _done) return;
    // Focus that moves away right after opening is the menu closing, not the
    // user clicking elsewhere.
    if (DateTime.now().difference(_openedAt) <
        const Duration(milliseconds: 400)) {
      return;
    }
    // Clicking away applies a good new name and otherwise leaves the old one.
    if (_changed && _valid) {
      _apply();
    } else {
      _cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final invalid = _problems.isNotEmpty;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: invalid ? cs.error : cs.primary, width: 1.5),
    );
    final field = TextField(
      key: _fieldKey,
      controller: _text,
      focusNode: _focus,
      style: widget.style,
      maxLines: 1,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: cs.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        enabledBorder: border,
        focusedBorder: border,
      ),
      onChanged: (text) => setState(() => _problems = _check(text)),
      onSubmitted: (_) => _apply(),
    );
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: invalid
          ? Tooltip(message: _problems.join('\n'), child: field)
          : field,
    );
  }
}

/// Renames [oldEntry] to [newName] inside [currentDirPath], as the rename
/// dialog does for one item: a failure shows a message. Returns whether the
/// rename happened.
Future<bool> renameEntryInline({
  required WidgetRef ref,
  required BuildContext context,
  required MountedContainer container,
  required RawEntry oldEntry,
  required String newName,
  required String currentDirPath,
}) async {
  final l10n = context.l10n;
  final api = ref.read(vaultFileIoApiProvider);
  final opService = ref.read(fileOperationServiceProvider);
  final marks = ref.read(
    fileBrowserPinsBookmarksProvider(container.volId).notifier,
  );
  final oldName = oldEntry.name;
  if (newName == oldName) return false;
  final built = PathComponents(
    parentSegments: currentDirPath.isEmpty
        ? <String>[]
        : currentDirPath.split('/'),
    name: newName,
    type: oldEntry.isDir ? EntryType.folder : EntryType.file,
    fsType: resolveFilesystemType(container),
  ).validateAndBuild(l10n);
  if (built is! PathBuildSuccess) return false;
  final oldFull = currentDirPath.isEmpty ? oldName : '$currentDirPath/$oldName';
  final ok = await api.renameFile(container, oldFull, built.path);
  if (ok) {
    opService.notifyVolumeContentChanged(container.volId);
    // Bookmarks and pins on the entry (or inside a renamed folder) follow.
    unawaited(marks.remapPaths(container, {oldFull: built.path}));
  } else if (context.mounted) {
    showAppSnackBar(
      context,
      message: l10n.couldntRenameSingle(oldName),
      tone: AppBannerTone.error,
    );
  }
  return ok;
}
