enum MediaDecoderMode {
  auto,
  hardware,
  software,
  ffmpeg;

  static MediaDecoderMode fromJson(String? value) =>
      MediaDecoderMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => MediaDecoderMode.auto,
      );
}
