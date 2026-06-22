import 'package:flutter/material.dart';

enum SortBy { name, size, extension }

/// Encapsulates sort-field / direction state and the comparator used to order
/// directory entries.  Mix into any [State] that renders a sortable file list.
mixin SortMixin<T extends StatefulWidget> on State<T> {
  SortBy sortBy = SortBy.name;
  bool sortAscending = true;

  void setSort(SortBy by) {
    setState(() {
      if (sortBy == by) {
        sortAscending = !sortAscending;
      } else {
        sortBy = by;
        sortAscending = true;
      }
    });
  }

  int compareItems(String a, String b) {
    String nameOf(String raw) => raw.startsWith('[DIR] ')
        ? raw.replaceFirst('[DIR] ', '')
        : raw.split('|').first;

    int sizeOf(String raw) {
      if (raw.startsWith('[DIR] ')) return 0;
      final p = raw.split('|');
      return p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
    }

    final aName = nameOf(a), bName = nameOf(b);
    int result;
    switch (sortBy) {
      case SortBy.name:
        result = aName.toLowerCase().compareTo(bName.toLowerCase());
        break;
      case SortBy.size:
        result = sizeOf(a).compareTo(sizeOf(b));
        break;
      case SortBy.extension:
        String extOf(String n) =>
            n.contains('.') ? n.split('.').last.toLowerCase() : '';
        result = extOf(aName).compareTo(extOf(bName));
        if (result == 0) result = aName.toLowerCase().compareTo(bName.toLowerCase());
        break;
    }
    return sortAscending ? result : -result;
  }

  /// Builds a [PopupMenuItem] for the sort menu, showing active direction.
  PopupMenuItem<SortBy> buildSortMenuItem(SortBy value, String label) {
    final cs = Theme.of(context).colorScheme;
    final isActive = sortBy == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            isActive
                ? (sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                : Icons.sort,
            size: 16,
            color: isActive ? cs.primary : null,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}