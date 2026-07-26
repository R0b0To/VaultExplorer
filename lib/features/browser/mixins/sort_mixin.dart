import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';

enum SortBy {
  name,
  size,
  extension,
  date;

  String toJson() => this.name;

  static SortBy fromJson(String? value) => switch (value) {
        'size' => SortBy.size,
        'extension' => SortBy.extension,
        'date' => SortBy.date,
        _ => SortBy.name,
      };
}

mixin SortMixin<T extends StatefulWidget> on State<T> {
  SortBy sortBy = SortBy.name;
  bool sortAscending = true;

  void setSort(SortBy by) {
    setState(() {
      if (sortBy == by) {
        sortAscending = !sortAscending;
      } else {
        sortBy = by;
        sortAscending = switch (by) {
          SortBy.name => true,
          SortBy.extension => true,
          SortBy.size => false,
          SortBy.date => false,
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
        if (result == 0) {
          result = ea.name.toLowerCase().compareTo(eb.name.toLowerCase());
        }
    }
    return sortAscending ? result : -result;
  }
}