import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart' show AppBannerTone;
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta_parser.dart';

import 'image_metadata_editor.dart';
import 'metadata_edit_logic.dart';
import 'metadata_edit_providers.dart';
import 'metadata_edit_service.dart';

/// One file the metadata actions work on.
class MetadataEditTarget {
  const MetadataEditTarget({
    required this.container,
    required this.path,
    required this.sizeBytes,
    required this.modifiedSecs,
  });

  final MountedContainer container;
  final String path;
  final int sizeBytes;
  final int modifiedSecs;

  String get name => path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;

  /// Whether tags, dates and removal can be written into the file itself.
  bool get canEditEmbedded => ImageMetadataEditor.canEdit(name);
}

/// Opens the "Edit metadata" menu for [targets]: edit tags, edit date and
/// time, remove metadata. [onChanged] gets the files that were rewritten, so
/// the caller can refresh what it shows (and forget cached metadata).
Future<void> showMetadataEditMenu(
  BuildContext context,
  WidgetRef ref,
  List<MetadataEditTarget> targets, {
  void Function(List<MetadataEditTarget> changed)? onChanged,
}) async {
  if (targets.isEmpty) return;
  if (targets.every((t) => t.container.readOnly)) {
    showAppSnackBar(context, message: context.l10n.metadataReadOnlyMessage, tone: AppBannerTone.warning);
    return;
  }
  final l10n = context.l10n;
  final choice = await showModalBottomSheet<_MenuChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: Text(l10n.editTagsAction),
            onTap: () => Navigator.pop(sheetContext, _MenuChoice.tags),
          ),
          ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: Text(l10n.editDateTimeAction),
            onTap: () => Navigator.pop(sheetContext, _MenuChoice.date),
          ),
          ListTile(
            leading: const Icon(Icons.layers_clear_outlined),
            title: Text(l10n.removeMetadataAction),
            onTap: () => Navigator.pop(sheetContext, _MenuChoice.strip),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Text(
              l10n.metadataFormatsNote,
              style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _MenuChoice.tags:
      await _editTags(context, ref, targets, onChanged);
    case _MenuChoice.date:
      await _editDate(context, ref, targets, onChanged);
    case _MenuChoice.strip:
      await _removeMetadata(context, ref, targets, onChanged);
  }
}

enum _MenuChoice { tags, date, strip }

enum _Step { changed, unchanged, skipped, failed }

// ── Tags ───────────────────────────────────────────────────────────────────

Future<List<String>> _readKeywords(MetadataEditService service, MetadataEditTarget t) async {
  if (!t.canEditEmbedded || t.sizeBytes <= 0) return const [];
  try {
    final source = await service.openSource(t.container, t.path);
    if (source == null) return const [];
    final header = await source.read(0, GalleryMetaParser.headerBytes);
    return GalleryMetaParser.parse(header).tags;
  } on Object {
    // A file that cannot be read has no tags to show; the edit itself
    // reports the failure.
    return const [];
  }
}

