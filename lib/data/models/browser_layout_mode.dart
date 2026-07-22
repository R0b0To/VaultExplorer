/// Represents the layout arrangement used inside the file browser.
enum BrowserLayoutMode {
  /// Detailed, full-width rows with metadata.
  list,

  /// Compact rows optimized for high information density.
  compact,

  /// Multi-column grid optimized for visual media or galleries.
  grid;

  // ── Human-readable labels ─────────────────────────────────────────────────

  String get label {
    switch (this) {
      case BrowserLayoutMode.list:
        return 'Detailed list';
      case BrowserLayoutMode.compact:
        return 'Compact list';
      case BrowserLayoutMode.grid:
        return 'Gallery grid';
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
      default:
        return null; // Return null so we know it isn't configured
    }
  }
}
