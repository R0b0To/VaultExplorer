/// A run of items under one header of a grouped file view.
///
/// Kept free of Flutter imports so that the grouping and layout code built on
/// it can be exercised by plain Dart tests.
class DateGroup<T> {
  final DateTime? date;

  /// Header text of a group that is not a plain day (a month, a folder, a
  /// camera...). Null for the day groups `computeDateGroups` makes, whose
  /// header is built from [date] by `formatDateGroupHeader`.
  final String? label;
  final List<T> items;

  /// Index of each item of [items] in the flat list the groups were made from.
  final List<int> globalIndices;

  DateGroup({
    required this.date,
    this.label,
    required this.items,
    required this.globalIndices,
  });
}
