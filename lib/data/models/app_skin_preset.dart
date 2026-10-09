/// Built-in color and component palettes available to the whole app.
enum AppSkinPreset {
  defaultSkin,
  oledPureBlack,
  custom;

  String get id => name;

  static AppSkinPreset fromJson(Object? value) {
    for (final preset in AppSkinPreset.values) {
      if (preset.id == value) return preset;
    }
    return AppSkinPreset.defaultSkin;
  }
}
