/// Represents the layout arrangement used inside the file browser.
enum BrowserLayoutMode {
  /// Detailed, full-width rows with metadata.
  list,

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
        return 'Shows files and folders in a detailed list with sizes and modification dates.';
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