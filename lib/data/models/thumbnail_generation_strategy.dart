enum ThumbnailGenerationStrategy {
  firstFrame,
  frameAtPercentage,
  hybrid;

  static ThumbnailGenerationStrategy fromJson(String? value) =>
      ThumbnailGenerationStrategy.values.firstWhere(
        (strategy) => strategy.name == value,
        orElse: () => ThumbnailGenerationStrategy.hybrid,
      );
}
