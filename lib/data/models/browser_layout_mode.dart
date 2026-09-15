/// Represents the layout arrangement used inside the file browser.
enum BrowserLayoutMode {
  /// Full-width rows with metadata (date/size/type) right-aligned in
  /// columns on a single line per item. Labelled "Columned list" in the UI
  /// -- was called "Detailed list" before [detailed] was introduced.
  list,

  /// Two-row rows: the filename on its own line, with date and size shown
  /// together on a second line underneath instead of in aligned columns.
  /// Labelled "Detailed list" in the UI.
  detailed,

  /// Compact rows optimized for high information density.
  compact,

  /// Multi-column grid optimized for visual media or galleries.
  grid,

  /// Variable-height, Pinterest-style multi-column layout for galleries.
  masonry;

  // ── Human-readable labels ─────────────────────────────────────────────────

  String get label {
    switch (this) {
      case BrowserLayoutMode.list:
        return 'Columned list';
      case BrowserLayoutMode.detailed:
        return 'Detailed list';
      case BrowserLayoutMode.compact:
        return 'Compact list';
      case BrowserLayoutMode.grid:
        return 'Gallery grid';
      case BrowserLayoutMode.masonry:
        return 'Masonry';
    }
  }

  String get description {
    switch (this) {
      case BrowserLayoutMode.list:
        return 'Shows files and folders in a single-row list with sizes and modification dates aligned in columns.';
      case BrowserLayoutMode.detailed:
        return 'Shows files and folders as two-line rows: the name on top, with size and modification date underneath.';
      case BrowserLayoutMode.compact:
        return 'Shows files and folders in a tight, high-density list view.';
      case BrowserLayoutMode.grid:
        return 'Shows files and folders as visual cards in a multi-column gallery grid.';
      case BrowserLayoutMode.masonry:
        return 'Shows files and folders in a variable-height, Pinterest-style column layout.';
    }
  }

  // ── JSON serialisation ────────────────────────────────────────────────────

  String toJson() {
    switch (this) {
      case BrowserLayoutMode.list:
        return 'list';
      case BrowserLayoutMode.detailed:
        return 'detailed';
      case BrowserLayoutMode.compact:
        return 'compact';
      case BrowserLayoutMode.grid:
        return 'grid';
      case BrowserLayoutMode.masonry:
        return 'masonry';
    }
  }

  static BrowserLayoutMode? fromJson(String? value) {
    switch (value) {
      case 'list':
        return BrowserLayoutMode.list;
      case 'detailed':
        return BrowserLayoutMode.detailed;
      case 'compact':
        return BrowserLayoutMode.compact;
      case 'grid':
        return BrowserLayoutMode.grid;
      case 'masonry':
        return BrowserLayoutMode.masonry;
      default:
        return null; // Return null so we know it isn't configured
    }
  }
}