Future<void> _editTags(
  BuildContext context,
  WidgetRef ref,
  List<MetadataEditTarget> targets,
  void Function(List<MetadataEditTarget>)? onChanged,
) async {
  final service = ref.read(metadataEditServiceProvider);
  final editable = [
    for (final t in targets)
      if (t.canEditEmbedded && !t.container.readOnly) t,
  ];
  final existing = <String, List<String>>{};
  final result = await showDialog<_TagsResult>(
    context: context,
    builder: (_) => _TagsDialog(
      targets: editable,
      load: (t) async => existing[t.path] = await _readKeywords(service, t),
    ),
  );
  if (result == null || !context.mounted) return;
  await _runBatch(context, targets, onChanged, (t) async {
    if (!t.canEditEmbedded) return _Step.skipped;
    final before = existing[t.path] ?? await _readKeywords(service, t);
    final after = mergeKeywords(before, result.add, result.remove);
    if (_sameList(before, after)) return _Step.unchanged;
    final outcome = await service.apply(
      t.container,
      t.path,
      MetadataEdit(keywords: after),
      keepModifiedSecs: t.modifiedSecs,
    );
    return _stepOf(outcome);
  });
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

_Step _stepOf(MetadataEditOutcome o) => switch (o.status) {
  MetadataEditStatus.changed => _Step.changed,
  MetadataEditStatus.unchanged => _Step.unchanged,
  MetadataEditStatus.unsupported || MetadataEditStatus.readOnly => _Step.skipped,
  MetadataEditStatus.failed => _Step.failed,
};

class _TagsResult {
  const _TagsResult(this.add, this.remove);
  final Set<String> add;
  final Set<String> remove;
}

class _TagsDialog extends StatefulWidget {
  const _TagsDialog({required this.targets, required this.load});

  final List<MetadataEditTarget> targets;
  final Future<List<String>> Function(MetadataEditTarget) load;

  @override
  State<_TagsDialog> createState() => _TagsDialogState();
}

class _TagsDialogState extends State<_TagsDialog> {
  final _input = TextEditingController();
  bool _loading = true;

  /// What the files already carry: lower-case key to (spelling, files).
  final Map<String, ({String tag, int files})> _existing = {};
  final Set<String> _removed = {};
  final List<String> _added = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
  }

  Future<void> _loadAll() async {
    for (var i = 0; i < widget.targets.length; i += 4) {
      final batch = widget.targets.skip(i).take(4);
      final lists = await Future.wait(batch.map(widget.load));
      for (final tags in lists) {
        final seen = <String>{};
        for (final t in tags) {
          final k = t.toLowerCase();
          if (!seen.add(k)) continue;
          final cur = _existing[k];
          _existing[k] = (tag: cur?.tag ?? t, files: (cur?.files ?? 0) + 1);
        }
      }
      if (!mounted) return;
      setState(() {});
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _commitInput() {
    var changed = false;
    for (final raw in _input.text.split(',')) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      final k = t.toLowerCase();
      if (_existing.containsKey(k)) {
        // Typing a tag the files already have brings back a removed one.
        changed = _removed.remove(_existing[k]!.tag) || changed;
      } else if (!_added.any((a) => a.toLowerCase() == k)) {
        _added.add(t);
        changed = true;
      }
    }
    _input.clear();
    if (changed) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final multi = widget.targets.length > 1;
    final shown = [
      for (final e in _existing.values)
        if (!_removed.contains(e.tag)) e,
    ]..sort((a, b) => a.tag.toLowerCase().compareTo(b.tag.toLowerCase()));
    final dirty = _added.isNotEmpty || _removed.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.editTagsAction),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _input,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: l10n.tagsAddHint,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_rounded),
                    onPressed: _commitInput,
                  ),
                ),
                onSubmitted: (_) => _commitInput(),
              ),
              const SizedBox(height: 12),
              if (_loading) const LinearProgressIndicator(),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final a in _added)
                    InputChip(
                      label: Text(a),
                      avatar: const Icon(Icons.add_rounded, size: 16),
                      onDeleted: () => setState(() => _added.remove(a)),
                    ),
                  for (final e in shown)
                    InputChip(
                      label: Text(multi ? '${e.tag} · ${e.files}/${widget.targets.length}' : e.tag),
                      onDeleted: () => setState(() => _removed.add(e.tag)),
                    ),
                ],
              ),
              if (!_loading && shown.isEmpty && _added.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l10n.tagsNoneYet),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: dirty || _input.text.trim().isNotEmpty
              ? () {
                  _commitInput();
                  Navigator.pop(context, _TagsResult(_added.toSet(), _removed.toSet()));
                }
              : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

// ── Date and time ──────────────────────────────────────────────────────────

enum _DateMode { set, shift, fromModified, fromName }

class _DateChoice {
  const _DateChoice(this.mode, {this.wall, this.shift, required this.alsoSetModified});
  final _DateMode mode;
  final DateTime? wall;
  final Duration? shift;
  final bool alsoSetModified;
}

