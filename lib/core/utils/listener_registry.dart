class ListenerRegistry<T> {
  final List<void Function(T event)> _listeners = [];

  void add(void Function(T event) listener) {
    _listeners.add(listener);
  }

  void remove(void Function(T event) listener) {
    _listeners.remove(listener);
  }

  /// Dispatches [event] to a snapshot of the current listeners, so a
  /// listener that adds/removes another listener mid-dispatch (e.g. during
  /// widget dispose) can't trigger a concurrent-modification error.
  void notify(T event) {
    for (final listener in List<void Function(T event)>.of(_listeners)) {
      listener(event);
    }
  }
}
