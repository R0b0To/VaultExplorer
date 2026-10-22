// Compatibility barrel. The standalone `FileBrowserScreen` wrapper is gone:
// decoy mode and every other route now host the same `BrowserTabsShell`, so
// there is exactly one chrome host. Remaining importers only need these
// re-exports; point them at the real files and delete this barrel.
export 'controllers/file_browser_navigation_controller.dart' show PathSegment;
export 'widgets/directory_content_view.dart' show DirectoryContentView;