Future<void> _editDate(
  BuildContext context,
  WidgetRef ref,
  List<MetadataEditTarget> targets,
  void Function(List<MetadataEditTarget>)? onChanged,
) async {
  final service = ref.read(metadataEditServiceProvider);
  final choice = await showDialog<_DateChoice>(
    context: context,
    builder: (_) => _DateDialog(targets: targets),
  );
  if (choice == null || !context.mounted) return;

  await _runBatch(context, targets, onChanged, (t) async {
    if (t.container.readOnly) return _Step.skipped;
    DateTime? wall;
    switch (choice.mode) {
      case _DateMode.set:
        wall = choice.wall;
      case _DateMode.fromModified:
        wall = wallClockOfEpochSecs(t.modifiedSecs);
      case _DateMode.fromName:
        wall = dateFromFileName(t.name);
      case _DateMode.shift:
        var base = wallClockOfEpochSecs(t.modifiedSecs);
        if (t.canEditEmbedded && t.sizeBytes > 0) {
          final source = await service.openSource(t.container, t.path);
          if (source != null) {
            final taken = GalleryMetaParser.parse(await source.read(0, GalleryMetaParser.headerBytes)).takenWallClock;
            if (taken != null) base = taken;
          }
        }
        wall = shiftWallClock(base, choice.shift ?? Duration.zero);
    }
    if (wall == null) return _Step.skipped;

    final modified = epochSecsOfWallClock(wall);
    if (!t.canEditEmbedded) {
      // Videos, HEIC and the like have no dates this app can write into the
      // file, so the file's own modified date is what changes.
      final ok = await service.setModifiedTime(t.container, t.path, modified);
      return ok ? _Step.changed : _Step.failed;
    }
    final setModified = choice.alsoSetModified && choice.mode != _DateMode.fromModified;
    final outcome = await service.apply(
      t.container,
      t.path,
      MetadataEdit(takenWallClock: wall),
      keepModifiedSecs: t.modifiedSecs,
      newModifiedSecs: setModified ? modified : null,
    );
    return _stepOf(outcome);
  });
}

class _DateDialog extends StatefulWidget {
  const _DateDialog({required this.targets});
  final List<MetadataEditTarget> targets;

  @override
  State<_DateDialog> createState() => _DateDialogState();
}

class _DateDialogState extends State<_DateDialog> {
  _DateMode _mode = _DateMode.set;
  late DateTime _date;
  late TimeOfDay _time;
  bool _alsoModified = true;
  bool _later = true;
  final _days = TextEditingController(text: '0');
  final _hours = TextEditingController(text: '0');
  final _minutes = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    final first = wallClockOfEpochSecs(widget.targets.first.modifiedSecs);
    _date = DateTime(first.year, first.month, first.day);
    _time = TimeOfDay(hour: first.hour, minute: first.minute);
  }

  @override
  void dispose() {
    _days.dispose();
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Duration get _shift {
    int n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
    final d = Duration(days: n(_days), hours: n(_hours), minutes: n(_minutes));
    return _later ? d : -d;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loc = MaterialLocalizations.of(context);
    final modes = {
      _DateMode.set: l10n.dateModeSet,
      _DateMode.shift: l10n.dateModeShift,
      _DateMode.fromModified: l10n.dateModeFromModified,
      _DateMode.fromName: l10n.dateModeFromName,
    };
    final matches = widget.targets.where((t) => dateFromFileName(t.name) != null).length;
    final canApply = switch (_mode) {
      _DateMode.fromName => matches > 0,
      _DateMode.shift => _shift != Duration.zero,
      _ => true,
    };
    return AlertDialog(
      title: Text(l10n.editDateTimeAction),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final e in modes.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _mode == e.key,
                      onSelected: (_) => setState(() => _mode = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_mode == _DateMode.set) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_rounded),
                  title: Text(loc.formatMediumDate(_date)),
                  onTap: _pickDate,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time_rounded),
                  title: Text(loc.formatTimeOfDay(_time)),
                  onTap: _pickTime,
                ),
              ],
              if (_mode == _DateMode.shift) ...[
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: true, label: Text(l10n.dateShiftLater)),
                    ButtonSegment(value: false, label: Text(l10n.dateShiftEarlier)),
                  ],
                  selected: {_later},
                  onSelectionChanged: (s) => setState(() => _later = s.first),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final f in [
                      (_days, l10n.dateDaysLabel),
                      (_hours, l10n.dateHoursLabel),
                      (_minutes, l10n.dateMinutesLabel),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: TextField(
                            controller: f.$1,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: f.$2),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (_mode == _DateMode.fromName)
                Text(l10n.dateFromNameMatches(matches, widget.targets.length)),
              if (_mode != _DateMode.fromModified)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.dateAlsoSetModified),
                  value: _alsoModified,
                  onChanged: (v) => setState(() => _alsoModified = v),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: canApply
              ? () => Navigator.pop(
                  context,
                  _DateChoice(
                    _mode,
                    wall: DateTime.utc(_date.year, _date.month, _date.day, _time.hour, _time.minute),
                    shift: _shift,
                    alsoSetModified: _alsoModified,
                  ),
                )
              : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

// ── Remove metadata ────────────────────────────────────────────────────────

