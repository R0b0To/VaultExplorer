// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get cancel => 'Annuler';

  @override
  String get close => 'Fermer';

  @override
  String get search => 'Rechercher';

  @override
  String get goBack => 'Retour';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => 'Aller à la page';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return 'Numéro de page (1 - $pageCount)';
  }

  @override
  String get pdfViewerPageLabel => 'Page';

  @override
  String get pdfViewerGoButton => 'Aller';

  @override
  String get pdfViewerSearchHint => 'Rechercher dans le document';

  @override
  String get pdfViewerNoMatches => 'Aucun résultat';

  @override
  String get pdfViewerPreviousMatch => 'Résultat précédent';

  @override
  String get pdfViewerNextMatch => 'Résultat suivant';

  @override
  String get pdfViewerCloseSearch => 'Fermer la recherche';

  @override
  String get pdfViewerPrintTooltip => 'Imprimer le document';

  @override
  String get pdfViewerLoadingDocument => 'Chargement du document…';

  @override
  String get pdfViewerCannotOpenTitle => 'Impossible d\'ouvrir le PDF';

  @override
  String get pdfViewerFailedToLoad => 'Échec du chargement du PDF';

  @override
  String get pdfViewerEditTooltip => 'Modifier';

  @override
  String get pdfViewerDoneEditingTooltip => 'Terminer la modification';

  @override
  String get pdfViewerSaveFailed =>
      'Impossible d\'enregistrer les modifications de ce PDF';

  @override
  String get pdfViewerEditUnavailable =>
      'La modification n\'est pas disponible pour ce document';

  @override
  String get paste => 'Coller';

  @override
  String get clear => 'Effacer';

  @override
  String get clipboardVerbMove => 'Déplacer';

  @override
  String get clipboardVerbCopy => 'Copier';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb ($count) — Appuyez pour les détails, appui long pour coller';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb ($count) — Détails du presse-papiers';
  }

  @override
  String clipboardSourceLabel(String source) {
    return 'Source : $source';
  }

  @override
  String get clipboardDefaultSourceName => 'Coffre';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '1 élément',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count éléments supplémentaires',
      one: '+1 élément supplémentaire',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => 'Paramètres avancés';

  @override
  String get pimFieldLabel => 'PIM  (laisser vide pour la valeur par défaut)';

  @override
  String get encryptionAlgorithmLabel => 'Algorithme de chiffrement';

  @override
  String get hashAlgorithmLabel => 'Algorithme de hachage';

  @override
  String get clipboardVerbMoving => 'Déplacement';

  @override
  String get clipboardVerbCopying => 'Copie';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '1 élément',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return ' depuis \"$source\"';
  }

  @override
  String get clipboardOpenContainerToPaste => 'Ouvrez un conteneur pour coller';

  @override
  String get keyfilesOptionalLabel => 'Fichiers-clés (facultatif)';

  @override
  String get addFile => 'Ajouter un fichier';

  @override
  String get noKeyfilesAttached => 'Aucun fichier-clé joint';

  @override
  String get completed => 'Terminé';

  @override
  String get dismiss => 'Ignorer';

  @override
  String byteProgressText(String transferred, String total, int pct) {
    return '$transferred / $total  ($pct %)';
  }

  @override
  String countProgressText(int done, int total, int pct) {
    return '$done / $total  ($pct %)';
  }

  @override
  String multiOpLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transferts',
      one: '1 transfert',
    );
    return '$_temp0';
  }

  @override
  String multiOpSublabel(String summary) {
    return '$summary · appuyez pour tout voir';
  }

  @override
  String get thumbnailSizeResolutionLabel =>
      'Taille des miniatures (résolution)';

  @override
  String get jpegCompressionQualityLabel => 'Qualité de compression JPEG';

  @override
  String get done => 'Terminé';

  @override
  String get confirm => 'Confirmer';

  @override
  String get couldNotPickKeyfiles =>
      'Impossible de sélectionner les fichiers-clés';

  @override
  String get filesystemLabelEncryptedVault => 'ce coffre chiffré';

  @override
  String get filesystemLabelThisContainer => 'ce conteneur';

  @override
  String get nounFile => 'fichier';

  @override
  String get nounFolder => 'dossier';

  @override
  String get nounFileCapitalized => 'Fichier';

  @override
  String get nounFolderCapitalized => 'Dossier';

  @override
  String get unitBytes => 'octets';

  @override
  String get unitCharacters => 'caractères';

  @override
  String get validationEmptyName => 'Le nom ne peut pas être vide.';

  @override
  String validationReservedNavName(String name, String noun) {
    return '\"$name\" est un nom de navigation réservé et ne peut pas être utilisé comme nom de $noun.';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return '\"$char\" à la position $position n\'est pas autorisé dans un nom sur $fsLabel.';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return 'La position $position contient un caractère de contrôle non imprimable (code $code), non autorisé sur $fsLabel.';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '\"$name\" est un nom de périphérique réservé sur $fsLabel (correspond à CON, PRN, AUX, NUL, COM0–9 ou LPT0–9) et ne peut pas être utilisé, avec ou sans extension de fichier.';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return 'Les noms de $noun ne peuvent pas se terminer par une espace sur $fsLabel';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return 'Les noms de $noun ne peuvent pas se terminer par un \".\" sur $fsLabel';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return 'Ce nom fait $length $unit ; $fsLabel autorise au maximum $maxLength $unit par nom de $noun.';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return 'Le chemin complet fait $length caractères ; $fsLabel autorise au maximum $maxLength.';
  }

  @override
  String conflictSameType(String noun, String name) {
    return 'Un $noun nommé \"$name\" existe déjà ici.';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return 'Un $existingNoun nommé \"$name\" existe déjà ici — il ne peut pas partager son nom avec un $candidateNoun.';
  }

  @override
  String get readOnlyContainerWarning =>
      'Ce conteneur est monté en lecture seule.';

  @override
  String get hiddenVolumeProtectionTriggeredWarning =>
      'Une écriture sur ce volume externe aurait endommagé le volume caché ; elle a donc été bloquée. Ce conteneur est passé en lecture seule pour le reste de cette session.';

  @override
  String get protectHiddenVolumeToggleTitle => 'Protéger le volume caché';

  @override
  String get protectHiddenVolumeToggleSubtitle =>
      'Empêcher les dommages causés par l\'écriture sur le volume externe';

  @override
  String get protectHiddenVolumeCredentialsRequired =>
      'Un mot de passe ou un fichier-clé du volume caché est requis pour le protéger';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimer $count éléments ?',
      one: 'Supprimer 1 élément ?',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning =>
      'Ces éléments seront définitivement supprimés, y compris tout le contenu des dossiers sélectionnés.';

  @override
  String get deleteFilesWarning =>
      'Ces éléments seront définitivement effacés de votre volume chiffré.';

  @override
  String get delete => 'Supprimer';

  @override
  String get remove => 'Retirer';

  @override
  String get create => 'Créer';

  @override
  String get rename => 'Renommer';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Renommer $count éléments',
      one: 'Renommer 1 élément',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => 'Nouveau dossier';

  @override
  String get newTextFileTitle => 'Nouveau fichier texte';

  @override
  String get folderNameHint => 'Nom du dossier';

  @override
  String get filenameHint => 'nomdefichier.txt';

  @override
  String get newNameHint => 'Nouveau nom';

  @override
  String get baseNameHint => 'Nom de base';

  @override
  String couldntCreateItem(String name) {
    return 'Impossible de créer \"$name\" — vérifiez que le conteneur est toujours monté';
  }

  @override
  String couldntRenameSingle(String name) {
    return 'Impossible de renommer \"$name\" — un élément portant ce nom existe peut-être déjà';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Impossible de renommer $count éléments : $reason',
      one: 'Impossible de renommer 1 élément : $reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Impossible de renommer $count éléments',
      one: 'Impossible de renommer 1 élément',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize =>
      'Saisissez une taille cachée valide supérieure à 0';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter =>
      'La taille du volume caché doit être inférieure à celle du volume externe';

  @override
  String get hiddenVolumeErrorTooLargeForContainer =>
      'La taille du volume caché est trop grande pour la taille de ce conteneur';

  @override
  String get hiddenVolumeErrorCredentialsRequired =>
      'Un mot de passe caché ou un fichier-clé est requis pour créer un volume caché';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      'Les identifiants du volume caché (mot de passe, PIM et fichiers-clés) ne peuvent pas être identiques à ceux du volume externe.';

  @override
  String get vaultItemTypePassword => 'Mot de passe';

  @override
  String get vaultItemTypePaymentCard => 'Carte de paiement';

  @override
  String get vaultItemTypeIdentity => 'Identité';

  @override
  String get vaultItemTypeSecureNote => 'Note sécurisée';

  @override
  String get vaultItemTypeBankAccount => 'Compte bancaire';

  @override
  String get vaultItemTypeSoftwareLicense => 'Licence logicielle';

  @override
  String get fieldUsernameEmail => 'Nom d\'utilisateur / E-mail';

  @override
  String get fieldPassword => 'Mot de passe';

  @override
  String get fieldWebsiteUrl => 'URL du site web';

  @override
  String get fieldTotpSecret => 'Secret TOTP (2FA)';

  @override
  String get fieldNotes => 'Notes';

  @override
  String get fieldCardholderName => 'Nom du titulaire';

  @override
  String get fieldCardNumber => 'Numéro de carte';

  @override
  String get fieldExpiryMMYY => 'Expiration (MM/AA)';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldIssuingBank => 'Banque émettrice';

  @override
  String get fieldFullName => 'Nom complet';

  @override
  String get fieldDateOfBirth => 'Date de naissance';

  @override
  String get fieldNationality => 'Nationalité';

  @override
  String get fieldPassportNumber => 'Numéro de passeport';

  @override
  String get fieldPassportExpiry => 'Expiration du passeport';

  @override
  String get fieldNationalIdSsn => 'Carte d\'identité / N° sécurité sociale';

  @override
  String get fieldDriversLicense => 'Permis de conduire';

  @override
  String get fieldAddress => 'Adresse';

  @override
  String get fieldPhone => 'Téléphone';

  @override
  String get fieldEmail => 'E-mail';

  @override
  String get fieldNote => 'Note';

  @override
  String get fieldBankName => 'Nom de la banque';

  @override
  String get fieldAccountHolder => 'Titulaire du compte';

  @override
  String get fieldAccountNumber => 'Numéro de compte';

  @override
  String get fieldRoutingSortCode => 'Code d\'acheminement / Code guichet';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => 'Type de compte';

  @override
  String get fieldProductName => 'Nom du produit';

  @override
  String get fieldLicenseKey => 'Clé de licence';

  @override
  String get fieldRegisteredTo => 'Enregistré à';

  @override
  String get fieldPurchaseDate => 'Date d\'achat';

  @override
  String get fieldExpiryRenewalDate => 'Date d\'expiration / de renouvellement';

  @override
  String get fieldDownloadUrl => 'URL de téléchargement';

  @override
  String get fieldRegistrationEmail => 'E-mail d\'enregistrement';

  @override
  String get titleRequired => 'Le titre est requis';

  @override
  String newTypeTitle(String typeLabel) {
    return 'Nouveau $typeLabel';
  }

  @override
  String editItemTitle(String title) {
    return 'Modifier $title';
  }

  @override
  String get save => 'Enregistrer';

  @override
  String typeNameHint(String typeLabel) {
    return 'Nom de $typeLabel';
  }

  @override
  String get titleSectionLabel => 'Titre';

  @override
  String get fieldsSectionLabel => 'Champs';

  @override
  String get encryptedStorageHint =>
      'Tous les champs sont stockés chiffrés dans le conteneur.';

  @override
  String copiedSuffix(String fieldLabel) {
    return '$fieldLabel copié';
  }

  @override
  String get copy => 'Copier';

  @override
  String get failedToSaveCheckMounted =>
      'Échec de l\'enregistrement — vérifiez que le conteneur est toujours monté';

  @override
  String get discardChangesTitle => 'Abandonner les modifications ?';

  @override
  String get discardChangesMessage =>
      'Vos modifications non enregistrées seront perdues.';

  @override
  String get discard => 'Abandonner';

  @override
  String get keepEditing => 'Continuer la modification';

  @override
  String get deleteItemTitle => 'Supprimer l\'élément ?';

  @override
  String deleteItemMessage(String title) {
    return '\"$title\" sera définitivement supprimé du coffre.';
  }

  @override
  String get removeFromBookmarks => 'Retirer des favoris';

  @override
  String get addToBookmarks => 'Ajouter aux favoris';

  @override
  String get edit => 'Modifier';

  @override
  String labelCopiedToClipboard(String label) {
    return '$label copié dans le presse-papiers';
  }

  @override
  String get noFieldsFilledIn =>
      'Aucun champ rempli.\nAppuyez sur Modifier pour ajouter des détails.';

  @override
  String get sectionLabelDetails => 'Détails';

  @override
  String get sectionLabelInfo => 'Infos';

  @override
  String get metaLabelType => 'Type';

  @override
  String get metaLabelCreated => 'Créé';

  @override
  String get metaLabelModified => 'Modifié';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return 'Copier $fieldLabel';
  }

  @override
  String get readOnlyCantAddItemsTooltip =>
      'Lecture seule — impossible d\'ajouter des éléments';

  @override
  String get extractArchive => 'Extraire l\'archive';

  @override
  String get newItemTooltip => 'Nouvel élément';

  @override
  String get camera => 'Appareil photo';

  @override
  String get importFiles => 'Importer des fichiers';

  @override
  String get importFolder => 'Importer un dossier';

  @override
  String get secureItem => 'Élément sécurisé';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archive Explorer';

  @override
  String get archiveExplorerPermissionTitle => 'Accès au stockage requis';

  @override
  String get archiveExplorerPermissionMessage =>
      'Autorisez l\'accès à vos fichiers pour parcourir et extraire les archives .zip du dossier Téléchargements.';

  @override
  String get archiveExplorerGrantAccess => 'Autoriser l\'accès';

  @override
  String get archiveExplorerEmptyTitle => 'Aucune archive trouvée';

  @override
  String get archiveExplorerEmptyMessage =>
      'Les fichiers zip que vous téléchargez apparaîtront ici.';

  @override
  String get archiveExplorerRefreshTooltip => 'Actualiser';

  @override
  String archiveExplorerEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '1 élément',
    );
    return '$_temp0';
  }

  @override
  String get archiveExplorerExtractAll => 'Tout extraire';

  @override
  String get archiveExplorerExtracting => 'Extraction en cours…';

  @override
  String archiveExplorerExtractSuccess(int count, String name) {
    return '$count fichiers extraits vers Download/Extracted/$name';
  }

  @override
  String get archiveExplorerExtractFailed =>
      'Impossible d\'extraire cette archive.';

  @override
  String get archiveExplorerOpenFailed => 'Impossible d\'ouvrir cette archive.';

  @override
  String get archiveExplorerOpenArchive => 'Ouvrir une archive…';

  @override
  String get archiveExplorerUnresolvedPath =>
      'Impossible d\'accéder directement à ce fichier. Essayez plutôt d\'en choisir un dans Téléchargements.';

  @override
  String get archiveExplorerExtractTo => 'Extraire vers…';

  @override
  String get archiveExplorerPreview => 'Aperçu';

  @override
  String get archiveExplorerChoosingDestination => 'Choix de la destination…';

  @override
  String get archiveExplorerNoDestinationChosen =>
      'Aucune destination choisie.';

  @override
  String archiveExplorerExtractSuccessTo(int count, String path) {
    return '$count fichiers extraits vers $path';
  }

  @override
  String get archiveBrowserEmptyTitle => 'Dossier vide';

  @override
  String get archiveBrowserEmptyMessage =>
      'Ce dossier ne contient aucun fichier.';

  @override
  String get archiveBrowserRoot => 'Archive';

  @override
  String get archiveBrowserOpenFileFailed => 'Impossible d\'ouvrir ce fichier.';

  @override
  String get fileAssocInAppTextEditor => 'Éditeur de texte intégré';

  @override
  String get fileAssocInAppMediaViewer => 'Lecteur multimédia intégré';

  @override
  String fileAssocAppPrefix(String name) {
    return 'Application : $name';
  }

  @override
  String get fileAssocExternalApp => 'Application externe';

  @override
  String get appSettingsTitle => 'Paramètres de l\'application';

  @override
  String get sectionSecurityPrivacy => 'Sécurité et confidentialité';

  @override
  String get sectionAppearanceInterface => 'Apparence et interface';

  @override
  String get sectionVaultFileHandling => 'Coffre et gestion des fichiers';

  @override
  String get masterPasswordTitle => 'Mot de passe principal';

  @override
  String get masterPasswordActiveSubtitle =>
      'Actif — appuyez sur l\'interrupteur pour le retirer';

  @override
  String get masterPasswordInactiveSubtitle =>
      'Exiger un mot de passe pour ouvrir l\'application';

  @override
  String get newPasswordLabel => 'Nouveau mot de passe';

  @override
  String get masterPasswordFieldLabel => 'Mot de passe principal';

  @override
  String get confirmPasswordLabel => 'Confirmer le mot de passe';

  @override
  String get update => 'Mettre à jour';

  @override
  String get setPassword => 'Définir le mot de passe';

  @override
  String get biometricUnlockTitle => 'Déverrouillage biométrique';

  @override
  String get biometricUnlockSubtitle =>
      'Authentifiez-vous pour monter le conteneur en toute sécurité';

  @override
  String get changeMasterPasswordTitle => 'Changer le mot de passe principal';

  @override
  String get changeMasterPasswordSubtitle =>
      'Mettre à jour les identifiants du mot de passe principal';

  @override
  String get autoLockContainersTitle =>
      'Verrouillage automatique des conteneurs';

  @override
  String get autoLockContainersSubtitle =>
      'Verrouiller automatiquement les coffres ouverts après une période d\'inactivité';

  @override
  String get autoLockTimeoutLabel => 'Délai de verrouillage automatique';

  @override
  String get immediately => 'Immédiatement';

  @override
  String nMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get blockScreenshotsTitle => 'Bloquer les captures d\'écran';

  @override
  String get blockScreenshotsSubtitle =>
      'Empêcher les captures d\'écran et masquer l\'aperçu dans les applications récentes';

  @override
  String get keepVaultsRunningInBackgroundTitle =>
      'Garder les coffres actifs en arrière-plan';

  @override
  String get keepVaultsRunningInBackgroundSubtitle =>
      'Afficher une notification et garder les coffres ouverts disponibles après avoir quitté l\'application. Les clés du coffre restent en mémoire jusqu\'au verrouillage.';

  @override
  String get notificationPermissionDeniedMessage =>
      'Autorisation de notification refusée. Les coffres resteront tout de même ouverts, mais la notification persistante ne sera pas affichée.';

  @override
  String get discreteModeTitle => 'Mode Masque';

  @override
  String get discreteModeActiveSubtitle =>
      'Actif — l\'application apparaît actuellement sous le nom \"Archive Explorer\"';

  @override
  String get discreteModeInactiveSubtitle =>
      'Déguiser cette application en explorateur d\'archives zip sur l\'écran d\'accueil';

  @override
  String get enableDiscreteModeTitle => 'Activer le Mode Masque ?';

  @override
  String get disableDiscreteModeTitle => 'Désactiver le Mode Masque ?';

  @override
  String get enableDiscreteModeMessage =>
      'L\'icône et le nom de l\'application sur votre écran d\'accueil deviendront \"Archive Explorer\". Elle fonctionnera comme un explorateur et extracteur d\'archives zip.\n\nPour accéder à votre coffre, ouvrez Archive Explorer et maintenez le doigt sur le titre pendant 2 secondes.';

  @override
  String get disableDiscreteModeMessage =>
      'L\'icône et le nom de l\'application sur votre écran d\'accueil redeviendront \"Vault Explorer\".';

  @override
  String get enable => 'Activer';

  @override
  String get disable => 'Désactiver';

  @override
  String get discreteModeEnabledSnack =>
      'Mode Masque activé. L\'application va se fermer — rouvrez-la depuis la nouvelle icône du lanceur.';

  @override
  String get discreteModeDisabledSnack =>
      'Mode Masque désactivé. L\'application va se fermer — rouvrez-la depuis la nouvelle icône du lanceur.';

  @override
  String get failedToChangeDiscreteMode => 'Échec du changement de Mode Masque';

  @override
  String get cacheDerivedKeysTitle =>
      'Mettre en cache les clés dérivées par défaut';

  @override
  String get cacheDerivedKeysSubtitle =>
      'Stocker les clés dérivées dans le Keystore pour des déverrouillages plus rapides';

  @override
  String get appThemeLabel => 'Thème de l\'application';

  @override
  String get systemDefault => 'Par défaut du système';

  @override
  String get lightTheme => 'Thème clair';

  @override
  String get darkTheme => 'Thème sombre';

  @override
  String get useMaterialYouTitle => 'Utiliser Material You';

  @override
  String get useMaterialYouSubtitle =>
      'Adapter les couleurs de l\'application à votre fond d\'écran (Android 12+)';

  @override
  String get pureBlackThemeTitle => 'Noir pur (OLED)';

  @override
  String get pureBlackThemeSubtitle =>
      'Fond d\'écran noir pur pour économiser la batterie et réduire le reflet sur les écrans OLED (thème sombre uniquement)';

  @override
  String get sortContainersByLabel => 'Trier les conteneurs par';

  @override
  String get swapCardSwipeActionsTitle =>
      'Inverser les actions de balayage des cartes';

  @override
  String get swapCardSwipeActionsSubtitle =>
      'Afficher Modifier à gauche et Retirer à droite lors du balayage des cartes';

  @override
  String get swipeGestureHintTitle => 'Indice de geste de balayage';

  @override
  String get swipeGestureHintSubtitle =>
      'Afficher une animation d\'aperçu sur le premier conteneur';

  @override
  String get autoOpenOnUnlockTitle => 'Ouverture automatique au déverrouillage';

  @override
  String get autoOpenOnUnlockActiveSubtitle =>
      'Ouvrir automatiquement après le déverrouillage d\'un coffre';

  @override
  String get autoOpenOnUnlockInactiveSubtitle =>
      'Déverrouiller le coffre uniquement et rester sur le tableau de bord';

  @override
  String get enableJsHtmlTitle => 'Activer JavaScript dans la visionneuse HTML';

  @override
  String get jsEnabledSubtitle =>
      'JavaScript activé pour les fichiers HTML locaux';

  @override
  String get jsDisabledSubtitle =>
      'JavaScript désactivé pour les fichiers HTML locaux';

  @override
  String get fastStorageAccessTitle => 'Accès rapide au stockage';

  @override
  String get fastStorageAccessGrantedSubtitle =>
      'Accès à tous les fichiers accordé (vitesse maximale)';

  @override
  String get fastStorageAccessNotGrantedSubtitle =>
      'Accordez l\'accès à tous les fichiers dans les paramètres système pour une vitesse optimale';

  @override
  String get enableFastStorageAccessTitle =>
      'Activer l\'accès rapide au stockage';

  @override
  String get enableFastStorageAccessMessage =>
      'Accorder l\'accès à \"Tous les fichiers\" permet à Vault Explorer d\'effectuer des opérations de fichiers POSIX directes, augmentant les performances des coffres dossier jusqu\'à 1000 fois.';

  @override
  String get disableStorageAccessTitle => 'Désactiver l\'accès au stockage';

  @override
  String get disableStorageAccessMessage =>
      'Android exige que l\'accès à \"Tous les fichiers\" soit désactivé dans les paramètres système. Voulez-vous ouvrir les Paramètres pour le désactiver ?';

  @override
  String get enableStoragePermissionLegacyTitle =>
      'Autoriser l\'accès au stockage';

  @override
  String get enableStoragePermissionLegacyMessage =>
      'Vault Explorer a besoin de l\'autorisation de stockage pour effectuer des opérations de fichiers directes, ce qui accélère les performances des coffres dossier. Android va maintenant vous demander de confirmer.';

  @override
  String get disableStoragePermissionLegacyMessage =>
      'Android exige que l\'autorisation de stockage soit désactivée dans les paramètres système. Voulez-vous ouvrir les Paramètres pour la désactiver ?';

  @override
  String get openSettings => 'Ouvrir les paramètres';

  @override
  String get useThisPasswordButton => 'Use This Password';

  @override
  String get quickPasswordGeneratorSheetTitle => 'Password Generator';

  @override
  String get androidFileProviderTitle => 'Fournisseur de fichiers Android';

  @override
  String get androidFileProviderSubtitle =>
      'Exposer les nouveaux conteneurs au sélecteur de fichiers Android par défaut';

  @override
  String get thumbnailCachingDefaultLabel =>
      'Mise en cache des miniatures (par défaut)';

  @override
  String get thumbnailQualityDefaultLabel =>
      'Qualité des miniatures (par défaut)';

  @override
  String get fileAssociationsHeader => 'Associations de fichiers';

  @override
  String get noFileAssociationsYet =>
      'Aucune association de fichiers mémorisée pour le moment. Vous serez invité à en choisir une à l\'ouverture des fichiers.';

  @override
  String get defaultActionsHeader =>
      'Actions par défaut à l\'ouverture de fichiers non standard :';

  @override
  String get removeAssociationTooltip => 'Supprimer l\'association';

  @override
  String get sectionBackupRestore => 'Sauvegarde';

  @override
  String get exportSettingsTitle => 'Exporter les paramètres';

  @override
  String get exportSettingsSubtitle =>
      'Enregistrer les paramètres de l\'application et la disposition du gestionnaire de fichiers dans un fichier';

  @override
  String get importSettingsTitle => 'Importer les paramètres';

  @override
  String get importSettingsSubtitle =>
      'Restaurer les paramètres de l\'application et la disposition du gestionnaire de fichiers à partir d\'un fichier';

  @override
  String get importSettingsConfirmTitle => 'Importer les paramètres ?';

  @override
  String get importSettingsConfirmMessage =>
      'Cela remplacera vos paramètres actuels et la disposition du gestionnaire de fichiers. Cette action est irréversible.';

  @override
  String get exportSettingsSuccessMessage => 'Paramètres exportés';

  @override
  String get importSettingsSuccessMessage => 'Paramètres importés';

  @override
  String get exportSettingsErrorMessage =>
      'Impossible d\'exporter les paramètres';

  @override
  String get importSettingsInvalidFileMessage =>
      'Ce fichier n\'est pas une exportation de paramètres valide';

  @override
  String get sectionDebug => 'Débogage';

  @override
  String get debugLoggingTitle => 'Journalisation de débogage';

  @override
  String get debugLoggingSubtitle =>
      'Enregistrer des journaux de diagnostic détaillés pour les opérations sur les conteneurs';

  @override
  String get logcatTitle => 'Logcat';

  @override
  String get logcatSubtitle =>
      'Voir et enregistrer les journaux de l\'appareil';

  @override
  String logcatSavedMessage(String path) {
    return 'Journal enregistré dans $path';
  }

  @override
  String get logcatSaveErrorMessage => 'Échec de l\'enregistrement du journal';

  @override
  String get logcatCopiedMessage => 'Journal copié dans le presse-papiers';

  @override
  String get logcatUnavailableMessage =>
      'Logcat n\'est pas disponible sur cet appareil';

  @override
  String get logcatEmptyMessage => 'En attente de lignes de journal…';

  @override
  String get logcatClearTooltip => 'Effacer le journal';

  @override
  String get logcatSaveTooltip => 'Enregistrer le journal';

  @override
  String get logcatFilterAppOnly => 'Application uniquement';

  @override
  String get logcatFilterAll => 'Tous les journaux';

  @override
  String get logcatSearchHint => 'Rechercher dans les journaux…';

  @override
  String get logcatClearedMessage => 'Journaux effacés';

  @override
  String get logcatCopyTooltip => 'Copier le journal';

  @override
  String get retryButton => 'Réessayer';

  @override
  String get aboutAppTitle => 'À propos de VaultExplorer';

  @override
  String versionInfoSubtitle(String version) {
    return 'Version $version · Licences open source et détails';
  }

  @override
  String get failedToSaveSettings =>
      'Échec de l\'enregistrement des paramètres';

  @override
  String get masterPasswordSetSnack => 'Mot de passe principal défini';

  @override
  String get passwordCannotBeEmpty => 'Le mot de passe ne peut pas être vide';

  @override
  String get atLeast4CharsRequired => 'Au moins 4 caractères requis';

  @override
  String get passwordsDoNotMatch => 'Les mots de passe ne correspondent pas';

  @override
  String get failedToHashPassword =>
      'Échec du hachage du mot de passe — veuillez réessayer';

  @override
  String get languageLabel => 'Langue';

  @override
  String get biometricNotAvailable =>
      'Biométrie non disponible sur cet appareil';

  @override
  String get unlockVaultExplorerReason => 'Déverrouiller VaultExplorer';

  @override
  String biometricErrorWithCode(String code) {
    return 'Erreur biométrique : $code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds secondes',
      one: '1 seconde',
    );
    return 'Trop de tentatives échouées. Réessayez dans $_temp0.';
  }

  @override
  String get enterMasterPasswordPrompt =>
      'Saisissez votre mot de passe principal';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts tentatives échouées',
      one: '1 tentative échouée',
    );
    return 'Mot de passe incorrect. Verrouillé pendant ${seconds}s après $_temp0.';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts tentatives échouées',
      one: '1 tentative échouée',
    );
    return 'Mot de passe incorrect ($_temp0).';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle =>
      'Saisissez votre mot de passe principal pour continuer';

  @override
  String get masterPasswordFieldLabelTitleCase => 'Mot de passe principal';

  @override
  String get unlock => 'Déverrouiller';

  @override
  String get useBiometric => 'Utiliser la biométrie';

  @override
  String get connectAtLeast4Dots => 'Reliez au moins 4 points';

  @override
  String get patternsDontMatch =>
      'Les schémas ne correspondent pas — réessayez';

  @override
  String get drawUnlockPatternTitle => 'Dessiner le schéma de déverrouillage';

  @override
  String get confirmPatternTitle => 'Confirmez votre schéma';

  @override
  String get drawSamePatternAgain => 'Dessinez à nouveau le même schéma';

  @override
  String get enterAtLeast4Digits => 'Saisissez au moins 4 chiffres';

  @override
  String get pinsDontMatch => 'Les codes PIN ne correspondent pas — réessayez';

  @override
  String get createUnlockPinTitle => 'Créez votre code PIN de déverrouillage';

  @override
  String get confirmPinTitle => 'Confirmez votre code PIN';

  @override
  String get enterSamePinAgain => 'Saisissez à nouveau le même code PIN';

  @override
  String get enterUnlockPinTitle => 'Saisir le code PIN de déverrouillage';

  @override
  String get wrongPinTryAgain => 'Code PIN incorrect — réessayez';

  @override
  String get enterYourPinSequence => 'Saisissez votre code PIN';

  @override
  String get enterPinToMount => 'Saisissez votre code PIN pour monter';

  @override
  String get noPinConfiguredMessage =>
      'Aucun code PIN configuré. Veuillez saisir le mot de passe manuellement.';

  @override
  String pinLockedForSeconds(int seconds) {
    return 'Trop de tentatives échouées. Verrouillé pendant ${seconds}s.';
  }

  @override
  String get initSecureCredsPinMessage =>
      'Initialisation des identifiants sécurisés. Veuillez déverrouiller manuellement une fois pour autoriser l\'accès par code PIN.';

  @override
  String get setPinButton => 'Définir un code PIN';

  @override
  String get changePinButton => 'Changer le code PIN';

  @override
  String get pinSetupRequiredBeforeSaving =>
      'Configurez un code PIN avant d\'enregistrer.';

  @override
  String get pinSetupRequiredAboveBeforeSaving =>
      'Configurez un code PIN ci-dessus avant d\'enregistrer.';

  @override
  String get verifyPinTitle => 'Vérifier le code PIN';

  @override
  String get incorrectPinError => 'Code PIN incorrect';

  @override
  String removedFromListSnack(String name) {
    return '\"$name\" retiré de la liste';
  }

  @override
  String get clearRecentHistoryTitle => 'Effacer l\'historique récent ?';

  @override
  String get clearRecentHistoryMessage =>
      'Cela supprimera tous les documents récents de votre liste. Les fichiers réels sur votre appareil ne seront pas affectés.';

  @override
  String get clearAll => 'Tout effacer';

  @override
  String get recentHistoryClearedSnack => 'Historique récent effacé';

  @override
  String get moreOptionsTooltip => 'Plus d\'options';

  @override
  String get clearHistoryMenuItem => 'Effacer l\'historique';

  @override
  String get openPdfFile => 'Ouvrir un fichier PDF';

  @override
  String get noDocumentsYetTitle => 'Aucun document pour le moment';

  @override
  String get openPdfToStartMessage =>
      'Ouvrez un PDF depuis votre appareil pour commencer la lecture.';

  @override
  String get removeFromListMenuItem => 'Retirer de la liste';

  @override
  String get justNow => 'À l\'instant';

  @override
  String minutesAgo(int count) {
    return 'il y a $count min';
  }

  @override
  String hoursAgo(int count) {
    return 'il y a $count h';
  }

  @override
  String daysAgo(int count) {
    return 'il y a $count j';
  }

  @override
  String get usbDriveDisconnectedLocked =>
      'Clé USB déconnectée — conteneur verrouillé';

  @override
  String get containerAlreadyMounted => 'Ce conteneur est déjà monté.';

  @override
  String get noVaultFolderFormatDetected =>
      'Aucun fichier masterkey.cryptomator, gocryptfs.conf ou cryfs.config trouvé dans ce dossier.';

  @override
  String get savedContainerSettingsNotFound =>
      'Les paramètres enregistrés pour ce conteneur sont introuvables.';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return 'Impossible de mettre à jour l\'emplacement du conteneur : $error';
  }

  @override
  String filePickerFailed(String error) {
    return 'Échec du sélecteur de fichiers : $error';
  }

  @override
  String get selectContainerFirst => 'Sélectionnez d\'abord un conteneur';

  @override
  String get passwordOrKeyfilesRequired =>
      'Mot de passe ou fichiers-clés requis';

  @override
  String get slowPerformanceWarningTitle =>
      'Avertissement de performance lente';

  @override
  String get slowPerformanceWarningMessage =>
      'L\'accès direct au stockage est actuellement désactivé.\n\nCryFS stocke les fichiers répartis sur des milliers de petits blocs. L\'ouverture de coffres CryFS non vides via le SAF Android sera très lente.\n\nVoulez-vous ouvrir les Paramètres pour accorder l\'accès à \"Tous les fichiers\" pour une vitesse rapide ?';

  @override
  String get unlockAnyway => 'Déverrouiller quand même';

  @override
  String get defaultVaultName => 'Coffre';

  @override
  String get defaultContainerName => 'Conteneur';

  @override
  String get incorrectPasswordOrInvalidVault =>
      'Mot de passe incorrect ou coffre invalide';

  @override
  String get incorrectPasswordOrInvalidContainer =>
      'Mot de passe incorrect ou conteneur invalide';

  @override
  String get genericUnknownError => 'Erreur inconnue';

  @override
  String get decryptingLabel => 'Déchiffrement…';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return 'Essai de l\'emplacement de clé $attempted sur $total…';
  }

  @override
  String get luksKeyslotProgressUnknown => 'Essai d\'un emplacement de clé…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return 'Vérification de l\'identifiant $attempted sur $total…';
  }

  @override
  String get bitlockerCredentialProgressUnknown =>
      'Vérification de l\'identifiant…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return 'Essai de $algo ($slotName)…';
  }

  @override
  String get unlockContainerLabel => 'Déverrouiller le conteneur';

  @override
  String get mountContainerTitle => 'Monter un conteneur';

  @override
  String get containerFileSegmentLabel => 'Fichier conteneur';

  @override
  String get folderVaultSegmentLabel => 'Coffre dossier';

  @override
  String formatContainerLabel(String format) {
    return 'Conteneur $format';
  }

  @override
  String formatVaultLabel(String format) {
    return 'Coffre $format';
  }

  @override
  String formatDriveLabel(String format) {
    return 'Lecteur $format';
  }

  @override
  String get encryptedContainerLabel => 'Conteneur chiffré';

  @override
  String get tapToSelectVaultFolder =>
      'Appuyez pour sélectionner le dossier du coffre…';

  @override
  String get tapToSelectContainerFile =>
      'Appuyez pour sélectionner le fichier conteneur…';

  @override
  String get containerMissingTitle => 'Conteneur manquant';

  @override
  String get filePathCouldNotBeResolved =>
      'Le chemin du fichier n\'a pas pu être résolu';

  @override
  String get containerMissingExplanation =>
      'Le fichier conteneur a peut-être été déplacé, supprimé, ou son support de stockage est actuellement déconnecté.';

  @override
  String get retryButtonLabel => 'Réessayer';

  @override
  String get locateFileButtonLabel => 'Localiser le fichier';

  @override
  String get authenticateToMountSubtitle =>
      'Authentifiez-vous pour monter le conteneur en toute sécurité';

  @override
  String get usePasswordButtonLabel => 'Utiliser le mot de passe';

  @override
  String get authenticateButtonLabel => 'S\'authentifier';

  @override
  String get drawUnlockPatternCardTitle =>
      'Dessiner le schéma de déverrouillage';

  @override
  String get wrongPatternTryAgain => 'Schéma incorrect — réessayez';

  @override
  String get connectYourPatternSequence => 'Reliez votre séquence de schéma';

  @override
  String get usePasswordInsteadButtonLabel =>
      'Utiliser le mot de passe à la place';

  @override
  String get passwordHintFolderVault => 'Saisissez le mot de passe du coffre';

  @override
  String get passwordHintBitlocker =>
      'Saisissez le mot de passe ou la clé de récupération';

  @override
  String get passwordHintContainer => 'Saisissez le mot de passe du conteneur';

  @override
  String get usingSavedPasswordTooltip =>
      'Utilisation du mot de passe enregistré';

  @override
  String get luksKeyfileReplacesPasswordNote =>
      'Pour les conteneurs LUKS, le fichier-clé remplace le mot de passe.';

  @override
  String get readOnlyModeUsbSubtitle =>
      'Monter sans autoriser de modifications sur ce lecteur';

  @override
  String get readOnlyModeContainerSubtitle =>
      'Monter sans autoriser de modifications sur ce conteneur';

  @override
  String get rememberContainerLabel => 'Mémoriser le conteneur';

  @override
  String get rememberContainerSubtitle =>
      'Épingler le conteneur sur le tableau de bord pour un accès rapide';

  @override
  String get cancelUnlockButtonLabel => 'Annuler le déverrouillage';

  @override
  String get biometricSubjectContainer => 'conteneur';

  @override
  String get biometricSubjectUsbDrive => 'clé USB';

  @override
  String get usbNoSavedCredentialsMessage =>
      'Aucun mot de passe enregistré trouvé. Veuillez le saisir manuellement.';

  @override
  String get decryptingDriveLabel => 'Déchiffrement du lecteur…';

  @override
  String get usbDeviceAlreadyActiveMounted =>
      'Ce périphérique USB est déjà actif et monté.';

  @override
  String reconnectUsbDriveTitle(String label) {
    return 'Reconnecter \"$label\"';
  }

  @override
  String get unlockUsbDriveTitle => 'Déverrouiller la clé USB';

  @override
  String get noUsbStorageDetectedTitle => 'Aucun stockage USB détecté';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return 'Authentifiez-vous pour déverrouiller $subject';
  }

  @override
  String get noPatternConfiguredMessage =>
      'Aucun schéma configuré. Veuillez saisir le mot de passe manuellement.';

  @override
  String patternLockedForSeconds(int seconds) {
    return 'Trop de tentatives échouées. Verrouillé pendant ${seconds}s.';
  }

  @override
  String get initSecureCredsBiometricMessage =>
      'Initialisation des identifiants sécurisés. Veuillez déverrouiller manuellement une fois pour autoriser l\'accès biométrique.';

  @override
  String get initSecureCredsPatternMessage =>
      'Initialisation des identifiants sécurisés. Veuillez déverrouiller manuellement une fois pour autoriser l\'accès par schéma.';

  @override
  String get mountExistingContainerTitle => 'Monter un conteneur existant';

  @override
  String get mountExistingContainerSubtitle =>
      'Déverrouiller un conteneur fichier que vous possédez déjà';

  @override
  String get mountSplitContainerTitle => 'Monter un conteneur fractionné';

  @override
  String get mountSplitContainerSubtitle =>
      'Déverrouiller directement un conteneur fractionné, sans le réunir au préalable';

  @override
  String get mountUsbDriveTitle => 'Monter une clé USB';

  @override
  String get mountUsbDriveSubtitle =>
      'Déverrouiller un conteneur sur une clé USB OTG';

  @override
  String get formatUsbDriveTitle => 'Formater une clé USB';

  @override
  String get formatUsbDriveSubtitle =>
      'Effacer un lecteur et y créer un nouveau conteneur chiffré';

  @override
  String get createNewContainerTitle => 'Créer un nouveau conteneur';

  @override
  String get createNewContainerSubtitle =>
      'Formater un tout nouveau coffre chiffré';

  @override
  String get lockBeforeRemovingWarning =>
      'Verrouillez le conteneur avant de le retirer.';

  @override
  String get settingsTooltip => 'Paramètres';

  @override
  String get addVaultFabLabel => 'Ajouter un coffre';

  @override
  String removedLabelUndo(String label) {
    return '\"$label\" retiré';
  }

  @override
  String get undo => 'Annuler';

  @override
  String get pdfViewerNoSourceProvided => 'Aucune source PDF fournie.';

  @override
  String get pdfViewerFileEmpty => 'Le fichier PDF est vide ou illisible.';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return 'Échec de la vérification de la taille du fichier PDF : $error';
  }

  @override
  String get pdfViewerErrorLoadingTitle => 'Erreur de chargement du PDF';

  @override
  String get pdfViewerNoDocumentLoaded => 'Aucun document PDF chargé.';

  @override
  String get add => 'Ajouter';

  @override
  String get reset => 'Réinitialiser';

  @override
  String couldNotExpose(String name) {
    return 'Impossible d\'exposer \"$name\".';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return '\"$name\" est maintenant disponible pour les autres applications.';
  }

  @override
  String couldNotUnmount(String name) {
    return 'Impossible de démonter \"$name\".';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments épinglés',
      one: '1 élément épinglé',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments désépinglés',
      one: '1 élément désépinglé',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning =>
      'Montage en lecture seule — les miniatures s\'afficheront mais ne seront pas enregistrées dans le conteneur pour cette session.';

  @override
  String failedLoadingFolder(String type) {
    return 'Échec du chargement du dossier : $type';
  }

  @override
  String failedToReadArchive(String type) {
    return 'Échec de la lecture de l\'archive : $type';
  }

  @override
  String archiveFormatNotSupported(String ext) {
    return 'Le format d\'archive .$ext n\'est pas encore pris en charge';
  }

  @override
  String get failedToReadFileFromArchive =>
      'Échec de la lecture du fichier depuis l\'archive';

  @override
  String failedToExtractFile(String type) {
    return 'Échec de l\'extraction du fichier : $type';
  }

  @override
  String get failedToReadSecureItem =>
      'Échec de la lecture de l\'élément sécurisé';

  @override
  String get openFileDialogTitle => 'Ouvrir le fichier';

  @override
  String chooseHowToOpen(String name) {
    return 'Choisissez comment ouvrir \"$name\" :';
  }

  @override
  String get playVideoAudioViewImageInApp =>
      'Lire la vidéo/l\'audio ou afficher l\'image dans l\'application';

  @override
  String get viewEditTextMarkdownCode =>
      'Afficher/modifier du texte, markdown, code';

  @override
  String get sendFileToThirdPartyApp =>
      'Envoyer le fichier vers une application tierce';

  @override
  String get openAsEllipsis => 'Ouvrir en tant que…';

  @override
  String get chooseFileTypeToOpenAs =>
      'Choisir le type de fichier à utiliser pour l\'ouverture';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return 'Toujours mémoriser ce choix pour les fichiers .$ext';
  }

  @override
  String get alwaysRememberChoiceNoExt =>
      'Toujours mémoriser ce choix pour les fichiers sans extension';

  @override
  String get openAsDialogTitle => 'Ouvrir en tant que';

  @override
  String get mimeTypeText => 'Texte';

  @override
  String get mimeTypeImage => 'Image';

  @override
  String get mimeTypeVideo => 'Vidéo';

  @override
  String get mimeTypeAudio => 'Audio';

  @override
  String get mimeTypeArchive => 'Archive';

  @override
  String get mimeTypeOther => 'Autre';

  @override
  String get scanningSubfoldersForMedia =>
      'Analyse des sous-dossiers à la recherche de médias…';

  @override
  String get noMediaFilesFoundRecursive =>
      'Aucun fichier média trouvé dans ce dossier ou ses sous-dossiers';

  @override
  String failedToScanSubfolders(String error) {
    return 'Échec de l\'analyse des sous-dossiers : $error';
  }

  @override
  String scanningSubfoldersForMediaProgress(int count) {
    return 'Recherche de médias dans les sous-dossiers… $count vérifiés';
  }

  @override
  String get mediaScanCancelled => 'Recherche de médias annulée';

  @override
  String get mediaScanLimitReached =>
      'Recherche arrêtée après avoir vérifié de nombreux dossiers. Aucun média trouvé.';

  @override
  String get noAppFoundForFileType =>
      'Aucune application trouvée pour ce type de fichier';

  @override
  String couldNotOpenFile(String name) {
    return 'Impossible d\'ouvrir \"$name\"';
  }

  @override
  String get readOnlyCantMove =>
      'Ce conteneur est monté en lecture seule — les éléments ne peuvent pas en être déplacés.';

  @override
  String get readOnlyCantPaste =>
      'Ce conteneur est monté en lecture seule — les éléments ne peuvent pas y être collés.';

  @override
  String get clipboardSourceInvalid =>
      'La source du presse-papiers n\'est pas valide';

  @override
  String get crossContainerPasteNotConfigured =>
      'Le collage entre conteneurs n\'est pas configuré.';

  @override
  String get crossContainerPasteRequiresBothMounted =>
      'Le collage entre conteneurs nécessite que les deux conteneurs restent montés.';

  @override
  String get readOnlyCantDelete =>
      'Ce conteneur est monté en lecture seule — les éléments ne peuvent pas être supprimés.';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments supprimés',
      one: '1 élément supprimé',
    );
    return '$_temp0';
  }

  @override
  String deletedWithFailures(int deleted, int failed) {
    return '$deleted supprimés · $failed échoués';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers exportés',
      one: '1 fichier exporté',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed => 'Exportation annulée ou échouée';

  @override
  String exportError(String type) {
    return 'Erreur d\'exportation : $type';
  }

  @override
  String get deleteOriginalTitle => 'Supprimer l\'original ?';

  @override
  String get deleteOriginalFolderMessage =>
      'Supprimer le dossier d\'origine de votre appareil maintenant qu\'il a été importé ?';

  @override
  String get deleteOriginalFilesMessage =>
      'Supprimer le(s) fichier(s) d\'origine de votre appareil maintenant qu\'il(s) a/ont été importé(s) ?';

  @override
  String get keepOriginal => 'Conserver l\'original';

  @override
  String get deleteOriginalButton => 'Supprimer l\'original';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments d\'origine supprimés',
      one: '1 élément d\'origine supprimé',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals =>
      'Impossible de supprimer le(s) original/originaux';

  @override
  String get videoCapturedEncrypted => 'Vidéo capturée et chiffrée';

  @override
  String get photoCapturedEncrypted => 'Photo capturée et chiffrée';

  @override
  String cameraCaptureFailed(String type) {
    return 'Échec de la capture par l\'appareil photo : $type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return 'Extraire tous les fichiers vers le dossier \"$folder\" ?';
  }

  @override
  String get extract => 'Extraire';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers extraits',
      one: '1 fichier extrait',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return 'Échec de l\'extraction : $type';
  }

  @override
  String get closeSearchTooltip => 'Fermer la recherche';

  @override
  String get searchInThisFolderTooltip => 'Rechercher dans ce dossier';

  @override
  String get playMediaHereTooltip => 'Lire les médias ici';

  @override
  String get rootFolderLabel => 'Racine';

  @override
  String folderPickerFailed(String error) {
    return 'Échec du sélecteur de dossier : $error';
  }

  @override
  String get addAVaultTitle => 'Ajouter un coffre';

  @override
  String get selectEmptyDestinationFolderFirst =>
      'Sélectionnez d\'abord un dossier de destination vide';

  @override
  String get passwordRequired => 'Un mot de passe est requis';

  @override
  String get vaultCreatedSuccessfully => 'Coffre créé avec succès.';

  @override
  String get vaultCreationFailedEmptyFolder =>
      'Échec de la création du coffre — assurez-vous que le dossier sélectionné est vide.';

  @override
  String get unknownErrorOccurred => 'Une erreur inconnue s\'est produite';

  @override
  String get containerNameRequired => 'Le nom du conteneur est requis';

  @override
  String get enterValidSizeGreaterThanZero =>
      'Saisissez une taille valide supérieure à 0';

  @override
  String get passwordOrKeyfileRequired =>
      'Un mot de passe ou au moins un fichier-clé est requis';

  @override
  String get standardVolumePasswordsDoNotMatch =>
      'Les mots de passe du volume standard ne correspondent pas';

  @override
  String get hiddenVolumePasswordsDoNotMatch =>
      'Les mots de passe du volume caché ne correspondent pas';

  @override
  String get containerFileCreatedSuccessfully =>
      'Fichier conteneur créé avec succès.';

  @override
  String get containerCreationCancelledOrFailed =>
      'Création du conteneur annulée ou échouée.';

  @override
  String insufficientSpaceForContainer(String needed, String available) {
    return 'Espace libre insuffisant à la destination. Nécessite $needed, seulement $available disponible.';
  }

  @override
  String get vaultKindContainerFile => 'Fichier conteneur';

  @override
  String get vaultKindFolderVault => 'Coffre dossier';

  @override
  String get formatFileSystemLabel => 'Formater le système de fichiers';

  @override
  String get standardVolumeHeader => 'Volume standard';

  @override
  String get containerFormatLabel => 'Format du conteneur';

  @override
  String get fileNameLabel => 'Nom du fichier';

  @override
  String get containerSizeLabel => 'Taille du conteneur';

  @override
  String get unitLabel => 'Unité';

  @override
  String get passwordFieldLabel => 'Mot de passe';

  @override
  String get confirmPasswordFieldLabelTitleCase => 'Confirmer le mot de passe';

  @override
  String get hiddenVolumeHeader => 'Volume caché';

  @override
  String get createHiddenVolumeToggleTitle => 'Créer un volume caché';

  @override
  String get createInvisibleSecondaryVolume =>
      'Créer un volume secondaire invisible';

  @override
  String get setOuterPasswordFirstToEnable =>
      'Définissez d\'abord le mot de passe ou les fichiers-clés externes pour activer';

  @override
  String get hiddenPasswordLabel => 'Mot de passe caché';

  @override
  String get confirmHiddenPasswordLabel => 'Confirmer le mot de passe caché';

  @override
  String get hiddenSizeLabel => 'Taille cachée';

  @override
  String get unitMbMegabytes => 'Mo (Mégaoctets)';

  @override
  String get unitGbGigabytes => 'Go (Gigaoctets)';

  @override
  String get hiddenFileSystemLabel => 'Système de fichiers caché';

  @override
  String get vaultFormatLabel => 'Format du coffre';

  @override
  String get gocryptfsCipherLabel => 'Chiffrement du contenu';

  @override
  String get cryfsCipherLabel => 'Chiffrement du contenu';

  @override
  String get cryfsBlockSizeLabel => 'Taille des blocs';

  @override
  String get destinationFolderLabel => 'Dossier de destination';

  @override
  String get selectEmptyFolderLabel => 'Sélectionnez un dossier vide';

  @override
  String get tapToChooseVaultLocation =>
      'Appuyez pour choisir où le coffre sera créé…';

  @override
  String get folderVaultLimitationsNote =>
      'Les coffres dossier ne prennent pas en charge les fichiers-clés, le PIM, les volumes cachés, ni le choix des algorithmes VeraCrypt/LUKS.';

  @override
  String get createVaultButton => 'Créer le coffre';

  @override
  String get createContainerButton => 'Créer le conteneur';

  @override
  String get vaultCreationInProgressWait =>
      'Création du coffre en cours. Veuillez patienter.';

  @override
  String get containerCreationInProgressWait =>
      'Création du conteneur en cours. Veuillez patienter.';

  @override
  String get createEncryptedVaultTitle => 'Créer un coffre chiffré';

  @override
  String get createEncryptedContainerTitle => 'Créer un conteneur chiffré';

  @override
  String get unitMbShort => 'Mo';

  @override
  String get unitGbShort => 'Go';

  @override
  String failedToListUsbDevices(String error) {
    return 'Échec du listage des périphériques USB : $error';
  }

  @override
  String get usbPermissionDenied => 'Autorisation USB refusée';

  @override
  String get couldNotReadDriveCapacity =>
      'Impossible de lire la capacité du lecteur — saisissez la taille manuellement.';

  @override
  String get selectUsbDriveFirst => 'Sélectionnez d\'abord une clé USB';

  @override
  String eraseDeviceTitle(String name) {
    return 'Effacer \"$name\" ?';
  }

  @override
  String get eraseDeviceMessage =>
      'Cela effacera définitivement tout le contenu actuel de cette clé USB et le remplacera par un nouveau conteneur chiffré. Cette action est irréversible.';

  @override
  String get eraseAndCreateButton => 'Effacer et créer';

  @override
  String get usbPermissionRequiredToContinue =>
      'L\'autorisation USB est requise pour continuer';

  @override
  String get usbContainerCreatedSnack =>
      'Conteneur USB créé. Utilisez \"Monter une clé USB\" pour le déverrouiller.';

  @override
  String get usbContainerCreationFailed =>
      'Échec de la création du conteneur USB.';

  @override
  String get usbStandardVolumeSectionHeader => 'Clé USB et volume standard';

  @override
  String get formattingErasesEverythingWarning =>
      'Le formatage efface tout le contenu actuel du lecteur sélectionné.';

  @override
  String get selectUsbDriveLabel => 'Sélectionner une clé USB';

  @override
  String get noUsbStorageDetected => 'Aucun stockage USB détecté';

  @override
  String get connectOtgDriveToFormat =>
      'Connectez une clé OTG pour la formater';

  @override
  String get refreshListButton => 'Actualiser la liste';

  @override
  String get readyToFormat => 'Prêt à formater';

  @override
  String get permissionRequired => 'Autorisation requise';

  @override
  String get readingDriveCapacity => 'Lecture de la capacité du lecteur…';

  @override
  String get mustNotExceedDriveCapacity =>
      'Ne doit pas dépasser la capacité réelle du lecteur.';

  @override
  String get quickFormatTitle => 'Formatage rapide';

  @override
  String get quickFormatDescription =>
      'Ignore le remplissage à zéro du lecteur. Plus rapide, mais n\'efface pas les anciennes données de façon sécurisée.';

  @override
  String get eraseAndCreateContainerButton => 'Effacer et créer le conteneur';

  @override
  String get usbContainerCreationInProgressWait =>
      'Création du conteneur en cours. Veuillez patienter.';

  @override
  String get formatUsbDriveScreenTitle => 'Formater la clé USB';

  @override
  String get playlistTransitionAnimationLabel =>
      'Animation de transition de la playlist';

  @override
  String get playlistTransitionSlideLabel => 'Glissement (par défaut)';

  @override
  String get playlistTransitionFadeLabel => 'Fondu';

  @override
  String get playlistTransitionZoomLabel => 'Zoom et mise à l\'échelle';

  @override
  String get playlistTransitionDepthLabel => 'Empilement en profondeur';

  @override
  String get playlistTransitionCubeLabel => 'Cube 3D';

  @override
  String get playlistTransitionFlipLabel => 'Retournement 3D';

  @override
  String get unlockVaultTitle => 'Déverrouiller le coffre';

  @override
  String get openContainerTitle => 'Ouvrir le conteneur';

  @override
  String get selectContainerFileOrFolder =>
      'Sélectionner un fichier ou un dossier';

  @override
  String get readOnlyModeLabel => 'Mode lecture seule';

  @override
  String get readOnlyModeSubtitle =>
      'Empêche toute opération d\'écriture ou de modification sur le coffre';

  @override
  String get selectUsbDeviceLabel => 'Sélectionner un périphérique USB';

  @override
  String get noUsbDevicesFound =>
      'Aucun périphérique de stockage USB compatible trouvé';

  @override
  String get containerConfigTitle => 'Configuration du coffre';

  @override
  String get changePasswordTitle => 'Changer le mot de passe';

  @override
  String get confirmNewPasswordLabel => 'Confirmer le nouveau mot de passe';

  @override
  String get cameraCaptureTitle => 'Appareil photo du coffre';

  @override
  String get takingPhoto => 'Capture de la photo…';

  @override
  String get savingToVault => 'Enregistrement dans le coffre…';

  @override
  String get noVaultSelected => 'Aucun coffre sélectionné';

  @override
  String get mediaDiagnosticsTitle => 'Diagnostics multimédias';

  @override
  String get advancedViewerSettingsTitle => 'Paramètres de la visionneuse';

  @override
  String get textEditorSaveConfirmTitle => 'Modifications non enregistrées';

  @override
  String get textEditorSaveConfirmMessage =>
      'Voulez-vous enregistrer vos modifications avant de fermer ?';

  @override
  String get saveAndClose => 'Enregistrer et fermer';

  @override
  String get discardChanges => 'Abandonner les modifications';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments sélectionnés',
      one: '1 élément sélectionné',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'Tout sélectionner';

  @override
  String get deselectAll => 'Tout désélectionner';

  @override
  String get sortOptionsTitle => 'Trier les fichiers';

  @override
  String get layoutModeList => 'Vue en liste';

  @override
  String get layoutModeGrid => 'Vue en grille';

  @override
  String get layoutModeMasonry => 'Mosaïque';

  @override
  String get fileOperationsTitle => 'Opérations sur les fichiers';

  @override
  String get conflictResolutionTitle => 'Conflit de fichier';

  @override
  String get replaceExistingFile => 'Remplacer le fichier existant';

  @override
  String get keepBothFiles =>
      'Conserver les deux (renommer le nouveau fichier)';

  @override
  String get skipFile => 'Ignorer ce fichier';

  @override
  String get noVaultsFoundTitle => 'Aucun coffre trouvé';

  @override
  String get noVaultsFoundSubtitle =>
      'Créez un nouveau conteneur chiffré ou ajoutez un coffre existant pour commencer.';

  @override
  String get addExistingVaultButton => 'Ajouter un coffre existant';

  @override
  String get sortContainersModeManual => 'Manuel (glisser pour réorganiser)';

  @override
  String get sortContainersModeUnlockStatus =>
      'État de déverrouillage (déverrouillés en premier)';

  @override
  String get sortContainersModeNameAZ => 'Nom (A–Z)';

  @override
  String get sortContainersModeNameZA => 'Nom (Z–A)';

  @override
  String get sortContainersModeNewest => 'Plus récents en premier';

  @override
  String get sortContainersModeOldest => 'Plus anciens en premier';

  @override
  String get thumbnailCacheAppCacheLabel => 'Cache de l\'application';

  @override
  String get thumbnailCacheAppCacheDesc =>
      'Stocké chiffré dans le cache de l\'application. Rapide ; effacé automatiquement en cas de manque d\'espace.';

  @override
  String get thumbnailCacheInContainerLabel => 'Dans le conteneur';

  @override
  String get thumbnailCacheInContainerDesc =>
      'Stocké dans le conteneur chiffré. Protégé par le conteneur lui-même, mais l\'écriture est plus lente.';

  @override
  String get thumbnailCacheHiddenFolderLabel => 'Dossier caché';

  @override
  String get thumbnailCacheHiddenFolderDesc =>
      'Stocké dans un dossier caché .thumbcache à la racine. Contrairement au cache de l\'application, il n\'est pas effacé automatiquement.';

  @override
  String get thumbnailCacheDisabledLabel => 'Désactivé';

  @override
  String get thumbnailCacheDisabledDesc =>
      'Aucun cache disque. Les miniatures sont régénérées à chaque chargement.';

  @override
  String get unlockContainerTitle => 'Déverrouiller le conteneur';

  @override
  String get containerFileSegment => 'Fichier conteneur';

  @override
  String get folderVaultSegment => 'Coffre dossier';

  @override
  String get enableButtonLabel => 'Activer';

  @override
  String get retryButtonLabelShort => 'Réessayer';

  @override
  String get locateFileButton => 'Localiser le fichier';

  @override
  String get authenticateButton => 'S\'authentifier';

  @override
  String get cancelUnlockButton => 'Annuler le déverrouillage';

  @override
  String tryingKeyslotProgress(int attempted, int total) {
    return 'Essai de l\'emplacement de clé $attempted sur $total…';
  }

  @override
  String get tryingKeyslotSingle => 'Essai d\'un emplacement de clé…';

  @override
  String verifyingCredentialProgress(int attempted, int total) {
    return 'Vérification de l\'identifiant $attempted sur $total…';
  }

  @override
  String get verifyingCredentialSingle => 'Vérification de l\'identifiant…';

  @override
  String tryingAlgoSlot(String algo, String slotName) {
    return 'Essai de $algo ($slotName)…';
  }

  @override
  String get hiddenVolumeSlotName => 'Volume caché';

  @override
  String get standardVolumeSlotName => 'Volume standard';

  @override
  String get containerMissingSubtitle =>
      'Le chemin du fichier n\'a pas pu être résolu';

  @override
  String get containerMissingBody =>
      'Le fichier conteneur a peut-être été déplacé, supprimé, ou son support de stockage est actuellement déconnecté.';

  @override
  String get connectPatternSequence => 'Reliez votre séquence de schéma';

  @override
  String get passwordLabel => 'Mot de passe';

  @override
  String get enterVaultPasswordHint => 'Saisissez le mot de passe du coffre';

  @override
  String get enterBitlockerPasswordHint =>
      'Saisissez le mot de passe ou la clé de récupération';

  @override
  String get enterContainerPasswordHint =>
      'Saisissez le mot de passe du conteneur';

  @override
  String get readOnlyModeUsbSubtitleDrive =>
      'Monter sans autoriser de modifications sur ce lecteur';

  @override
  String get rememberDriveLabel => 'Mémoriser le lecteur';

  @override
  String get rememberDriveSubtitle =>
      'Épingler le lecteur sur le tableau de bord pour un accès rapide';

  @override
  String get unlockVaultButtonLabel => 'Déverrouiller le coffre';

  @override
  String get cryfsStorageAccessWarning =>
      'Les coffres CryFS utilisent des milliers de petits fichiers de blocs. Sans accès direct au stockage, les performances seront nettement plus lentes.';

  @override
  String get folderVaultStorageAccessWarning =>
      'L\'accès direct au stockage est désactivé. L\'ouverture et la lecture des fichiers dans les coffres dossier peuvent être plus lentes.';

  @override
  String get requestingPermission => 'Demande d\'autorisation…';

  @override
  String get unlockAndMountButton => 'Déverrouiller et monter';

  @override
  String get unlockDriveButton => 'Déverrouiller le lecteur';

  @override
  String couldntFindDevice(String deviceName) {
    return 'Impossible de trouver \"$deviceName\"';
  }

  @override
  String get plugDriveBackInRetry =>
      'Rebranchez le lecteur et appuyez sur Réessayer, ou sélectionnez-le ci-dessous s\'il apparaît sous un nom différent.';

  @override
  String get retryConnectionButton => 'Réessayer la connexion';

  @override
  String get refreshDevicesButton => 'Actualiser les périphériques';

  @override
  String get connectOtgDriveToMount =>
      'Connectez une clé USB OTG pour la monter';

  @override
  String get alreadyActive => 'Déjà actif';

  @override
  String get active => 'Actif';

  @override
  String get readyToUnlock => 'Prêt à déverrouiller';

  @override
  String get enterUsbPartitionPassword =>
      'Saisissez le mot de passe de la partition USB';

  @override
  String get biometricAuthenticationTitle => 'Authentification biométrique';

  @override
  String get biometricAuthUsbSubtitle =>
      'Authentifiez-vous pour déverrouiller et monter ce périphérique USB';

  @override
  String get connectPatternSequenceToMount =>
      'Reliez votre séquence de schéma pour monter';

  @override
  String get selectAllAction => 'Tout sélectionner';

  @override
  String get clearSelectionAction => 'Effacer la sélection';

  @override
  String get clearSelectionTooltip => 'Effacer la sélection';

  @override
  String get selectionOptionsTooltip => 'Options de sélection';

  @override
  String get readOnlyContainerTooltip => 'Conteneur en lecture seule';

  @override
  String get copyAction => 'Copier';

  @override
  String get moveAction => 'Déplacer';

  @override
  String get renameAction => 'Renommer';

  @override
  String get exportToDeviceAction => 'Exporter vers l\'appareil';

  @override
  String get openWithAppAction => 'Ouvrir avec une application';

  @override
  String get pinAction => 'Épingler';

  @override
  String get pinSelectedAction => 'Épingler la sélection';

  @override
  String get unpinAction => 'Désépingler';

  @override
  String get unpinSelectedAction => 'Désépingler la sélection';

  @override
  String get documentProviderSettingsMenu =>
      'Paramètres du fournisseur de documents';

  @override
  String get exposeAsDocumentProviderMenu =>
      'Exposer en tant que fournisseur de documents';

  @override
  String get moreOptionsTooltipShort => 'Plus d\'options';

  @override
  String get copyTooltip => 'Copier';

  @override
  String get searchInThisFolderHint => 'Rechercher dans ce dossier…';

  @override
  String get clearTooltip => 'Effacer';

  @override
  String get backToDashboardTooltip => 'Retour au tableau de bord';

  @override
  String get cancelPasteButton => 'Annuler le collage';

  @override
  String get cancelImportButton => 'Annuler l\'importation';

  @override
  String get continueButton => 'Continuer';

  @override
  String get skipButton => 'Ignorer';

  @override
  String get keepBothButton => 'Conserver les deux';

  @override
  String get clearAllButton => 'Tout effacer';

  @override
  String get autoMountWhenUnlocksTitle =>
      'Monter automatiquement au déverrouillage du conteneur';

  @override
  String get autoMountWhenUnlocksSubtitle =>
      'Exposer à nouveau ce dossier automatiquement la prochaine fois';

  @override
  String get unmountButton => 'Démonter';

  @override
  String get filtersMenuItem => 'Filtres';

  @override
  String get settingsMenuItem => 'Paramètres';

  @override
  String get sortOptionsTooltip => 'Options de tri';

  @override
  String get layoutOptionsTooltip => 'Options de mise en page';

  @override
  String get lockContainerTooltip => 'Verrouiller le conteneur';

  @override
  String get renameTooltip => 'Renommer';

  @override
  String get cancelUpdatingPasswordTooltip =>
      'Annuler la mise à jour du mot de passe';

  @override
  String get unlockSettingsButton => 'Paramètres de déverrouillage';

  @override
  String get updateSavedCredentialsButton =>
      'Mettre à jour les identifiants enregistrés';

  @override
  String get verifyCredentialsTitle => 'Vérifier les identifiants';

  @override
  String get verifyButton => 'Vérifier';

  @override
  String get displayNameTitle => 'Nom d\'affichage';

  @override
  String get containerNameHint => 'Nom du conteneur';

  @override
  String get deleteFileDialogTitle => 'Supprimer le fichier ?';

  @override
  String get deleteFilePermanentWarning =>
      'Cette action est définitive et irréversible.';

  @override
  String get unsavedChangesTitle => 'Modifications non enregistrées';

  @override
  String get unsavedChangesMessage =>
      'Vous avez des modifications non enregistrées. Voulez-vous les enregistrer avant de fermer ?';

  @override
  String get discardButton => 'Abandonner';

  @override
  String get decryptingFileContent => 'Déchiffrement du contenu du fichier...';

  @override
  String get cannotOpenFile => 'Impossible d\'ouvrir le fichier';

  @override
  String get changesSavedSuccessfully =>
      'Modifications enregistrées avec succès';

  @override
  String saveFailedWithError(String error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String linesCount(int count) {
    return 'Lignes : $count';
  }

  @override
  String charsCount(int count) {
    return 'Caractères : $count';
  }

  @override
  String get unsavedChangesLabel => 'Modifications non enregistrées';

  @override
  String get savedToVault => 'Enregistré dans le coffre';

  @override
  String get saveChangesTooltip => 'Enregistrer les modifications';

  @override
  String get textEditorDecryptFailedMessage =>
      'Échec du déchiffrement du fichier depuis le coffre.';

  @override
  String get textEditorInvalidTextFileMessage =>
      'Ce fichier ne semble pas être un fichier texte valide.';

  @override
  String get textEditorWriteBackFailedMessage =>
      'Échec de la réécriture du fichier dans le coffre.';

  @override
  String get backTooltip => 'Retour';

  @override
  String get forwardTooltip => 'Suivant';

  @override
  String get reloadTooltip => 'Recharger';

  @override
  String get optionsTooltip => 'Options';

  @override
  String get htmlViewerErrorTitle => 'Impossible d\'afficher cette page';

  @override
  String get htmlViewerLoadFailedMessage => 'Échec du chargement du fichier';

  @override
  String get enableJavaScriptDialogTitle => 'Activer JavaScript ?';

  @override
  String get enableJavaScriptDialogMessage =>
      'La page sera autorisée à exécuter ses propres scripts locaux. Elle n\'a toujours aucun accès réseau — rien dans ce coffre ne peut être envoyé ou reçu par Internet.';

  @override
  String get disableJavaScriptMenu => 'Désactiver JavaScript';

  @override
  String get enableJavaScriptMenu => 'Activer JavaScript';

  @override
  String get enterFullscreenMenu => 'Passer en plein écran';

  @override
  String failedToOpenExternalApp(String error) {
    return 'Échec de l\'ouverture dans une application externe : $error';
  }

  @override
  String get thisFolderMenu => 'Ce dossier';

  @override
  String get allInclSubfoldersMenu => 'Tout (sous-dossiers inclus)';

  @override
  String get disableShuffleMenu => 'Désactiver la lecture aléatoire';

  @override
  String get shufflePlaylistMenu => 'Lecture aléatoire de la playlist';

  @override
  String get playlistOptionsTooltip => 'Options de la playlist';

  @override
  String get enablePlaylistTooltip => 'Activer la playlist';

  @override
  String get moreActionsTooltip => 'Plus d\'actions';

  @override
  String get forcePortraitMenu => 'Forcer le mode portrait';

  @override
  String get forceLandscapeMenu => 'Forcer le mode paysage';

  @override
  String get autoRotateSensorMenu => 'Rotation automatique (capteur)';

  @override
  String get screenOrientationMenu => 'Orientation de l\'écran';

  @override
  String get playlistTransitionMenu => 'Transition de la playlist';

  @override
  String get renameFileMenu => 'Renommer le fichier';

  @override
  String get deleteFileMenu => 'Supprimer le fichier';

  @override
  String get thumbnailCarouselTooltip => 'Carrousel de miniatures';

  @override
  String get advancedSettingsTooltip => 'Paramètres avancés';

  @override
  String get previousTooltip => 'Précédent';

  @override
  String get nextTooltip => 'Suivant';

  @override
  String get diagnosticsCopiedToClipboard =>
      'Diagnostics copiés dans le presse-papiers';

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get copyDiagnosticsTooltip => 'Copier les diagnostics';

  @override
  String get closeTooltip => 'Fermer';

  @override
  String get diagnosticsPlaybackSection => 'Lecture';

  @override
  String get diagnosticsEngineSection => 'Moteur';

  @override
  String get diagnosticsStateLabel => 'État';

  @override
  String get diagnosticsResolutionLabel => 'Résolution';

  @override
  String get diagnosticsAspectRatioLabel => 'Format d\'image';

  @override
  String get diagnosticsPositionLabel => 'Position';

  @override
  String get diagnosticsDurationLabel => 'Durée';

  @override
  String get diagnosticsErrorLabel => 'Erreur';

  @override
  String get diagnosticsPlayerLabel => 'Lecteur';

  @override
  String get diagnosticsDecodingLabel => 'Décodage';

  @override
  String get diagnosticsExoPlayerValue => 'ExoPlayer (Android)';

  @override
  String get diagnosticsHardwareAcceleratedValue => 'Accéléré matériellement';

  @override
  String get diagnosticsUnknownValue => 'Inconnu';

  @override
  String get diagnosticsStateBuffering => 'Mise en mémoire tampon';

  @override
  String get diagnosticsStatePlaying => 'Lecture en cours';

  @override
  String get diagnosticsStatePaused => 'En pause';

  @override
  String get diagnosticsDurationUnavailable => '--:--';

  @override
  String get rotate90Label => 'Pivoter de 90°';

  @override
  String get imageFitModeLabel => 'Mode d\'ajustement de l\'image';

  @override
  String get slideshowDelayLabel => 'Délai du diaporama';

  @override
  String get playbackSpeedLabel => 'Vitesse de lecture';

  @override
  String get subtitlesLabel => 'Sous-titres';

  @override
  String get imageSettingsTitle => 'Paramètres de l\'image';

  @override
  String get playbackSettingsTitle => 'Paramètres de lecture';

  @override
  String get imageFitContain => 'Contenir';

  @override
  String get imageFitWidth => 'Ajuster à la largeur';

  @override
  String get imageFitHeight => 'Ajuster à la hauteur';

  @override
  String nSecondsDelay(int n) {
    return '$n secondes';
  }

  @override
  String playbackSpeedNormal(String speed) {
    return '${speed}x (Normal)';
  }

  @override
  String playbackSpeedValue(String speed) {
    return '${speed}x';
  }

  @override
  String slideshowDelaySecondsValue(int seconds) {
    return '${seconds}s';
  }

  @override
  String rotationDegreesValue(int degrees) {
    return '$degrees°';
  }

  @override
  String get settingsTooltipShort => 'Paramètres';

  @override
  String get sourceCodeTooltip => 'Code source';

  @override
  String get donateTooltip => 'Faire un don';

  @override
  String get shareAppTooltip => 'Partager l\'application';

  @override
  String get resetToDefaultsTooltip => 'Réinitialiser par défaut';

  @override
  String get usbUnlockContainerTitle => 'Déverrouiller le conteneur USB';

  @override
  String get usbMountContainerTitle => 'Monter une clé USB';

  @override
  String get staticLabel => 'Statique';

  @override
  String get unmuteTooltip => 'Rétablir le son';

  @override
  String get muteTooltip => 'Couper le son';

  @override
  String get playOnceDisabledTooltip =>
      'Lire une fois (avance automatique désactivée)';

  @override
  String get playAndAdvanceTooltip => 'Lire et passer au suivant';

  @override
  String get loopCurrentVideoTooltip => 'Boucler la vidéo actuelle';

  @override
  String get clearThumbnailCacheDialogTitle =>
      'Vider le cache des miniatures ?';

  @override
  String get clearThumbnailCacheDialogMessage =>
      'Cela supprimera les miniatures mises en cache pour ce coffre. Elles seront régénérées la prochaine fois que vous parcourrez les médias.';

  @override
  String get clearCacheButton => 'Vider le cache';

  @override
  String get appCacheClearedUnlockMessage =>
      'Cache de l\'application vidé. Déverrouillez le conteneur pour vider le cache interne.';

  @override
  String get allThumbnailCachesClearedMessage =>
      'Tous les caches de miniatures ont été vidés avec succès.';

  @override
  String get appCacheClearedContainerFailedMessage =>
      'Cache de l\'application vidé, mais échec du vidage à l\'intérieur du conteneur.';

  @override
  String get failedToClearThumbnailCachesMessage =>
      'Échec du vidage des caches de miniatures.';

  @override
  String get authenticateToModifySettingsPrompt =>
      'Authentifiez-vous pour modifier les paramètres';

  @override
  String get usbVaultSettingsTitle => 'Paramètres du coffre USB';

  @override
  String get vaultSettingsTitle => 'Paramètres du coffre';

  @override
  String get generalSectionHeader => 'Général';

  @override
  String get securityCredentialsSectionHeader => 'Sécurité et identifiants';

  @override
  String get securityOptionsLockedTitle => 'Options de sécurité verrouillées';

  @override
  String get authenticateOriginalCredentialsMessage =>
      'Authentifiez-vous avec les identifiants d\'origine du conteneur pour modifier les paramètres de sécurité.';

  @override
  String get unlockCredentialsLabel => 'Identifiants de déverrouillage';

  @override
  String get unavailableSuffixLabel => '(Indisponible)';

  @override
  String get patternSetupRequiredBeforeSaving =>
      'Configurez un schéma avant d\'enregistrer.';

  @override
  String get passwordKeystoreEncryptedHelperText =>
      'Le mot de passe est chiffré via l\'Android Keystore. Laissez vide si vous utilisez uniquement des fichiers-clés.';

  @override
  String get changePatternButton => 'Changer le schéma';

  @override
  String get setPatternButton => 'Définir un schéma';

  @override
  String get cacheDerivedKeyLabel => 'Mettre en cache la clé dérivée';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      'Ignorer le KDF scrypt de CryFS la prochaine fois (clé conservée dans l\'Android Keystore)';

  @override
  String get reuseKeyMaterialKeystoreSubtitle =>
      'Réutiliser la clé stockée dans l\'Android Keystore';

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle =>
      'Épingler l\'algorithme pour ignorer la détection automatique au déverrouillage.';

  @override
  String get changeContainerPasswordTitle =>
      'Changer le mot de passe du conteneur';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      'Les identifiants BitLocker ne peuvent pas être modifiés dans l\'application. Utilisez \"Gérer BitLocker\" sous Windows.';

  @override
  String get systemIntegrationSectionHeader => 'Système et intégration';

  @override
  String get autoLockDurationLabel => 'Durée avant verrouillage automatique';

  @override
  String get neverAutoLockOption => 'Jamais';

  @override
  String get exposeContentToFilePickerSubtitle =>
      'Exposer le contenu au sélecteur de fichiers système une fois déverrouillé';

  @override
  String get thumbnailStorageSectionHeader => 'Stockage des miniatures';

  @override
  String get cacheModeLabel => 'Mode de cache';

  @override
  String get useGlobalDefaultSubtitle =>
      'Utiliser la valeur par défaut globale';

  @override
  String get thumbnailQualityLabel => 'Qualité des miniatures';

  @override
  String get clearThumbnailCacheTitle => 'Vider le cache des miniatures';

  @override
  String get removeCachedThumbnailsSubtitle =>
      'Supprimer les miniatures d\'images et de vidéos mises en cache';

  @override
  String get vaultInformationSectionHeader => 'Informations sur le coffre';

  @override
  String get vaultInformationTileTitle => 'Voir les détails du coffre';

  @override
  String get vaultInformationTileSubtitle =>
      'Chiffrement, format et autres détails techniques';

  @override
  String get vaultInfoLocationLabel => 'Emplacement';

  @override
  String get vaultInfoRequiresUnlockTitle => 'Déverrouillage requis';

  @override
  String get vaultInfoRequiresUnlockMessage =>
      'Déverrouillez ce coffre pour voir ses détails techniques.';

  @override
  String get vaultInfoLoadFailedTitle =>
      'Impossible de charger les informations du coffre';

  @override
  String get vaultInfoLoadFailedMessage =>
      'Un problème est survenu lors de la lecture des détails de ce coffre.';

  @override
  String get vaultInfoVolumeSizeLabel => 'Taille du volume';

  @override
  String get vaultInfoFileSystemLabel => 'Système de fichiers';

  @override
  String get vaultInfoHiddenVolumeLabel => 'Volume caché';

  @override
  String get vaultInfoReadOnlyLabel => 'Lecture seule';

  @override
  String get vaultInfoLuksVersionLabel => 'Version LUKS';

  @override
  String get vaultInfoSectorSizeLabel => 'Taille de secteur';

  @override
  String get vaultInfoVaultFormatLabel => 'Format du coffre';

  @override
  String get vaultInfoCipherComboLabel => 'Combinaison de chiffrement';

  @override
  String get vaultInfoShorteningThresholdLabel =>
      'Seuil de raccourcissement des noms de fichiers';

  @override
  String get vaultInfoFormatVersionLabel => 'Version du format';

  @override
  String get vaultInfoContentCipherLabel => 'Chiffrement du contenu';

  @override
  String get vaultInfoFilenameEncryptionLabel => 'Noms de fichiers';

  @override
  String get vaultInfoPlaintextNamesValue => 'Non chiffrés';

  @override
  String get vaultInfoEncryptedNamesValue => 'Chiffrés';

  @override
  String get vaultInfoBlockCipherLabel => 'Chiffrement par bloc';

  @override
  String get vaultInfoBlockSizeLabel => 'Taille des blocs';

  @override
  String get vaultInfoCreatedWithVersionLabel => 'Créé avec';

  @override
  String get vaultInfoLastOpenedWithVersionLabel => 'Dernière ouverture avec';

  @override
  String get vaultInfoYesValue => 'Oui';

  @override
  String get vaultInfoNoValue => 'Non';

  @override
  String get vaultInfoBitlockerNote =>
      'Cette application n\'analyse pas les métadonnées d\'en-tête propres à BitLocker ; les détails de chiffrement et de version ne sont donc pas disponibles ici.';

  @override
  String get patternSetupRequiredAboveBeforeSaving =>
      'Configurez un schéma ci-dessus avant d\'enregistrer.';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      'Un mot de passe ou \"Mettre en cache la clé dérivée\" avec des fichiers-clés est requis pour cette méthode de déverrouillage.';

  @override
  String get saveConfigurationButton => 'Enregistrer la configuration';

  @override
  String get incorrectPatternError => 'Schéma incorrect';

  @override
  String get verifyPatternTitle => 'Vérifier le schéma';

  @override
  String get incorrectPasswordError => 'Mot de passe incorrect';

  @override
  String get verificationFailedError => 'Échec de la vérification';

  @override
  String get incorrectCredentialsError => 'Identifiants incorrects';

  @override
  String get containerPasswordOptionalLabel =>
      'Mot de passe du conteneur (facultatif si fichiers-clés uniquement)';

  @override
  String get pimOptionalLabel => 'PIM (facultatif)';

  @override
  String get usbDriveLockedLabel => 'Clé USB · Verrouillée';

  @override
  String get lockedContainerLabel => 'Conteneur verrouillé';

  @override
  String get operationInProgressWaitMessage =>
      'Une opération est en cours. Veuillez patienter avant de verrouiller.';

  @override
  String get reconnectUsbTooltip => 'Reconnecter la clé USB';

  @override
  String get unlockContainerTooltip => 'Déverrouiller le conteneur';

  @override
  String lockFailedMessage(String errorType) {
    return 'Échec du verrouillage : $errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired =>
      'Un nouveau mot de passe ou des fichiers-clés sont requis.';

  @override
  String get newPasswordsDoNotMatch =>
      'Les nouveaux mots de passe ne correspondent pas.';

  @override
  String get passwordChangedSuccessfullyMessage =>
      'Mot de passe changé avec succès.';

  @override
  String get failedToChangePasswordMessage =>
      'Échec du changement de mot de passe. Vérifiez les anciens identifiants.';

  @override
  String get currentCredentialsSectionHeader => 'Identifiants actuels';

  @override
  String get oldPasswordLabel => 'Ancien mot de passe';

  @override
  String get oldPimOptionalLabel => 'Ancien PIM (facultatif)';

  @override
  String get newCredentialsSectionHeader => 'Nouveaux identifiants';

  @override
  String get newPimOptionalLabel => 'Nouveau PIM (facultatif)';

  @override
  String get noContainersYetTitle => 'Aucun conteneur pour le moment';

  @override
  String get dashboardEmptyStateMessage =>
      'Montez un conteneur VeraCrypt, connectez une clé USB ou créez un tout nouveau coffre chiffré pour commencer.';

  @override
  String get sortFieldName => 'Nom';

  @override
  String get sortFieldSize => 'Taille';

  @override
  String get sortFieldType => 'Type';

  @override
  String get sortFieldDate => 'Date';

  @override
  String get layoutModeDetailedList => 'Liste détaillée';

  @override
  String get layoutModeCompactList => 'Liste compacte';

  @override
  String get layoutModeGalleryGrid => 'Grille galerie';

  @override
  String get readOnlyCantDeleteTooltip =>
      'Lecture seule — impossible de supprimer';

  @override
  String get readOnlyCantMoveTooltip =>
      'Lecture seule — impossible de déplacer';

  @override
  String get readOnlyCantRenameTooltip =>
      'Lecture seule — impossible de renommer';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes (calcul en cours…)';
  }

  @override
  String get sizeCalculatingLabel => 'calcul en cours…';

  @override
  String get editSecureItemsToRenameMessage =>
      'Modifiez les éléments sécurisés pour les renommer';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage =>
      'Les éléments du coffre ne peuvent pas être ouverts dans des applications externes';

  @override
  String get mountedReadOnlyTooltip => 'Monté en lecture seule';

  @override
  String get readOnlyBadgeAbbreviation => 'LS';

  @override
  String freeSpaceLabel(String bytes) {
    return '$bytes libres';
  }

  @override
  String get filteredLabel => 'filtré';

  @override
  String get statsStorageSectionHeader => 'STOCKAGE';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dossiers',
      one: '1 dossier',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers',
      one: '1 fichier',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => 'Tous les fichiers';

  @override
  String get filterImagesOption => 'Images';

  @override
  String get filterVideosOption => 'Vidéos';

  @override
  String get filterAudioOption => 'Audio';

  @override
  String get filterDocumentsOption => 'Documents';

  @override
  String get folderExposedAsStorageExplanation =>
      'Ce dossier est exposé en tant qu\'emplacement de stockage à part entière, permettant à d\'autres applications de parcourir et d\'ouvrir directement ses fichiers.';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments existent déjà',
      one: '1 élément existe déjà',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle =>
      'Choisissez ce qui se passe pour chaque élément, ou appliquez un choix à tous.';

  @override
  String get skipAllChipLabel => 'Tout ignorer';

  @override
  String get overwriteAllChipLabel => 'Tout remplacer';

  @override
  String get overwriteItemDropdownLabel => 'Remplacer';

  @override
  String get overwriteFolderDropdownLabel => 'Remplacer le dossier';

  @override
  String get fileOpsTransfersInProgressTitle => 'Transferts en cours';

  @override
  String get fileOpsRecentTransfersTitle => 'Transferts récents';

  @override
  String get fileOpsNoRecentTransfersMessage => 'Aucun transfert récent';

  @override
  String get fileOpsNoRecentTransfersSubtitle =>
      'Les copies, déplacements et suppressions apparaîtront ici pendant leur exécution.';

  @override
  String fileOpsShowDetailsLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '1 élément',
    );
    return '$_temp0';
  }

  @override
  String get fileOpsCancelTooltip => 'Annuler';

  @override
  String get fileOpsDismissTooltip => 'Ignorer';

  @override
  String get fileOpsRootDestinationLabel => 'Racine';

  @override
  String get fileOpsCancelledStatusLabel => 'Annulé';

  @override
  String fileOpsItemsFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments ont échoué :',
      one: '1 élément a échoué :',
    );
    return '$_temp0';
  }

  @override
  String fileOpsMoreItemsLabel(num count) {
    return '+ $count de plus';
  }

  @override
  String get transferActivityTooltip => 'Transferts';

  @override
  String fileOpsSpeedLabel(String speed) {
    return '$speed/s';
  }

  @override
  String fileOpsEtaLabel(String time) {
    return '~$time restant';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return 'Erreur de lecture du fichier : $error';
  }

  @override
  String get archivePreviewNotAvailableMessage =>
      'Aperçu non disponible pour ce type de fichier.';

  @override
  String get avifFailedToRenderMessage => 'Échec de l\'affichage de l\'AVIF';

  @override
  String get encryptedImageLoadFailedMessage =>
      'Échec du chargement de l\'image chiffrée';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return 'Échec du chargement de l\'image chiffrée : $error';
  }

  @override
  String get invalidOrCorruptedImageMessage =>
      'Format d\'image invalide ou corrompu.';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '$current sur $total';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '$current sur $total  ·  analyse en cours…';
  }

  @override
  String get mediaViewerScanningLabel => 'Analyse en cours…';

  @override
  String get mediaFileDeletedMessage => 'Fichier supprimé avec succès';

  @override
  String get mediaFileDeleteFailedMessage =>
      'Échec de la suppression du fichier';

  @override
  String get mediaFileRenamedMessage => 'Fichier renommé avec succès';

  @override
  String get aboutScreenTitle => 'À propos';

  @override
  String get couldNotOpenLinkMessage => 'Impossible d\'ouvrir le lien';

  @override
  String get fileManagerSettingsTitle =>
      'Paramètres du gestionnaire de fichiers';

  @override
  String get showMediaThumbnailsLabel => 'Afficher les miniatures des médias';

  @override
  String get showMediaThumbnailsDesc =>
      'Afficher des aperçus miniatures pour les images et vidéos en vue liste';

  @override
  String get showFileNamesLabel => 'Afficher les noms de fichiers';

  @override
  String get showFileNamesDesc =>
      'Afficher les libellés textuels sous les éléments en vue grille';

  @override
  String get showBreadcrumbBarLabel => 'Afficher le fil d\'Ariane';

  @override
  String get showBreadcrumbBarDesc =>
      'Barre de navigation du chemin en haut du navigateur';

  @override
  String get showStatsBarLabel => 'Afficher la barre de statistiques';

  @override
  String get showStatsBarDesc =>
      'Bandeau d\'informations sur le nombre de fichiers et l\'espace libre';

  @override
  String get autoStartPlaylistModeLabel =>
      'Démarrage automatique du mode playlist';

  @override
  String get autoStartPlaylistModeDesc =>
      'Démarrer automatiquement en mode playlist à l\'ouverture d\'un élément multimédia';

  @override
  String get showPlaylistCarouselLabel =>
      'Afficher le carrousel de la playlist';

  @override
  String get showPlaylistCarouselDesc =>
      'Afficher le bouton du carrousel de miniatures lors de la visualisation de playlists multimédias';

  @override
  String get videoPlaybackSliderLabel => 'Curseur de position de lecture vidéo';

  @override
  String get longPressPlaybackDiagnosticsHint =>
      'Appui long pour les diagnostics de lecture';

  @override
  String get staticImageModeLabel => 'Mode image statique';

  @override
  String slideshowModeActiveLabel(int seconds) {
    return 'Mode diaporama actif avec un délai de $seconds secondes';
  }

  @override
  String videoPlaybackModeLabel(String mode) {
    return 'Mode de lecture vidéo : $mode';
  }

  @override
  String get pauseLabel => 'Pause';

  @override
  String get playLabel => 'Lecture';

  @override
  String get emptyFolderTitle => 'Dossier vide';

  @override
  String get emptyFolderMessage =>
      'Utilisez l\'action Ajouter pour créer des fichiers ou en importer depuis l\'appareil.';

  @override
  String get noResultsTitle => 'Aucun résultat';

  @override
  String noResultsForQueryMessage(String query) {
    return 'Rien dans ce dossier ne correspond à \"$query\".';
  }

  @override
  String get closeCarouselTooltip => 'Fermer le carrousel';

  @override
  String get playlistScrollModeMenu => 'Mode de défilement de la playlist';

  @override
  String get playlistScrollHorizontalLabel => 'Horizontal';

  @override
  String get playlistScrollVerticalPageLabel => 'Vertical par page';

  @override
  String get playlistScrollVerticalContinuousLabel => 'Vertical continu';

  @override
  String get undoTooltip => 'Annuler';

  @override
  String get redoTooltip => 'Rétablir';

  @override
  String get autosavingLabel => 'Enregistrement automatique…';

  @override
  String get savingLabel => 'Enregistrement…';

  @override
  String autosavedAtLabel(String time) {
    return 'Enregistré automatiquement à $time';
  }

  @override
  String cameraDisconnectedError(String message) {
    return 'Appareil photo déconnecté : $message';
  }

  @override
  String get unknownErrorFallback => 'erreur inconnue';

  @override
  String get cameraPermissionsRequiredMessage =>
      'Les autorisations d\'appareil photo et de microphone sont requises pour utiliser l\'appareil photo.';

  @override
  String cameraErrorMessage(String error) {
    return 'Erreur de l\'appareil photo : $error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage =>
      'Échec de la capture de la photo';

  @override
  String get cameraRecordingFailedMessage => 'Échec de l\'enregistrement';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String get cameraRecordingTooShortMessage =>
      'L\'enregistrement était trop court pour être sauvegardé';

  @override
  String get cameraCouldNotSaveRecordingMessage =>
      'Impossible d\'enregistrer la vidéo';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return 'Impossible d\'enregistrer la vidéo : $error';
  }

  @override
  String get cameraCouldNotSwitchLensMessage =>
      'Impossible de changer d\'objectif';

  @override
  String get cameraEncryptingPhotoLabel => 'Chiffrement de la photo…';

  @override
  String get cameraEncryptingVideoLabel => 'Chiffrement de la vidéo…';

  @override
  String get aboutApplicationSectionHeader => 'Application';

  @override
  String get aboutTagline =>
      'Gratuit · Open source · Coffre chiffré hors ligne';

  @override
  String get aboutVersionTitle => 'Version';

  @override
  String aboutVersionSubtitle(String version) {
    return 'v$version';
  }

  @override
  String get aboutWhatsNewTitle => 'Nouveautés';

  @override
  String get aboutWhatsNewSubtitle =>
      'Voir les changements récents et les notes de version';

  @override
  String get aboutPrivacySecurityTitle => 'Confidentialité et sécurité';

  @override
  String get aboutPrivacySecuritySubtitle =>
      'Aucun accès réseau, rien d\'écrit non chiffré sur le disque';

  @override
  String get aboutSupportedFormatsSectionHeader => 'Formats pris en charge';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt et LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      'Volumes standards et cachés, PIM personnalisé, fichiers-clés, xts-plain64, Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker et BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle =>
      'Prise en charge des phrases de passe utilisateur et de la clé de récupération numérique à 48 chiffres';

  @override
  String get aboutDirectoryVaultsTitle => 'Coffres dossier';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator (v7/v8 SIV_GCM et SIV_CTRMAC), gocryptfs (v2 AES-GCM et XChaCha20), CryFS (v0.10+ XChaCha20 et AES)';

  @override
  String get aboutVhdTitle => 'Disques durs virtuels (VHD / VHDX)';

  @override
  String get aboutVhdSubtitle =>
      'Traduction BAT pour les images disque fixes et dynamiques extensibles';

  @override
  String get aboutNativeCoreEngineSectionHeader => 'Moteur natif principal';

  @override
  String get aboutCompiledLibrariesTitle => 'Bibliothèques C++ compilées';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.0 (cryptographie matérielle ARMv8 et SHA-2)\n• libavif et libgav1 (décodeur d\'image AVIF natif)\n• ChaN FatFs v4.0.4 (FAT12/16/32 et exFAT)\n• Tuxera NTFS-3G et mkntfs embarqué\n• e2fsprogs v1.47.4 libext2fs (ext2/ext3/ext4)\n• Dislocker Virtual I/O (BitLocker FVE / To Go)\n• VeraCrypt 1.26.29 (Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id/i)\n• cJSON v1.7.18 (métadonnées LUKS2 et Cryptomator)';

  @override
  String get aboutCommunitySectionHeader => 'Communauté et open source';

  @override
  String get aboutReportIssueTitle => 'Signaler un problème';

  @override
  String get aboutReportIssueSubtitle =>
      'Vous avez trouvé un bug ? Soumettez un signalement sur GitHub';

  @override
  String get reportIssueSheetTitle => 'Signaler un problème';

  @override
  String get reportIssueSheetSubtitle =>
      'Choisissez l\'option qui correspond le mieux à votre problème — elle ouvre un formulaire GitHub pré-rempli';

  @override
  String get reportIssueBugTitle => 'Rapport de bug';

  @override
  String get reportIssueBugSubtitle =>
      'Quelque chose a planté ou ne fonctionne pas correctement';

  @override
  String get reportIssueContainerTitle => 'Problème de conteneur / coffre';

  @override
  String get reportIssueContainerSubtitle =>
      'Problème de déverrouillage, de montage ou spécifique au format';

  @override
  String get reportIssueFeatureTitle => 'Demande de fonctionnalité';

  @override
  String get reportIssueFeatureSubtitle =>
      'Suggérer une idée ou une amélioration';

  @override
  String get reportIssueOtherTitle => 'Autre chose';

  @override
  String get reportIssueOtherSubtitle =>
      'Parcourir tous les modèles sur GitHub';

  @override
  String get aboutContributorsTitle => 'Contributeurs';

  @override
  String get aboutContributorsSubtitle =>
      'Les personnes qui ont aidé à créer VaultExplorer';

  @override
  String get aboutLicensesTitle => 'Licences open source';

  @override
  String get aboutLicensesSubtitle =>
      'Bibliothèques tierces utilisées dans cette application';

  @override
  String get aboutFooterMadeWithLove => 'Fait avec ❤ pour la confidentialité.';

  @override
  String get aboutVersionCopiedMessage =>
      'Infos de version copiées — pratique pour les rapports de bug';

  @override
  String aboutVersionClipboardText(String version) {
    return 'VaultExplorer v$version (Android)';
  }

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer — un coffre gratuit, open source et hors ligne pour Android.\n\nStockez mots de passe, notes et fichiers dans un conteneur chiffré (VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs, CryFS).\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage =>
      'Lien partageable copié dans le presse-papiers';

  @override
  String get aboutPrivacySheetTitle =>
      'Confidentialité et sécurité des données';

  @override
  String get aboutPrivacySheetSubtitle =>
      'Conception 100% hors ligne, sécurité de la mémoire locale';

  @override
  String get privacyPointNoNetworkTitle => 'Aucun accès réseau requis';

  @override
  String get privacyPointNoNetworkBody =>
      'VaultExplorer ne demande pas l\'autorisation android.permission.INTERNET sur Android. L\'application ne peut communiquer sur aucun réseau.';

  @override
  String get privacyPointNoDiskLeaksTitle =>
      'Zéro fuite non chiffrée sur le disque';

  @override
  String get privacyPointNoDiskLeaksBody =>
      'Le déchiffrement et le rechiffrement se font entièrement en mémoire système. Aucun fichier temporaire non chiffré n\'est jamais enregistré sur le stockage de l\'appareil.';

  @override
  String get privacyPointNoAnalyticsTitle =>
      'Aucun outil d\'analyse ni de télémétrie';

  @override
  String get privacyPointNoAnalyticsBody =>
      'Il n\'y a aucun rapport de plantage, suivi d\'utilisation, ou SDK tiers collectant des données sur vous ou votre appareil.';

  @override
  String get privacyPointKeystoreTitle =>
      'Les secrets restent dans l\'Android Keystore';

  @override
  String get privacyPointKeystoreBody =>
      'Les mots de passe mémorisés, les schémas et les clés dérivées mises en cache sont scellés avec AES-256-GCM dans l\'Android Keystore matériel.';

  @override
  String get privacyPointPosixTitle =>
      'Accélération POSIX et accès au stockage';

  @override
  String get privacyPointPosixBody =>
      'Les fichiers à l\'intérieur des coffres dossier sont lus et écrits directement lorsque possible, contournant la couche SAF plus lente d\'Android pour les gros dossiers.';

  @override
  String get privacyPointScreenClipboardTitle =>
      'Protection de l\'écran et du presse-papiers';

  @override
  String get privacyPointScreenClipboardBody =>
      'Blocage de l\'aperçu dans les captures d\'écran/le sélecteur de tâches (FLAG_SECURE), plus une désinfection automatique du presse-papiers corrompu lors de la mise au point de la fenêtre. Les mots de passe copiés depuis la Item Vault sont marqués comme sensibles sur Android 13+ et effacés automatiquement 30 secondes plus tard s\'ils ne sont pas utilisés.';

  @override
  String get privacyPointMaskModeTitle => 'Mode Masque';

  @override
  String get privacyPointMaskModeBody =>
      'Déguise éventuellement l\'application en un explorateur d\'archives zip fonctionnel, avec une icône et un nom différents. Maintenez le titre appuyé pendant 2 secondes pour accéder à votre véritable coffre.';

  @override
  String get privacyPointExternalLinksTitle =>
      'Les liens externes s\'ouvrent dans le navigateur';

  @override
  String get privacyPointExternalLinksBody =>
      'Appuyer sur un lien le transmet à votre application de navigateur par défaut, qui traite la demande.';

  @override
  String get truncatedListingWarning =>
      'Affichage des 50 000 premiers éléments — ce dossier en contient davantage.';

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '$size px · qualité $quality%';
  }

  @override
  String holdToSpeedIndicatorLabel(String speed) {
    return 'Vitesse ×$speed';
  }

  @override
  String get toolbarLayoutSectionHeader => 'Disposition de la barre d\'outils';

  @override
  String get listViewOptionsSectionHeader => 'Options de la vue en liste';

  @override
  String get detailedListViewColumnsSectionHeader =>
      'Colonnes de la liste détaillée';

  @override
  String get galleryGridViewSectionHeader => 'Vue en grille galerie';

  @override
  String get browserLayoutSectionHeader => 'Disposition du navigateur';

  @override
  String get mediaViewerSectionHeader => 'Visionneuse multimédia';

  @override
  String get viewModeAction => 'Mode d\'affichage';

  @override
  String get sortAction => 'Trier';

  @override
  String get playMediaAction => 'Lire les médias';

  @override
  String containerSpaceSummary(String free, String total) {
    return '$free libres · $total au total';
  }

  @override
  String volMountedSummary(int volId) {
    return 'Vol $volId · Monté';
  }

  @override
  String vaultOccupiedSpaceSummary(String used) {
    return '$used utilisés';
  }

  @override
  String get incorrectPasswordOrKeyfilesDriveError =>
      'Mot de passe/fichiers-clés incorrects ou lecteur non pris en charge';

  @override
  String driveUsableCapacity(int mb) {
    return 'Capacité utilisable du lecteur : $mb Mo. Ne doit pas être dépassée.';
  }

  @override
  String get unlockMethodManualPassword => 'Mot de passe manuel';

  @override
  String get unlockMethodRememberPassword => 'Mémoriser le mot de passe';

  @override
  String get unlockMethodBiometrics => 'Déverrouillage biométrique';

  @override
  String get unlockMethodPattern => 'Déverrouillage par schéma';

  @override
  String get unlockMethodPin => 'Déverrouillage par PIN';

  @override
  String get unlockMethodSubtitlePassword =>
      'Saisir le mot de passe à chaque fois';

  @override
  String get unlockMethodSubtitleRememberPassword =>
      'Stocké en toute sécurité dans l\'Android Keystore';

  @override
  String get unlockMethodSubtitleBiometrics =>
      'Utiliser l\'empreinte digitale ou le visage pour déverrouiller';

  @override
  String get unlockMethodSubtitlePattern =>
      'Dessiner un schéma pour déverrouiller';

  @override
  String get unlockMethodSubtitlePin => 'Saisir un code PIN pour déverrouiller';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError =>
      'Décodeur vidéo indisponible — conflit d\'accès au codec matériel';

  @override
  String get mediaStreamInitFailedError =>
      'Échec de l\'initialisation du flux multimédia';

  @override
  String get invalidAvifImage => 'Image AVIF invalide';

  @override
  String get verbImport => 'Importer';

  @override
  String get verbExport => 'Exporter';

  @override
  String get verbMove => 'Déplacer';

  @override
  String get verbCopy => 'Copier';

  @override
  String get verbDelete => 'Supprimer';

  @override
  String get verbImported => 'Importé';

  @override
  String get verbExported => 'Exporté';

  @override
  String get verbMoved => 'Déplacé';

  @override
  String get verbCopied => 'Copié';

  @override
  String get verbDeleted => 'Supprimé';

  @override
  String get verbImporting => 'Importation';

  @override
  String get verbExporting => 'Exportation';

  @override
  String get verbMoving => 'Déplacement';

  @override
  String get verbCopying => 'Copie';

  @override
  String get verbDeleting => 'Suppression';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '1 élément',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments $verb',
      one: '1 élément $verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return '$count ignorés';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return '$count échoués';
  }

  @override
  String get statusCancelled => 'Annulé';

  @override
  String get statusFailed => 'Échoué';

  @override
  String get statusCompleted => 'Terminé';

  @override
  String get fileOpCheckingSpace => 'Vérification de l\'espace disponible…';

  @override
  String get fileOpResolvingConflicts => 'Résolution des conflits…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return 'Espace insuffisant — $required nécessaires, seulement $free libres';
  }

  @override
  String get fileOpDiskFullPartialRemoved =>
      'Disque plein — fichiers partiels supprimés';

  @override
  String get fileOpMoveFailed => 'Échec du déplacement';

  @override
  String get fileOpCopyFailed => 'Échec de la copie';

  @override
  String get fileOpDeleteFailed => 'Échec de la suppression';

  @override
  String get fileOpDiskFull => 'Disque plein';

  @override
  String get fileOpImporting => 'Importation…';

  @override
  String get fileOpExporting => 'Exportation…';

  @override
  String fileOpImportingName(String name) {
    return 'Importation de $name…';
  }

  @override
  String fileOpExportingName(String name) {
    return 'Exportation de $name…';
  }

  @override
  String fileOpMovingName(String name) {
    return 'Déplacement de $name…';
  }

  @override
  String fileOpCopyingName(String name) {
    return 'Copie de $name…';
  }

  @override
  String get fileOpDeleting => 'Suppression…';

  @override
  String fileOpDeletingName(String name) {
    return 'Suppression de $name…';
  }

  @override
  String fileOpDeletedSoFar(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments supprimés',
      one: '1 élément supprimé',
    );
    return '$_temp0';
  }

  @override
  String get searchInSubfoldersHint =>
      'Rechercher dans tous les sous-dossiers…';

  @override
  String get deepSearchEnabledTooltip =>
      'Recherche dans les sous-dossiers — appuyez pour ce dossier uniquement';

  @override
  String get deepSearchDisabledTooltip =>
      'Recherche dans le dossier actuel — appuyez pour inclure les sous-dossiers';

  @override
  String get filterAction => 'Filtrer';

  @override
  String get bookmarkAction => 'Ajouter aux favoris';

  @override
  String get unbookmarkAction => 'Retirer des favoris';

  @override
  String get bookmarkSelectedAction => 'Ajouter la sélection aux favoris';

  @override
  String get unbookmarkSelectedAction => 'Retirer la sélection des favoris';

  @override
  String bookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments ajoutés aux favoris',
      one: '1 élément ajouté aux favoris',
    );
    return '$_temp0';
  }

  @override
  String unbookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments retirés des favoris',
      one: '1 élément retiré des favoris',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => 'Afficher la barre des favoris';

  @override
  String get showBookmarkBarDesc =>
      'Afficher les éléments favoris dans une barre ou un panneau latéral';

  @override
  String get bookmarkBarSectionHeader => 'Barre des favoris';

  @override
  String get noBookmarksYet => 'Aucun élément mis en favori pour le moment';

  @override
  String get reorderBookmarksTitle => 'Réorganiser les favoris';

  @override
  String get reorderBookmarksDesc =>
      'Faites glisser les éléments pour les réorganiser dans la barre des favoris';

  @override
  String get navBarVaultsLabel => 'Coffres';

  @override
  String get navBarToolsLabel => 'Outils';

  @override
  String get toolsScreenTitle => 'Outils';

  @override
  String get toolsSectionContainerUtilities => 'Utilitaires de conteneur';

  @override
  String get toolsSectionFileCryptography => 'Cryptographie de fichiers';

  @override
  String get toolsSectionStorageDiagnostics => 'Stockage et diagnostics';

  @override
  String get toolContainerSplitterTitle => 'Fractionner et joindre';

  @override
  String get toolContainerSplitterSubtitle =>
      'Fractionner un conteneur en morceaux, ou les réunir';

  @override
  String get toolContainerRepairTitle => 'Vérifier et réparer';

  @override
  String get toolContainerRepairSubtitle =>
      'Diagnostiquer les problèmes d\'en-tête ou de système de fichiers';

  @override
  String get toolSingleFileCryptoTitle => 'Chiffrer / déchiffrer des fichiers';

  @override
  String get toolSingleFileCryptoSubtitle =>
      'Protéger un ou plusieurs fichiers sans conteneur complet';

  @override
  String get toolStorageAnalyzerTitle => 'Analyseur de stockage';

  @override
  String get toolStorageAnalyzerSubtitle =>
      'Voir ce qui occupe de l\'espace dans un coffre monté';

  @override
  String get toolDuplicateFinderTitle => 'Détecteur de fichiers en double';

  @override
  String get toolDuplicateFinderSubtitle =>
      'Trouver et supprimer les fichiers en double identiques octet par octet pour libérer de l\'espace';

  @override
  String get toolHashVerifierTitle =>
      'Vérificateur de somme de contrôle et de hachage';

  @override
  String get toolHashVerifierSubtitle =>
      'Vérifier que les gros fichiers ne sont pas corrompus avec des sommes de contrôle MD5/SHA';

  @override
  String get hashVerifierModeCompute => 'Calculer';

  @override
  String get hashVerifierModeVerify => 'Vérifier';

  @override
  String get hashVerifierSelectSourceTitle =>
      'Sélectionner la source du fichier';

  @override
  String get hashVerifierAlgorithmsLabel => 'Algorithmes';

  @override
  String get hashVerifierNoAlgorithmSelected =>
      'Sélectionnez au moins un algorithme';

  @override
  String get hashVerifierFilesLabel => 'Fichiers à hacher';

  @override
  String hashVerifierFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers sélectionnés',
      one: '1 fichier sélectionné',
      zero: 'Aucun fichier sélectionné',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierComputeButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Calculer $count hachages',
      one: 'Calculer le hachage',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCancelButton => 'Annuler';

  @override
  String hashVerifierBatchProgressLabel(Object current, Object total) {
    return 'Fichier $current sur $total';
  }

  @override
  String get hashVerifierCancelledMessage => 'Annulé.';

  @override
  String hashVerifierComputeErrorsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers n\'ont pas pu être hachés',
      one: '1 fichier n\'a pas pu être haché',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCopiedMessage => 'Copié dans le presse-papiers';

  @override
  String get hashVerifierExportManifestButton =>
      'Exporter en tant que manifeste';

  @override
  String get hashVerifierExportAlgorithmLabel => 'Algorithme du manifeste';

  @override
  String hashVerifierExportSuccessMessage(Object path) {
    return 'Enregistré dans $path';
  }

  @override
  String hashVerifierExportFailedMessage(Object error) {
    return 'Échec de l\'exportation : $error';
  }

  @override
  String get hashVerifierLoadManifestButton => 'Charger un manifeste';

  @override
  String get hashVerifierChangeManifestButton => 'Changer';

  @override
  String get hashVerifierManifestLabel => 'Fichier manifeste';

  @override
  String hashVerifierManifestEntryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entrées',
      one: '1 entrée',
      zero: 'Aucune entrée',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierAutoAddFolderButton =>
      'Ajouter tous les fichiers de ce dossier';

  @override
  String get hashVerifierAddFilesToVerifyButton =>
      'Ajouter des fichiers à vérifier';

  @override
  String get hashVerifierVerifyAllButton => 'Tout vérifier';

  @override
  String hashVerifierVerifyProgressLabel(Object current, Object total) {
    return 'Vérification du fichier $current sur $total';
  }

  @override
  String hashVerifierSummaryMessage(
    Object ok,
    Object mismatch,
    Object missing,
  ) {
    return '$ok correspondent, $mismatch ne correspondent pas, $missing manquants';
  }

  @override
  String get hashVerifierStatusMatch => 'Correspond';

  @override
  String get hashVerifierStatusMismatch => 'Ne correspond pas';

  @override
  String get hashVerifierStatusMissing => 'Fichier non ajouté';

  @override
  String get hashVerifierStatusPending => 'Pas encore vérifié';

  @override
  String get hashVerifierExpectedLabel => 'Attendu';

  @override
  String get hashVerifierActualLabel => 'Réel';

  @override
  String hashVerifierExtraFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count fichiers supplémentaires non répertoriés dans le manifeste',
      one: '1 fichier supplémentaire non répertorié dans le manifeste',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierNoManifestLoadedMessage =>
      'Chargez un fichier manifeste pour commencer';

  @override
  String get hashVerifierManifestParseEmptyMessage =>
      'Aucune entrée de somme de contrôle trouvée dans ce fichier';

  @override
  String hashVerifierLoadManifestFailedMessage(Object error) {
    return 'Impossible de lire le manifeste : $error';
  }

  @override
  String hashVerifierAutoAddedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers ajoutés depuis le dossier du coffre',
      one: '1 fichier ajouté depuis le dossier du coffre',
      zero: 'Aucun nouveau fichier trouvé',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierModeVault => 'Coffre';

  @override
  String get hashVerifierVaultPickerLabel => 'Coffre';

  @override
  String get hashVerifierVaultNoVaultsMessage =>
      'Aucun coffre n\'est actuellement monté';

  @override
  String get hashVerifierCheckEntireVaultButton => 'Vérifier tout le coffre';

  @override
  String get hashVerifierVaultScanningLabel => 'Analyse du coffre…';

  @override
  String hashVerifierVaultFilesDiscoveredLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers découverts',
      one: '1 fichier découvert',
      zero: 'Aucun fichier découvert pour l\'instant',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmTitle => 'Vérifier tout le coffre ?';

  @override
  String hashVerifierVaultConfirmFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers',
      one: '1 fichier',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmWarning =>
      'Chaque fichier de ce coffre sera lu.';

  @override
  String get hashVerifierVaultEmptyMessage =>
      'Ce coffre n\'a aucun fichier à vérifier';

  @override
  String get hashVerifierVaultStartButton => 'Démarrer la vérification';

  @override
  String hashVerifierVaultHashingProgressLabel(Object current, Object total) {
    return 'Vérification $current / $total';
  }

  @override
  String get hashVerifierVaultCompleteTitle =>
      'Vérification du coffre terminée';

  @override
  String hashVerifierVaultCompleteFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers vérifiés',
      one: '1 fichier vérifié',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteBytesLabel(Object size) {
    return '$size traités';
  }

  @override
  String hashVerifierVaultCompleteSucceededLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count réussis',
      one: '1 réussi',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count échoués',
      one: '1 échoué',
      zero: '0 échoué',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultElapsedLabel(Object time) {
    return 'Temps écoulé : $time';
  }

  @override
  String get hashVerifierVaultCancelledMessage =>
      'Vérification du coffre annulée.';

  @override
  String hashVerifierVaultFailedMessage(Object error) {
    return 'Échec de la vérification du coffre : $error';
  }

  @override
  String get hashVerifierVaultNewCheckButton => 'Nouvelle vérification';

  @override
  String get hashVerifierVaultActionComputeTitle => 'Calculer tout le coffre';

  @override
  String get hashVerifierVaultActionComputeSubtitle =>
      'Hacher chaque fichier d\'un coffre';

  @override
  String get hashVerifierVaultActionVerifyTitle => 'Vérifier tout le coffre';

  @override
  String get hashVerifierVaultActionVerifySubtitle =>
      'Vérifier chaque fichier d\'un coffre par rapport à un manifeste chargé';

  @override
  String get hashVerifierVaultChangeActionButton => 'Changer';

  @override
  String get hashVerifierVaultVerifyButton => 'Vérifier tout le coffre';

  @override
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage =>
      'La vérification d\'un coffre entier nécessite un manifeste chargé depuis l\'intérieur d\'un coffre.';

  @override
  String get duplicateFinderTargetLabel => 'Coffre cible';

  @override
  String get duplicateFinderTargetAllVaults => 'Tous les coffres ouverts';

  @override
  String get duplicateFinderStartScan => 'Démarrer l\'analyse';

  @override
  String get duplicateFinderCancelScan => 'Annuler l\'analyse';

  @override
  String get duplicateFinderRescan => 'Réanalyser';

  @override
  String get duplicateFinderScanningStage1 =>
      'Étape 1 : indexation et regroupement par taille...';

  @override
  String get duplicateFinderScanningStage2 =>
      'Étape 2 : vérification des en-têtes partiels des fichiers...';

  @override
  String get duplicateFinderScanningStage3 =>
      'Étape 3 : vérification complète des hachages d\'octets...';

  @override
  String get duplicateFinderScanComplete => 'Analyse terminée';

  @override
  String get duplicateFinderNoDuplicatesTitle =>
      'Aucun fichier en double trouvé';

  @override
  String get duplicateFinderNoDuplicatesMessage =>
      'Tous les fichiers du/des coffre(s) analysé(s) contiennent des données d\'octets uniques.';

  @override
  String get duplicateFinderSelectRedundant =>
      'Sélectionner les copies redondantes';

  @override
  String get duplicateFinderSelectAll => 'Tout sélectionner';

  @override
  String get duplicateFinderDeselectAll => 'Tout désélectionner';

  @override
  String get duplicateFinderOriginalLabel => 'Original';

  @override
  String get duplicateFinderDuplicateLabel => 'Doublon';

  @override
  String get duplicateFinderConfirmDeleteTitle =>
      'Supprimer les fichiers en double ?';

  @override
  String get duplicateFinderSearchHint =>
      'Rechercher des doublons par nom ou chemin...';

  @override
  String get toolNotImplementedYetMessage =>
      'Cet outil n\'est pas encore relié au moteur natif — revenez lors d\'une prochaine mise à jour.';

  @override
  String get splitJoinModeSplit => 'Fractionner';

  @override
  String get splitJoinModeJoin => 'Joindre';

  @override
  String get splitSourceFileLabel => 'Fichier source';

  @override
  String get splitDestinationFolderLabel => 'Dossier de destination';

  @override
  String get splitChunkSizeLabel => 'Taille des morceaux';

  @override
  String get splitChunkSizeCustomLabel => 'Taille personnalisée (Mo)';

  @override
  String get splitChunkSizeFourMb => '4 Mo';

  @override
  String get splitChunkSizeCloud8mb => '8 Mo';

  @override
  String get splitChunkSizeCloud32mb => '32 Mo';

  @override
  String get splitChunkSizeCloud => '100 Mo';

  @override
  String get splitChunkSizeFat32 => '2 Go';

  @override
  String get splitChunkSizeFourGb => '4 Go';

  @override
  String get splitChunkSizeCustom => 'Personnalisé';

  @override
  String get splitContainerButton => 'Fractionner le conteneur';

  @override
  String get joinFirstPartLabel => 'Première partie';

  @override
  String get joinOutputFileNameLabel => 'Nom du fichier de sortie';

  @override
  String get joinContainerButton => 'Joindre les fichiers';

  @override
  String get chooseFileButton => 'Choisir un fichier';

  @override
  String get chooseFolderButton => 'Choisir un dossier';

  @override
  String get noFileSelectedLabel => 'Aucun fichier sélectionné';

  @override
  String get noFolderSelectedLabel => 'Aucun dossier sélectionné';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage => 'Conteneur fractionné avec succès';

  @override
  String get joinContainerSuccessMessage => 'Fichiers joints avec succès';

  @override
  String get cryptoDirectionEncrypt => 'Chiffrer';

  @override
  String get cryptoDirectionDecrypt => 'Déchiffrer';

  @override
  String get singleFileCryptoInputFileLabel => 'Fichiers d\'entrée';

  @override
  String get singleFileCryptoCipherLabel => 'Chiffrement';

  @override
  String get singleFileCryptoDeleteOriginalLabel =>
      'Supprimer les fichiers originaux après le chiffrement';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Chiffrer $count fichiers',
      one: 'Chiffrer le fichier',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Déchiffrer $count fichiers',
      one: 'Déchiffrer le fichier',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Terminé — $count fichiers traités',
      one: 'Terminé',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return '$succeeded fichiers traités sur $total — $failed échoués';
  }

  @override
  String get singleFileCryptoAddFilesButton => 'Ajouter des fichiers';

  @override
  String get singleFileCryptoClearFilesButton => 'Effacer';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers sélectionnés',
      one: '1 fichier sélectionné',
      zero: 'Aucun fichier sélectionné',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return 'Fichier $current sur $total';
  }

  @override
  String get repairTargetStepTitle => 'Choisir une cible';

  @override
  String get repairTargetUnmountedFileOption => 'Fichier non monté';

  @override
  String get repairTargetUnmountedFileSubtitle =>
      'Restaurer un en-tête de sauvegarde sur un conteneur que vous n\'avez pas ouvert';

  @override
  String get repairTargetMountedVolumeSubtitle =>
      'Exécuter une vérification du système de fichiers sur un coffre déjà ouvert';

  @override
  String get repairNoMountedVolumes => 'Aucun coffre n\'est actuellement monté';

  @override
  String get repairScanButton => 'Lancer l\'analyse de diagnostic';

  @override
  String get repairChangeTargetButton => 'Changer de cible';

  @override
  String get repairDiagnosisHealthy => 'Aucun problème détecté';

  @override
  String get repairDiagnosisHeaderCorrupted => 'En-tête corrompu';

  @override
  String get repairDiagnosisFilesystemDirty =>
      'Système de fichiers instable / démontage incorrect';

  @override
  String get repairRestoreBackupHeaderButton =>
      'Restaurer l\'en-tête de sauvegarde';

  @override
  String get repairRunFilesystemCheckButton =>
      'Exécuter la vérification et la réparation du système de fichiers';

  @override
  String get repairActionSucceededMessage => 'Réparation terminée avec succès';

  @override
  String get repairActionFailedMessage => 'L\'action de réparation a échoué';

  @override
  String get storageAnalyzerTargetLabel => 'Volume';

  @override
  String get storageAnalyzerNoTargetsTitle => 'Rien à analyser';

  @override
  String get storageAnalyzerNoTargetsMessage =>
      'Montez d\'abord un coffre, puis revenez ici pour voir la répartition de son stockage.';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return '$used sur $total utilisés';
  }

  @override
  String get storageAnalyzerHeaviestFilesHeader =>
      'Fichiers les plus volumineux';

  @override
  String get storageAnalyzerBreakdownHeader => 'Par type de fichier';

  @override
  String get storageAnalyzerScanningMessage => 'Analyse du volume…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return 'L\'analyse s\'est arrêtée après $count fichiers — les résultats peuvent être incomplets.';
  }

  @override
  String get storageAnalyzerNoFilesFound => 'Aucun fichier trouvé';

  @override
  String get storageCategoryImages => 'Images';

  @override
  String get storageCategoryVideos => 'Vidéos';

  @override
  String get storageCategoryAudio => 'Audio';

  @override
  String get storageCategoryDocuments => 'Documents';

  @override
  String get storageCategoryArchives => 'Archives';

  @override
  String get storageCategoryOther => 'Autre';

  @override
  String get keyfilePassphraseGeneratorTitle =>
      'Générateur de fichiers-clés et de phrases de passe';

  @override
  String get keyfilePassphraseGeneratorSubtitle =>
      'Générer des phrases de passe Diceware, des mots de passe personnalisés et des fichiers-clés à haute entropie';

  @override
  String get tabPassphrase => 'Phrase de passe';

  @override
  String get tabKeyfile => 'Fichier-clé';

  @override
  String get modeDiceware => 'Phrase de passe Diceware';

  @override
  String get modeCustomPassword => 'Mot de passe personnalisé';

  @override
  String get keyfileTypeBinary => 'Fichier-clé binaire (.key)';

  @override
  String get keyfileTypeImage => 'Fichier-clé image de bruit (.png)';

  @override
  String get copyPassphraseSuccess =>
      'Phrase de passe copiée dans le presse-papiers sensible';

  @override
  String get copyFingerprintSuccess =>
      'Empreinte SHA-256 copiée dans le presse-papiers';

  @override
  String get saveKeyfileToVault => 'Enregistrer dans un coffre monté';

  @override
  String get exportKeyfileToStorage =>
      'Exporter vers le stockage de l\'appareil';

  @override
  String get keyfileNoOpenVaultsMessage =>
      'Aucun coffre ouvert disponible. Veuillez d\'abord monter un coffre.';

  @override
  String get keyfileSelectDestinationVaultTitle =>
      'Sélectionner le coffre de destination';

  @override
  String keyfileVolumeIdLabel(Object volId) {
    return 'ID du volume : $volId';
  }

  @override
  String keyfileExportSuccessMessage(Object path) {
    return 'Fichier-clé exporté vers $path';
  }

  @override
  String keyfileExportFailedMessage(Object error) {
    return 'Échec de l\'exportation : $error';
  }

  @override
  String keyfileSavedToVaultMessage(Object vaultName, Object path) {
    return 'Fichier-clé enregistré dans $vaultName : $path';
  }

  @override
  String get keyfileWriteFailedMessage =>
      'Échec de l\'écriture du fichier-clé dans le coffre';

  @override
  String keyfileSaveErrorMessage(Object error) {
    return 'Erreur lors de l\'enregistrement dans le coffre : $error';
  }

  @override
  String get passphraseGeneratedSecretLabel => 'Secret généré';

  @override
  String get copyToClipboardTooltip => 'Copier dans le presse-papiers';

  @override
  String get generateNewTooltip => 'Générer un nouveau';

  @override
  String get passphraseStrengthWeak => 'Faible';

  @override
  String get passphraseStrengthGood => 'Bon';

  @override
  String get passphraseStrengthStrong => 'Fort';

  @override
  String get passphraseStrengthUnbreakable => 'Incassable';

  @override
  String get passphraseCrackTimeInstant => '< 1 seconde';

  @override
  String get passphraseCrackTimeShort => 'Quelques jours / mois';

  @override
  String get passphraseCrackTimeCenturies => 'Plusieurs siècles';

  @override
  String get passphraseCrackTimeMillionsOfYears => 'Des millions d\'années';

  @override
  String passphraseStrengthLabel(Object label) {
    return 'Robustesse : $label';
  }

  @override
  String passphraseEntropyBitsLabel(Object bits) {
    return '$bits bits d\'entropie';
  }

  @override
  String passphraseCrackTimeLabel(Object crackTime) {
    return 'Temps de cassage estimé : $crackTime';
  }

  @override
  String get dicewareOptionsTitle => 'Options Diceware EFF';

  @override
  String dicewareWordCountLabel(Object count) {
    return 'Nombre de mots : $count mots';
  }

  @override
  String dicewareWordCountBitsLabel(Object bits) {
    return '$bits bits';
  }

  @override
  String dicewareWordCountSliderLabel(Object count) {
    return '$count mots';
  }

  @override
  String get dicewareWordSeparatorLabel => 'Séparateur de mots';

  @override
  String get dicewareSeparatorHyphen => 'Trait d\'union ( - )';

  @override
  String get dicewareSeparatorSpace => 'Espace (   )';

  @override
  String get dicewareSeparatorUnderscore => 'Tiret bas ( _ )';

  @override
  String get dicewareSeparatorDot => 'Point ( . )';

  @override
  String get dicewareSeparatorSlash => 'Barre oblique ( / )';

  @override
  String get dicewareWordCasingLabel => 'Casse des mots';

  @override
  String get dicewareCasingLowercase => 'minuscules';

  @override
  String get dicewareCasingTitleCase => 'Casse de titre';

  @override
  String get dicewareCasingUppercase => 'MAJUSCULES';

  @override
  String get dicewareAppendDigitLabel => 'Ajouter un chiffre aléatoire (0-9)';

  @override
  String get dicewareAppendSymbolLabel =>
      'Ajouter un symbole aléatoire (!@#\$%)';

  @override
  String get customPasswordOptionsTitle =>
      'Options du mot de passe personnalisé';

  @override
  String customPasswordLengthLabel(Object length) {
    return 'Longueur : $length caractères';
  }

  @override
  String customPasswordLengthSliderLabel(Object length) {
    return '$length caractères';
  }

  @override
  String get customPasswordUppercaseLabel => 'Lettres majuscules (A-Z)';

  @override
  String get customPasswordLowercaseLabel => 'Lettres minuscules (a-z)';

  @override
  String get customPasswordNumbersLabel => 'Chiffres (0-9)';

  @override
  String get customPasswordSymbolsLabel => 'Symboles (!@#\$%^&*)';

  @override
  String get customPasswordExcludeAmbiguousLabel =>
      'Exclure les caractères ambigus (1, l, I, 0, O)';

  @override
  String get keyfileBinarySizeTitle => 'Taille du fichier-clé binaire';

  @override
  String get keyfileImageResolutionTitle => 'Résolution de l\'image de bruit';

  @override
  String get keyfilePresetBytes64 => '64 octets (standard VeraCrypt)';

  @override
  String get keyfilePresetBytes256 => '256 octets';

  @override
  String get keyfilePresetBytes2048 => '2 Ko';

  @override
  String get keyfilePresetBytes64kb => '64 Ko';

  @override
  String get keyfilePresetBytes1mb => '1 Mo (limite maximale)';

  @override
  String get keyfilePresetRes64 => '64 x 64 pixels (~16 Ko)';

  @override
  String get keyfilePresetRes256 => '256 x 256 pixels (~256 Ko)';

  @override
  String get keyfilePresetRes512 => '512 x 512 pixels (~1 Mo)';

  @override
  String get keyfileGenerateNewTooltip => 'Générer un nouveau fichier-clé';

  @override
  String keyfileSizeLabel(Object size) {
    return 'Taille : $size';
  }

  @override
  String get keyfileFingerprintLabel => 'Empreinte SHA-256';

  @override
  String get keyfileCopyFingerprintTooltip => 'Copier l\'empreinte';

  @override
  String get duplicateFinderNoVaultsTitle => 'Aucun coffre monté';

  @override
  String get duplicateFinderNoVaultsMessage =>
      'Déverrouillez et montez au moins un conteneur coffre pour rechercher des fichiers en double.';

  @override
  String duplicateFinderConfirmDeleteMessage(Object count, Object size) {
    return 'Voulez-vous vraiment supprimer définitivement $count fichier(s) en double ($size) de votre/vos coffre(s) ? Cette action est irréversible.';
  }

  @override
  String get duplicateFinderDeletePermanentlyButton =>
      'Supprimer définitivement';

  @override
  String duplicateFinderDeleteSuccessMessage(Object count) {
    return '$count fichier(s) en double supprimé(s) avec succès.';
  }

  @override
  String get duplicateFinderIntroTitle =>
      'Détecteur en 3 étapes par correspondance d\'octets';

  @override
  String get duplicateFinderIntroSubtitle =>
      'Détecte un contenu strictement identique, quel que soit le nom des fichiers.';

  @override
  String get duplicateFinderStagesDescription =>
      '• Étape 1 : regroupement par taille (parcours instantané des métadonnées)\n• Étape 2 : vérification partielle de l\'en-tête (en-tête SHA-256 de 16 Ko)\n• Étape 3 : vérification complète du hachage (correspondance exacte des octets SHA-256)';

  @override
  String get duplicateFinderScanningVaultFallback => 'Analyse du coffre...';

  @override
  String duplicateFinderProcessingFileLabel(Object fileName) {
    return 'Traitement : $fileName';
  }

  @override
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  ) {
    return 'Fichiers analysés : $scanned | Doublons trouvés : $groups groupes ($saved)';
  }

  @override
  String duplicateFinderGroupsFoundLabel(Object count) {
    return '$count groupes de doublons trouvés';
  }

  @override
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved) {
    return '$copies copies trouvées • Économisez $saved d\'espace de stockage';
  }

  @override
  String duplicateFinderVaultsSelectedLabel(Object count) {
    return '$count coffres sélectionnés';
  }

  @override
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  ) {
    return 'Groupe $groupIndex : $size ($count copies trouvées)';
  }

  @override
  String duplicateFinderRecoverableSpaceLabel(Object size) {
    return 'Espace récupérable : $size';
  }

  @override
  String get duplicateFinderPreviewFileTooltip => 'Aperçu du fichier';

  @override
  String duplicateFinderPreviewFailedMessage(Object fileName) {
    return 'Impossible d\'ouvrir l\'aperçu du fichier pour $fileName';
  }

  @override
  String duplicateFinderPreviewErrorMessage(Object error) {
    return 'Erreur d\'aperçu du fichier : $error';
  }

  @override
  String duplicateFinderFilesSelectedLabel(Object count) {
    return '$count fichiers sélectionnés';
  }

  @override
  String duplicateFinderBytesToBeFreedLabel(Object size) {
    return '$size à libérer';
  }

  @override
  String duplicateFinderDeleteSelectedButton(Object count) {
    return 'Supprimer la sélection ($count)';
  }

  @override
  String get vaultBrowserSwitchVaultTooltip => 'Changer de coffre';

  @override
  String get vaultBrowserRootFolderLabel => 'Dossier racine';

  @override
  String vaultFilePickerTitle(Object vaultName) {
    return 'Sélectionner des fichiers ($vaultName)';
  }

  @override
  String get vaultFilePickerEmptyMessage => 'Le dossier est vide';

  @override
  String vaultFilePickerConfirmButton(Object count) {
    return 'Sélectionner $count fichier(s)';
  }

  @override
  String vaultFolderPickerTitle(Object vaultName) {
    return 'Sélectionner un dossier ($vaultName)';
  }

  @override
  String get vaultFolderPickerEmptyMessage => 'Aucun sous-dossier ici';

  @override
  String get vaultFolderPickerRootLabel => 'Racine';

  @override
  String get vaultFolderPickerConfirmRootButton =>
      'Sélectionner le dossier racine';

  @override
  String vaultFolderPickerConfirmNamedButton(Object folderName) {
    return 'Sélectionner \"$folderName\"';
  }

  @override
  String get singleFileCryptoSelectInputTitle =>
      'Sélectionner les fichiers d\'entrée';

  @override
  String get singleFileCryptoFromDeviceTitle =>
      'Depuis le stockage de l\'appareil';

  @override
  String get singleFileCryptoFromDeviceSubtitle =>
      'Choisir des fichiers sur l\'appareil via le sélecteur système';

  @override
  String get singleFileCryptoFromVaultTitle => 'Depuis un coffre monté';

  @override
  String get singleFileCryptoFromVaultSubtitle =>
      'Choisir des fichiers dans un conteneur chiffré ouvert';

  @override
  String get singleFileCryptoSelectDestinationTitle =>
      'Sélectionner le dossier de destination';

  @override
  String get singleFileCryptoDeviceFolderTitle =>
      'Dossier de stockage de l\'appareil';

  @override
  String get singleFileCryptoDeviceFolderSubtitle =>
      'Enregistrer la sortie dans un dossier du stockage de l\'appareil';

  @override
  String get singleFileCryptoVaultFolderTitle => 'Dossier de coffre monté';

  @override
  String get singleFileCryptoVaultFolderSubtitle =>
      'Enregistrer la sortie dans un conteneur chiffré ouvert';

  @override
  String get toolsSectionBackupSync => 'Sauvegarde et synchronisation';

  @override
  String get toolVaultSyncTitle => 'Synchronisation de coffres';

  @override
  String get toolVaultSyncSubtitle =>
      'Comparer deux coffres et copier ce qui manque ou est plus récent';

  @override
  String get vaultSyncNoVaultsTitle => 'Aucun coffre monté';

  @override
  String get vaultSyncNoVaultsMessage =>
      'Montez au moins un coffre pour comparer et synchroniser ses fichiers.';

  @override
  String get vaultSyncLeftLabel => 'Gauche';

  @override
  String get vaultSyncRightLabel => 'Droite';

  @override
  String get vaultSyncTapToSelect =>
      'Appuyez pour sélectionner un coffre et un dossier';

  @override
  String get vaultSyncSwapTooltip => 'Inverser gauche et droite';

  @override
  String get vaultSyncSameLocationWarning =>
      'Les côtés gauche et droit doivent être des dossiers différents.';

  @override
  String get vaultSyncIntroTitle => 'Comparer deux coffres';

  @override
  String get vaultSyncIntroSubtitle =>
      'Choisissez un coffre à gauche et à droite (ou deux dossiers dans le même coffre) pour voir ce qui manque, a été modifié ou est plus récent de chaque côté.';

  @override
  String get vaultSyncCompareButton => 'Comparer';

  @override
  String get vaultSyncComparingLabel => 'Comparaison des coffres…';

  @override
  String vaultSyncCompareStatsLabel(Object dirs, Object entries) {
    return 'Dossiers analysés : $dirs | Différences trouvées : $entries';
  }

  @override
  String get vaultSyncCancelCompareButton => 'Annuler';

  @override
  String get vaultSyncInSyncTitle => 'Déjà synchronisé';

  @override
  String vaultSyncInSyncMessage(Object count) {
    return 'Les $count fichiers correspondants sont identiques des deux côtés.';
  }

  @override
  String get vaultSyncRecompareButton => 'Comparer à nouveau';

  @override
  String vaultSyncDifferencesFoundLabel(Object count) {
    return '$count différences trouvées';
  }

  @override
  String vaultSyncInSyncCountLabel(Object count) {
    return '$count fichiers déjà identiques des deux côtés';
  }

  @override
  String vaultSyncBadgeOnlyLeft(Object count) {
    return '$count uniquement à gauche';
  }

  @override
  String vaultSyncBadgeOnlyRight(Object count) {
    return '$count uniquement à droite';
  }

  @override
  String vaultSyncBadgeLeftNewer(Object count) {
    return '$count plus récents à gauche';
  }

  @override
  String vaultSyncBadgeRightNewer(Object count) {
    return '$count plus récents à droite';
  }

  @override
  String vaultSyncBadgeConflicts(Object count) {
    return '$count nécessitent une vérification';
  }

  @override
  String get vaultSyncDirectionLabel => 'Sens de synchronisation';

  @override
  String get vaultSyncDirectionTwoWay => 'Bidirectionnel (recommandé)';

  @override
  String get vaultSyncDirectionTwoWaySubtitle =>
      'Copie chaque fichier vers le côté qui ne l\'a pas ou en a une copie plus ancienne';

  @override
  String get vaultSyncDirectionLeftToRight =>
      'Gauche → Droite (unidirectionnel)';

  @override
  String get vaultSyncDirectionLeftToRightSubtitle =>
      'Transfère les fichiers nouveaux et mis à jour de gauche vers droite ; ne modifie jamais la gauche';

  @override
  String get vaultSyncDirectionRightToLeft =>
      'Droite → Gauche (unidirectionnel)';

  @override
  String get vaultSyncDirectionRightToLeftSubtitle =>
      'Transfère les fichiers nouveaux et mis à jour de droite vers gauche ; ne modifie jamais la droite';

  @override
  String get vaultSyncSearchHint => 'Rechercher dans les différences';

  @override
  String get vaultSyncStatusOnlyLeft => 'Uniquement à gauche';

  @override
  String get vaultSyncStatusOnlyRight => 'Uniquement à droite';

  @override
  String get vaultSyncStatusLeftNewer => 'Plus récent à gauche';

  @override
  String get vaultSyncStatusRightNewer => 'Plus récent à droite';

  @override
  String get vaultSyncStatusConflict => 'Vérification nécessaire';

  @override
  String get vaultSyncStatusTypeMismatch => 'Type incompatible';

  @override
  String get vaultSyncFolderOnlyLeftDetail => 'Dossier — uniquement à gauche';

  @override
  String get vaultSyncFolderOnlyRightDetail => 'Dossier — uniquement à droite';

  @override
  String vaultSyncBothSidesDetail(
    Object leftSize,
    Object leftDate,
    Object rightSize,
    Object rightDate,
  ) {
    return 'G : $leftSize · $leftDate  →  D : $rightSize · $rightDate';
  }

  @override
  String get vaultSyncTypeMismatchTooltip =>
      'Un fichier d\'un côté et un dossier de l\'autre — résolvez manuellement dans le navigateur de fichiers';

  @override
  String get vaultSyncChangeActionTooltip =>
      'Changer l\'action de synchronisation';

  @override
  String get vaultSyncActionCopyToRight => 'Copier → Droite';

  @override
  String get vaultSyncActionCopyToLeft => 'Copier → Gauche';

  @override
  String get vaultSyncActionSkip => 'Ignorer';

  @override
  String vaultSyncChangesQueuedLabel(Object count) {
    return '$count modifications en file d\'attente';
  }

  @override
  String get vaultSyncSyncNowButton => 'Synchroniser maintenant';

  @override
  String get vaultSyncConfirmTitle => 'Démarrer la synchronisation ?';

  @override
  String vaultSyncConfirmMessage(Object count, Object bytes) {
    return 'Cela copiera $count éléments ($bytes au total) entre les deux côtés. Les fichiers existants portant le même nom seront écrasés.';
  }

  @override
  String vaultSyncStartedMessage(Object count) {
    return 'Synchronisation démarrée — $count éléments en file d\'attente';
  }

  @override
  String vaultSyncPickLocationTitle(Object side) {
    return 'Sélectionner le coffre et le dossier ($side)';
  }

  @override
  String get vaultSyncReadOnlyBadge => 'Lecture seule';

  @override
  String get vaultSyncReadOnlyTooltip =>
      'Ce coffre est monté en lecture seule — les fichiers ne peuvent pas y être copiés';

  @override
  String get vaultSyncSyncingButton => 'Synchronisation…';

  @override
  String get vaultSyncNotEnoughSpaceTitle => 'Espace insuffisant';

  @override
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  ) {
    return 'Espace insuffisant à $side — $required nécessaires, seulement $free libres.';
  }

  @override
  String get removeMasterPasswordTitle => 'Retirer le mot de passe principal';

  @override
  String get confirmRemoveMasterPasswordMessage =>
      'Saisissez votre mot de passe principal actuel pour confirmer le retrait :';

  @override
  String get authenticateToRemoveMasterPassword =>
      'Authentifiez-vous pour retirer le mot de passe principal';

  @override
  String get incorrectPassword => 'Mot de passe incorrect';

  @override
  String get rememberPerFolderLayoutLabel =>
      'Mémoriser la disposition par dossier';

  @override
  String get rememberPerFolderLayoutDesc =>
      'Enregistrer une disposition d\'affichage distincte (liste, grille, mosaïque) pour chaque dossier';

  @override
  String get fileInfoAction => 'Infos';

  @override
  String get automationSectionHeader => 'Automatisation';

  @override
  String get automationTileTitle => 'Automatisation';

  @override
  String get automationTileSubtitle =>
      'Autoriser l\'automatisation à déverrouiller, verrouiller, importer ou exporter ce coffre';

  @override
  String get automationScreenTitle => 'Automatisation (Tasker / MacroDroid)';

  @override
  String get automationUsbUnsupportedMessage =>
      'L\'automatisation n\'est pas encore disponible pour les coffres connectés en USB.';

  @override
  String get automationThisVaultSectionHeader => 'Ce coffre';

  @override
  String get automationAccessLabel => 'Accès à l\'automatisation';

  @override
  String get automationPasswordSectionHeader =>
      'Mot de passe d\'automatisation';

  @override
  String get automationPasswordStoredHint =>
      'Un mot de passe est enregistré pour les appels UNLOCK_VAULT sans surveillance. Enregistrez-en un nouveau pour le remplacer, ou enregistrez un champ vide pour l\'effacer — l\'automatisation peut aussi fournir un mot de passe directement dans la diffusion au lieu de s\'appuyer sur celui-ci.';

  @override
  String get automationPasswordNotStoredHint =>
      'Facultatif. Sans mot de passe enregistré, l\'automatisation doit en fournir un à chaque diffusion UNLOCK_VAULT.';

  @override
  String get automationNewPasswordFieldLabel => 'Nouveau mot de passe';

  @override
  String get automationPasswordFieldLabel => 'Mot de passe';

  @override
  String get automationClearPasswordButton =>
      'Effacer le mot de passe enregistré';

  @override
  String get automationSavePasswordButton => 'Enregistrer le mot de passe';

  @override
  String get automationTokenSectionHeader => 'Jeton API';

  @override
  String get automationTokenDescription =>
      'Partagé par tous les coffres avec accès à l\'automatisation activé. L\'automatisation le renvoie à chaque diffusion ; un jeton erroné ou manquant est ignoré silencieusement, sans erreur.';

  @override
  String get automationRegenerateTokenButton => 'Régénérer le jeton';

  @override
  String get automationRegenerateTokenDialogTitle => 'Régénérer le jeton ?';

  @override
  String get automationRegenerateTokenDialogMessage =>
      'Tout profil Tasker ou macro MacroDroid utilisant le jeton actuel cessera de fonctionner silencieusement jusqu\'à ce que vous le mettiez à jour avec le nouveau.';

  @override
  String get automationRegenerateConfirmLabel => 'Régénérer';

  @override
  String get automationTokenRegeneratedMessage => 'Jeton régénéré.';

  @override
  String get automationRegenerateTokenFailedMessage =>
      'Impossible de régénérer le jeton.';

  @override
  String get automationUpdateSettingsFailedMessage =>
      'Impossible de mettre à jour les paramètres d\'automatisation.';

  @override
  String get automationSavePasswordFailedMessage =>
      'Impossible d\'enregistrer le mot de passe d\'automatisation.';

  @override
  String get automationPasswordClearedMessage =>
      'Mot de passe d\'automatisation effacé.';

  @override
  String get automationPasswordSavedMessage =>
      'Mot de passe d\'automatisation enregistré.';

  @override
  String get automationConfigSectionHeader => 'Chaînes de configuration';

  @override
  String get automationConfigIntro =>
      'Appuyez sur une valeur ci-dessous pour la copier. Dans Tasker, utilisez une action \"Send Intent\" ; dans MacroDroid, utilisez une action \"Intent\" avec le type d\'intent défini sur Broadcast — et non Activity ou Service, qui échoue avec \"unable to find explicit activity class\".';

  @override
  String get automationConfigPackageLabel => 'Nom du package';

  @override
  String get automationConfigClassLabel => 'Classe du récepteur';

  @override
  String get automationConfigVaultUriLabel => 'URI de ce coffre';

  @override
  String get automationConfigActionsSectionHeader => 'Actions de diffusion';

  @override
  String get automationActionUnlockLabel => 'Déverrouiller le coffre';

  @override
  String get automationActionLockLabel => 'Verrouiller le coffre';

  @override
  String get automationActionImportLabel => 'Importer un fichier';

  @override
  String get automationActionExportLabel => 'Exporter un fichier';

  @override
  String get automationActionWipeLabel => 'Effacer un fichier';

  @override
  String get automationDocCommentFootnote =>
      'L\'ensemble des extras et le contrat de diffusion des résultats sont documentés dans VaultAutomationReceiver.kt.';

  @override
  String get automationTierOffLabel => 'Désactivée';

  @override
  String get automationTierOffSubtitle =>
      'L\'automatisation ne peut pas accéder à ce coffre';

  @override
  String get automationTierLifecycleLabel =>
      'Déverrouillage / verrouillage uniquement';

  @override
  String get automationTierLifecycleSubtitle =>
      'L\'automatisation peut déverrouiller et verrouiller ce coffre, rien d\'autre';

  @override
  String get automationTierFullLabel =>
      'Déverrouillage / verrouillage + import-export de fichiers';

  @override
  String get automationTierFullSubtitle =>
      'L\'automatisation peut aussi importer et exporter des fichiers tant que ce coffre est déverrouillé';

  @override
  String get automationTutorialLinkLabel =>
      'Lire le tutoriel complet étape par étape';

  @override
  String get showHiddenFilesLabel => 'Afficher les fichiers cachés';

  @override
  String get showHiddenFilesDesc =>
      'Afficher les fichiers en point et les dossiers système';

  @override
  String get dontAskAgain => 'Ne plus demander';

  @override
  String get deleteAfterImportLabel =>
      'Supprimer les fichiers après importation';

  @override
  String get deleteAfterImportModeAsk => 'Demander à chaque fois';

  @override
  String get deleteAfterImportModeAskSubtitle =>
      'Demander s\'il faut supprimer les fichiers originaux après l\'importation';

  @override
  String get deleteAfterImportModeKeep =>
      'Conserver les originaux (ne pas supprimer)';

  @override
  String get deleteAfterImportModeKeepSubtitle =>
      'Ne jamais supprimer les fichiers originaux et ne pas demander';

  @override
  String get deleteAfterImportModeDelete =>
      'Supprimer les originaux automatiquement';

  @override
  String get deleteAfterImportModeDeleteSubtitle =>
      'Supprimer automatiquement les fichiers originaux de l\'appareil après l\'importation';

  @override
  String get wizardBackButton => 'Retour';

  @override
  String get wizardNextButton => 'Suivant';

  @override
  String get wizardStepTypeTitle => 'Type';

  @override
  String get wizardStepBasicInfoTitle => 'Infos de base';

  @override
  String get wizardStepAdvancedTitle => 'Avancé';

  @override
  String get wizardStepReviewTitle => 'Vérification';

  @override
  String get wizardCreateTypePrompt => 'Que souhaitez-vous créer ?';

  @override
  String get wizardChooseFormatPrompt => 'Choisissez un format de conteneur';

  @override
  String get wizardEncryptionDetailsRowTitle => 'Détails du chiffrement';

  @override
  String get wizardHiddenVolumeRowSubtitleConfigured =>
      'Configuré — appuyez pour vérifier';

  @override
  String get wizardHiddenVolumeRowSubtitleNeedsSetup =>
      'Appuyez pour configurer';

  @override
  String get wizardSummaryTitle => 'Résumé';

  @override
  String get wizardSummaryPasswordLabel => 'Mot de passe';

  @override
  String get wizardPasswordSetValue => 'Défini';

  @override
  String get wizardPasswordNotSetValue =>
      'Non défini (utilisation de fichiers-clés)';

  @override
  String get wizardSummaryKeyfilesLabel => 'Fichiers-clés';

  @override
  String get wizardSummaryPimDefaultValue => 'Par défaut';

  @override
  String get wizardSummaryPimLabel => 'PIM';

  @override
  String get wizardSummaryDriveLabel => 'Clé USB';

  @override
  String get sectionKeyStorageIntegration =>
      'Stockage des clés et accès système';

  @override
  String get sectionMaskMode => 'Mode Masque';

  @override
  String get advancedOptionsTitle => 'Options avancées';

  @override
  String get audioTrackTitle => 'Piste audio';

  @override
  String get noAudioTracksAvailable => 'Aucune piste audio disponible';

  @override
  String trackNumberLabel(int number) {
    return 'Piste $number';
  }

  @override
  String subtitleTrackNumberLabel(int number) {
    return 'Sous-titre $number';
  }

  @override
  String get offLabel => 'Désactivé';

  @override
  String get externalSubtitlesLabel => 'Sous-titres externes (.srt/.vtt)';

  @override
  String get externalLabel => 'Externe';

  @override
  String get subtitleSizeLabel => 'Taille';

  @override
  String get subtitleSizeSmall => 'P';

  @override
  String get subtitleSizeMedium => 'M';

  @override
  String get subtitleSizeLarge => 'G';

  @override
  String get subtitleSizeExtraLarge => 'TG';

  @override
  String get subtitlePositionLabel => 'Position';

  @override
  String get subtitlePositionBottom => 'Bas';

  @override
  String get subtitlePositionLower => 'Tiers inférieur';

  @override
  String get subtitlePositionCenter => 'Centre';

  @override
  String get subtitlePositionTop => 'Haut';

  @override
  String get editImageAction => 'Modifier l\'image';

  @override
  String get imageEditorUnsupportedFormatMessage =>
      'Ce format d\'image n\'est pas pris en charge pour la modification.';

  @override
  String get cropToolLabel => 'Recadrer';

  @override
  String get drawToolLabel => 'Dessiner';

  @override
  String get textToolLabel => 'Texte';

  @override
  String get redactToolLabel => 'Caviarder';

  @override
  String get rotateLeftTooltip => 'Pivoter à gauche';

  @override
  String get rotateRightTooltip => 'Pivoter à droite';

  @override
  String get cropAspectFreeLabel => 'Libre';

  @override
  String get cropAspectSquareLabel => 'Carré';

  @override
  String get cropAspectOriginalLabel => 'Original';

  @override
  String get applyCropTooltip => 'Appliquer le recadrage';

  @override
  String get annotationColorTooltip => 'Couleur';

  @override
  String get annotationStrokeWidthTooltip => 'Épaisseur du trait';

  @override
  String get clearAnnotationsTooltip => 'Effacer toutes les annotations';

  @override
  String get resetImageTooltip => 'Réinitialiser à l\'original';

  @override
  String get resetImageConfirmTitle => 'Réinitialiser l\'image ?';

  @override
  String get resetImageConfirmMessage =>
      'Cela annule tous les recadrages et dessins effectués dans cette session.';

  @override
  String get addTextAnnotationTitle => 'Ajouter du texte';

  @override
  String get addTextAnnotationHint => 'Tapez quelque chose…';

  @override
  String get textToolHint => 'Touchez l\'image pour ajouter du texte';

  @override
  String get saveImageSheetTitle => 'Enregistrer les modifications';

  @override
  String get saveAsNewFileOption => 'Enregistrer sous un nouveau fichier';

  @override
  String get saveAsNewFileDescription => 'Conserve l\'original intact';

  @override
  String get overwriteOriginalOption => 'Écraser l\'original';

  @override
  String get overwriteOriginalDescription => 'Remplace le fichier original';

  @override
  String get newFileNameLabel => 'Nom du fichier';

  @override
  String get imageEditorPngNoteMessage =>
      'Les images modifiées sont enregistrées au format PNG.';

  @override
  String get imageSavedMessage => 'Image enregistrée';

  @override
  String imageSaveFailedMessage(String error) {
    return 'Impossible d\'enregistrer l\'image : $error';
  }

  @override
  String get advancedRenameButton => 'Avancé';

  @override
  String get advancedRenameBatchTitle => 'Renommage par lot';

  @override
  String get advancedRenameRulesTab => 'Règles';

  @override
  String advancedRenamePreviewTab(int count) {
    return 'Aperçu ($count)';
  }

  @override
  String get advancedRenameSearchReplaceTitle => 'Rechercher et remplacer';

  @override
  String get advancedRenameFindTextLabel => 'Rechercher du texte';

  @override
  String get advancedRenameFindTextHint =>
      'Saisissez un texte ou un motif à faire correspondre...';

  @override
  String get advancedRenameReplaceWithLabel => 'Remplacer par';

  @override
  String get advancedRenameReplaceWithHint => 'Nouveau texte ou variables...';

  @override
  String get advancedRenameInsertVariableTooltip =>
      'Insérer un jeton de variable dynamique';

  @override
  String get advancedRenameDateTimeTokens => 'JETONS DE DATE ET HEURE';

  @override
  String advancedRenameStandardDate(String token) {
    return 'Date standard ($token)';
  }

  @override
  String advancedRenameYearFourDigit(String token) {
    return 'Année sur 4 chiffres ($token)';
  }

  @override
  String advancedRenameMonth(String token) {
    return 'Mois ($token)';
  }

  @override
  String advancedRenameDayOfMonth(String token) {
    return 'Jour du mois ($token)';
  }

  @override
  String advancedRenameTime(String token) {
    return 'Heure ($token)';
  }

  @override
  String get advancedRenameDynamicIdentifiers => 'IDENTIFIANTS DYNAMIQUES';

  @override
  String advancedRenameUniqueUuid(String token) {
    return 'UUID v4 unique ($token)';
  }

  @override
  String get advancedRenameRandomAlphanumeric =>
      'Alphanumérique aléatoire (8 caractères)';

  @override
  String get advancedRenameRandomDigits => 'Chiffres aléatoires (6 chiffres)';

  @override
  String get advancedRenameEmbeddedCounter => 'COMPTEUR INTÉGRÉ';

  @override
  String advancedRenamePaddedCounter(String token) {
    return 'Compteur avec zéros ($token)';
  }

  @override
  String get advancedRenameRegex => 'Regex';

  @override
  String get advancedRenameMatchCase => 'Respecter la casse';

  @override
  String get advancedRenameAllOccurrences => 'Toutes les occurrences';

  @override
  String get advancedRenameScopeFormatting => 'Portée et mise en forme';

  @override
  String get advancedRenameApplyChangesTo => 'Appliquer les modifications à';

  @override
  String get advancedRenameFilename => 'Nom du fichier';

  @override
  String get advancedRenameExtension => 'Extension';

  @override
  String get advancedRenameBoth => 'Les deux';

  @override
  String get advancedRenameCaseTransformation => 'Transformation de la casse';

  @override
  String get advancedRenameNoChange => 'Aucun changement';

  @override
  String get advancedRenameLowercase => 'minuscules';

  @override
  String get advancedRenameUppercase => 'MAJUSCULES';

  @override
  String get advancedRenameTitleCase => 'Casse de titre';

  @override
  String get advancedRenameCapitalize => 'Mettre en majuscule';

  @override
  String get advancedRenameSequentialCounter => 'Compteur séquentiel';

  @override
  String get advancedRenameCounterDescription =>
      'Ajouter des numéros ordonnés en préfixe ou suffixe';

  @override
  String get advancedRenameSuffix => 'Suffixe (fin)';

  @override
  String get advancedRenamePrefix => 'Préfixe (début)';

  @override
  String get advancedRenameStartAt => 'Commencer à';

  @override
  String get advancedRenameDigits => 'Chiffres';

  @override
  String get advancedRenameDigitsHint => 'ex. 2 (01)';

  @override
  String get advancedRenameSeparator => 'Séparateur';

  @override
  String get advancedRenameSeparatorHint => '_ or -';

  @override
  String get advancedRenameLivePreview => 'Aperçu en direct';

  @override
  String get advancedRenameDeselect => 'Désélectionner';

  @override
  String get advancedRenameSelectAll => 'Tout sélectionner';

  @override
  String get advancedRenameNoFilesSelected => 'Aucun fichier sélectionné';

  @override
  String get advancedRenameNameConflictDetected => 'Conflit de nom détecté';

  @override
  String get advancedRenameCheckPreviewToFix =>
      'Vérifiez l\'onglet Aperçu pour corriger';

  @override
  String get advancedRenameReadyToRename => 'Prêt à renommer';

  @override
  String get advancedRenameErrorsDetected => 'Erreurs détectées';

  @override
  String advancedRenameApply(int count) {
    return 'Appliquer ($count)';
  }

  @override
  String get advancedRenameNameCollisionWithinBatch =>
      'Conflit de nom au sein du lot.';

  @override
  String get advancedRenameCollidesWithUnselectedFile =>
      'Entre en conflit avec un fichier non sélectionné.';

  @override
  String advancedRenameReadyCount(int valid, int total) {
    return '$valid prêts à renommer (sur $total)';
  }

  @override
  String advancedRenameReadyOfTotal(int valid, int total) {
    return '$valid sur $total prêts';
  }

  @override
  String advancedRenameRenamedItems(int succeeded, int failed) {
    return '$succeeded éléments renommés ($failed échoués).';
  }

  @override
  String advancedRenameSuccessfullyRenamed(int count) {
    return '$count éléments renommés avec succès.';
  }

  @override
  String get advancedRenameMonthsFull =>
      'janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre';

  @override
  String get advancedRenameMonthsAbbr =>
      'janv|févr|mars|avr|mai|juin|juil|août|sept|oct|nov|déc';

  @override
  String get advancedRenameDaysFull =>
      'lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche';

  @override
  String get advancedRenameDaysAbbr => 'lun|mar|mer|jeu|ven|sam|dim';

  @override
  String get advancedRenameResolveConflicts =>
      'Résolvez les conflits de nom avant d\'appliquer';

  @override
  String advancedRenameChangedCount(int changed, int total) {
    return '$changed sur $total';
  }

  @override
  String get automationKeyfilesPimSectionHeader => 'Fichiers-clés et PIM';

  @override
  String get automationKeyfilesPimDescription =>
      'Stocké avec le mot de passe d\'automatisation ci-dessus et utilisé de la même façon pour les appels UNLOCK_VAULT — pour un coffre VeraCrypt/LUKS normalement déverrouillé avec un fichier-clé et/ou un PIM non par défaut plutôt qu\'un simple mot de passe.';

  @override
  String get automationSavePimButton => 'Enregistrer le PIM';

  @override
  String get automationCameraSectionHeader =>
      'Automatisation de l\'appareil photo';

  @override
  String get automationCameraDescription =>
      'Permet à l\'automatisation de déclencher TAKE_PHOTO / START_RECORDING / STOP_RECORDING pour ce coffre. Désactivé par défaut même avec l\'accès complet — contrairement à l\'import/export de fichiers, une photo ne nécessite aucune indication à l\'écran, il s\'agit donc d\'une activation explicite distincte.';

  @override
  String get automationAllowCameraCapture =>
      'Autoriser la capture par l\'appareil photo';

  @override
  String get automationPimSavedMessage => 'PIM enregistré';

  @override
  String get automationActionImportFolderLabel => 'Importer un dossier';

  @override
  String get automationActionExportFolderLabel => 'Exporter un dossier';

  @override
  String get automationActionTakePhotoLabel => 'Prendre une photo';

  @override
  String get automationActionStartRecordingLabel =>
      'Démarrer l\'enregistrement';

  @override
  String get automationActionStopRecordingLabel => 'Arrêter l\'enregistrement';

  @override
  String get filePropertiesSectionHeader => 'PROPRIÉTÉS DU FICHIER';

  @override
  String get fullPathLabel => 'Chemin complet';

  @override
  String get sizeLabel => 'Taille';

  @override
  String get modifiedLabel => 'Modifié';

  @override
  String get vaultLabel => 'Coffre';

  @override
  String get mediaDimensionsSectionHeader => 'MÉDIA ET DIMENSIONS';

  @override
  String get resolutionLabel => 'Résolution';

  @override
  String get aspectRatioLabel => 'Format d\'image';

  @override
  String get formatLabel => 'Format';

  @override
  String get exifCameraDataSectionHeader => 'DONNÉES EXIF ET APPAREIL PHOTO';

  @override
  String get cameraLabel => 'Appareil photo';

  @override
  String get lensLabel => 'Objectif';

  @override
  String get dateTakenLabel => 'Date de prise de vue';

  @override
  String get shutterSpeedLabel => 'Vitesse d\'obturation';

  @override
  String get apertureLabel => 'Ouverture';

  @override
  String get isoLabel => 'ISO';

  @override
  String get focalLengthLabel => 'Distance focale';

  @override
  String get flashLabel => 'Flash';

  @override
  String get softwareLabel => 'Logiciel';

  @override
  String get gpsLocationLabel => 'Position GPS';

  @override
  String get integrityChecksumSectionHeader => 'INTÉGRITÉ ET SOMME DE CONTRÔLE';

  @override
  String get computingHashMessage => 'Calcul du hachage…';

  @override
  String get tapCalculateToVerifyMessage =>
      'Appuyez sur Calculer pour vérifier';

  @override
  String get calculateButton => 'Calculer';

  @override
  String get copyDiagnosticsButton => 'Copier les diagnostics';

  @override
  String get closeButton => 'Fermer';

  @override
  String get hwAcceleratedBadge => 'ACCÉLÉRATION MATÉRIELLE';

  @override
  String get swDecoderBadge => 'DÉCODEUR LOGICIEL';

  @override
  String get videoDecoderHardwareSection => 'DÉCODEUR VIDÉO ET MATÉRIEL';

  @override
  String get decoderNameLabel => 'Nom du décodeur';

  @override
  String get accelerationLabel => 'Accélération';

  @override
  String get hardwareGpuDirect => 'Matériel (GPU direct)';

  @override
  String get softwareCpuFallback => 'Logiciel (repli CPU)';

  @override
  String get unknownValue => 'Inconnu';

  @override
  String get framerateLabel => 'Fréquence d\'images';

  @override
  String get variableOrUnknown => 'Variable / Inconnu';

  @override
  String get videoCodecLabel => 'Codec vidéo';

  @override
  String get autoDetected => 'Détecté automatiquement';

  @override
  String get colorFormatLabel => 'Format de couleur';

  @override
  String get initLatencyLabel => 'Latence d\'initialisation';

  @override
  String get audioEngineSection => 'MOTEUR AUDIO';

  @override
  String get audioDecoderLabel => 'Décodeur audio';

  @override
  String get audioCodecLabel => 'Codec audio';

  @override
  String get pipelineHealthSection => 'PIPELINE ET ÉTAT';

  @override
  String get playbackStateLabel => 'État de lecture';

  @override
  String get decryptedBufferLabel => 'Tampon déchiffré';

  @override
  String secondsCached(String seconds) {
    return '$seconds s mises en cache';
  }

  @override
  String get droppedFramesLabel => 'Images abandonnées';

  @override
  String nFrames(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images',
      one: '1 image',
    );
    return '$_temp0';
  }

  @override
  String get sourceStorageLabel => 'Stockage source';

  @override
  String directJniStreamSource(int volId) {
    return 'Flux JNI C++ direct (volId=$volId)';
  }

  @override
  String get archivesTabLabel => 'Archives';

  @override
  String get filesTabLabel => 'Files';

  @override
  String get filesPermissionMessage =>
      'Allow access to browse files on your device.';

  @override
  String get filesEmptyTitle => 'No files here';

  @override
  String get filesEmptyMessage => 'This folder is empty.';

  @override
  String get filesNewFolderTooltip => 'New folder';

  @override
  String get filesNewFolderDialogTitle => 'New folder';

  @override
  String get filesNameHint => 'Name';

  @override
  String get filesCreate => 'Create';

  @override
  String get filesRename => 'Rename';

  @override
  String get filesDelete => 'Delete';

  @override
  String get filesShare => 'Share';

  @override
  String get filesCopy => 'Copy';

  @override
  String get filesMove => 'Move';

  @override
  String get filesDeleteConfirmTitle => 'Delete permanently?';

  @override
  String get filesChooseDestinationTitle => 'Choose a folder';

  @override
  String get filesMoveHere => 'Move here';

  @override
  String get filesCopyHere => 'Copy here';

  @override
  String get filesSelectAllTooltip => 'Select all';

  @override
  String get filesCloseSelectionTooltip => 'Close';

  @override
  String get filesFolderCreated => 'Folder created';

  @override
  String get filesCreateFolderFailed => 'Couldn\'t create folder';

  @override
  String get filesRenamed => 'Renamed';

  @override
  String get filesRenameFailed => 'Couldn\'t rename';

  @override
  String get filesNameAlreadyExists => 'That name is already taken';

  @override
  String get filesDeleted => 'Deleted';

  @override
  String get filesDeleteFailed => 'Couldn\'t delete';

  @override
  String get filesMoved => 'Moved';

  @override
  String get filesMoveFailed => 'Couldn\'t move';

  @override
  String get filesCopied => 'Copied';

  @override
  String get filesCopyFailed => 'Couldn\'t copy';

  @override
  String get filesOpenFailed => 'Couldn\'t open this file';

  @override
  String get filesShareFailed => 'Couldn\'t share this file';

  @override
  String get filesFilterTooltip => 'Filter';

  @override
  String get filesFilterAll => 'All files';

  @override
  String get filesFilterImages => 'Images';

  @override
  String get filesFilterVideos => 'Videos';

  @override
  String get filesFilterAudio => 'Audio';

  @override
  String get filesFilterDocuments => 'Documents';

  @override
  String get filesTextTooLarge => 'This file is too large to preview here.';

  @override
  String get filesTextSaved => 'Saved';

  @override
  String get filesTextSaveFailed => 'Couldn\'t save';
}
