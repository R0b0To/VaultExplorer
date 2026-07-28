/// Ordered highest-to-lowest priority. A [visible] request always preempts
/// queued [adjacent]/[background] slots up to the queue's max concurrency —
/// it does not preempt work already `FETCHING`
enum TaskPriority {
  /// An on-screen tile (grid/masonry/list) or the media viewer's current
  /// page. The thing the user is looking at right now.
  visible,

  /// Off-screen but adjacent to what's visible: the media viewer's
  /// next/prev prefetch, or a playlist-carousel neighbor tile.
  adjacent,

  /// Speculative, non-adjacent prefetch (e.g. a future "warm this whole
  /// folder" feature). No current caller uses this tier yet — it exists so
  /// that feature doesn't need another migration later (Roadmap Phase 2
  /// item 8).
  background,
}
