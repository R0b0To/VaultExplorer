import 'package:material_ui/material_ui.dart';

/// The root navigator. Anything that lives above the app's routes (the skin
/// editor's floating controls) uses it to open a page.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'appNavigator',
);
