import 'package:flutter/foundation.dart';

/// Whether the app's *own* predictive-back animations are on
/// (Settings -> Appearance & Interface -> Navigation).
///
/// It follows the same route as the theme, language and dynamic-colour
/// notifiers in `vault_explorer_app.dart`: the app root needs the value before
/// (and without) the settings controller, so it is fed from the loaded
/// `AppSettings` at startup and again whenever the setting changes or an
/// import replaces it. Defaults to on, which is how the app has always behaved.
///
/// It covers exactly the two places where the app claims a back gesture to
/// animate it itself:
///  * the page transition that follows the finger
///    (`CrossfadePageTransitionsBuilder` in `app_theme.dart`), and
///  * the folder preview in the file browser (`DirectoryContentView`).
///
/// Those places only look at it when a gesture *starts*. When it is off they
/// simply leave the gesture unclaimed, and Flutter then does what it does for
/// the 3-button navigation bar: a plain pop (through the usual `PopScope`
/// handlers) when the gesture is committed, and nothing at all when it is
/// cancelled. A gesture that is already being followed always runs to its end,
/// so flipping the setting can never strand a half-drawn preview.
///
/// It deliberately has no say over Android's own Predictive Back: the
/// manifest's `enableOnBackInvokedCallback`, the framework's back callback
/// registration and the system animations (home screen, previous activity)
/// are untouched.
///
/// The camera screens also override `handleStartBackGesture`, but only to
/// intercept back (discard / review handling), not to animate it, so they do
/// not consult this.
final ValueNotifier<bool> appPredictiveBackNotifier = ValueNotifier(true);
