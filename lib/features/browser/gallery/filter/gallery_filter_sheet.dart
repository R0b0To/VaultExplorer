import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

import 'gallery_facets.dart';
import 'gallery_filter_controller.dart';
import 'gallery_filter_l10n.dart';
import 'gallery_filter_labels.dart';
import 'gallery_filters.dart';
import 'gallery_grouping.dart';
import 'gallery_meta_index.dart';

/// Opens the gallery filter: choose what to show (by type, date, tag, place,
/// camera, orientation, rating, size, folder, or what is missing) and how to
/// section it.
///
/// [subjects] is called whenever the sheet needs the files to count (the
/// whole gallery, before filtering); [visibleCount] is how many the current
/// filters leave.
Future<void> showGalleryFilterSheet(
  BuildContext context, {
  required GalleryFilterController controller,
  required GalleryMetaIndex index,
  required List<GalleryFilterSubject> Function() subjects,
  required int Function() visibleCount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => GalleryFilterSheet(
        controller: controller,
        index: index,
        subjects: subjects,
        visibleCount: visibleCount,
        scrollController: scroll,
      ),
    ),
  );
}

class GalleryFilterSheet extends StatefulWidget {
  const GalleryFilterSheet({
    super.key,
    required this.controller,
    required this.index,
    required this.subjects,
    required this.visibleCount,
    required this.scrollController,
  });

  final GalleryFilterController controller;
  final GalleryMetaIndex index;
  final List<GalleryFilterSubject> Function() subjects;
  final int Function() visibleCount;
  final ScrollController scrollController;

  @override
  State<GalleryFilterSheet> createState() => _GalleryFilterSheetState();
}

class _GalleryFilterSheetState extends State<GalleryFilterSheet> {
  static const int _collapsedChips = 12;

  final TextEditingController _search = TextEditingController();
  final Set<String> _expanded = {};
  int? _openYear;

