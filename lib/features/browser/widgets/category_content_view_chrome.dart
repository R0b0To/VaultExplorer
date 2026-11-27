part of 'category_content_view.dart';

/// The breadcrumb path and subtitle widgets and the toolbar and settings hooks.
///
/// Moved out of [_CategoryContentViewState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _CategoryChrome on _CategoryContentViewState {
  /// Builds breadcrumb steps linking segments to locations.
  List<_CategoryPathStep> _buildPathSteps(
    CategoryLocation location, [
    AppLocalizations? l10n,
  ]) {
    final effectiveL10n = l10n ?? (mounted ? context.l10n : null);
    final topLocation = _snapshot.contributingSources.length == 1
        ? CategoryLocation(_snapshot.contributingSources.first, '')
        : CategoryLocation.top;

    final rootLabel = _scoped
        ? widget.scopedContainer!.displayName
        : (effectiveL10n != null
              ? widget.category.label(effectiveL10n)
              : widget.category.storageKey);

    final steps = <_CategoryPathStep>[
      _CategoryPathStep(
        segment: PathSegment(rootLabel, ''),
        location: topLocation,
      ),
    ];
    if (location.volId == null) return steps;

    final multipleSources = _snapshot.contributingSources.length > 1;
    final source = _sources[location.volId];
    if (source != null && multipleSources) {
      steps.add(
        _CategoryPathStep(
          segment: PathSegment(source.label, source.label),
          location: CategoryLocation(location.volId, ''),
        ),
      );
    }

    if (location.dirPath.isNotEmpty) {
      final parts = location.dirPath.split('/');
      var accumulated = '';
      for (final part in parts) {
        accumulated = accumulated.isEmpty ? part : '$accumulated/$part';
        final fat = multipleSources && source != null
            ? '${source.label}/$accumulated'
            : accumulated;
        steps.add(
          _CategoryPathStep(
            segment: PathSegment(part, fat),
            location: CategoryLocation(location.volId, accumulated),
          ),
        );
      }
    }

    return steps;
  }

  List<PathSegment> _buildPathStack(
    CategoryLocation location, [
    AppLocalizations? l10n,
  ]) {
    return _buildPathSteps(location, l10n).map((s) => s.segment).toList();
  }

  String _buildLeftTruncatedPath(
    String rootName,
    List<PathSegment> stack,
    double maxWidth,
    TextStyle style,
  ) {
    if (stack.length == 1) return rootName;
    final allLabels = [rootName, ...stack.sublist(1).map((s) => s.label)];
    final fullPath = allLabels.join('/');
    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    if (measure(fullPath) <= maxWidth) {
      return fullPath;
    }
    int low = 0;
    int high = fullPath.length - 1;
    int bestK = fullPath.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final candidate = '…${fullPath.substring(mid)}';
      if (measure(candidate) <= maxWidth) {
        bestK = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return '…${fullPath.substring(bestK)}';
  }

  String _buildStatsSubtitle(
    List<CategoryEntry> items,
    List<MountedContainer> mountedVaults, [
    AppLocalizations? l10n,
  ]) {
    final effectiveL10n = l10n ?? (mounted ? context.l10n : null);
    if (effectiveL10n == null) return '';
    final sourceOrCategory = _scoped
        ? widget.category.label(effectiveL10n)
        : _sourceLabel(mountedVaults, effectiveL10n);
    if (_folderMode) {
      final dirCount = items.where((e) => e.isDir).length;
      final fileCount = items.where((e) => !e.isDir).length;
      final parts = <String>[];
      if (dirCount > 0) parts.add(effectiveL10n.statsFolderCount(dirCount));
      parts.add(effectiveL10n.statsFileCount(fileCount));
      parts.add(sourceOrCategory);
      return parts.join(' · ');
    }
    return '${effectiveL10n.statsFileCount(items.length)} · $sourceOrCategory';
  }

  void _updateToolbarConfig(
    FileManagerToolbarConfig Function(FileManagerToolbarConfig) update,
  ) {
    final current = ref.read(fileManagerToolbarSettingsProvider(null)).config;
    final updated = update(current);
    ref.read(fileManagerToolbarServiceProvider).save(updated);
    ref
        .read(fileManagerToolbarSettingsProvider(null).notifier)
        .applyImportedConfig(updated);
  }

  Future<void> _openFileManagerSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SkinAreaScope(
          area: SkinArea.settings,
          child: FileManagerToolbarSettingsScreen(),
        ),
      ),
    );
  }
}
