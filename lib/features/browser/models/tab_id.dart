import 'package:flutter/foundation.dart';

/// Opaque identity for a browser session.
///
/// A tab identity is deliberately distinct from a vault's volume slot. A
/// folder tab, a standalone/decoy browser session, and two tabs pointing at
/// the same vault therefore never share navigation, selection, search, or
/// sorting state by accident.
@immutable
final class TabId implements Comparable<TabId> {
  const TabId(this.value);

  static int _nextValue = 1;

  /// Allocates a process-unique session id. IDs are never recycled while the
  /// process is alive, even after their tab or standalone route is disposed.
  factory TabId.allocate() => TabId(_nextValue++);

  final int value;

  @override
  int compareTo(TabId other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is TabId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TabId($value)';
}