  GalleryFacets? _facets;
  int _facetsRevision = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.index.addListener(_changed);
    _search.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.index.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  GalleryFacets get _currentFacets {
    final cached = _facets;
    if (cached != null && _facetsRevision == widget.index.revision) return cached;
    _facetsRevision = widget.index.revision;
    return _facets = GalleryFacets.compute(
      widget.subjects(),
      labels: context.galleryFilterLabels,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facets = _currentFacets;
    final controller = widget.controller;
    final l = context.l10n;
    final labels = context.galleryFilterLabels;
    final needle = _search.text.trim().toLowerCase();
    final visible = widget.visibleCount();

    bool matchesNeedle(GalleryFacet f) =>
        needle.isEmpty || f.filter.label(labels).toLowerCase().contains(needle);

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                controller.hasFilters
                    ? l.galleryFilterShownOfTotal(visible, facets.total)
                    : l.galleryFilterTotal(facets.total),
                style: theme.textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: controller.hasFilters ? controller.clear : null,
              child: Text(l.galleryFilterClear),
            ),
          ],
        ),
      ),
      if (widget.index.isIndexing)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.galleryFilterIndexing(widget.index.done, widget.index.total),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: widget.index.total == 0
                    ? null
                    : widget.index.done / widget.index.total,
              ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: l.galleryFilterSearchHint,
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _search.clear,
                  ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (text) {
            final t = text.trim();
            if (t.isEmpty) return;
            controller.filters = controller.filters.add(GalleryQueryFilter(t));
            _search.clear();
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(
          l.galleryFilterTapHint,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ),
      _groupBySection(theme, l),
      _section(
        'type',
        l.galleryFilterSectionType,
        [for (final f in facets.types) f],
        matchesNeedle,
      ),
      _dateSection(facets, matchesNeedle),
      _section('tag', l.galleryFilterSectionTags, facets.tags.where(matchesNeedle).toList(), (_) => true),
      _section('place', l.galleryFilterSectionPlaces, facets.places.where(matchesNeedle).toList(), (_) => true,
          tooltip: (f) => galleryPlaceHint(f.filter as GalleryPlaceFilter, labels)),
      _section('camera', l.galleryFilterSectionCameras, facets.cameras.where(matchesNeedle).toList(), (_) => true),
      _section('orientation', l.galleryFilterSectionOrientation, facets.orientations, matchesNeedle),
      _section('rating', l.galleryFilterSectionRating, facets.ratings, matchesNeedle),
      _section('size', l.galleryFilterSectionSize, facets.sizes, matchesNeedle),
      _section('folder', l.galleryFilterSectionFolders, facets.folders.where(matchesNeedle).toList(), (_) => true,
          tooltip: (f) {
        final p = (f.filter as GalleryFolderFilter).path;
        return p.isEmpty ? '/' : p;
      }),
      _section('missing', l.galleryFilterSectionMissing, facets.missing, matchesNeedle),
      const SizedBox(height: 24),
    ];

    return ListView(controller: widget.scrollController, children: children);
  }

  Widget _groupBySection(ThemeData theme, AppLocalizations l) {
    final controller = widget.controller;
    final labels = {
      GalleryGroupBy.none: l.galleryGroupNone,
      GalleryGroupBy.day: l.galleryGroupDay,
      GalleryGroupBy.month: l.galleryGroupMonth,
      GalleryGroupBy.year: l.galleryGroupYear,
      GalleryGroupBy.folder: l.galleryGroupFolder,
      GalleryGroupBy.type: l.galleryGroupType,
      GalleryGroupBy.place: l.galleryGroupPlace,
      GalleryGroupBy.camera: l.galleryGroupCamera,
    };
    return _titled(
      l.galleryFilterGroupBy,
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final g in GalleryGroupBy.values)
            ChoiceChip(
              label: Text(labels[g]!),
              selected: controller.groupBy == g,
              onSelected: (_) => controller.groupBy = g,
            ),
        ],
      ),
    );
  }

  Widget _dateSection(GalleryFacets facets, bool Function(GalleryFacet) matchesNeedle) {
    if (facets.years.isEmpty) return const SizedBox.shrink();
    final years = facets.years.where(matchesNeedle).toList();
    final set = widget.controller.filters;
    // Open the months of a selected year automatically.
    final selectedYear = _openYear ??
        [
          for (final f in facets.years)
            if (set.includes(f.filter)) (f.filter as GalleryDateFilter).year,
        ].firstOrNull;
    final months = selectedYear == null ? const <GalleryFacet>[] : (facets.monthsByYear[selectedYear] ?? const []);
    return _titled(
      context.l10n.galleryFilterSectionDate,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chips('year', years),
          if (months.isNotEmpty) ...[
            const SizedBox(height: 8),
            _chips('month', months),
          ],
        ],
      ),
    );
  }

  Widget _section(
    String id,
    String title,
    List<GalleryFacet> facets,
    bool Function(GalleryFacet) keep, {
    String Function(GalleryFacet)? tooltip,
  }) {
    final shown = facets.where(keep).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return _titled(title, _chips(id, shown, tooltip: tooltip));
  }

  Widget _titled(String title, Widget child) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );

  Widget _chips(String id, List<GalleryFacet> facets, {String Function(GalleryFacet)? tooltip}) {
    final controller = widget.controller;
    final set = controller.filters;
    final labels = context.galleryFilterLabels;
    final l = context.l10n;
    final all = _expanded.contains(id);
    final limited = !all && facets.length > _collapsedChips;
    // Selected chips are always shown, even beyond the collapsed limit.
    final list = limited
        ? [
            ...facets.take(_collapsedChips),
            ...facets.skip(_collapsedChips).where((f) => set.contains(f.filter) || set.excludes(f.filter)),
          ]
        : facets;
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final f in list)
          Builder(
            builder: (context) {
              final on = set.includes(f.filter);
              final off = set.excludes(f.filter);
              final chip = GestureDetector(
                onLongPress: () => controller.exclude(f.filter),
                child: FilterChip(
                  label: Text(
                    '${f.filter.label(labels)} · ${f.count}',
                    style: off
                        ? TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: scheme.error,
                          )
                        : null,
                  ),
                  selected: on || off,
                  selectedColor: off ? scheme.errorContainer : null,
                  showCheckmark: !off,
                  avatar: off ? Icon(Icons.block_rounded, size: 16, color: scheme.error) : null,
                  onSelected: (_) {
                    if (id == 'year') {
                      setState(() => _openYear = (f.filter as GalleryDateFilter).year);
                    }
                    controller.toggle(f.filter);
                  },
                ),
              );
              final tip = tooltip?.call(f);
              return tip == null ? chip : Tooltip(message: tip, child: chip);
            },
          ),
        if (limited)
          ActionChip(
            label: Text(l.galleryFilterShowAll(facets.length)),
            onPressed: () => setState(() => _expanded.add(id)),
          )
        else if (all && facets.length > _collapsedChips)
          ActionChip(
            label: Text(l.galleryFilterShowFewer),
            onPressed: () => setState(() => _expanded.remove(id)),
          ),
      ],
    );
  }
}

/// The filters in force, as a row of chips under the app bar: tap one to flip
/// it between "only" and "not", its cross to drop it. Also says while photo
/// details are still being read, since filters on tags and places only see
/// what has been read so far.
class GalleryFilterBar extends StatelessWidget {
  const GalleryFilterBar({
    super.key,
    required this.controller,
    required this.index,
    required this.shown,
    required this.total,
    required this.onOpen,
  });

  final GalleryFilterController controller;
  final GalleryMetaIndex index;
  final int shown;
  final int total;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final filters = controller.filters.filters;
    final indexing = index.isIndexing;
    if (filters.isEmpty && !indexing) return const SizedBox.shrink();
    final labels = context.galleryFilterLabels;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (filters.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.filter_list_rounded, size: 18),
                    label: Text('$shown / $total'),
                    onPressed: onOpen,
                  ),
                  for (final f in filters)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: InputChip(
                        label: Text(
                          f.label(labels),
                          style: f.reversed
                              ? TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: scheme.error,
                                )
                              : null,
                        ),
                        avatar: f.reversed
                            ? Icon(Icons.block_rounded, size: 16, color: scheme.error)
                            : null,
                        onPressed: () => controller.filters = controller.filters.flip(f),
                        onDeleted: () => controller.remove(f),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: TextButton(
                      onPressed: controller.clear,
                      child: Text(context.l10n.galleryFilterClear),
                    ),
                  ),
                ],
              ),
            ),
          if (indexing)
            LinearProgressIndicator(
              minHeight: 2,
              value: index.total == 0 ? null : index.done / index.total,
            ),
        ],
      ),
    );
  }
}

@visibleForTesting
String galleryFilterSummary(GalleryFilterSet set, GalleryFilterLabels labels) =>
    set.filters.map((f) => '${f.reversed ? '-' : ''}${f.label(labels)}').join(', ');
