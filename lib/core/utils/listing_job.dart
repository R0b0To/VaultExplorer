/// A directory listing that is in progress and can be abandoned.
///
/// [result] completes with the finished listing, or with null if the job was
/// cancelled (or, for sources that report failure that way, if it failed).
/// Callers that start a newer listing cancel the older one first, so a worker
/// that is still reading a huge folder does not keep competing with the one
/// that replaced it.
class ListingJob<T> {
  ListingJob(this.result, void Function() onCancel) : _onCancel = onCancel;

  /// A job that is already finished and has nothing to cancel.
  ListingJob.completed(T value) : this(Future<T?>.value(value), _noop);

  /// A job for a source that cannot be interrupted: [result] runs to the end.
  ListingJob.uninterruptible(Future<T?> result) : this(result, _noop);

  final Future<T?> result;
  final void Function() _onCancel;
  bool _cancelled = false;

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Asks the job to stop. Safe to call more than once, and after completion.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }

  /// The same job with its result converted by [convert] (null stays null).
  ListingJob<R> map<R>(R Function(T value) convert) {
    final mapped = ListingJob<R>(
      result.then((value) => value == null ? null : convert(value)),
      cancel,
    );
    return mapped;
  }

  static void _noop() {}
}