Future<void> _removeMetadata(
  BuildContext context,
  WidgetRef ref,
  List<MetadataEditTarget> targets,
  void Function(List<MetadataEditTarget>)? onChanged,
) async {
  final service = ref.read(metadataEditServiceProvider);
  final choice = await showDialog<({Set<MetadataKind> kinds, bool keepOrientation})>(
    context: context,
    builder: (_) => const _StripDialog(),
  );
  if (choice == null || !context.mounted) return;
  await _runBatch(context, targets, onChanged, (t) async {
    if (!t.canEditEmbedded) return _Step.skipped;
    final outcome = await service.apply(
      t.container,
      t.path,
      MetadataEdit(strip: choice.kinds, keepOrientation: choice.keepOrientation),
      keepModifiedSecs: t.modifiedSecs,
    );
    return _stepOf(outcome);
  });
}

class _StripDialog extends StatefulWidget {
  const _StripDialog();

  @override
  State<_StripDialog> createState() => _StripDialogState();
}

class _StripDialogState extends State<_StripDialog> {
  // The colour profile is left out by default: removing it can change how
  // the colours of a wide-gamut photo look.
  final Set<MetadataKind> _kinds = {
    MetadataKind.exif,
    MetadataKind.xmp,
    MetadataKind.iptc,
    MetadataKind.comment,
  };
  bool _keepOrientation = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = {
      MetadataKind.exif: l10n.stripExifLabel,
      MetadataKind.xmp: l10n.stripXmpLabel,
      MetadataKind.iptc: l10n.stripIptcLabel,
      MetadataKind.comment: l10n.stripCommentsLabel,
      MetadataKind.iccProfile: l10n.stripIccLabel,
    };
    return AlertDialog(
      title: Text(l10n.removeMetadataAction),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in labels.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: _kinds.contains(e.key),
                  onChanged: (v) => setState(() => v == true ? _kinds.add(e.key) : _kinds.remove(e.key)),
                ),
              if (_kinds.contains(MetadataKind.exif))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.stripKeepOrientationLabel),
                  subtitle: Text(l10n.stripKeepOrientationDesc),
                  value: _keepOrientation,
                  onChanged: (v) => setState(() => _keepOrientation = v),
                ),
              const SizedBox(height: 8),
              Text(
                l10n.stripWarning,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          onPressed: _kinds.isEmpty
              ? null
              : () => Navigator.pop(context, (kinds: Set.of(_kinds), keepOrientation: _keepOrientation)),
          child: Text(l10n.remove),
        ),
      ],
    );
  }
}

// ── Running a batch ────────────────────────────────────────────────────────

/// Runs [step] on every target one after another behind a progress dialog the
/// person can cancel, then reports what happened.
Future<void> _runBatch(
  BuildContext context,
  List<MetadataEditTarget> targets,
  void Function(List<MetadataEditTarget>)? onChanged,
  Future<_Step> Function(MetadataEditTarget) step,
) async {
  final progress = ValueNotifier<int>(0);
  var cancelled = false;
  final navigator = Navigator.of(context, rootNavigator: true);
  final outer = context;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (_, done, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dialogContext.l10n.metadataProgress(done, targets.length)),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: targets.isEmpty ? null : done / targets.length),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => cancelled = true,
              child: Text(dialogContext.l10n.cancel),
            ),
          ],
        ),
      ),
    ),
  );

  final changed = <MetadataEditTarget>[];
  var unchanged = 0;
  var skipped = 0;
  var failed = 0;
  for (final t in targets) {
    if (cancelled) break;
    _Step result;
    try {
      result = await step(t);
    } on Object {
      // One damaged file must not stop the rest of the batch.
      result = _Step.failed;
    }
    switch (result) {
      case _Step.changed:
        changed.add(t);
      case _Step.unchanged:
        unchanged++;
      case _Step.skipped:
        skipped++;
      case _Step.failed:
        failed++;
    }
    progress.value++;
  }
  progress.dispose();
  if (navigator.canPop()) navigator.pop();

  if (changed.isNotEmpty) onChanged?.call(changed);
  if (!outer.mounted) return;
  final l10n = outer.l10n;
  final parts = <String>[
    if (changed.isNotEmpty) l10n.metadataResultUpdated(changed.length),
    if (changed.isEmpty && unchanged > 0) l10n.metadataResultUnchanged,
    if (skipped > 0) l10n.metadataResultSkipped(skipped),
    if (failed > 0) l10n.metadataResultFailed(failed),
  ];
  showAppSnackBar(
    outer,
    message: parts.join(' · '),
    tone: failed > 0
        ? AppBannerTone.error
        : (changed.isNotEmpty ? AppBannerTone.success : AppBannerTone.info),
  );
}
