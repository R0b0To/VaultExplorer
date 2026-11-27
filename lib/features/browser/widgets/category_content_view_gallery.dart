part of 'category_content_view.dart';

/// Gallery mode: metadata indexing, subject grouping and the filter button and
/// menu.
///
/// Moved out of [_CategoryContentViewState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _CategoryGallery on _CategoryContentViewState {
  /// Reading the details of every photo costs a read per file, so full filter
  /// metadata is only requested when the filter is opened, a filter or search
  /// is active, or grouping by place or camera is on. Date groups separately
  /// request indexing so their order can use capture dates instead of file
  /// modification times.
  void _markMetaWanted() {
    if (_metaWanted) return;
    _metaWanted = true;
    _scheduleMetaIndexing(
      delay: _galleryFilter.groupBy.isDate ? Duration.zero : null,
    );
    unawaited(_loadPlaces());
  }

  void _scheduleMetaWanted() {
    if (_metaWanted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed) _markMetaWanted();
    });
  }

  void _scheduleMetaIndexing({Duration? delay}) {
    _metaTimer?.cancel();
    _metaTimer = Timer(
      delay ?? const Duration(milliseconds: 400),
      _startMetaIndexing,
    );
  }

  void _startMetaIndexing() {
    if (_disposed || !_isGallery) return;
    // Where a source may keep its index depends on its thumbnail settings; the
    // stored index of one whose settings are still loading would be skipped
    // for the whole session.
    if (_thumbs.values.any((t) => t == null)) {
      _scheduleMetaIndexing();
      return;
    }
    unawaited(_loadMetaIndex());
  }

  GalleryFilterSubject _subjectOf(RawEntry e) {
    final ce = e as CategoryEntry;
    final metaRev = _metaIndex?.publishedRevision ?? 0;
    if (ce.cachedSubjectRevision == metaRev && ce.cachedSubject != null) {
      return ce.cachedSubject! as GalleryFilterSubject;
    }
    final meta =
        _metaIndex?.lookup(
          ce.sourceVolId,
          ce.path,
          ce.sizeBytes,
          ce.modifiedSecs,
        ) ??
        GalleryMeta.empty;
    final subject = GalleryFilterSubject(
      sourceVolId: ce.sourceVolId,
      name: ce.baseName,
      parentPath: ce.parentPath,
      extension: ce.extension,
      sizeBytes: ce.sizeBytes,
      modifiedSecs: ce.modifiedSecs,
      meta: meta,
      placeResolver: _places,
    );
    ce.cachedSubject = subject;
    ce.cachedSubjectRevision = metaRev;
    return subject;
  }

  bool _matchesGallery(
    CategoryEntry e,
    GalleryQueryFilter? query,
    GalleryFilterSet filters,
  ) {
    final subject = _subjectOf(e);
    if (query != null && !query.positive(subject)) return false;
    return filters.matches(subject);
  }

  /// Orders two entries by the date the gallery files them under: when the
  /// photo was taken if its file says so, else its modified date (see
  /// [GalleryFilterSubject.date]). 0 when both are the same moment.
  int _compareByCaptureDate(RawEntry a, RawEntry b) {
    if (a.isDir || b.isDir) return 0;
    final da = _subjectOf(a).date?.millisecondsSinceEpoch ?? 0;
    final db = _subjectOf(b).date?.millisecondsSinceEpoch ?? 0;
    return da.compareTo(db);
  }

  GalleryGrouper _galleryGrouper(GalleryGroupBy by) => GalleryGrouper(
    by: by,
    subjectOf: _subjectOf,
    ascending: _sortBy == SortBy.date && _sortAscending,
    labels: _galleryLabels,
  );

  List<GalleryFilterSubject> _gallerySubjects() => [
    for (final e in flatCategoryListing(
      _snapshot,
      location: _effectiveLocation,
    ))
      _subjectOf(e),
  ];

  void _openGalleryFilter() {
    _markMetaWanted();
    unawaited(
      showGalleryFilterSheet(
        context,
        controller: _galleryFilter,
        index: _meta,
        subjects: _gallerySubjects,
        visibleCount: () => _currentItems().length,
      ),
    );
  }

  Widget _galleryFilterButton(BuildContext context) {
    final active = _galleryFilter.hasFilters;
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        active ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
        color: active ? cs.primary : null,
      ),
      tooltip: context.l10n.galleryFilterTooltip,
      onPressed: _openGalleryFilter,
    );
  }

  List<Widget> _galleryFilterMenuItems(BuildContext menuContext) => [
    MenuItemButton(
      leadingIcon: const Icon(Icons.tune_rounded, size: 18),
      onPressed: _openGalleryFilter,
      child: Text(menuContext.l10n.galleryFilterMenuOpen),
    ),
    if (_galleryFilter.hasFilters)
      MenuItemButton(
        leadingIcon: const Icon(Icons.clear_all_rounded, size: 18),
        onPressed: _galleryFilter.clear,
        child: Text(menuContext.l10n.galleryFilterClearAll),
      ),
  ];
}
