/// When the app's windows come and go on desktop, and what that means for the
/// app.
///
/// Every window is a peer: the main window is one of them, closing it does not
/// close the others, and the app ends when the last one is gone, as with the
/// windows of a desktop file manager. This class holds only the rules; it knows
/// nothing about Flutter or native windows (the callbacks do the work), so they
/// can be tested without either.
///
/// Two kinds of windows matter:
///
/// * the **main window**, which shows the vault list and the lock gate, and
/// * **independent** windows (a file manager window) that can stand on their
///   own. The other secondary windows (a vault's settings) only exist to serve
///   the main window and close along with it.
class DesktopWindowPolicy {
  DesktopWindowPolicy({
    required this.independentWindowCount,
    required this.closeWindowsServingMain,
    required this.closeAllSecondaryWindows,
    required this.openMainWindow,
    required this.exitApp,
  });

  /// How many independent secondary windows are open right now.
  final int Function() independentWindowCount;

  /// Closes the secondary windows that only exist to serve the main window.
  final void Function() closeWindowsServingMain;

  /// Closes every secondary window, independent ones included.
  final void Function() closeAllSecondaryWindows;

  /// Opens a new main window. Only called when there is none.
  final void Function() openMainWindow;

  /// Ends the app.
  final void Function() exitApp;

  bool _mainOpen = false;
  bool _exiting = false;

  bool get isMainOpen => _mainOpen;

  /// Whether the app is on its way out.
  bool get isExiting => _exiting;

  /// The main window now exists (at startup, or reopened after a lock).
  void mainWindowOpened() {
    _mainOpen = true;
  }

  /// The main window is gone: the person closed it.
  ///
  /// The windows that only served it close with it; the app goes on only if an
  /// independent window is left.
  void mainWindowClosed() {
    _mainOpen = false;
    closeWindowsServingMain();
    _endIfNothingIsLeft();
  }

  /// A secondary window opened or closed. Call after the count changed.
  void secondaryWindowsChanged() {
    _endIfNothingIsLeft();
  }

  /// The app locked: nothing from the vaults may stay on screen, and the lock
  /// gate (which the main window draws) must be there to meet the person.
  ///
  /// The main window is brought back *before* the others close. Closing the
  /// last independent window while there is no main window would otherwise end
  /// the app instead of locking it.
  void lockRequested() {
    if (!_mainOpen) {
      _mainOpen = true;
      openMainWindow();
    }
    closeAllSecondaryWindows();
  }

  void _endIfNothingIsLeft() {
    if (_exiting || _mainOpen || independentWindowCount() > 0) return;
    _exiting = true;
    exitApp();
  }
}
