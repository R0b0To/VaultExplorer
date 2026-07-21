import 'package:flutter/material.dart';
import '../../../utils/raw_entry.dart';

enum SortBy { name, size, extension, date }

/// Encapsulates sort-field / direction state and the comparator used to order
/// directory entries.  Mix into any [State] that renders a sortable file list.
///
/// Operates on already-parsed [RawEntry] values (parsed once at the
/// directory-listing boundary) rather than re-parsing the wire string on
/// every comparison during a sort.
mixin SortMixin<T extends StatefulWidget> on State<T> {
  SortBy sortBy = SortBy.name;
  bool sortAscending = true;

  void setSort(SortBy by) {
    setState(() {
      if (sortBy == by) {
        sortAscending = !sortAscending;
      } else {
        sortBy = by;
        // Sensible defaults: alphabetical fields start A→Z; magnitude fields
        // start largest/newest first so the most relevant items are on top.
        sortAscending = switch (by) {
          SortBy.name => true,
          SortBy.extension => true,
          SortBy.size => false, // largest first
          SortBy.date => false, // newest first
        };
      }
    });
  }

  int compareItems(RawEntry ea, RawEntry eb) {
    int result;
    switch (sortBy) {
      case SortBy.name:
        result = ea.name.toLowerCase().compareTo(eb.name.toLowerCase());

      case SortBy.size:
        result = ea.sizeBytes.compareTo(eb.sizeBytes);
        // Tie-break alphabetically so the order is stable.
        if (result == 0) {
          result = ea.name.toLowerCase().compareTo(eb.name.toLowerCase());
        }

      case SortBy.extension:
        String extOf(String name) =>
            name.contains('.') ? name.split('.').last.toLowerCase() : '';
        result = extOf(ea.name).compareTo(extOf(eb.name));
        if (result == 0) {
          result = ea.name.toLowerCase().compareTo(eb.name.toLowerCase());
        }

      case SortBy.date:
        result = ea.modifiedSecs.compareTo(eb.modifiedSecs);
        // Tie-break alphabetically.
        if (result == 0) {
          result = ea.name.toLowerCase().compareTo(eb.name.toLowerCase());
        }
    }

    return sortAscending ? result : -result;
  }
}