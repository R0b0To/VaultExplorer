import 'package:flutter/material.dart';

/// Manages item-selection mode. Mix into any [State] that needs a multi-select
/// UI — the mixin owns [isSelectionMode] and [selectedItems] so the host class
/// doesn't have to declare them.
mixin SelectionMixin<T extends StatefulWidget> on State<T> {
  bool isSelectionMode = false;
  final Set<String> selectedItems = {};

  void toggleSelectItem(String item) {
    setState(() {
      if (selectedItems.contains(item)) {
        selectedItems.remove(item);
        if (selectedItems.isEmpty) isSelectionMode = false;
      } else {
        selectedItems.add(item);
      }
    });
  }

  void exitSelectionMode() {
    setState(() {
      isSelectionMode = false;
      selectedItems.clear();
    });
  }
}