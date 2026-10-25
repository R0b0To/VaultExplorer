import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

/// Title and one-line explanation for each Material / status color role of a
/// skin, keyed by role name. Shared by the skin controls page and the floating
/// color picker so both describe a color the same way.
Map<String, (String, String)> skinColorRoleCopy(BuildContext context) => {
  'primary': (
    context.l10n.skinActionAccent,
    context.l10n.skinEmphasisForActionIconsActiveControlsProgressAndLinks,
  ),
  'onPrimary': (
    context.l10n.skinTextAndIconsOnAccentButtons,
    context.l10n.skinForegroundForButtonsFilledWithTheActionAccentColor,
  ),
  'primaryContainer': (
    context.l10n.skinSelectionAndIconTileBackground,
    context.l10n.skinSelectedFilesAndVaultFormat076e52,
  ),
  'onPrimaryContainer': (
    context.l10n.skinTextAndIconsOnSelectionColors,
    context.l10n.skinForegroundForIconTilesAndOtherPrimaryContainerSurfaces,
  ),
  'primaryFixed': (
    context.l10n.skinSteadyMainAccent,
    context.l10n.skinAPrimaryAccentThatStaysTheSameInLightAndDarkSurfaces,
  ),
  'primaryFixedDim': (
    context.l10n.skinMutedSteadyMainAccent,
    context.l10n.skinASofterVersionOfTheSteadyPrimaryAccent,
  ),
  'onPrimaryFixed': (
    context.l10n.skinTextOnSteadyMainAccent,
    context.l10n.skinForegroundForPrimaryFixedColors,
  ),
  'onPrimaryFixedVariant': (
    context.l10n.skinMutedTextOnSteadyMainAccent,
    context.l10n.skinSecondaryForegroundForPrimaryFixedColors,
  ),
  'secondary': (
    context.l10n.skinSecondaryAccent,
    context.l10n.skinSupportingActionsAndLessProminentHighlights,
  ),
  'onSecondary': (
    context.l10n.skinTextOnSecondaryAccent,
    context.l10n.skinLabelsAndIconsOnSecondaryColoredAreas,
  ),
  'secondaryContainer': (
    context.l10n.skinSecondaryBackground,
    context.l10n.skinSoftFillForSupportingContent,
  ),
  'onSecondaryContainer': (
    context.l10n.skinTextOnSecondaryBackgrounds,
    context.l10n.skinForegroundForSecondaryContainers,
  ),
  'secondaryFixed': (
    context.l10n.skinSteadySecondaryAccent,
    context.l10n.skinASecondaryAccentThatStaysTheSameAcrossSurfaces,
  ),
  'secondaryFixedDim': (
    context.l10n.skinMutedSteadySecondaryAccent,
    context.l10n.skinASofterVersionOfTheSteadySecondaryAccent,
  ),
  'onSecondaryFixed': (
    context.l10n.skinTextOnSteadySecondaryAccent,
    context.l10n.skinForegroundForSecondaryFixedColors,
  ),
  'onSecondaryFixedVariant': (
    context.l10n.skinMutedTextOnSteadySecondaryAccent,
    context.l10n.skinSecondaryForegroundForSecondaryFixedColors,
  ),
  'tertiary': (
    context.l10n.skinExtraAccentColor,
    context.l10n.skinDecorativeHighlightsAndContrastingAccents,
  ),
  'onTertiary': (
    context.l10n.skinTextOnExtraAccent,
    context.l10n.skinLabelsAndIconsOnTertiaryColoredAreas,
  ),
  'tertiaryContainer': (
    context.l10n.skinExtraAccentBackground,
    context.l10n.skinSoftFillForTertiaryContent,
  ),
  'onTertiaryContainer': (
    context.l10n.skinTextOnExtraAccentBackgrounds,
    context.l10n.skinForegroundForTertiaryContainers,
  ),
  'tertiaryFixed': (
    context.l10n.skinSteadyExtraAccent,
    context.l10n.skinATertiaryAccentThatStaysTheSameAcrossSurfaces,
  ),
  'tertiaryFixedDim': (
    context.l10n.skinMutedSteadyExtraAccent,
    context.l10n.skinASofterVersionOfTheSteadyTertiaryAccent,
  ),
  'onTertiaryFixed': (
    context.l10n.skinTextOnSteadyExtraAccent,
    context.l10n.skinForegroundForTertiaryFixedColors,
  ),
  'onTertiaryFixedVariant': (
    context.l10n.skinMutedTextOnSteadyExtraAccent,
    context.l10n.skinSecondaryForegroundForTertiaryFixedColors,
  ),
  'error': (
    context.l10n.skinErrorColor,
    context.l10n.skinErrorsDestructiveActionsAndInvalidInput,
  ),
  'onError': (
    context.l10n.skinTextOnErrorColor,
    context.l10n.skinLabelsAndIconsOnErrorColoredAreas,
  ),
  'errorContainer': (
    context.l10n.skinErrorBackground,
    context.l10n.skinSoftFillBehindErrorMessages,
  ),
  'onErrorContainer': (
    context.l10n.skinTextOnErrorBackgrounds,
    context.l10n.skinForegroundForErrorContainers,
  ),
  'surface': (
    context.l10n.skinPageBackground,
    context.l10n.skinTheMainBackgroundBehindAppContent,
  ),
  'onSurface': (
    context.l10n.skinMainTextAndIcons,
    context.l10n.skinPrimaryContentDrawnOnPageAndCardBackgrounds,
  ),
  'surfaceDim': (
    context.l10n.skinDimmedBackground,
    context.l10n.skinTheDarkestNeutralSurfaceLayer,
  ),
  'surfaceBright': (
    context.l10n.skinBrightBackground,
    context.l10n.skinTheLightestNeutralSurfaceLayer,
  ),
  'surfaceContainerLowest': (
    context.l10n.skinDeepestCardLayer,
    context.l10n.skinTheLowestAndQuietestSurfaceContainer,
  ),
  'surfaceContainerLow': (
    context.l10n.skinLowCardLayer,
    context.l10n.skinSubtleCardsAndRecessedAreas,
  ),
  'surfaceContainer': (
    context.l10n.skinStandardCardLayer,
    context.l10n.skinCommonCardsAndGroupedContent,
  ),
  'surfaceContainerHigh': (
    context.l10n.skinRaisedCardLayer,
    context.l10n.skinRaisedCardsMenusAndAppBars,
  ),
  'surfaceContainerHighest': (
    context.l10n.skinTopCardLayer,
    context.l10n.skinProminentPanelsAndSelectedSurfaces,
  ),
  'onSurfaceVariant': (
    context.l10n.skinSecondaryTextAndIcons,
    context.l10n.skinDetailsHintsAndSupportingLabels,
  ),
  'outline': (
    context.l10n.skinStrongBorder,
    context.l10n.skinVisibleBordersAndSeparators,
  ),
  'outlineVariant': (
    context.l10n.skinSubtleBorder,
    context.l10n.skinQuietOutlinesAndLowEmphasisSeparators,
  ),
  'shadow': (
    context.l10n.skinShadowTint,
    context.l10n.skinTintUsedByElevatedSurfaces,
  ),
  'scrim': (
    context.l10n.skinModalBackdrop,
    context.l10n.skinTintBehindDialogsAndModalSheets,
  ),
  'inverseSurface': (
    context.l10n.skinInvertedSurface,
    context.l10n.skinAContrastingSurfaceForInverseElements,
  ),
  'onInverseSurface': (
    context.l10n.skinTextOnInvertedSurfaces,
    context.l10n.skinForegroundUsedOverInverseSurfaces,
  ),
  'inversePrimary': (
    context.l10n.skinInvertedMainAccent,
    context.l10n.skinPrimaryAccentUsedOnInverseSurfaces,
  ),
  'surfaceTint': (
    context.l10n.skinElevationTint,
    context.l10n.skinTintAppliedToElevatedSurfaces,
  ),
  'success': (
    context.l10n.skinSuccessColor,
    context.l10n.skinCompletedActionsAndPositiveStatus,
  ),
  'onSuccess': (
    context.l10n.skinTextOnSuccessColor,
    context.l10n.skinForegroundForSuccessColoredContent,
  ),
  'successContainer': (
    context.l10n.skinSuccessBackground,
    context.l10n.skinSoftFillBehindPositiveStatusMessages,
  ),
  'onSuccessContainer': (
    context.l10n.skinTextOnSuccessBackgrounds,
    context.l10n.skinForegroundForSuccessContainers,
  ),
  'warning': (
    context.l10n.skinWarningColor,
    context.l10n.skinCautionAttentionAndPendingStatus,
  ),
  'onWarning': (
    context.l10n.skinTextOnWarningColor,
    context.l10n.skinForegroundForWarningColoredContent,
  ),
  'warningContainer': (
    context.l10n.skinWarningBackground,
    context.l10n.skinSoftFillBehindWarningMessages,
  ),
  'onWarningContainer': (
    context.l10n.skinTextOnWarningBackgrounds,
    context.l10n.skinForegroundForWarningContainers,
  ),
  'bookmark': (
    context.l10n.skinBookmarkColor,
    context.l10n.skinSavedAndBookmarkedItems,
  ),
};

/// The translated title of a color [role], or a readable version of the role
/// name ("onSurfaceVariant" -> "On Surface Variant") when it has none.
String skinColorRoleLabel(BuildContext context, String role) =>
    skinColorRoleCopy(context)[role]?.$1 ?? skinRoleFallbackLabel(role);

String skinRoleFallbackLabel(String role) => role
    .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
    .replaceFirstMapped(
      RegExp(r'^[a-z]'),
      (match) => match.group(0)!.toUpperCase(),
    );
