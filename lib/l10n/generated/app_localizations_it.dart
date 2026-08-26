// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get cancel => 'Annulla';

  @override
  String get close => 'Chiudi';

  @override
  String get search => 'Cerca';

  @override
  String get goBack => 'Indietro';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => 'Vai alla pagina';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return 'Numero di pagina (1 - $pageCount)';
  }

  @override
  String get pdfViewerPageLabel => 'Pagina';

  @override
  String get pdfViewerGoButton => 'Vai';

  @override
  String get pdfViewerSearchHint => 'Cerca nel documento';

  @override
  String get pdfViewerNoMatches => 'Nessun risultato';

  @override
  String get pdfViewerPreviousMatch => 'Risultato precedente';

  @override
  String get pdfViewerNextMatch => 'Risultato successivo';

  @override
  String get pdfViewerCloseSearch => 'Chiudi ricerca';

  @override
  String get pdfViewerPrintTooltip => 'Stampa documento';

  @override
  String get pdfViewerLoadingDocument => 'Caricamento documento…';

  @override
  String get pdfViewerCannotOpenTitle => 'Impossibile aprire il PDF';

  @override
  String get pdfViewerFailedToLoad => 'Impossibile caricare il PDF';

  @override
  String get pdfViewerEditTooltip => 'Modifica';

  @override
  String get pdfViewerDoneEditingTooltip => 'Modifica completata';

  @override
  String get pdfViewerSaveFailed =>
      'Impossibile salvare le modifiche a questo PDF';

  @override
  String get pdfViewerEditUnavailable =>
      'La modifica non è disponibile per questo documento';

  @override
  String get paste => 'Incolla';

  @override
  String get clear => 'Cancella';

  @override
  String get clipboardVerbMove => 'Sposta';

  @override
  String get clipboardVerbCopy => 'Copia';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb ($count) — Tocca per i dettagli, tieni premuto per incollare';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb ($count) — Dettagli appunti';
  }

  @override
  String clipboardSourceLabel(String source) {
    return 'Origine: $source';
  }

  @override
  String get clipboardDefaultSourceName => 'Vault';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi',
      one: '1 elemento',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count altri elementi',
      one: '+1 altro elemento',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => 'Parametri avanzati';

  @override
  String get pimFieldLabel => 'PIM  (lascia vuoto per il valore predefinito)';

  @override
  String get encryptionAlgorithmLabel => 'Algoritmo di cifratura';

  @override
  String get hashAlgorithmLabel => 'Algoritmo di hash';

  @override
  String get clipboardVerbMoving => 'Spostamento';

  @override
  String get clipboardVerbCopying => 'Copia';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi',
      one: '1 elemento',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return ' da \"$source\"';
  }

  @override
  String get clipboardOpenContainerToPaste =>
      'Apri un contenitore per incollare';

  @override
  String get keyfilesOptionalLabel => 'File chiave (opzionale)';

  @override
  String get addFile => 'Aggiungi file';

  @override
  String get noKeyfilesAttached => 'Nessun file chiave allegato';

  @override
  String get completed => 'Completato';

  @override
  String get dismiss => 'Ignora';

  @override
  String byteProgressText(String transferred, String total, int pct) {
    return '$transferred / $total  ($pct%)';
  }

  @override
  String countProgressText(int done, int total, int pct) {
    return '$done / $total  ($pct%)';
  }

  @override
  String multiOpLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trasferimenti',
      one: '1 trasferimento',
    );
    return '$_temp0';
  }

  @override
  String multiOpSublabel(String summary) {
    return '$summary · tocca per vedere tutto';
  }

  @override
  String get thumbnailSizeResolutionLabel =>
      'Dimensione miniature (risoluzione)';

  @override
  String get jpegCompressionQualityLabel => 'Qualità di compressione JPEG';

  @override
  String get done => 'Fatto';

  @override
  String get confirm => 'Conferma';

  @override
  String get couldNotPickKeyfiles => 'Impossibile selezionare i file chiave';

  @override
  String get filesystemLabelEncryptedVault => 'questo vault cifrato';

  @override
  String get filesystemLabelThisContainer => 'questo contenitore';

  @override
  String get nounFile => 'file';

  @override
  String get nounFolder => 'cartella';

  @override
  String get nounFileCapitalized => 'File';

  @override
  String get nounFolderCapitalized => 'Cartella';

  @override
  String get unitBytes => 'byte';

  @override
  String get unitCharacters => 'caratteri';

  @override
  String get validationEmptyName => 'Il nome non può essere vuoto.';

  @override
  String validationReservedNavName(String name, String noun) {
    return '\"$name\" è un nome di navigazione riservato e non può essere usato come nome di $noun.';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return '\"$char\" in posizione $position non è consentito in un nome su $fsLabel.';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return 'La posizione $position contiene un carattere di controllo non stampabile (codice $code), non consentito su $fsLabel.';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '\"$name\" è un nome di dispositivo riservato su $fsLabel (corrisponde a CON, PRN, AUX, NUL, COM0–9 o LPT0–9) e non può essere usato, con o senza estensione file.';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return 'I nomi di $noun non possono terminare con uno spazio su $fsLabel';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return 'I nomi di $noun non possono terminare con un \".\" su $fsLabel';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return 'Questo nome è lungo $length $unit; $fsLabel consente al massimo $maxLength $unit per nome di $noun.';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return 'Il percorso completo è lungo $length caratteri; $fsLabel consente al massimo $maxLength.';
  }

  @override
  String conflictSameType(String noun, String name) {
    return 'Esiste già qui un $noun chiamato \"$name\".';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return 'Esiste già qui un $existingNoun chiamato \"$name\" — non può condividere il nome con un $candidateNoun.';
  }

  @override
  String get readOnlyContainerWarning =>
      'Questo contenitore è montato in sola lettura.';

  @override
  String get hiddenVolumeProtectionTriggeredWarning =>
      'Una scrittura su questo volume esterno avrebbe danneggiato il volume nascosto, quindi è stata bloccata. Questo contenitore è stato impostato in sola lettura per il resto della sessione.';

  @override
  String get protectHiddenVolumeToggleTitle => 'Proteggi volume nascosto';

  @override
  String get protectHiddenVolumeToggleSubtitle =>
      'Previene i danni causati dalla scrittura sul volume esterno';

  @override
  String get protectHiddenVolumeCredentialsRequired =>
      'Per proteggere il volume nascosto è necessaria una password o un file chiave';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminare $count elementi?',
      one: 'Eliminare 1 elemento?',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning =>
      'Questi elementi verranno eliminati definitivamente, incluso tutto il contenuto delle cartelle selezionate.';

  @override
  String get deleteFilesWarning =>
      'Questi elementi verranno cancellati definitivamente dal tuo volume cifrato.';

  @override
  String get delete => 'Elimina';

  @override
  String get remove => 'Rimuovi';

  @override
  String get create => 'Crea';

  @override
  String get rename => 'Rinomina';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Rinomina $count elementi',
      one: 'Rinomina 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => 'Nuova cartella';

  @override
  String get newTextFileTitle => 'Nuovo file di testo';

  @override
  String get folderNameHint => 'Nome cartella';

  @override
  String get filenameHint => 'nomefile.txt';

  @override
  String get newNameHint => 'Nuovo nome';

  @override
  String get baseNameHint => 'Nome base';

  @override
  String couldntCreateItem(String name) {
    return 'Impossibile creare \"$name\" — verifica che il contenitore sia ancora montato';
  }

  @override
  String couldntRenameSingle(String name) {
    return 'Impossibile rinominare \"$name\" — potrebbe esistere già un elemento con questo nome';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Impossibile rinominare $count elementi: $reason',
      one: 'Impossibile rinominare 1 elemento: $reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Impossibile rinominare $count elementi',
      one: 'Impossibile rinominare 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize =>
      'Inserisci una dimensione valida maggiore di 0';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter =>
      'La dimensione del volume nascosto deve essere inferiore a quella del volume esterno';

  @override
  String get hiddenVolumeErrorTooLargeForContainer =>
      'La dimensione del volume nascosto è troppo grande per questo contenitore';

  @override
  String get hiddenVolumeErrorCredentialsRequired =>
      'È richiesta una password o un file chiave nascosti quando si crea un volume nascosto';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      'Le credenziali del volume nascosto (password, PIM e file chiave) non possono essere identiche a quelle del volume esterno.';

  @override
  String get vaultItemTypePassword => 'Password';

  @override
  String get vaultItemTypePaymentCard => 'Carta di pagamento';

  @override
  String get vaultItemTypeIdentity => 'Identità';

  @override
  String get vaultItemTypeSecureNote => 'Nota sicura';

  @override
  String get vaultItemTypeBankAccount => 'Conto bancario';

  @override
  String get vaultItemTypeSoftwareLicense => 'Licenza software';

  @override
  String get fieldUsernameEmail => 'Nome utente / Email';

  @override
  String get fieldPassword => 'Password';

  @override
  String get fieldWebsiteUrl => 'URL sito web';

  @override
  String get fieldTotpSecret => 'Chiave segreta TOTP (2FA)';

  @override
  String get fieldNotes => 'Note';

  @override
  String get fieldCardholderName => 'Nome intestatario';

  @override
  String get fieldCardNumber => 'Numero carta';

  @override
  String get fieldExpiryMMYY => 'Scadenza (MM/AA)';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldIssuingBank => 'Banca emittente';

  @override
  String get fieldFullName => 'Nome completo';

  @override
  String get fieldDateOfBirth => 'Data di nascita';

  @override
  String get fieldNationality => 'Nazionalità';

  @override
  String get fieldPassportNumber => 'Numero passaporto';

  @override
  String get fieldPassportExpiry => 'Scadenza passaporto';

  @override
  String get fieldNationalIdSsn => 'Carta d\'identità / Codice fiscale';

  @override
  String get fieldDriversLicense => 'Patente di guida';

  @override
  String get fieldAddress => 'Indirizzo';

  @override
  String get fieldPhone => 'Telefono';

  @override
  String get fieldEmail => 'Email';

  @override
  String get fieldNote => 'Nota';

  @override
  String get fieldBankName => 'Nome banca';

  @override
  String get fieldAccountHolder => 'Intestatario del conto';

  @override
  String get fieldAccountNumber => 'Numero di conto';

  @override
  String get fieldRoutingSortCode => 'Codice ABI / Sort Code';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => 'Tipo di conto';

  @override
  String get fieldProductName => 'Nome prodotto';

  @override
  String get fieldLicenseKey => 'Chiave di licenza';

  @override
  String get fieldRegisteredTo => 'Registrato a';

  @override
  String get fieldPurchaseDate => 'Data di acquisto';

  @override
  String get fieldExpiryRenewalDate => 'Data di scadenza / rinnovo';

  @override
  String get fieldDownloadUrl => 'URL di download';

  @override
  String get fieldRegistrationEmail => 'Email di registrazione';

  @override
  String get titleRequired => 'Il titolo è obbligatorio';

  @override
  String newTypeTitle(String typeLabel) {
    return 'Nuovo $typeLabel';
  }

  @override
  String editItemTitle(String title) {
    return 'Modifica $title';
  }

  @override
  String get save => 'Salva';

  @override
  String typeNameHint(String typeLabel) {
    return 'Nome $typeLabel';
  }

  @override
  String get titleSectionLabel => 'Titolo';

  @override
  String get fieldsSectionLabel => 'Campi';

  @override
  String get encryptedStorageHint =>
      'Tutti i campi sono memorizzati cifrati all\'interno del contenitore.';

  @override
  String copiedSuffix(String fieldLabel) {
    return '$fieldLabel copiato';
  }

  @override
  String get copy => 'Copia';

  @override
  String get failedToSaveCheckMounted =>
      'Salvataggio non riuscito — verifica che il contenitore sia ancora montato';

  @override
  String get discardChangesTitle => 'Annullare le modifiche?';

  @override
  String get discardChangesMessage =>
      'Le modifiche non salvate andranno perse.';

  @override
  String get discard => 'Annulla modifiche';

  @override
  String get keepEditing => 'Continua a modificare';

  @override
  String get deleteItemTitle => 'Eliminare l\'elemento?';

  @override
  String deleteItemMessage(String title) {
    return '\"$title\" verrà eliminato definitivamente dal vault.';
  }

  @override
  String get removeFromBookmarks => 'Rimuovi dai preferiti';

  @override
  String get addToBookmarks => 'Aggiungi ai preferiti';

  @override
  String get edit => 'Modifica';

  @override
  String labelCopiedToClipboard(String label) {
    return '$label copiato negli appunti';
  }

  @override
  String get noFieldsFilledIn =>
      'Nessun campo compilato.\nTocca Modifica per aggiungere dettagli.';

  @override
  String get sectionLabelDetails => 'Dettagli';

  @override
  String get sectionLabelInfo => 'Info';

  @override
  String get metaLabelType => 'Tipo';

  @override
  String get metaLabelCreated => 'Creato';

  @override
  String get metaLabelModified => 'Modificato';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return 'Copia $fieldLabel';
  }

  @override
  String get readOnlyCantAddItemsTooltip =>
      'Sola lettura — impossibile aggiungere elementi';

  @override
  String get extractArchive => 'Estrai archivio';

  @override
  String get newItemTooltip => 'Nuovo elemento';

  @override
  String get camera => 'Fotocamera';

  @override
  String get importFiles => 'Importa file';

  @override
  String get importFolder => 'Importa cartella';

  @override
  String get secureItem => 'Elemento sicuro';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archive Explorer';

  @override
  String get archiveExplorerPermissionTitle =>
      'Accesso all\'archiviazione necessario';

  @override
  String get archiveExplorerPermissionMessage =>
      'Consenti l\'accesso ai tuoi file per sfogliare ed estrarre archivi .zip dalla cartella Download.';

  @override
  String get archiveExplorerGrantAccess => 'Concedi accesso';

  @override
  String get archiveExplorerEmptyTitle => 'Nessun archivio trovato';

  @override
  String get archiveExplorerEmptyMessage =>
      'I file zip scaricati appariranno qui.';

  @override
  String get archiveExplorerRefreshTooltip => 'Aggiorna';

  @override
  String archiveExplorerEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get archiveExplorerExtractAll => 'Estrai tutto';

  @override
  String get archiveExplorerExtracting => 'Estrazione…';

  @override
  String archiveExplorerExtractSuccess(int count, String name) {
    return 'Estratti $count file in Download/Extracted/$name';
  }

  @override
  String get archiveExplorerExtractFailed =>
      'Impossibile estrarre questo archivio.';

  @override
  String get archiveExplorerOpenFailed => 'Impossibile aprire questo archivio.';

  @override
  String get archiveExplorerOpenArchive => 'Apri archivio…';

  @override
  String get archiveExplorerUnresolvedPath =>
      'Impossibile accedere direttamente a questo file. Prova a sceglierne uno dalla cartella Download.';

  @override
  String get archiveExplorerExtractTo => 'Estrai in…';

  @override
  String get archiveExplorerPreview => 'Anteprima';

  @override
  String get archiveExplorerChoosingDestination => 'Scelta della destinazione…';

  @override
  String get archiveExplorerNoDestinationChosen =>
      'Nessuna destinazione scelta.';

  @override
  String archiveExplorerExtractSuccessTo(int count, String path) {
    return 'Estratti $count file in $path';
  }

  @override
  String get archiveBrowserEmptyTitle => 'Cartella vuota';

  @override
  String get archiveBrowserEmptyMessage => 'Questa cartella non contiene file.';

  @override
  String get archiveBrowserRoot => 'Archivio';

  @override
  String get archiveBrowserOpenFileFailed => 'Impossibile aprire questo file.';

  @override
  String get fileAssocInAppTextEditor => 'Editor di testo integrato';

  @override
  String get fileAssocInAppMediaViewer =>
      'Visualizzatore multimediale integrato';

  @override
  String fileAssocAppPrefix(String name) {
    return 'App: $name';
  }

  @override
  String get fileAssocExternalApp => 'App esterna';

  @override
  String get appSettingsTitle => 'Impostazioni app';

  @override
  String get sectionSecurityPrivacy => 'Sicurezza e privacy';

  @override
  String get sectionAppearanceInterface => 'Aspetto e interfaccia';

  @override
  String get sectionVaultFileHandling => 'Vault e gestione file';

  @override
  String get masterPasswordTitle => 'Password principale';

  @override
  String get masterPasswordActiveSubtitle =>
      'Attiva — tocca l\'interruttore per rimuoverla';

  @override
  String get masterPasswordInactiveSubtitle =>
      'Richiedi una password per aprire l\'app';

  @override
  String get newPasswordLabel => 'Nuova password';

  @override
  String get masterPasswordFieldLabel => 'Password principale';

  @override
  String get confirmPasswordLabel => 'Conferma password';

  @override
  String get update => 'Aggiorna';

  @override
  String get setPassword => 'Imposta password';

  @override
  String get biometricUnlockTitle => 'Sblocco biometrico';

  @override
  String get biometricUnlockSubtitle =>
      'Autenticati per montare in sicurezza il contenitore';

  @override
  String get changeMasterPasswordTitle => 'Cambia password principale';

  @override
  String get changeMasterPasswordSubtitle =>
      'Aggiorna le credenziali della password principale';

  @override
  String get autoLockContainersTitle => 'Blocco automatico contenitori';

  @override
  String get autoLockContainersSubtitle =>
      'Blocca automaticamente i vault aperti dopo un periodo di inattività';

  @override
  String get autoLockTimeoutLabel => 'Tempo di blocco automatico';

  @override
  String get immediately => 'Immediatamente';

  @override
  String nMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minuti',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get blockScreenshotsTitle => 'Blocca screenshot';

  @override
  String get blockScreenshotsSubtitle =>
      'Impedisce gli screenshot e nasconde l\'anteprima nelle app recenti';

  @override
  String get keepVaultsRunningInBackgroundTitle =>
      'Mantieni i contenitori aperti in background';

  @override
  String get keepVaultsRunningInBackgroundSubtitle =>
      'Mostra una notifica e mantiene i vault aperti disponibili dopo aver lasciato l\'app. Le chiavi del vault restano in memoria finché non vengono bloccate.';

  @override
  String get notificationPermissionDeniedMessage =>
      'Permesso di notifica negato. I vault resteranno comunque aperti, ma la notifica persistente non verrà mostrata.';

  @override
  String get discreteModeTitle => 'Modalità mascherata';

  @override
  String get discreteModeActiveSubtitle =>
      'Attiva — l\'app appare attualmente come \"Archive Explorer\"';

  @override
  String get discreteModeInactiveSubtitle =>
      'Maschera questa app come browser di archivi zip nella schermata Home';

  @override
  String get enableDiscreteModeTitle => 'Attivare la modalità mascherata?';

  @override
  String get disableDiscreteModeTitle => 'Disattivare la modalità mascherata?';

  @override
  String get enableDiscreteModeMessage =>
      'L\'icona e il nome dell\'app nella schermata Home cambieranno in \"Archive Explorer\". Funzionerà come browser ed estrattore di archivi zip.\n\nPer accedere al tuo vault, apri Archive Explorer e tieni premuto il dito sul titolo per 3 secondi.';

  @override
  String get disableDiscreteModeMessage =>
      'L\'icona e il nome dell\'app nella schermata Home torneranno a \"Vault Explorer\".';

  @override
  String get enable => 'Attiva';

  @override
  String get disable => 'Disattiva';

  @override
  String get discreteModeEnabledSnack =>
      'Modalità mascherata attivata. L\'app si chiuderà — riaprila dalla nuova icona nel launcher.';

  @override
  String get discreteModeDisabledSnack =>
      'Modalità mascherata disattivata. L\'app si chiuderà — riaprila dalla nuova icona nel launcher.';

  @override
  String get failedToChangeDiscreteMode =>
      'Impossibile modificare la modalità mascherata';

  @override
  String get cacheDerivedKeysTitle =>
      'Memorizza nella cache le chiavi derivate per impostazione predefinita';

  @override
  String get cacheDerivedKeysSubtitle =>
      'Memorizza il materiale della chiave derivata nel Keystore per sblocchi più rapidi';

  @override
  String get appThemeLabel => 'Tema dell\'app';

  @override
  String get systemDefault => 'Predefinito di sistema';

  @override
  String get lightTheme => 'Tema chiaro';

  @override
  String get darkTheme => 'Tema scuro';

  @override
  String get useMaterialYouTitle => 'Usa Material You';

  @override
  String get useMaterialYouSubtitle =>
      'Abbina i colori dell\'app allo sfondo (Android 12+)';

  @override
  String get sortContainersByLabel => 'Ordina contenitori per';

  @override
  String get swapCardSwipeActionsTitle =>
      'Inverti azioni di scorrimento delle schede';

  @override
  String get swapCardSwipeActionsSubtitle =>
      'Mostra Modifica a sinistra e Rimuovi a destra scorrendo le schede';

  @override
  String get swipeGestureHintTitle => 'Suggerimento gesto di scorrimento';

  @override
  String get swipeGestureHintSubtitle =>
      'Mostra l\'animazione di anteprima della scheda al primo contenitore';

  @override
  String get autoOpenOnUnlockTitle => 'Apertura automatica allo sblocco';

  @override
  String get autoOpenOnUnlockActiveSubtitle =>
      'Apri automaticamente dopo aver sbloccato un vault';

  @override
  String get autoOpenOnUnlockInactiveSubtitle =>
      'Sblocca solo il vault e resta sulla dashboard';

  @override
  String get enableJsHtmlTitle => 'Attiva JavaScript nel visualizzatore HTML';

  @override
  String get jsEnabledSubtitle => 'JavaScript attivato per i file HTML locali';

  @override
  String get jsDisabledSubtitle =>
      'JavaScript disattivato per i file HTML locali';

  @override
  String get fastStorageAccessTitle => 'Accesso rapido all\'archiviazione';

  @override
  String get fastStorageAccessGrantedSubtitle =>
      'Accesso a tutti i file concesso (velocità massima)';

  @override
  String get fastStorageAccessNotGrantedSubtitle =>
      'Concedi l\'accesso a tutti i file nelle impostazioni di sistema per la massima velocità';

  @override
  String get enableFastStorageAccessTitle =>
      'Attiva accesso rapido all\'archiviazione';

  @override
  String get enableFastStorageAccessMessage =>
      'Concedere \"Accesso a tutti i file\" permette a Vault Explorer di eseguire operazioni POSIX dirette sui file, aumentando le prestazioni dei vault a cartella fino a 1000 volte.';

  @override
  String get disableStorageAccessTitle =>
      'Disattiva accesso all\'archiviazione';

  @override
  String get disableStorageAccessMessage =>
      'Android richiede che \"Accesso a tutti i file\" venga disattivato nelle impostazioni di sistema. Vuoi aprire le Impostazioni per disattivarlo?';

  @override
  String get enableStoragePermissionLegacyTitle =>
      'Consenti accesso all\'archiviazione';

  @override
  String get enableStoragePermissionLegacyMessage =>
      'Vault Explorer necessita dell\'autorizzazione di archiviazione per eseguire operazioni dirette sui file, aumentando le prestazioni dei vault a cartella. Android ti chiederà ora di confermare.';

  @override
  String get disableStoragePermissionLegacyMessage =>
      'Android richiede che l\'autorizzazione di archiviazione venga disattivata nelle impostazioni di sistema. Vuoi aprire le Impostazioni per disattivarla?';

  @override
  String get openSettings => 'Apri impostazioni';

  @override
  String get androidFileProviderTitle => 'Provider file Android';

  @override
  String get androidFileProviderSubtitle =>
      'Esponi i nuovi contenitori al selettore file di Android per impostazione predefinita';

  @override
  String get thumbnailCachingDefaultLabel => 'Cache miniature (predefinita)';

  @override
  String get thumbnailQualityDefaultLabel => 'Qualità miniature (predefinita)';

  @override
  String get fileAssociationsHeader => 'Associazioni file';

  @override
  String get noFileAssociationsYet =>
      'Nessuna associazione file memorizzata. Ti verrà chiesto all\'apertura dei file.';

  @override
  String get defaultActionsHeader =>
      'Azioni predefinite per l\'apertura di file non standard:';

  @override
  String get removeAssociationTooltip => 'Rimuovi associazione';

  @override
  String get sectionBackupRestore => 'Backup';

  @override
  String get exportSettingsTitle => 'Esporta impostazioni';

  @override
  String get exportSettingsSubtitle =>
      'Salva le impostazioni dell\'app e il layout del file manager in un file';

  @override
  String get importSettingsTitle => 'Importa impostazioni';

  @override
  String get importSettingsSubtitle =>
      'Ripristina le impostazioni dell\'app e il layout del file manager da un file';

  @override
  String get importSettingsConfirmTitle => 'Importare le impostazioni?';

  @override
  String get importSettingsConfirmMessage =>
      'Questo sostituirà le impostazioni correnti dell\'app e il layout del file manager. L\'operazione non può essere annullata.';

  @override
  String get exportSettingsSuccessMessage => 'Impostazioni esportate';

  @override
  String get importSettingsSuccessMessage => 'Impostazioni importate';

  @override
  String get exportSettingsErrorMessage =>
      'Impossibile esportare le impostazioni';

  @override
  String get importSettingsInvalidFileMessage =>
      'Questo file non è un\'esportazione di impostazioni valida';

  @override
  String get sectionDebug => 'Debug';

  @override
  String get debugLoggingTitle => 'Debug logging';

  @override
  String get debugLoggingSubtitle =>
      'Record detailed diagnostic logs for container operations';

  @override
  String get logcatTitle => 'Logcat';

  @override
  String get logcatSubtitle => 'View and save device logs';

  @override
  String logcatSavedMessage(String path) {
    return 'Log saved to $path';
  }

  @override
  String get logcatSaveErrorMessage => 'Failed to save log';

  @override
  String get logcatCopiedMessage => 'Log copied to clipboard';

  @override
  String get logcatUnavailableMessage =>
      'Logcat is not available on this device';

  @override
  String get logcatEmptyMessage => 'Waiting for log lines…';

  @override
  String get logcatClearTooltip => 'Clear log';

  @override
  String get logcatSaveTooltip => 'Save log';

  @override
  String get logcatFilterAppOnly => 'App Only';

  @override
  String get logcatFilterAll => 'All Logs';

  @override
  String get logcatSearchHint => 'Search logs…';

  @override
  String get logcatClearedMessage => 'Logs cleared';

  @override
  String get logcatCopyTooltip => 'Copy log';

  @override
  String get retryButton => 'Riprova';

  @override
  String get aboutAppTitle => 'Informazioni su VaultExplorer';

  @override
  String versionInfoSubtitle(String version) {
    return 'Versione $version · Licenze open source e dettagli';
  }

  @override
  String get failedToSaveSettings => 'Impossibile salvare le impostazioni';

  @override
  String get masterPasswordSetSnack => 'Password principale impostata';

  @override
  String get passwordCannotBeEmpty => 'La password non può essere vuota';

  @override
  String get atLeast4CharsRequired => 'Sono richiesti almeno 4 caratteri';

  @override
  String get passwordsDoNotMatch => 'Le password non corrispondono';

  @override
  String get failedToHashPassword =>
      'Impossibile calcolare l\'hash della password — riprova';

  @override
  String get languageLabel => 'Lingua';

  @override
  String get biometricNotAvailable =>
      'Autenticazione biometrica non disponibile su questo dispositivo';

  @override
  String get unlockVaultExplorerReason => 'Sblocca VaultExplorer';

  @override
  String biometricErrorWithCode(String code) {
    return 'Errore biometrico: $code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds secondi',
      one: '1 secondo',
    );
    return 'Troppi tentativi falliti. Riprova tra $_temp0.';
  }

  @override
  String get enterMasterPasswordPrompt =>
      'Inserisci la tua password principale';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts tentativi falliti',
      one: '1 tentativo fallito',
    );
    return 'Password errata. Bloccato per ${seconds}s a causa di $_temp0.';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts tentativi falliti',
      one: '1 tentativo fallito',
    );
    return 'Password errata ($_temp0).';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle =>
      'Inserisci la tua password principale per continuare';

  @override
  String get masterPasswordFieldLabelTitleCase => 'Password principale';

  @override
  String get unlock => 'Sblocca';

  @override
  String get useBiometric => 'Usa biometria';

  @override
  String get connectAtLeast4Dots => 'Collega almeno 4 punti';

  @override
  String get patternsDontMatch => 'Gli schemi non corrispondono — riprova';

  @override
  String get drawUnlockPatternTitle => 'Disegna lo schema di sblocco';

  @override
  String get confirmPatternTitle => 'Conferma il tuo schema';

  @override
  String get drawSamePatternAgain => 'Disegna di nuovo lo stesso schema';

  @override
  String get enterAtLeast4Digits => 'Enter at least 4 digits';

  @override
  String get pinsDontMatch => 'PINs don\'t match — try again';

  @override
  String get createUnlockPinTitle => 'Create your unlock PIN';

  @override
  String get confirmPinTitle => 'Confirm your PIN';

  @override
  String get enterSamePinAgain => 'Enter the same PIN again';

  @override
  String get enterUnlockPinTitle => 'Enter Unlock PIN';

  @override
  String get wrongPinTryAgain => 'Wrong PIN — try again';

  @override
  String get enterYourPinSequence => 'Enter your PIN';

  @override
  String get enterPinToMount => 'Enter your PIN to mount';

  @override
  String get noPinConfiguredMessage =>
      'No PIN configured. Please enter password manually.';

  @override
  String pinLockedForSeconds(int seconds) {
    return 'Too many failed attempts. Locked for ${seconds}s.';
  }

  @override
  String get initSecureCredsPinMessage =>
      'Initializing secure credentials. Please unlock manually once to authorize PIN access.';

  @override
  String get setPinButton => 'Set PIN';

  @override
  String get changePinButton => 'Change PIN';

  @override
  String get pinSetupRequiredBeforeSaving => 'Set up a PIN before saving.';

  @override
  String get pinSetupRequiredAboveBeforeSaving =>
      'Set up a PIN above before saving.';

  @override
  String get verifyPinTitle => 'Verify PIN';

  @override
  String get incorrectPinError => 'Incorrect PIN';

  @override
  String removedFromListSnack(String name) {
    return '\"$name\" rimosso dall\'elenco';
  }

  @override
  String get clearRecentHistoryTitle => 'Cancellare la cronologia recente?';

  @override
  String get clearRecentHistoryMessage =>
      'Questo rimuoverà tutti i documenti recenti dal tuo elenco. I file effettivi sul tuo dispositivo non verranno modificati.';

  @override
  String get clearAll => 'Cancella tutto';

  @override
  String get recentHistoryClearedSnack => 'Cronologia recente cancellata';

  @override
  String get moreOptionsTooltip => 'Altre opzioni';

  @override
  String get clearHistoryMenuItem => 'Cancella cronologia';

  @override
  String get openPdfFile => 'Apri file PDF';

  @override
  String get noDocumentsYetTitle => 'Ancora nessun documento';

  @override
  String get openPdfToStartMessage =>
      'Apri un PDF dal tuo dispositivo per iniziare a leggere.';

  @override
  String get removeFromListMenuItem => 'Rimuovi dall\'elenco';

  @override
  String get justNow => 'Proprio ora';

  @override
  String minutesAgo(int count) {
    return '${count}m fa';
  }

  @override
  String hoursAgo(int count) {
    return '${count}h fa';
  }

  @override
  String daysAgo(int count) {
    return '${count}g fa';
  }

  @override
  String get usbDriveDisconnectedLocked =>
      'Unità USB disconnessa — contenitore bloccato';

  @override
  String get containerAlreadyMounted => 'Questo contenitore è già montato.';

  @override
  String get noVaultFolderFormatDetected =>
      'Nessun masterkey.cryptomator, gocryptfs.conf o cryfs.config trovato in quella cartella.';

  @override
  String get savedContainerSettingsNotFound =>
      'Impossibile trovare le impostazioni salvate per questo contenitore.';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return 'Impossibile aggiornare la posizione del contenitore: $error';
  }

  @override
  String filePickerFailed(String error) {
    return 'Selezione file non riuscita: $error';
  }

  @override
  String get selectContainerFirst => 'Seleziona prima un contenitore';

  @override
  String get passwordOrKeyfilesRequired =>
      'È richiesta una password o dei file chiave';

  @override
  String get slowPerformanceWarningTitle => 'Avviso prestazioni ridotte';

  @override
  String get slowPerformanceWarningMessage =>
      'L\'accesso diretto all\'archiviazione è attualmente disattivato.\n\nCryFS memorizza i file in migliaia di piccoli blocchi. L\'apertura di vault CryFS non vuoti tramite Android SAF sarà molto lenta.\n\nVuoi aprire le Impostazioni per concedere \"Accesso a tutti i file\" e ottenere velocità elevate?';

  @override
  String get unlockAnyway => 'Sblocca comunque';

  @override
  String get defaultVaultName => 'Vault';

  @override
  String get defaultContainerName => 'Contenitore';

  @override
  String get incorrectPasswordOrInvalidVault =>
      'Password errata o vault non valido';

  @override
  String get incorrectPasswordOrInvalidContainer =>
      'Password errata o contenitore non valido';

  @override
  String get genericUnknownError => 'Errore sconosciuto';

  @override
  String get decryptingLabel => 'Decifratura…';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return 'Tentativo dello slot chiave $attempted di $total…';
  }

  @override
  String get luksKeyslotProgressUnknown => 'Tentativo dello slot chiave…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return 'Verifica della credenziale $attempted di $total…';
  }

  @override
  String get bitlockerCredentialProgressUnknown =>
      'Verifica della credenziale…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return 'Tentativo con $algo ($slotName)…';
  }

  @override
  String get unlockContainerLabel => 'Sblocca contenitore';

  @override
  String get mountContainerTitle => 'Monta contenitore';

  @override
  String get containerFileSegmentLabel => 'File contenitore';

  @override
  String get folderVaultSegmentLabel => 'Vault a cartella';

  @override
  String formatContainerLabel(String format) {
    return 'Contenitore $format';
  }

  @override
  String formatVaultLabel(String format) {
    return 'Vault $format';
  }

  @override
  String formatDriveLabel(String format) {
    return 'Unità $format';
  }

  @override
  String get encryptedContainerLabel => 'Contenitore cifrato';

  @override
  String get tapToSelectVaultFolder =>
      'Tocca per selezionare la cartella del vault…';

  @override
  String get tapToSelectContainerFile =>
      'Tocca per selezionare il file contenitore…';

  @override
  String get containerMissingTitle => 'Contenitore mancante';

  @override
  String get filePathCouldNotBeResolved =>
      'Impossibile risolvere il percorso del file';

  @override
  String get containerMissingExplanation =>
      'Il file contenitore potrebbe essere stato spostato, eliminato, oppure la sua unità di archiviazione host è attualmente disconnessa.';

  @override
  String get retryButtonLabel => 'Riprova';

  @override
  String get locateFileButtonLabel => 'Individua file';

  @override
  String get authenticateToMountSubtitle =>
      'Autenticati per montare in sicurezza il contenitore';

  @override
  String get usePasswordButtonLabel => 'Usa password';

  @override
  String get authenticateButtonLabel => 'Autentica';

  @override
  String get drawUnlockPatternCardTitle => 'Disegna lo schema di sblocco';

  @override
  String get wrongPatternTryAgain => 'Schema errato — riprova';

  @override
  String get connectYourPatternSequence => 'Collega la sequenza del tuo schema';

  @override
  String get usePasswordInsteadButtonLabel => 'Usa invece la password';

  @override
  String get passwordHintFolderVault => 'Inserisci la password del vault';

  @override
  String get passwordHintBitlocker =>
      'Inserisci la password o la chiave di recupero';

  @override
  String get passwordHintContainer => 'Inserisci la password del contenitore';

  @override
  String get usingSavedPasswordTooltip => 'Utilizzo della password salvata';

  @override
  String get luksKeyfileReplacesPasswordNote =>
      'Per i contenitori LUKS il file chiave sostituisce la password.';

  @override
  String get readOnlyModeUsbSubtitle =>
      'Monta senza consentire modifiche a questa unità';

  @override
  String get readOnlyModeContainerSubtitle =>
      'Monta senza consentire modifiche a questo contenitore';

  @override
  String get rememberContainerLabel => 'Ricorda contenitore';

  @override
  String get rememberContainerSubtitle =>
      'Fissa il contenitore sulla dashboard per un accesso rapido';

  @override
  String get cancelUnlockButtonLabel => 'Annulla sblocco';

  @override
  String get biometricSubjectContainer => 'contenitore';

  @override
  String get biometricSubjectUsbDrive => 'unità USB';

  @override
  String get usbNoSavedCredentialsMessage =>
      'Nessuna password salvata trovata. Inseriscila manualmente.';

  @override
  String get decryptingDriveLabel => 'Decifratura unità…';

  @override
  String get usbDeviceAlreadyActiveMounted =>
      'Questo dispositivo USB è già attivo e montato.';

  @override
  String reconnectUsbDriveTitle(String label) {
    return 'Riconnetti \"$label\"';
  }

  @override
  String get unlockUsbDriveTitle => 'Sblocca unità USB';

  @override
  String get noUsbStorageDetectedTitle => 'Nessuna archiviazione USB rilevata';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return 'Autenticati per sbloccare $subject';
  }

  @override
  String get noPatternConfiguredMessage =>
      'Nessuno schema configurato. Inserisci la password manualmente.';

  @override
  String patternLockedForSeconds(int seconds) {
    return 'Troppi tentativi falliti. Bloccato per ${seconds}s.';
  }

  @override
  String get initSecureCredsBiometricMessage =>
      'Inizializzazione delle credenziali sicure. Sblocca manualmente una volta per autorizzare l\'accesso biometrico.';

  @override
  String get initSecureCredsPatternMessage =>
      'Inizializzazione delle credenziali sicure. Sblocca manualmente una volta per autorizzare l\'accesso tramite schema.';

  @override
  String get mountExistingContainerTitle => 'Monta contenitore esistente';

  @override
  String get mountExistingContainerSubtitle =>
      'Sblocca un file contenitore che possiedi già';

  @override
  String get mountSplitContainerTitle => 'Monta contenitore diviso';

  @override
  String get mountSplitContainerSubtitle =>
      'Sblocca direttamente un contenitore diviso, senza prima unirlo';

  @override
  String get mountUsbDriveTitle => 'Monta unità USB';

  @override
  String get mountUsbDriveSubtitle =>
      'Sblocca un contenitore su un\'unità flash OTG';

  @override
  String get formatUsbDriveTitle => 'Formatta unità USB';

  @override
  String get formatUsbDriveSubtitle =>
      'Cancella un\'unità e crea su di essa un nuovo contenitore cifrato';

  @override
  String get createNewContainerTitle => 'Crea nuovo contenitore';

  @override
  String get createNewContainerSubtitle =>
      'Formatta un vault cifrato completamente nuovo';

  @override
  String get lockBeforeRemovingWarning =>
      'Blocca il contenitore prima di rimuoverlo.';

  @override
  String get settingsTooltip => 'Impostazioni';

  @override
  String get addVaultFabLabel => 'Aggiungi vault';

  @override
  String removedLabelUndo(String label) {
    return '\"$label\" rimosso';
  }

  @override
  String get undo => 'Annulla';

  @override
  String get pdfViewerNoSourceProvided => 'Nessuna origine PDF fornita.';

  @override
  String get pdfViewerFileEmpty => 'Il file PDF è vuoto o illeggibile.';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return 'Impossibile verificare la dimensione del file PDF: $error';
  }

  @override
  String get pdfViewerErrorLoadingTitle => 'Errore nel caricamento del PDF';

  @override
  String get pdfViewerNoDocumentLoaded => 'Nessun documento PDF caricato.';

  @override
  String get add => 'Aggiungi';

  @override
  String get reset => 'Ripristina';

  @override
  String couldNotExpose(String name) {
    return 'Impossibile esporre \"$name\".';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return '\"$name\" è ora disponibile per altre app.';
  }

  @override
  String couldNotUnmount(String name) {
    return 'Impossibile smontare \"$name\".';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Fissati $count elementi',
      one: 'Fissato 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Rimossi dai fissati $count elementi',
      one: 'Rimosso dai fissati 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning =>
      'Montaggio in sola lettura — le miniature verranno mostrate ma non salvate all\'interno del contenitore in questa sessione.';

  @override
  String failedLoadingFolder(String type) {
    return 'Caricamento cartella non riuscito: $type';
  }

  @override
  String failedToReadArchive(String type) {
    return 'Lettura archivio non riuscita: $type';
  }

  @override
  String archiveFormatNotSupported(String ext) {
    return 'Il formato archivio .$ext non è ancora supportato';
  }

  @override
  String get failedToReadFileFromArchive =>
      'Lettura del file dall\'archivio non riuscita';

  @override
  String failedToExtractFile(String type) {
    return 'Estrazione file non riuscita: $type';
  }

  @override
  String get failedToReadSecureItem =>
      'Lettura dell\'elemento sicuro non riuscita';

  @override
  String get openFileDialogTitle => 'Apri file';

  @override
  String chooseHowToOpen(String name) {
    return 'Scegli come aprire \"$name\":';
  }

  @override
  String get playVideoAudioViewImageInApp =>
      'Riproduci video/audio o visualizza immagini nell\'app';

  @override
  String get viewEditTextMarkdownCode =>
      'Visualizza/modifica testo, markdown, codice';

  @override
  String get sendFileToThirdPartyApp => 'Invia file a un\'app di terze parti';

  @override
  String get openAsEllipsis => 'Apri come…';

  @override
  String get chooseFileTypeToOpenAs => 'Scegli il tipo di file con cui aprire';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return 'Ricorda sempre la scelta per i file .$ext';
  }

  @override
  String get alwaysRememberChoiceNoExt =>
      'Ricorda sempre la scelta per i file senza estensione';

  @override
  String get openAsDialogTitle => 'Apri come';

  @override
  String get mimeTypeText => 'Testo';

  @override
  String get mimeTypeImage => 'Immagine';

  @override
  String get mimeTypeVideo => 'Video';

  @override
  String get mimeTypeAudio => 'Audio';

  @override
  String get mimeTypeArchive => 'Archivio';

  @override
  String get mimeTypeOther => 'Altro';

  @override
  String get scanningSubfoldersForMedia =>
      'Scansione delle sottocartelle per contenuti multimediali…';

  @override
  String get noMediaFilesFoundRecursive =>
      'Nessun file multimediale trovato in questa cartella o nelle sue sottocartelle';

  @override
  String failedToScanSubfolders(String error) {
    return 'Scansione delle sottocartelle non riuscita: $error';
  }

  @override
  String get noAppFoundForFileType =>
      'Nessuna app trovata per questo tipo di file';

  @override
  String couldNotOpenFile(String name) {
    return 'Impossibile aprire \"$name\"';
  }

  @override
  String get readOnlyCantMove =>
      'Questo contenitore è montato in sola lettura — gli elementi non possono essere spostati da qui.';

  @override
  String get readOnlyCantPaste =>
      'Questo contenitore è montato in sola lettura — non è possibile incollare elementi qui.';

  @override
  String get clipboardSourceInvalid => 'L\'origine degli appunti non è valida';

  @override
  String get crossContainerPasteNotConfigured =>
      'L\'incolla tra contenitori diversi non è configurato.';

  @override
  String get crossContainerPasteRequiresBothMounted =>
      'L\'incolla tra contenitori diversi richiede che entrambi restino montati.';

  @override
  String get readOnlyCantDelete =>
      'Questo contenitore è montato in sola lettura — non è possibile eliminare elementi.';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminati $count elementi',
      one: 'Eliminato 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String deletedWithFailures(int deleted, int failed) {
    return '$deleted eliminati · $failed non riusciti';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Esportati $count file',
      one: 'Esportato 1 file',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed => 'Esportazione annullata o non riuscita';

  @override
  String exportError(String type) {
    return 'Errore di esportazione: $type';
  }

  @override
  String get deleteOriginalTitle => 'Eliminare l\'originale?';

  @override
  String get deleteOriginalFolderMessage =>
      'Eliminare la cartella originale dal dispositivo ora che è stata importata?';

  @override
  String get deleteOriginalFilesMessage =>
      'Eliminare i file originali dal dispositivo ora che sono stati importati?';

  @override
  String get keepOriginal => 'Mantieni originale';

  @override
  String get deleteOriginalButton => 'Elimina originale';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminati $count elementi originali',
      one: 'Eliminato 1 elemento originale',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals => 'Impossibile eliminare gli originali';

  @override
  String get videoCapturedEncrypted => 'Video acquisito e cifrato';

  @override
  String get photoCapturedEncrypted => 'Foto acquisita e cifrata';

  @override
  String cameraCaptureFailed(String type) {
    return 'Acquisizione dalla fotocamera non riuscita: $type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return 'Estrarre tutti i file nella cartella \"$folder\"?';
  }

  @override
  String get extract => 'Estrai';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Estratti $count file',
      one: 'Estratto 1 file',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return 'Estrazione non riuscita: $type';
  }

  @override
  String get closeSearchTooltip => 'Chiudi ricerca';

  @override
  String get searchInThisFolderTooltip => 'Cerca in questa cartella';

  @override
  String get playMediaHereTooltip => 'Riproduci contenuti multimediali qui';

  @override
  String get rootFolderLabel => 'Radice';

  @override
  String folderPickerFailed(String error) {
    return 'Selezione cartella non riuscita: $error';
  }

  @override
  String get addAVaultTitle => 'Aggiungi un vault';

  @override
  String get selectEmptyDestinationFolderFirst =>
      'Seleziona prima una cartella di destinazione vuota';

  @override
  String get passwordRequired => 'È richiesta una password';

  @override
  String get vaultCreatedSuccessfully => 'Vault creato con successo.';

  @override
  String get vaultCreationFailedEmptyFolder =>
      'Creazione del vault non riuscita — assicurati che la cartella selezionata sia vuota.';

  @override
  String get unknownErrorOccurred => 'Si è verificato un errore sconosciuto';

  @override
  String get containerNameRequired => 'Il nome del contenitore è obbligatorio';

  @override
  String get enterValidSizeGreaterThanZero =>
      'Inserisci una dimensione valida maggiore di 0';

  @override
  String get passwordOrKeyfileRequired =>
      'È richiesta una password o almeno un file chiave';

  @override
  String get standardVolumePasswordsDoNotMatch =>
      'Le password del volume standard non corrispondono';

  @override
  String get hiddenVolumePasswordsDoNotMatch =>
      'Le password del volume nascosto non corrispondono';

  @override
  String get containerFileCreatedSuccessfully =>
      'File contenitore creato con successo.';

  @override
  String get containerCreationCancelledOrFailed =>
      'Creazione del contenitore annullata o non riuscita.';

  @override
  String get vaultKindContainerFile => 'File contenitore';

  @override
  String get vaultKindFolderVault => 'Vault a cartella';

  @override
  String get formatFileSystemLabel => 'Formatta file system';

  @override
  String get standardVolumeHeader => 'Volume standard';

  @override
  String get containerFormatLabel => 'Formato contenitore';

  @override
  String get fileNameLabel => 'Nome file';

  @override
  String get containerSizeLabel => 'Dimensione contenitore';

  @override
  String get unitLabel => 'Unità';

  @override
  String get passwordFieldLabel => 'Password';

  @override
  String get confirmPasswordFieldLabelTitleCase => 'Conferma password';

  @override
  String get hiddenVolumeHeader => 'Volume nascosto';

  @override
  String get createHiddenVolumeToggleTitle => 'Crea volume nascosto';

  @override
  String get createInvisibleSecondaryVolume =>
      'Crea un volume secondario invisibile';

  @override
  String get setOuterPasswordFirstToEnable =>
      'Imposta prima la password o i file chiave esterni per attivare';

  @override
  String get hiddenPasswordLabel => 'Password nascosta';

  @override
  String get confirmHiddenPasswordLabel => 'Conferma password nascosta';

  @override
  String get hiddenSizeLabel => 'Dimensione nascosta';

  @override
  String get unitMbMegabytes => 'MB (Megabyte)';

  @override
  String get unitGbGigabytes => 'GB (Gigabyte)';

  @override
  String get hiddenFileSystemLabel => 'File system nascosto';

  @override
  String get vaultFormatLabel => 'Formato vault';

  @override
  String get gocryptfsCipherLabel => 'Cifrario del contenuto';

  @override
  String get cryfsCipherLabel => 'Cifrario del contenuto';

  @override
  String get cryfsBlockSizeLabel => 'Dimensione blocco';

  @override
  String get destinationFolderLabel => 'Cartella di destinazione';

  @override
  String get selectEmptyFolderLabel => 'Seleziona una cartella vuota';

  @override
  String get tapToChooseVaultLocation =>
      'Tocca per scegliere dove verrà creato il vault…';

  @override
  String get folderVaultLimitationsNote =>
      'I vault a cartella non supportano file chiave, PIM, volumi nascosti o la scelta del cifrario VeraCrypt/LUKS.';

  @override
  String get createVaultButton => 'Crea vault';

  @override
  String get createContainerButton => 'Crea contenitore';

  @override
  String get vaultCreationInProgressWait =>
      'Creazione del vault in corso. Attendere.';

  @override
  String get containerCreationInProgressWait =>
      'Creazione del contenitore in corso. Attendere.';

  @override
  String get createEncryptedVaultTitle => 'Crea vault cifrato';

  @override
  String get createEncryptedContainerTitle => 'Crea contenitore cifrato';

  @override
  String get unitMbShort => 'MB';

  @override
  String get unitGbShort => 'GB';

  @override
  String failedToListUsbDevices(String error) {
    return 'Impossibile elencare i dispositivi USB: $error';
  }

  @override
  String get usbPermissionDenied => 'Autorizzazione USB negata';

  @override
  String get couldNotReadDriveCapacity =>
      'Impossibile leggere la capacità dell\'unità — inserisci la dimensione manualmente.';

  @override
  String get selectUsbDriveFirst => 'Seleziona prima un\'unità USB';

  @override
  String eraseDeviceTitle(String name) {
    return 'Cancellare \"$name\"?';
  }

  @override
  String get eraseDeviceMessage =>
      'Questo cancellerà definitivamente tutto ciò che è attualmente presente su questa unità USB e lo sostituirà con un nuovo contenitore cifrato. L\'operazione non può essere annullata.';

  @override
  String get eraseAndCreateButton => 'Cancella e crea';

  @override
  String get usbPermissionRequiredToContinue =>
      'È richiesta l\'autorizzazione USB per continuare';

  @override
  String get usbContainerCreatedSnack =>
      'Contenitore USB creato. Usa \"Monta unità USB\" per sbloccarlo.';

  @override
  String get usbContainerCreationFailed =>
      'Creazione del contenitore USB non riuscita.';

  @override
  String get usbStandardVolumeSectionHeader => 'Unità USB e volume standard';

  @override
  String get formattingErasesEverythingWarning =>
      'La formattazione cancella tutto ciò che è attualmente presente sull\'unità selezionata.';

  @override
  String get selectUsbDriveLabel => 'Seleziona unità USB';

  @override
  String get noUsbStorageDetected => 'Nessuna archiviazione USB rilevata';

  @override
  String get connectOtgDriveToFormat => 'Collega un\'unità OTG da formattare';

  @override
  String get refreshListButton => 'Aggiorna elenco';

  @override
  String get readyToFormat => 'Pronto per la formattazione';

  @override
  String get permissionRequired => 'Autorizzazione richiesta';

  @override
  String get readingDriveCapacity => 'Lettura capacità unità…';

  @override
  String get mustNotExceedDriveCapacity =>
      'Non deve superare la capacità effettiva dell\'unità.';

  @override
  String get quickFormatTitle => 'Formattazione rapida';

  @override
  String get quickFormatDescription =>
      'Salta l\'azzeramento dell\'unità. Più veloce, ma non cancella in modo sicuro i dati precedenti.';

  @override
  String get eraseAndCreateContainerButton => 'Cancella e crea contenitore';

  @override
  String get usbContainerCreationInProgressWait =>
      'Creazione del contenitore in corso. Attendere.';

  @override
  String get formatUsbDriveScreenTitle => 'Formatta unità USB';

  @override
  String get playlistTransitionAnimationLabel =>
      'Animazione transizione playlist';

  @override
  String get playlistTransitionSlideLabel => 'Scorrimento (predefinito)';

  @override
  String get playlistTransitionFadeLabel => 'Dissolvenza';

  @override
  String get playlistTransitionZoomLabel => 'Zoom e scala';

  @override
  String get playlistTransitionDepthLabel => 'Pila in profondità';

  @override
  String get playlistTransitionCubeLabel => 'Cubo 3D';

  @override
  String get playlistTransitionFlipLabel => 'Capovolgimento 3D';

  @override
  String get unlockVaultTitle => 'Sblocca vault';

  @override
  String get openContainerTitle => 'Apri contenitore';

  @override
  String get selectContainerFileOrFolder => 'Seleziona file o cartella';

  @override
  String get readOnlyModeLabel => 'Modalità sola lettura';

  @override
  String get readOnlyModeSubtitle =>
      'Impedisce qualsiasi operazione di scrittura o modifica sul vault';

  @override
  String get selectUsbDeviceLabel => 'Seleziona dispositivo USB';

  @override
  String get noUsbDevicesFound =>
      'Nessun dispositivo di archiviazione USB compatibile trovato';

  @override
  String get containerConfigTitle => 'Configurazione vault';

  @override
  String get changePasswordTitle => 'Cambia password';

  @override
  String get confirmNewPasswordLabel => 'Conferma nuova password';

  @override
  String get cameraCaptureTitle => 'Fotocamera vault';

  @override
  String get takingPhoto => 'Acquisizione foto…';

  @override
  String get savingToVault => 'Salvataggio nel vault…';

  @override
  String get noVaultSelected => 'Nessun vault selezionato';

  @override
  String get mediaDiagnosticsTitle => 'Diagnostica multimediale';

  @override
  String get advancedViewerSettingsTitle => 'Impostazioni visualizzatore';

  @override
  String get textEditorSaveConfirmTitle => 'Modifiche non salvate';

  @override
  String get textEditorSaveConfirmMessage =>
      'Vuoi salvare le modifiche prima di chiudere?';

  @override
  String get saveAndClose => 'Salva e chiudi';

  @override
  String get discardChanges => 'Annulla modifiche';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi selezionati',
      one: '1 elemento selezionato',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'Seleziona tutto';

  @override
  String get deselectAll => 'Deseleziona tutto';

  @override
  String get sortOptionsTitle => 'Ordina file';

  @override
  String get layoutModeList => 'Vista elenco';

  @override
  String get layoutModeGrid => 'Vista griglia';

  @override
  String get layoutModeMasonry => 'Mosaico';

  @override
  String get fileOperationsTitle => 'Operazioni sui file';

  @override
  String get conflictResolutionTitle => 'Conflitto file';

  @override
  String get replaceExistingFile => 'Sostituisci il file esistente';

  @override
  String get keepBothFiles => 'Mantieni entrambi (rinomina il nuovo file)';

  @override
  String get skipFile => 'Salta questo file';

  @override
  String get noVaultsFoundTitle => 'Nessun vault trovato';

  @override
  String get noVaultsFoundSubtitle =>
      'Crea un nuovo contenitore cifrato o aggiungi un vault esistente per iniziare.';

  @override
  String get addExistingVaultButton => 'Aggiungi vault esistente';

  @override
  String get sortContainersModeManual => 'Manuale (trascina per riordinare)';

  @override
  String get sortContainersModeUnlockStatus =>
      'Stato di sblocco (sbloccati per primi)';

  @override
  String get sortContainersModeNameAZ => 'Nome (A–Z)';

  @override
  String get sortContainersModeNameZA => 'Nome (Z–A)';

  @override
  String get sortContainersModeNewest => 'Più recenti per primi';

  @override
  String get sortContainersModeOldest => 'Meno recenti per primi';

  @override
  String get thumbnailCacheAppCacheLabel => 'Cache dell\'app';

  @override
  String get thumbnailCacheAppCacheDesc =>
      'Memorizzata cifrata nella cache dell\'app. Veloce; viene cancellata automaticamente in caso di scarsità di spazio.';

  @override
  String get thumbnailCacheInContainerLabel => 'Nel contenitore';

  @override
  String get thumbnailCacheInContainerDesc =>
      'Memorizzata all\'interno del contenitore cifrato. Protetta dal contenitore stesso, ma la scrittura è più lenta.';

  @override
  String get thumbnailCacheDisabledLabel => 'Disattivata';

  @override
  String get thumbnailCacheDisabledDesc =>
      'Nessuna cache su disco. Le miniature vengono rigenerate a ogni caricamento.';

  @override
  String get unlockContainerTitle => 'Sblocca contenitore';

  @override
  String get containerFileSegment => 'File contenitore';

  @override
  String get folderVaultSegment => 'Vault a cartella';

  @override
  String get enableButtonLabel => 'Attiva';

  @override
  String get retryButtonLabelShort => 'Riprova';

  @override
  String get locateFileButton => 'Individua file';

  @override
  String get authenticateButton => 'Autentica';

  @override
  String get cancelUnlockButton => 'Annulla sblocco';

  @override
  String tryingKeyslotProgress(int attempted, int total) {
    return 'Tentativo dello slot chiave $attempted di $total…';
  }

  @override
  String get tryingKeyslotSingle => 'Tentativo dello slot chiave…';

  @override
  String verifyingCredentialProgress(int attempted, int total) {
    return 'Verifica della credenziale $attempted di $total…';
  }

  @override
  String get verifyingCredentialSingle => 'Verifica della credenziale…';

  @override
  String tryingAlgoSlot(String algo, String slotName) {
    return 'Tentativo con $algo ($slotName)…';
  }

  @override
  String get hiddenVolumeSlotName => 'Volume nascosto';

  @override
  String get standardVolumeSlotName => 'Volume standard';

  @override
  String get containerMissingSubtitle =>
      'Impossibile risolvere il percorso del file';

  @override
  String get containerMissingBody =>
      'Il file contenitore potrebbe essere stato spostato, eliminato, oppure la sua unità di archiviazione host è attualmente disconnessa.';

  @override
  String get connectPatternSequence => 'Collega la sequenza del tuo schema';

  @override
  String get passwordLabel => 'Password';

  @override
  String get enterVaultPasswordHint => 'Inserisci la password del vault';

  @override
  String get enterBitlockerPasswordHint =>
      'Inserisci la password o la chiave di recupero';

  @override
  String get enterContainerPasswordHint =>
      'Inserisci la password del contenitore';

  @override
  String get readOnlyModeUsbSubtitleDrive =>
      'Monta senza consentire modifiche a questa unità';

  @override
  String get rememberDriveLabel => 'Ricorda unità';

  @override
  String get rememberDriveSubtitle =>
      'Fissa l\'unità sulla dashboard per un accesso rapido';

  @override
  String get unlockVaultButtonLabel => 'Sblocca vault';

  @override
  String get cryfsStorageAccessWarning =>
      'I vault CryFS utilizzano migliaia di piccoli file a blocchi. Senza l\'accesso diretto all\'archiviazione, le prestazioni saranno molto più lente.';

  @override
  String get folderVaultStorageAccessWarning =>
      'L\'accesso diretto all\'archiviazione è disattivato. L\'apertura e la lettura dei file nei vault a cartella potrebbero essere più lente.';

  @override
  String get requestingPermission => 'Richiesta autorizzazione…';

  @override
  String get unlockAndMountButton => 'Sblocca e monta';

  @override
  String get unlockDriveButton => 'Sblocca unità';

  @override
  String couldntFindDevice(String deviceName) {
    return 'Impossibile trovare \"$deviceName\"';
  }

  @override
  String get plugDriveBackInRetry =>
      'Ricollega l\'unità e tocca Riprova, oppure selezionala di seguito se compare con un nome diverso.';

  @override
  String get retryConnectionButton => 'Riprova connessione';

  @override
  String get refreshDevicesButton => 'Aggiorna dispositivi';

  @override
  String get connectOtgDriveToMount => 'Collega un\'unità flash OTG da montare';

  @override
  String get alreadyActive => 'Già attivo';

  @override
  String get active => 'Attivo';

  @override
  String get readyToUnlock => 'Pronto per lo sblocco';

  @override
  String get enterUsbPartitionPassword =>
      'Inserisci la password della partizione USB';

  @override
  String get biometricAuthenticationTitle => 'Autenticazione biometrica';

  @override
  String get biometricAuthUsbSubtitle =>
      'Autenticati per sbloccare e montare questo dispositivo USB';

  @override
  String get connectPatternSequenceToMount =>
      'Collega la sequenza del tuo schema per montare';

  @override
  String get selectAllAction => 'Seleziona tutto';

  @override
  String get clearSelectionAction => 'Cancella selezione';

  @override
  String get clearSelectionTooltip => 'Cancella selezione';

  @override
  String get selectionOptionsTooltip => 'Opzioni di selezione';

  @override
  String get readOnlyContainerTooltip => 'Contenitore in sola lettura';

  @override
  String get copyAction => 'Copia';

  @override
  String get moveAction => 'Sposta';

  @override
  String get renameAction => 'Rinomina';

  @override
  String get exportToDeviceAction => 'Esporta sul dispositivo';

  @override
  String get openWithAppAction => 'Apri con app';

  @override
  String get pinAction => 'Fissa';

  @override
  String get pinSelectedAction => 'Fissa selezionati';

  @override
  String get unpinAction => 'Rimuovi dai fissati';

  @override
  String get unpinSelectedAction => 'Rimuovi selezionati dai fissati';

  @override
  String get documentProviderSettingsMenu => 'Impostazioni provider documenti';

  @override
  String get exposeAsDocumentProviderMenu => 'Esponi come provider documenti';

  @override
  String get moreOptionsTooltipShort => 'Altre opzioni';

  @override
  String get copyTooltip => 'Copia';

  @override
  String get searchInThisFolderHint => 'Cerca in questa cartella…';

  @override
  String get clearTooltip => 'Cancella';

  @override
  String get backToDashboardTooltip => 'Torna alla dashboard';

  @override
  String get cancelPasteButton => 'Annulla incolla';

  @override
  String get cancelImportButton => 'Annulla importazione';

  @override
  String get continueButton => 'Continua';

  @override
  String get skipButton => 'Salta';

  @override
  String get keepBothButton => 'Mantieni entrambi';

  @override
  String get clearAllButton => 'Cancella tutto';

  @override
  String get autoMountWhenUnlocksTitle =>
      'Monta automaticamente allo sblocco del contenitore';

  @override
  String get autoMountWhenUnlocksSubtitle =>
      'Esponi di nuovo automaticamente questa cartella la prossima volta';

  @override
  String get unmountButton => 'Smonta';

  @override
  String get filtersMenuItem => 'Filtri';

  @override
  String get settingsMenuItem => 'Impostazioni';

  @override
  String get sortOptionsTooltip => 'Opzioni di ordinamento';

  @override
  String get layoutOptionsTooltip => 'Opzioni di layout';

  @override
  String get lockContainerTooltip => 'Blocca contenitore';

  @override
  String get renameTooltip => 'Rinomina';

  @override
  String get cancelUpdatingPasswordTooltip => 'Annulla aggiornamento password';

  @override
  String get unlockSettingsButton => 'Sblocca impostazioni';

  @override
  String get updateSavedCredentialsButton => 'Aggiorna credenziali salvate';

  @override
  String get verifyCredentialsTitle => 'Verifica credenziali';

  @override
  String get verifyButton => 'Verifica';

  @override
  String get displayNameTitle => 'Nome visualizzato';

  @override
  String get containerNameHint => 'Nome contenitore';

  @override
  String get deleteFileDialogTitle => 'Eliminare il file?';

  @override
  String get deleteFilePermanentWarning =>
      'Questa azione è permanente e non può essere annullata.';

  @override
  String get unsavedChangesTitle => 'Modifiche non salvate';

  @override
  String get unsavedChangesMessage =>
      'Hai modifiche non salvate. Vuoi salvarle prima di chiudere?';

  @override
  String get discardButton => 'Annulla modifiche';

  @override
  String get decryptingFileContent => 'Decifratura del contenuto del file...';

  @override
  String get cannotOpenFile => 'Impossibile aprire il file';

  @override
  String get changesSavedSuccessfully => 'Modifiche salvate con successo';

  @override
  String saveFailedWithError(String error) {
    return 'Salvataggio non riuscito: $error';
  }

  @override
  String linesCount(int count) {
    return 'Righe: $count';
  }

  @override
  String charsCount(int count) {
    return 'Caratteri: $count';
  }

  @override
  String get unsavedChangesLabel => 'Modifiche non salvate';

  @override
  String get savedToVault => 'Salvato nel vault';

  @override
  String get saveChangesTooltip => 'Salva modifiche';

  @override
  String get textEditorDecryptFailedMessage =>
      'Impossibile decifrare il file dal vault.';

  @override
  String get textEditorInvalidTextFileMessage =>
      'Il file non sembra essere un file di testo valido.';

  @override
  String get textEditorWriteBackFailedMessage =>
      'Impossibile riscrivere il file nel vault.';

  @override
  String get backTooltip => 'Indietro';

  @override
  String get forwardTooltip => 'Avanti';

  @override
  String get reloadTooltip => 'Ricarica';

  @override
  String get optionsTooltip => 'Opzioni';

  @override
  String get htmlViewerErrorTitle => 'Impossibile visualizzare questa pagina';

  @override
  String get htmlViewerLoadFailedMessage => 'Caricamento del file non riuscito';

  @override
  String get enableJavaScriptDialogTitle => 'Attivare JavaScript?';

  @override
  String get enableJavaScriptDialogMessage =>
      'Alla pagina sarà consentito eseguire i propri script locali. Non ha comunque accesso alla rete — nulla in questo vault può essere inviato o ricevuto tramite Internet.';

  @override
  String get disableJavaScriptMenu => 'Disattiva JavaScript';

  @override
  String get enableJavaScriptMenu => 'Attiva JavaScript';

  @override
  String get enterFullscreenMenu => 'Attiva schermo intero';

  @override
  String failedToOpenExternalApp(String error) {
    return 'Impossibile aprire nell\'app esterna: $error';
  }

  @override
  String get thisFolderMenu => 'Questa cartella';

  @override
  String get allInclSubfoldersMenu => 'Tutto (incluse sottocartelle)';

  @override
  String get disableShuffleMenu => 'Disattiva riproduzione casuale';

  @override
  String get shufflePlaylistMenu => 'Riproduzione casuale playlist';

  @override
  String get playlistOptionsTooltip => 'Opzioni playlist';

  @override
  String get enablePlaylistTooltip => 'Attiva playlist';

  @override
  String get moreActionsTooltip => 'Altre azioni';

  @override
  String get forcePortraitMenu => 'Forza verticale';

  @override
  String get forceLandscapeMenu => 'Forza orizzontale';

  @override
  String get autoRotateSensorMenu => 'Rotazione automatica (sensore)';

  @override
  String get screenOrientationMenu => 'Orientamento schermo';

  @override
  String get playlistTransitionMenu => 'Transizione playlist';

  @override
  String get renameFileMenu => 'Rinomina file';

  @override
  String get deleteFileMenu => 'Elimina file';

  @override
  String get thumbnailCarouselTooltip => 'Carosello miniature';

  @override
  String get advancedSettingsTooltip => 'Impostazioni avanzate';

  @override
  String get previousTooltip => 'Precedente';

  @override
  String get nextTooltip => 'Successivo';

  @override
  String get diagnosticsCopiedToClipboard =>
      'Diagnostica copiata negli appunti';

  @override
  String get diagnosticsTitle => 'Diagnostica';

  @override
  String get copyDiagnosticsTooltip => 'Copia diagnostica';

  @override
  String get closeTooltip => 'Chiudi';

  @override
  String get diagnosticsPlaybackSection => 'Riproduzione';

  @override
  String get diagnosticsEngineSection => 'Motore';

  @override
  String get diagnosticsStateLabel => 'Stato';

  @override
  String get diagnosticsResolutionLabel => 'Risoluzione';

  @override
  String get diagnosticsAspectRatioLabel => 'Proporzioni';

  @override
  String get diagnosticsPositionLabel => 'Posizione';

  @override
  String get diagnosticsDurationLabel => 'Durata';

  @override
  String get diagnosticsErrorLabel => 'Errore';

  @override
  String get diagnosticsPlayerLabel => 'Player';

  @override
  String get diagnosticsDecodingLabel => 'Decodifica';

  @override
  String get diagnosticsExoPlayerValue => 'ExoPlayer (Android)';

  @override
  String get diagnosticsHardwareAcceleratedValue => 'Accelerata via hardware';

  @override
  String get diagnosticsUnknownValue => 'Sconosciuto';

  @override
  String get diagnosticsStateBuffering => 'Buffering';

  @override
  String get diagnosticsStatePlaying => 'In riproduzione';

  @override
  String get diagnosticsStatePaused => 'In pausa';

  @override
  String get diagnosticsDurationUnavailable => '--:--';

  @override
  String get rotate90Label => 'Ruota di 90°';

  @override
  String get imageFitModeLabel => 'Modalità adattamento immagine';

  @override
  String get slideshowDelayLabel => 'Ritardo presentazione';

  @override
  String get playbackSpeedLabel => 'Velocità di riproduzione';

  @override
  String get subtitlesLabel => 'Sottotitoli';

  @override
  String get imageSettingsTitle => 'Impostazioni immagine';

  @override
  String get playbackSettingsTitle => 'Impostazioni di riproduzione';

  @override
  String get imageFitContain => 'Contieni';

  @override
  String get imageFitWidth => 'Adatta larghezza';

  @override
  String get imageFitHeight => 'Adatta altezza';

  @override
  String nSecondsDelay(int n) {
    return '$n secondi';
  }

  @override
  String playbackSpeedNormal(String speed) {
    return '${speed}x (normale)';
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
  String get settingsTooltipShort => 'Impostazioni';

  @override
  String get sourceCodeTooltip => 'Codice sorgente';

  @override
  String get donateTooltip => 'Dona';

  @override
  String get shareAppTooltip => 'Condividi app';

  @override
  String get resetToDefaultsTooltip => 'Ripristina impostazioni predefinite';

  @override
  String get usbUnlockContainerTitle => 'Sblocca contenitore USB';

  @override
  String get usbMountContainerTitle => 'Monta unità USB';

  @override
  String get staticLabel => 'Statico';

  @override
  String get unmuteTooltip => 'Riattiva audio';

  @override
  String get muteTooltip => 'Disattiva audio';

  @override
  String get playOnceDisabledTooltip =>
      'Riproduci una volta (avanzamento automatico disattivato)';

  @override
  String get playAndAdvanceTooltip => 'Riproduci e avanza al successivo';

  @override
  String get loopCurrentVideoTooltip => 'Ripeti video corrente';

  @override
  String get clearThumbnailCacheDialogTitle =>
      'Cancellare la cache delle miniature?';

  @override
  String get clearThumbnailCacheDialogMessage =>
      'Questo eliminerà le miniature memorizzate per questo vault. Verranno rigenerate la prossima volta che sfoglierai i contenuti multimediali.';

  @override
  String get clearCacheButton => 'Cancella cache';

  @override
  String get appCacheClearedUnlockMessage =>
      'Cache dell\'app cancellata. Sblocca il contenitore per cancellare la cache interna.';

  @override
  String get allThumbnailCachesClearedMessage =>
      'Tutte le cache delle miniature sono state cancellate con successo.';

  @override
  String get appCacheClearedContainerFailedMessage =>
      'Cache dell\'app cancellata, ma non è stato possibile cancellare quella interna al contenitore.';

  @override
  String get failedToClearThumbnailCachesMessage =>
      'Impossibile cancellare le cache delle miniature.';

  @override
  String get authenticateToModifySettingsPrompt =>
      'Autenticati per modificare le impostazioni';

  @override
  String get usbVaultSettingsTitle => 'Impostazioni vault USB';

  @override
  String get vaultSettingsTitle => 'Impostazioni vault';

  @override
  String get generalSectionHeader => 'Generale';

  @override
  String get securityCredentialsSectionHeader => 'Sicurezza e credenziali';

  @override
  String get securityOptionsLockedTitle => 'Opzioni di sicurezza bloccate';

  @override
  String get authenticateOriginalCredentialsMessage =>
      'Autenticati con le credenziali originali del contenitore per modificare le impostazioni di sicurezza.';

  @override
  String get unlockCredentialsLabel => 'Credenziali di sblocco';

  @override
  String get unavailableSuffixLabel => '(Non disponibile)';

  @override
  String get patternSetupRequiredBeforeSaving =>
      'Configura uno schema prima di salvare.';

  @override
  String get passwordKeystoreEncryptedHelperText =>
      'La password è cifrata usando l\'Android Keystore. Lascia vuoto se usi solo file chiave.';

  @override
  String get changePatternButton => 'Cambia schema';

  @override
  String get setPatternButton => 'Imposta schema';

  @override
  String get cacheDerivedKeyLabel => 'Memorizza nella cache la chiave derivata';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      'Salta il KDF scrypt di CryFS la prossima volta (chiave mantenuta nell\'Android Keystore)';

  @override
  String get reuseKeyMaterialKeystoreSubtitle =>
      'Riutilizza il materiale della chiave nell\'Android Keystore';

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle =>
      'Fissa l\'algoritmo per saltare il rilevamento automatico allo sblocco.';

  @override
  String get changeContainerPasswordTitle => 'Cambia password del contenitore';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      'Le credenziali BitLocker non possono essere modificate nell\'app. Usa \"Gestisci BitLocker\" su Windows.';

  @override
  String get systemIntegrationSectionHeader => 'Sistema e integrazione';

  @override
  String get autoLockDurationLabel => 'Durata blocco automatico';

  @override
  String get neverAutoLockOption => 'Mai';

  @override
  String get exposeContentToFilePickerSubtitle =>
      'Esponi i contenuti al selettore file di sistema quando sbloccato';

  @override
  String get thumbnailStorageSectionHeader => 'Archiviazione miniature';

  @override
  String get cacheModeLabel => 'Modalità cache';

  @override
  String get useGlobalDefaultSubtitle => 'Usa impostazione globale predefinita';

  @override
  String get thumbnailQualityLabel => 'Qualità miniature';

  @override
  String get clearThumbnailCacheTitle => 'Cancella cache miniature';

  @override
  String get removeCachedThumbnailsSubtitle =>
      'Rimuove le miniature di immagini e video memorizzate';

  @override
  String get vaultInformationSectionHeader => 'Informazioni sul vault';

  @override
  String get vaultInformationTileTitle => 'Visualizza dettagli del vault';

  @override
  String get vaultInformationTileSubtitle =>
      'Cifratura, formato e altri dettagli tecnici';

  @override
  String get vaultInfoLocationLabel => 'Posizione';

  @override
  String get vaultInfoRequiresUnlockTitle => 'Sblocco necessario';

  @override
  String get vaultInfoRequiresUnlockMessage =>
      'Sblocca questo vault per visualizzarne i dettagli tecnici.';

  @override
  String get vaultInfoLoadFailedTitle =>
      'Impossibile caricare le informazioni sul vault';

  @override
  String get vaultInfoLoadFailedMessage =>
      'Si è verificato un errore durante la lettura dei dettagli di questo vault.';

  @override
  String get vaultInfoVolumeSizeLabel => 'Dimensione del volume';

  @override
  String get vaultInfoHiddenVolumeLabel => 'Volume nascosto';

  @override
  String get vaultInfoReadOnlyLabel => 'Sola lettura';

  @override
  String get vaultInfoLuksVersionLabel => 'Versione LUKS';

  @override
  String get vaultInfoSectorSizeLabel => 'Dimensione settore';

  @override
  String get vaultInfoVaultFormatLabel => 'Formato del vault';

  @override
  String get vaultInfoCipherComboLabel => 'Combinazione di cifratura';

  @override
  String get vaultInfoShorteningThresholdLabel =>
      'Soglia di accorciamento nomi file';

  @override
  String get vaultInfoFormatVersionLabel => 'Versione del formato';

  @override
  String get vaultInfoContentCipherLabel => 'Cifratura del contenuto';

  @override
  String get vaultInfoFilenameEncryptionLabel => 'Nomi dei file';

  @override
  String get vaultInfoPlaintextNamesValue => 'In chiaro';

  @override
  String get vaultInfoEncryptedNamesValue => 'Cifrati';

  @override
  String get vaultInfoBlockCipherLabel => 'Cifrario a blocchi';

  @override
  String get vaultInfoBlockSizeLabel => 'Dimensione blocco';

  @override
  String get vaultInfoCreatedWithVersionLabel => 'Creato con';

  @override
  String get vaultInfoLastOpenedWithVersionLabel => 'Ultima apertura con';

  @override
  String get vaultInfoYesValue => 'Sì';

  @override
  String get vaultInfoNoValue => 'No';

  @override
  String get vaultInfoBitlockerNote =>
      'Questa app non analizza i metadati dell\'header proprietario di BitLocker, quindi qui non sono disponibili i dettagli su cifratura e versione.';

  @override
  String get patternSetupRequiredAboveBeforeSaving =>
      'Configura uno schema qui sopra prima di salvare.';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      'Per questo metodo di sblocco è richiesta una password o \"Memorizza chiave derivata\" con file chiave.';

  @override
  String get saveConfigurationButton => 'Salva configurazione';

  @override
  String get incorrectPatternError => 'Schema errato';

  @override
  String get verifyPatternTitle => 'Verifica schema';

  @override
  String get incorrectPasswordError => 'Password errata';

  @override
  String get verificationFailedError => 'Verifica non riuscita';

  @override
  String get incorrectCredentialsError => 'Credenziali errate';

  @override
  String get containerPasswordOptionalLabel =>
      'Password del contenitore (opzionale solo con file chiave)';

  @override
  String get pimOptionalLabel => 'PIM (opzionale)';

  @override
  String get usbDriveLockedLabel => 'Unità USB · Bloccata';

  @override
  String get lockedContainerLabel => 'Contenitore bloccato';

  @override
  String get operationInProgressWaitMessage =>
      'Un\'operazione è in corso. Attendi prima di bloccare.';

  @override
  String get reconnectUsbTooltip => 'Riconnetti USB';

  @override
  String get unlockContainerTooltip => 'Sblocca contenitore';

  @override
  String lockFailedMessage(String errorType) {
    return 'Blocco non riuscito: $errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired =>
      'Sono richiesti una nuova password o dei file chiave.';

  @override
  String get newPasswordsDoNotMatch => 'Le nuove password non corrispondono.';

  @override
  String get passwordChangedSuccessfullyMessage =>
      'Password cambiata con successo.';

  @override
  String get failedToChangePasswordMessage =>
      'Impossibile cambiare la password. Verifica le credenziali precedenti.';

  @override
  String get currentCredentialsSectionHeader => 'Credenziali attuali';

  @override
  String get oldPasswordLabel => 'Vecchia password';

  @override
  String get oldPimOptionalLabel => 'Vecchio PIM (opzionale)';

  @override
  String get newCredentialsSectionHeader => 'Nuove credenziali';

  @override
  String get newPimOptionalLabel => 'Nuovo PIM (opzionale)';

  @override
  String get noContainersYetTitle => 'Ancora nessun contenitore';

  @override
  String get dashboardEmptyStateMessage =>
      'Monta un contenitore VeraCrypt, collega un\'unità USB o crea un nuovo vault cifrato per iniziare.';

  @override
  String get sortFieldName => 'Nome';

  @override
  String get sortFieldSize => 'Dimensione';

  @override
  String get sortFieldType => 'Tipo';

  @override
  String get sortFieldDate => 'Data';

  @override
  String get layoutModeDetailedList => 'Elenco dettagliato';

  @override
  String get layoutModeCompactList => 'Elenco compatto';

  @override
  String get layoutModeGalleryGrid => 'Griglia galleria';

  @override
  String get readOnlyCantDeleteTooltip =>
      'Sola lettura — impossibile eliminare';

  @override
  String get readOnlyCantMoveTooltip => 'Sola lettura — impossibile spostare';

  @override
  String get readOnlyCantRenameTooltip =>
      'Sola lettura — impossibile rinominare';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes (calcolo in corso…)';
  }

  @override
  String get sizeCalculatingLabel => 'calcolo in corso…';

  @override
  String get editSecureItemsToRenameMessage =>
      'Modifica gli elementi sicuri per rinominarli';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage =>
      'Gli elementi del vault non possono essere aperti in app esterne';

  @override
  String get mountedReadOnlyTooltip => 'Montato in sola lettura';

  @override
  String get readOnlyBadgeAbbreviation => 'SL';

  @override
  String freeSpaceLabel(String bytes) {
    return '$bytes liberi';
  }

  @override
  String get filteredLabel => 'filtrato';

  @override
  String get statsStorageSectionHeader => 'ARCHIVIAZIONE';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cartelle',
      one: '1 cartella',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count file',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => 'Tutti i file';

  @override
  String get filterImagesOption => 'Immagini';

  @override
  String get filterVideosOption => 'Video';

  @override
  String get filterAudioOption => 'Audio';

  @override
  String get filterDocumentsOption => 'Documenti';

  @override
  String get folderExposedAsStorageExplanation =>
      'Questa cartella è esposta come propria unità di archiviazione, così altre app possono sfogliare e aprire direttamente i suoi file.';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi esistono già',
      one: '1 elemento esiste già',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle =>
      'Scegli cosa fare per ogni elemento, oppure applica una scelta a tutti.';

  @override
  String get skipAllChipLabel => 'Salta tutti';

  @override
  String get overwriteAllChipLabel => 'Sovrascrivi tutti';

  @override
  String get overwriteItemDropdownLabel => 'Sovrascrivi';

  @override
  String get overwriteFolderDropdownLabel => 'Sovrascrivi cartella';

  @override
  String get fileOpsTransfersInProgressTitle => 'Trasferimenti in corso';

  @override
  String get fileOpsRecentTransfersTitle => 'Trasferimenti recenti';

  @override
  String get fileOpsNoRecentTransfersMessage => 'Nessun trasferimento recente';

  @override
  String get fileOpsNoRecentTransfersSubtitle =>
      'Copie, spostamenti ed eliminazioni appariranno qui durante l\'esecuzione.';

  @override
  String fileOpsShowDetailsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get fileOpsCancelTooltip => 'Annulla';

  @override
  String get fileOpsRootDestinationLabel => 'Radice';

  @override
  String get fileOpsCancelledStatusLabel => 'Annullato';

  @override
  String fileOpsItemsFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items failed:',
      one: '1 item failed:',
    );
    return '$_temp0';
  }

  @override
  String fileOpsMoreItemsLabel(num count) {
    return '+ altri $count';
  }

  @override
  String get transferActivityTooltip => 'Trasferimenti';

  @override
  String fileOpsSpeedLabel(String speed) {
    return '$speed/s';
  }

  @override
  String fileOpsEtaLabel(String time) {
    return '~$time rimanente';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return 'Errore nella lettura del file: $error';
  }

  @override
  String get archivePreviewNotAvailableMessage =>
      'Anteprima non disponibile per questo tipo di file.';

  @override
  String get avifFailedToRenderMessage =>
      'Impossibile visualizzare il file AVIF';

  @override
  String get encryptedImageLoadFailedMessage =>
      'Impossibile caricare l\'immagine cifrata';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return 'Impossibile caricare l\'immagine cifrata: $error';
  }

  @override
  String get invalidOrCorruptedImageMessage =>
      'Formato immagine non valido o danneggiato.';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '$current di $total';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '$current di $total  ·  scansione…';
  }

  @override
  String get mediaViewerScanningLabel => 'Scansione…';

  @override
  String get mediaFileDeletedMessage => 'File eliminato con successo';

  @override
  String get mediaFileDeleteFailedMessage => 'Impossibile eliminare il file';

  @override
  String get mediaFileRenamedMessage => 'File rinominato con successo';

  @override
  String get aboutScreenTitle => 'Informazioni';

  @override
  String get couldNotOpenLinkMessage => 'Impossibile aprire il link';

  @override
  String get fileManagerSettingsTitle => 'Impostazioni file manager';

  @override
  String get showMediaThumbnailsLabel => 'Mostra miniature multimediali';

  @override
  String get showMediaThumbnailsDesc =>
      'Mostra anteprime in miniatura per immagini e video nella vista elenco';

  @override
  String get showFileNamesLabel => 'Mostra nomi file';

  @override
  String get showFileNamesDesc =>
      'Mostra etichette di testo sotto gli elementi nella vista a griglia';

  @override
  String get showBreadcrumbBarLabel => 'Mostra barra breadcrumb';

  @override
  String get showBreadcrumbBarDesc =>
      'Barra di navigazione del percorso in cima al browser';

  @override
  String get showStatsBarLabel => 'Mostra barra statistiche';

  @override
  String get showStatsBarDesc => 'Banner con numero di file e spazio libero';

  @override
  String get autoStartPlaylistModeLabel =>
      'Avvia automaticamente la modalità playlist';

  @override
  String get autoStartPlaylistModeDesc =>
      'Avvia automaticamente in modalità playlist quando apri un elemento multimediale';

  @override
  String get showPlaylistCarouselLabel => 'Mostra carosello playlist';

  @override
  String get showPlaylistCarouselDesc =>
      'Mostra il pulsante del carosello miniature durante la visualizzazione di playlist multimediali';

  @override
  String get videoPlaybackSliderLabel =>
      'Cursore di posizione riproduzione video';

  @override
  String get longPressPlaybackDiagnosticsHint =>
      'Tieni premuto per la diagnostica di riproduzione';

  @override
  String get staticImageModeLabel => 'Modalità immagine statica';

  @override
  String slideshowModeActiveLabel(int seconds) {
    return 'Modalità presentazione attiva con $seconds secondi di ritardo';
  }

  @override
  String videoPlaybackModeLabel(String mode) {
    return 'Modalità riproduzione video: $mode';
  }

  @override
  String get pauseLabel => 'Pausa';

  @override
  String get playLabel => 'Riproduci';

  @override
  String get emptyFolderTitle => 'Cartella vuota';

  @override
  String get emptyFolderMessage =>
      'Usa l\'azione Aggiungi per creare file o importarli dal dispositivo.';

  @override
  String get noResultsTitle => 'Nessun risultato';

  @override
  String noResultsForQueryMessage(String query) {
    return 'Niente in questa cartella corrisponde a \"$query\".';
  }

  @override
  String get closeCarouselTooltip => 'Chiudi carosello';

  @override
  String get playlistScrollModeMenu => 'Modalità scorrimento playlist';

  @override
  String get playlistScrollHorizontalLabel => 'Orizzontale';

  @override
  String get playlistScrollVerticalPageLabel => 'Verticale a pagine';

  @override
  String get playlistScrollVerticalContinuousLabel => 'Verticale continuo';

  @override
  String get undoTooltip => 'Annulla';

  @override
  String get redoTooltip => 'Ripeti';

  @override
  String get autosavingLabel => 'Salvataggio automatico…';

  @override
  String get savingLabel => 'Salvataggio…';

  @override
  String autosavedAtLabel(String time) {
    return 'Salvato automaticamente alle $time';
  }

  @override
  String cameraDisconnectedError(String message) {
    return 'Fotocamera disconnessa: $message';
  }

  @override
  String get unknownErrorFallback => 'errore sconosciuto';

  @override
  String get cameraPermissionsRequiredMessage =>
      'Sono richieste le autorizzazioni per fotocamera e microfono per usare la fotocamera.';

  @override
  String cameraErrorMessage(String error) {
    return 'Errore fotocamera: $error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage =>
      'Acquisizione della foto non riuscita';

  @override
  String get cameraRecordingFailedMessage => 'Registrazione non riuscita';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return 'Registrazione non riuscita: $error';
  }

  @override
  String get cameraRecordingTooShortMessage =>
      'La registrazione era troppo breve per essere salvata';

  @override
  String get cameraCouldNotSaveRecordingMessage =>
      'Impossibile salvare la registrazione';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return 'Impossibile salvare la registrazione: $error';
  }

  @override
  String get cameraCouldNotSwitchLensMessage =>
      'Impossibile cambiare obiettivo';

  @override
  String get cameraEncryptingPhotoLabel => 'Cifratura foto…';

  @override
  String get cameraEncryptingVideoLabel => 'Cifratura video…';

  @override
  String get aboutApplicationSectionHeader => 'Applicazione';

  @override
  String get aboutTagline => 'Gratis · Open source · Vault cifrato offline';

  @override
  String get aboutVersionTitle => 'Versione';

  @override
  String aboutVersionSubtitle(String version) {
    return 'v$version · Tocca per copiare le informazioni sulla versione per le segnalazioni di bug';
  }

  @override
  String get aboutWhatsNewTitle => 'Novità';

  @override
  String get aboutWhatsNewSubtitle =>
      'Vedi le modifiche recenti e le note di rilascio';

  @override
  String get aboutPrivacySecurityTitle => 'Privacy e sicurezza';

  @override
  String get aboutPrivacySecuritySubtitle =>
      'Nessun accesso alla rete, nulla di non cifrato viene mai scritto su disco';

  @override
  String get aboutSupportedFormatsSectionHeader => 'Formati supportati';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt e LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      'Volumi standard e nascosti, PIM personalizzato, file chiave, xts-plain64, Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker e BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle =>
      'Supporto per passphrase utente e chiave di recupero numerica a 48 cifre';

  @override
  String get aboutDirectoryVaultsTitle => 'Vault a cartella';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator (v7/v8 SIV_GCM e SIV_CTRMAC), gocryptfs (v2 AES-GCM e XChaCha20), CryFS (v0.10+ XChaCha20 e AES)';

  @override
  String get aboutVhdTitle => 'Dischi rigidi virtuali (VHD / VHDX)';

  @override
  String get aboutVhdSubtitle =>
      'Traduzione BAT per immagini disco fisse ed espandibili dinamiche';

  @override
  String get aboutNativeCoreEngineSectionHeader => 'Motore nativo';

  @override
  String get aboutCompiledLibrariesTitle => 'Librerie C++ compilate';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.0 (crittografia hardware ARMv8 e SHA-2)\n• libavif e libgav1 (decodificatore immagini AVIF nativo)\n• ChaN FatFs v4.0.4 (FAT12/16/32 ed exFAT)\n• Tuxera NTFS-3G e mkntfs integrato\n• e2fsprogs v1.47.4 libext2fs (ext2/ext3/ext4)\n• Dislocker Virtual I/O (BitLocker FVE / To Go)\n• VeraCrypt 1.26.29 (Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id/i)\n• cJSON v1.7.18 (metadati LUKS2 e Cryptomator)';

  @override
  String get aboutCommunitySectionHeader => 'Community e open source';

  @override
  String get aboutReportIssueTitle => 'Segnala un problema';

  @override
  String get aboutReportIssueSubtitle =>
      'Hai trovato un bug? Invia una segnalazione su GitHub';

  @override
  String get reportIssueSheetTitle => 'Report an Issue';

  @override
  String get reportIssueSheetSubtitle =>
      'Pick the option that best matches your issue — it opens a pre-filled GitHub form';

  @override
  String get reportIssueBugTitle => 'Bug Report';

  @override
  String get reportIssueBugSubtitle =>
      'Something crashed or isn\'t working right';

  @override
  String get reportIssueContainerTitle => 'Container / Vault Problem';

  @override
  String get reportIssueContainerSubtitle =>
      'Unlock, mount, or format-specific issue';

  @override
  String get reportIssueFeatureTitle => 'Feature Request';

  @override
  String get reportIssueFeatureSubtitle => 'Suggest an idea or improvement';

  @override
  String get reportIssueOtherTitle => 'Something Else';

  @override
  String get reportIssueOtherSubtitle => 'Browse all templates on GitHub';

  @override
  String get aboutContributorsTitle => 'Collaboratori';

  @override
  String get aboutContributorsSubtitle =>
      'Le persone che hanno contribuito a realizzare VaultExplorer';

  @override
  String get aboutLicensesTitle => 'Licenze open source';

  @override
  String get aboutLicensesSubtitle =>
      'Librerie di terze parti usate in questa app';

  @override
  String get aboutFooterMadeWithLove => 'Realizzato con ❤ per la privacy.';

  @override
  String get aboutVersionCopiedMessage =>
      'Informazioni sulla versione copiate — utili per le segnalazioni di bug';

  @override
  String aboutVersionClipboardText(String version) {
    return 'VaultExplorer v$version (Android)';
  }

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer — un vault gratuito, open source e offline per Android.\n\nMemorizza password, note e file all\'interno di un contenitore cifrato (VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs, CryFS).\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage =>
      'Link condivisibile copiato negli appunti';

  @override
  String get aboutPrivacySheetTitle => 'Privacy e sicurezza dei dati';

  @override
  String get aboutPrivacySheetSubtitle =>
      'Design di sicurezza al 100% offline, in memoria locale';

  @override
  String get privacyPointNoNetworkTitle => 'Nessun accesso alla rete richiesto';

  @override
  String get privacyPointNoNetworkBody =>
      'VaultExplorer non richiede l\'autorizzazione android.permission.INTERNET su Android. Non può comunicare tramite alcuna rete.';

  @override
  String get privacyPointNoDiskLeaksTitle =>
      'Zero fughe di dati non cifrati su disco';

  @override
  String get privacyPointNoDiskLeaksBody =>
      'La decifratura e la ricifratura avvengono interamente nella memoria di sistema. I file temporanei non cifrati non vengono mai salvati nell\'archiviazione del dispositivo.';

  @override
  String get privacyPointNoAnalyticsTitle => 'Nessuna analisi o telemetria';

  @override
  String get privacyPointNoAnalyticsBody =>
      'Non c\'è alcuna segnalazione di arresti anomali, tracciamento dell\'utilizzo o SDK di terze parti che raccoglie dati su di te o sul tuo dispositivo.';

  @override
  String get privacyPointKeystoreTitle =>
      'I segreti restano nell\'Android Keystore';

  @override
  String get privacyPointKeystoreBody =>
      'Password memorizzate, schemi e chiavi derivate nella cache sono sigillati con AES-256-GCM nell\'Android Keystore basato su hardware.';

  @override
  String get privacyPointPosixTitle =>
      'Accelerazione POSIX e accesso all\'archiviazione';

  @override
  String get privacyPointPosixBody =>
      'I file all\'interno dei vault a cartella vengono letti e scritti direttamente quando possibile, bypassando il più lento livello SAF di Android per le cartelle di grandi dimensioni.';

  @override
  String get privacyPointScreenClipboardTitle => 'Protezione schermo e appunti';

  @override
  String get privacyPointScreenClipboardBody =>
      'Blocco dell\'anteprima screenshot/app recenti (FLAG_SECURE) e pulizia automatica di appunti corrotti quando la finestra ottiene il focus.';

  @override
  String get privacyPointMaskModeTitle => 'Modalità mascherata';

  @override
  String get privacyPointMaskModeBody =>
      'Maschera facoltativamente l\'app come un funzionante browser di archivi zip, con un\'icona e un nome diversi. Tieni premuto il titolo per 3 secondi per raggiungere il tuo vault reale.';

  @override
  String get privacyPointExternalLinksTitle =>
      'I link esterni si aprono nel browser';

  @override
  String get privacyPointExternalLinksBody =>
      'Toccando i link si passa il controllo alla tua app browser predefinita, che gestisce la richiesta.';

  @override
  String get truncatedListingWarning =>
      'Vengono mostrati i primi 50.000 elementi — questa cartella ne contiene altri.';

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '$size px · qualità $quality%';
  }

  @override
  String holdToSpeedIndicatorLabel(String speed) {
    return 'Velocità $speed×';
  }

  @override
  String get toolbarLayoutSectionHeader => 'Layout barra degli strumenti';

  @override
  String get listViewOptionsSectionHeader => 'Opzioni vista elenco';

  @override
  String get detailedListViewColumnsSectionHeader =>
      'Colonne vista elenco dettagliato';

  @override
  String get galleryGridViewSectionHeader => 'Vista griglia galleria';

  @override
  String get browserLayoutSectionHeader => 'Layout browser';

  @override
  String get mediaViewerSectionHeader => 'Visualizzatore multimediale';

  @override
  String get viewModeAction => 'Modalità visualizzazione';

  @override
  String get sortAction => 'Ordina';

  @override
  String get playMediaAction => 'Riproduci contenuto multimediale';

  @override
  String containerSpaceSummary(String free, String total) {
    return '$free liberi · $total totali';
  }

  @override
  String volMountedSummary(int volId) {
    return 'Vol $volId · Montato';
  }

  @override
  String vaultOccupiedSpaceSummary(String used) {
    return '$used occupati';
  }

  @override
  String get incorrectPasswordOrKeyfilesDriveError =>
      'Password/file chiave errati o unità non supportata';

  @override
  String driveUsableCapacity(int mb) {
    return 'Capacità utilizzabile dell\'unità: $mb MB. Non deve essere superata.';
  }

  @override
  String get unlockMethodManualPassword => 'Password manuale';

  @override
  String get unlockMethodRememberPassword => 'Ricorda password';

  @override
  String get unlockMethodBiometrics => 'Sblocco biometrico';

  @override
  String get unlockMethodPattern => 'Sblocco con schema';

  @override
  String get unlockMethodPin => 'PIN Unlock';

  @override
  String get unlockMethodSubtitlePassword => 'Digita la password ogni volta';

  @override
  String get unlockMethodSubtitleRememberPassword =>
      'Memorizzata in modo sicuro nell\'Android Keystore';

  @override
  String get unlockMethodSubtitleBiometrics =>
      'Usa impronta digitale o volto per sbloccare';

  @override
  String get unlockMethodSubtitlePattern => 'Disegna uno schema per sbloccare';

  @override
  String get unlockMethodSubtitlePin => 'Enter a PIN to unlock';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError =>
      'Decodificatore video non disponibile — conflitto sul codec hardware';

  @override
  String get mediaStreamInitFailedError =>
      'Inizializzazione dello stream multimediale non riuscita';

  @override
  String get invalidAvifImage => 'Immagine AVIF non valida';

  @override
  String get verbImport => 'Importa';

  @override
  String get verbMove => 'Sposta';

  @override
  String get verbCopy => 'Copia';

  @override
  String get verbDelete => 'Elimina';

  @override
  String get verbImported => 'Importato';

  @override
  String get verbMoved => 'Spostato';

  @override
  String get verbCopied => 'Copiato';

  @override
  String get verbDeleted => 'Eliminato';

  @override
  String get verbImporting => 'Importazione';

  @override
  String get verbMoving => 'Spostamento';

  @override
  String get verbCopying => 'Copia';

  @override
  String get verbDeleting => 'Eliminazione';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi $verb',
      one: '1 elemento $verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return '$count saltati';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return '$count non riusciti';
  }

  @override
  String get statusCancelled => 'Annullato';

  @override
  String get statusFailed => 'Non riuscito';

  @override
  String get statusCompleted => 'Completato';

  @override
  String get fileOpCheckingSpace => 'Controllo spazio disponibile…';

  @override
  String get fileOpResolvingConflicts => 'Risoluzione conflitti…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return 'Spazio insufficiente — servono $required, disponibili solo $free';
  }

  @override
  String get fileOpDiskFullPartialRemoved =>
      'Disco pieno — i file parziali sono stati rimossi';

  @override
  String get fileOpMoveFailed => 'Spostamento non riuscito';

  @override
  String get fileOpCopyFailed => 'Copia non riuscita';

  @override
  String get fileOpDeleteFailed => 'Eliminazione non riuscita';

  @override
  String get fileOpDiskFull => 'Disco pieno';

  @override
  String get fileOpImporting => 'Importazione…';

  @override
  String fileOpImportingName(String name) {
    return 'Importazione di $name…';
  }

  @override
  String fileOpMovingName(String name) {
    return 'Spostamento di $name…';
  }

  @override
  String fileOpCopyingName(String name) {
    return 'Copia di $name…';
  }

  @override
  String get fileOpDeleting => 'Eliminazione…';

  @override
  String fileOpDeletingName(String name) {
    return 'Eliminazione di $name…';
  }

  @override
  String fileOpDeletedSoFar(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi rimossi',
      one: '1 elemento rimosso',
    );
    return '$_temp0';
  }

  @override
  String get searchInSubfoldersHint => 'Cerca in tutte le sottocartelle…';

  @override
  String get deepSearchEnabledTooltip =>
      'Ricerca nelle sottocartelle — tocca per limitare alla cartella corrente';

  @override
  String get deepSearchDisabledTooltip =>
      'Ricerca nella cartella corrente — tocca per cercare nelle sottocartelle';

  @override
  String get filterAction => 'Filtra';

  @override
  String get bookmarkAction => 'Aggiungi ai preferiti';

  @override
  String get unbookmarkAction => 'Rimuovi dai preferiti';

  @override
  String get bookmarkSelectedAction => 'Aggiungi selezionati ai preferiti';

  @override
  String get unbookmarkSelectedAction => 'Rimuovi selezionati dai preferiti';

  @override
  String bookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Aggiunti $count elementi ai preferiti',
      one: 'Aggiunto 1 elemento ai preferiti',
    );
    return '$_temp0';
  }

  @override
  String unbookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Rimossi $count elementi dai preferiti',
      one: 'Rimosso 1 elemento dai preferiti',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => 'Mostra barra dei preferiti';

  @override
  String get showBookmarkBarDesc =>
      'Mostra gli elementi preferiti in una barra o barra laterale dei preferiti';

  @override
  String get bookmarkBarSectionHeader => 'Barra dei preferiti';

  @override
  String get noBookmarksYet => 'Ancora nessun elemento preferito salvato';

  @override
  String get reorderBookmarksTitle => 'Riordina preferiti';

  @override
  String get reorderBookmarksDesc =>
      'Trascina gli elementi per riordinarli nella barra dei preferiti';

  @override
  String get navBarVaultsLabel => 'Vault';

  @override
  String get navBarToolsLabel => 'Strumenti';

  @override
  String get toolsScreenTitle => 'Strumenti';

  @override
  String get toolsSectionContainerUtilities => 'Utilità contenitore';

  @override
  String get toolsSectionFileCryptography => 'Crittografia file';

  @override
  String get toolsSectionStorageDiagnostics => 'Archiviazione e diagnostica';

  @override
  String get toolContainerSplitterTitle => 'Dividi e unisci';

  @override
  String get toolContainerSplitterSubtitle =>
      'Dividi un contenitore in parti, oppure riuniscile';

  @override
  String get toolContainerRepairTitle => 'Controlla e ripara';

  @override
  String get toolContainerRepairSubtitle =>
      'Diagnostica problemi di intestazione o file system';

  @override
  String get toolSingleFileCryptoTitle => 'Cifra / Decifra file';

  @override
  String get toolSingleFileCryptoSubtitle =>
      'Proteggi uno o più file senza un contenitore completo';

  @override
  String get toolStorageAnalyzerTitle => 'Analizzatore archiviazione';

  @override
  String get toolStorageAnalyzerSubtitle =>
      'Scopri cosa occupa spazio in un vault montato';

  @override
  String get toolDuplicateFinderTitle => 'Ricerca file duplicati';

  @override
  String get toolDuplicateFinderSubtitle =>
      'Trova e rimuovi file duplicati identici byte per byte per recuperare spazio';

  @override
  String get toolHashVerifierTitle => 'Checksum e verifica hash file';

  @override
  String get toolHashVerifierSubtitle =>
      'Verifica che i file di grandi dimensioni non siano danneggiati usando i checksum MD5/SHA';

  @override
  String get hashVerifierModeCompute => 'Calcola';

  @override
  String get hashVerifierModeVerify => 'Verifica';

  @override
  String get hashVerifierSelectSourceTitle => 'Seleziona origine file';

  @override
  String get hashVerifierAlgorithmsLabel => 'Algoritmi';

  @override
  String get hashVerifierNoAlgorithmSelected => 'Seleziona almeno un algoritmo';

  @override
  String get hashVerifierFilesLabel => 'File da sottoporre a hash';

  @override
  String hashVerifierFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count file selezionati',
      one: '1 file selezionato',
      zero: 'Nessun file selezionato',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierComputeButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Calcola $count hash',
      one: 'Calcola hash',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCancelButton => 'Annulla';

  @override
  String hashVerifierBatchProgressLabel(Object current, Object total) {
    return 'File $current di $total';
  }

  @override
  String get hashVerifierCancelledMessage => 'Annullato.';

  @override
  String hashVerifierComputeErrorsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Impossibile calcolare l\'hash di $count file',
      one: 'Impossibile calcolare l\'hash di 1 file',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCopiedMessage => 'Copiato negli appunti';

  @override
  String get hashVerifierExportManifestButton => 'Esporta come manifesto';

  @override
  String get hashVerifierExportAlgorithmLabel => 'Algoritmo del manifesto';

  @override
  String hashVerifierExportSuccessMessage(Object path) {
    return 'Salvato in $path';
  }

  @override
  String hashVerifierExportFailedMessage(Object error) {
    return 'Esportazione non riuscita: $error';
  }

  @override
  String get hashVerifierLoadManifestButton => 'Carica manifesto';

  @override
  String get hashVerifierChangeManifestButton => 'Cambia';

  @override
  String get hashVerifierManifestLabel => 'File manifesto';

  @override
  String hashVerifierManifestEntryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count voci',
      one: '1 voce',
      zero: 'Nessuna voce',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierAutoAddFolderButton =>
      'Aggiungi tutti i file da questa cartella';

  @override
  String get hashVerifierAddFilesToVerifyButton =>
      'Aggiungi file da verificare';

  @override
  String get hashVerifierVerifyAllButton => 'Verifica tutto';

  @override
  String hashVerifierVerifyProgressLabel(Object current, Object total) {
    return 'Verifica del file $current di $total';
  }

  @override
  String hashVerifierSummaryMessage(
    Object ok,
    Object mismatch,
    Object missing,
  ) {
    return '$ok corrispondenti, $mismatch non corrispondenti, $missing mancanti';
  }

  @override
  String get hashVerifierStatusMatch => 'Corrispondente';

  @override
  String get hashVerifierStatusMismatch => 'Non corrispondente';

  @override
  String get hashVerifierStatusMissing => 'File non aggiunto';

  @override
  String get hashVerifierStatusPending => 'Non ancora verificato';

  @override
  String get hashVerifierExpectedLabel => 'Previsto';

  @override
  String get hashVerifierActualLabel => 'Effettivo';

  @override
  String hashVerifierExtraFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count file aggiuntivi non elencati nel manifesto',
      one: '1 file aggiuntivo non elencato nel manifesto',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierNoManifestLoadedMessage =>
      'Carica un file manifesto per iniziare';

  @override
  String get hashVerifierManifestParseEmptyMessage =>
      'Nessuna voce di checksum trovata in questo file';

  @override
  String hashVerifierLoadManifestFailedMessage(Object error) {
    return 'Impossibile leggere il manifesto: $error';
  }

  @override
  String hashVerifierAutoAddedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Aggiunti $count file dalla cartella del vault',
      one: 'Aggiunto 1 file dalla cartella del vault',
      zero: 'Nessun nuovo file trovato',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierModeVault => 'Vault';

  @override
  String get hashVerifierVaultPickerLabel => 'Vault';

  @override
  String get hashVerifierVaultNoVaultsMessage =>
      'Nessun vault attualmente montato';

  @override
  String get hashVerifierCheckEntireVaultButton => 'Controlla l\'intero vault';

  @override
  String get hashVerifierVaultScanningLabel => 'Scansione del vault…';

  @override
  String hashVerifierVaultFilesDiscoveredLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count file trovati',
      one: '1 file trovato',
      zero: 'Nessun file trovato ancora',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmTitle => 'Controllare l\'intero vault?';

  @override
  String hashVerifierVaultConfirmFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count file',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmWarning =>
      'Verrà letto ogni file di questo vault.';

  @override
  String get hashVerifierVaultEmptyMessage =>
      'Questo vault non ha file da controllare';

  @override
  String get hashVerifierVaultStartButton => 'Avvia controllo';

  @override
  String hashVerifierVaultHashingProgressLabel(Object current, Object total) {
    return 'Controllo $current / $total';
  }

  @override
  String get hashVerifierVaultCompleteTitle => 'Controllo del vault completato';

  @override
  String hashVerifierVaultCompleteFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count file controllati',
      one: '1 file controllato',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteBytesLabel(Object size) {
    return '$size elaborati';
  }

  @override
  String hashVerifierVaultCompleteSucceededLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count riusciti',
      one: '1 riuscito',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count non riusciti',
      one: '1 non riuscito',
      zero: '0 non riusciti',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultElapsedLabel(Object time) {
    return 'Trascorso: $time';
  }

  @override
  String get hashVerifierVaultCancelledMessage =>
      'Controllo del vault annullato.';

  @override
  String hashVerifierVaultFailedMessage(Object error) {
    return 'Controllo del vault non riuscito: $error';
  }

  @override
  String get hashVerifierVaultNewCheckButton => 'Nuovo controllo';

  @override
  String get hashVerifierVaultActionComputeTitle => 'Calcola l\'intero vault';

  @override
  String get hashVerifierVaultActionComputeSubtitle =>
      'Calcola l\'hash di ogni file di un vault';

  @override
  String get hashVerifierVaultActionVerifyTitle => 'Verifica l\'intero vault';

  @override
  String get hashVerifierVaultActionVerifySubtitle =>
      'Controlla ogni file di un vault rispetto a un manifesto caricato';

  @override
  String get hashVerifierVaultChangeActionButton => 'Cambia';

  @override
  String get hashVerifierVaultVerifyButton => 'Verifica l\'intero vault';

  @override
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage =>
      'Verificare un intero vault richiede un manifesto caricato dall\'interno di un vault.';

  @override
  String get duplicateFinderTargetLabel => 'Vault di destinazione';

  @override
  String get duplicateFinderTargetAllVaults => 'Tutti i vault aperti';

  @override
  String get duplicateFinderStartScan => 'Avvia scansione';

  @override
  String get duplicateFinderCancelScan => 'Annulla scansione';

  @override
  String get duplicateFinderRescan => 'Ripeti scansione';

  @override
  String get duplicateFinderScanningStage1 =>
      'Fase 1: indicizzazione e raggruppamento per dimensione...';

  @override
  String get duplicateFinderScanningStage2 =>
      'Fase 2: controllo delle intestazioni parziali dei file...';

  @override
  String get duplicateFinderScanningStage3 =>
      'Fase 3: verifica completa degli hash byte per byte...';

  @override
  String get duplicateFinderScanComplete => 'Scansione completata';

  @override
  String get duplicateFinderNoDuplicatesTitle =>
      'Nessun file duplicato trovato';

  @override
  String get duplicateFinderNoDuplicatesMessage =>
      'Tutti i file nei vault analizzati contengono byte unici.';

  @override
  String get duplicateFinderSelectRedundant => 'Seleziona ridondanti';

  @override
  String get duplicateFinderSelectAll => 'Seleziona tutto';

  @override
  String get duplicateFinderDeselectAll => 'Deseleziona tutto';

  @override
  String get duplicateFinderOriginalLabel => 'Originale';

  @override
  String get duplicateFinderDuplicateLabel => 'Duplicato';

  @override
  String get duplicateFinderConfirmDeleteTitle => 'Eliminare i file duplicati?';

  @override
  String get duplicateFinderSearchHint =>
      'Cerca duplicati per nome file o percorso...';

  @override
  String get toolNotImplementedYetMessage =>
      'Questo strumento non è ancora collegato al motore nativo — riprova in un futuro aggiornamento.';

  @override
  String get splitJoinModeSplit => 'Dividi';

  @override
  String get splitJoinModeJoin => 'Unisci';

  @override
  String get splitSourceFileLabel => 'File di origine';

  @override
  String get splitDestinationFolderLabel => 'Cartella di destinazione';

  @override
  String get splitChunkSizeLabel => 'Dimensione parti';

  @override
  String get splitChunkSizeCustomLabel => 'Dimensione personalizzata (MB)';

  @override
  String get splitChunkSizeFourMb => '4 MB';

  @override
  String get splitChunkSizeCloud8mb => '8 MB';

  @override
  String get splitChunkSizeCloud32mb => '32 MB';

  @override
  String get splitChunkSizeCloud => '100 MB';

  @override
  String get splitChunkSizeFat32 => '2 GB';

  @override
  String get splitChunkSizeFourGb => '4 GB';

  @override
  String get splitChunkSizeCustom => 'Personalizzata';

  @override
  String get splitContainerButton => 'Dividi contenitore';

  @override
  String get joinFirstPartLabel => 'Prima parte';

  @override
  String get joinOutputFileNameLabel => 'Nome file di output';

  @override
  String get joinContainerButton => 'Unisci file';

  @override
  String get chooseFileButton => 'Scegli file';

  @override
  String get chooseFolderButton => 'Scegli cartella';

  @override
  String get noFileSelectedLabel => 'Nessun file selezionato';

  @override
  String get noFolderSelectedLabel => 'Nessuna cartella selezionata';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage => 'Contenitore diviso con successo';

  @override
  String get joinContainerSuccessMessage => 'File uniti con successo';

  @override
  String get cryptoDirectionEncrypt => 'Cifra';

  @override
  String get cryptoDirectionDecrypt => 'Decifra';

  @override
  String get singleFileCryptoInputFileLabel => 'File di input';

  @override
  String get singleFileCryptoCipherLabel => 'Cifrario';

  @override
  String get singleFileCryptoDeleteOriginalLabel =>
      'Elimina i file originali dopo la cifratura';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cifra $count file',
      one: 'Cifra file',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Decifra $count file',
      one: 'Decifra file',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Fatto — $count file elaborati',
      one: 'Fatto',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return '$succeeded di $total file elaborati — $failed non riusciti';
  }

  @override
  String get singleFileCryptoAddFilesButton => 'Aggiungi file';

  @override
  String get singleFileCryptoClearFilesButton => 'Cancella';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count file selezionati',
      one: '1 file selezionato',
      zero: 'Nessun file selezionato',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return 'File $current di $total';
  }

  @override
  String get repairTargetStepTitle => 'Scegli una destinazione';

  @override
  String get repairTargetUnmountedFileOption => 'File non montato';

  @override
  String get repairTargetUnmountedFileSubtitle =>
      'Ripristina un\'intestazione di backup su un contenitore che non hai aperto';

  @override
  String get repairTargetMountedVolumeSubtitle =>
      'Esegui un controllo del file system su un vault già aperto';

  @override
  String get repairNoMountedVolumes => 'Nessun vault attualmente montato';

  @override
  String get repairScanButton => 'Esegui scansione diagnostica';

  @override
  String get repairChangeTargetButton => 'Cambia destinazione';

  @override
  String get repairDiagnosisHealthy => 'Nessun problema trovato';

  @override
  String get repairDiagnosisHeaderCorrupted => 'Intestazione danneggiata';

  @override
  String get repairDiagnosisFilesystemDirty =>
      'File system sporco / smontaggio non pulito';

  @override
  String get repairRestoreBackupHeaderButton =>
      'Ripristina intestazione di backup';

  @override
  String get repairRunFilesystemCheckButton =>
      'Esegui controllo e correzione del file system';

  @override
  String get repairActionSucceededMessage =>
      'Riparazione completata con successo';

  @override
  String get repairActionFailedMessage =>
      'L\'azione di riparazione non è riuscita';

  @override
  String get storageAnalyzerTargetLabel => 'Volume';

  @override
  String get storageAnalyzerNoTargetsTitle => 'Niente da analizzare';

  @override
  String get storageAnalyzerNoTargetsMessage =>
      'Monta prima un vault, poi torna qui per vedere la ripartizione dell\'archiviazione.';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return '$used di $total usati';
  }

  @override
  String get storageAnalyzerHeaviestFilesHeader => 'File più pesanti';

  @override
  String get storageAnalyzerBreakdownHeader => 'Per tipo di file';

  @override
  String get storageAnalyzerScanningMessage => 'Scansione del volume…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return 'Scansione interrotta anticipatamente dopo $count file — i risultati potrebbero essere incompleti.';
  }

  @override
  String get storageAnalyzerNoFilesFound => 'Nessun file trovato';

  @override
  String get storageCategoryImages => 'Immagini';

  @override
  String get storageCategoryVideos => 'Video';

  @override
  String get storageCategoryAudio => 'Audio';

  @override
  String get storageCategoryDocuments => 'Documenti';

  @override
  String get storageCategoryArchives => 'Archivi';

  @override
  String get storageCategoryOther => 'Altro';

  @override
  String get keyfilePassphraseGeneratorTitle =>
      'Generatore file chiave e passphrase';

  @override
  String get keyfilePassphraseGeneratorSubtitle =>
      'Genera passphrase Diceware, password personalizzate e file chiave ad alta entropia';

  @override
  String get tabPassphrase => 'Passphrase';

  @override
  String get tabKeyfile => 'File chiave';

  @override
  String get modeDiceware => 'Passphrase Diceware';

  @override
  String get modeCustomPassword => 'Password personalizzata';

  @override
  String get keyfileTypeBinary => 'File chiave binario (.key)';

  @override
  String get keyfileTypeImage => 'File chiave immagine rumore (.png)';

  @override
  String get copyPassphraseSuccess =>
      'Passphrase copiata negli appunti protetti';

  @override
  String get copyFingerprintSuccess => 'Impronta SHA-256 copiata negli appunti';

  @override
  String get saveKeyfileToVault => 'Salva nel vault montato';

  @override
  String get exportKeyfileToStorage =>
      'Esporta nell\'archiviazione del dispositivo';

  @override
  String get keyfileNoOpenVaultsMessage =>
      'Nessun vault aperto disponibile. Monta prima un vault.';

  @override
  String get keyfileSelectDestinationVaultTitle =>
      'Seleziona vault di destinazione';

  @override
  String keyfileVolumeIdLabel(Object volId) {
    return 'ID volume: $volId';
  }

  @override
  String keyfileExportSuccessMessage(Object path) {
    return 'File chiave esportato in $path';
  }

  @override
  String keyfileExportFailedMessage(Object error) {
    return 'Esportazione non riuscita: $error';
  }

  @override
  String keyfileSavedToVaultMessage(Object vaultName, Object path) {
    return 'File chiave salvato in $vaultName: $path';
  }

  @override
  String get keyfileWriteFailedMessage =>
      'Impossibile scrivere il file chiave nel vault';

  @override
  String keyfileSaveErrorMessage(Object error) {
    return 'Errore nel salvataggio nel vault: $error';
  }

  @override
  String get passphraseGeneratedSecretLabel => 'Segreto generato';

  @override
  String get copyToClipboardTooltip => 'Copia negli appunti';

  @override
  String get generateNewTooltip => 'Genera nuovo';

  @override
  String get passphraseStrengthWeak => 'Debole';

  @override
  String get passphraseStrengthGood => 'Buona';

  @override
  String get passphraseStrengthStrong => 'Forte';

  @override
  String get passphraseStrengthUnbreakable => 'Inviolabile';

  @override
  String get passphraseCrackTimeInstant => '< 1 secondo';

  @override
  String get passphraseCrackTimeShort => 'Alcuni giorni / mesi';

  @override
  String get passphraseCrackTimeCenturies => 'Diversi secoli';

  @override
  String get passphraseCrackTimeMillionsOfYears => 'Milioni di anni';

  @override
  String passphraseStrengthLabel(Object label) {
    return 'Robustezza: $label';
  }

  @override
  String passphraseEntropyBitsLabel(Object bits) {
    return '$bits bit di entropia';
  }

  @override
  String passphraseCrackTimeLabel(Object crackTime) {
    return 'Tempo di violazione stimato: $crackTime';
  }

  @override
  String get dicewareOptionsTitle => 'Opzioni EFF Diceware';

  @override
  String dicewareWordCountLabel(Object count) {
    return 'Numero di parole: $count parole';
  }

  @override
  String dicewareWordCountBitsLabel(Object bits) {
    return '$bits bit';
  }

  @override
  String dicewareWordCountSliderLabel(Object count) {
    return '$count parole';
  }

  @override
  String get dicewareWordSeparatorLabel => 'Separatore parole';

  @override
  String get dicewareSeparatorHyphen => 'Trattino ( - )';

  @override
  String get dicewareSeparatorSpace => 'Spazio (   )';

  @override
  String get dicewareSeparatorUnderscore => 'Trattino basso ( _ )';

  @override
  String get dicewareSeparatorDot => 'Punto ( . )';

  @override
  String get dicewareSeparatorSlash => 'Barra ( / )';

  @override
  String get dicewareWordCasingLabel => 'Maiuscole/minuscole parole';

  @override
  String get dicewareCasingLowercase => 'minuscolo';

  @override
  String get dicewareCasingTitleCase => 'Iniziale maiuscola';

  @override
  String get dicewareCasingUppercase => 'MAIUSCOLO';

  @override
  String get dicewareAppendDigitLabel => 'Aggiungi cifra casuale (0-9)';

  @override
  String get dicewareAppendSymbolLabel => 'Aggiungi simbolo casuale (!@#\$%)';

  @override
  String get customPasswordOptionsTitle => 'Opzioni password personalizzata';

  @override
  String customPasswordLengthLabel(Object length) {
    return 'Lunghezza: $length caratteri';
  }

  @override
  String customPasswordLengthSliderLabel(Object length) {
    return '$length caratteri';
  }

  @override
  String get customPasswordUppercaseLabel => 'Lettere maiuscole (A-Z)';

  @override
  String get customPasswordLowercaseLabel => 'Lettere minuscole (a-z)';

  @override
  String get customPasswordNumbersLabel => 'Numeri (0-9)';

  @override
  String get customPasswordSymbolsLabel => 'Simboli (!@#\$%^&*)';

  @override
  String get customPasswordExcludeAmbiguousLabel =>
      'Escludi caratteri ambigui (1, l, I, 0, O)';

  @override
  String get keyfileBinarySizeTitle => 'Dimensione file chiave binario';

  @override
  String get keyfileImageResolutionTitle => 'Risoluzione immagine rumore';

  @override
  String get keyfilePresetBytes64 => '64 byte (standard VeraCrypt)';

  @override
  String get keyfilePresetBytes256 => '256 byte';

  @override
  String get keyfilePresetBytes2048 => '2 KB';

  @override
  String get keyfilePresetBytes64kb => '64 KB';

  @override
  String get keyfilePresetBytes1mb => '1 MB (limite massimo)';

  @override
  String get keyfilePresetRes64 => '64 x 64 pixel (~16 KB)';

  @override
  String get keyfilePresetRes256 => '256 x 256 pixel (~256 KB)';

  @override
  String get keyfilePresetRes512 => '512 x 512 pixel (~1 MB)';

  @override
  String get keyfileGenerateNewTooltip => 'Genera nuovo file chiave';

  @override
  String keyfileSizeLabel(Object size) {
    return 'Dimensione: $size';
  }

  @override
  String get keyfileFingerprintLabel => 'Impronta SHA-256';

  @override
  String get keyfileCopyFingerprintTooltip => 'Copia impronta';

  @override
  String get duplicateFinderNoVaultsTitle => 'Nessun vault montato';

  @override
  String get duplicateFinderNoVaultsMessage =>
      'Sblocca e monta almeno un vault contenitore per cercare file duplicati.';

  @override
  String duplicateFinderConfirmDeleteMessage(Object count, Object size) {
    return 'Sei sicuro di voler eliminare definitivamente $count file duplicati ($size) dai tuoi vault? Questa azione non può essere annullata.';
  }

  @override
  String get duplicateFinderDeletePermanentlyButton =>
      'Elimina definitivamente';

  @override
  String duplicateFinderDeleteSuccessMessage(Object count) {
    return 'Eliminati con successo $count file duplicati.';
  }

  @override
  String get duplicateFinderIntroTitle =>
      'Ricerca a 3 fasi per contenuto identico';

  @override
  String get duplicateFinderIntroSubtitle =>
      'Rileva contenuti esattamente identici indipendentemente dal nome file.';

  @override
  String get duplicateFinderStagesDescription =>
      '• Fase 1: raggruppamento per dimensione (scansione istantanea dei metadati)\n• Fase 2: controllo intestazione parziale (SHA-256 su 16 KB di intestazione)\n• Fase 3: verifica completa dell\'hash (corrispondenza esatta byte per byte SHA-256)';

  @override
  String get duplicateFinderScanningVaultFallback => 'Scansione del vault...';

  @override
  String duplicateFinderProcessingFileLabel(Object fileName) {
    return 'Elaborazione: $fileName';
  }

  @override
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  ) {
    return 'File analizzati: $scanned | Duplicati trovati: $groups gruppi ($saved)';
  }

  @override
  String duplicateFinderGroupsFoundLabel(Object count) {
    return '$count gruppi di duplicati trovati';
  }

  @override
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved) {
    return '$copies copie trovate • Risparmia $saved di spazio';
  }

  @override
  String duplicateFinderVaultsSelectedLabel(Object count) {
    return '$count vault selezionati';
  }

  @override
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  ) {
    return 'Gruppo $groupIndex: $size ($count copie trovate)';
  }

  @override
  String duplicateFinderRecoverableSpaceLabel(Object size) {
    return 'Spazio recuperabile: $size';
  }

  @override
  String get duplicateFinderPreviewFileTooltip => 'Anteprima file';

  @override
  String duplicateFinderPreviewFailedMessage(Object fileName) {
    return 'Impossibile aprire l\'anteprima del file per $fileName';
  }

  @override
  String duplicateFinderPreviewErrorMessage(Object error) {
    return 'Errore nell\'anteprima del file: $error';
  }

  @override
  String duplicateFinderFilesSelectedLabel(Object count) {
    return '$count file selezionati';
  }

  @override
  String duplicateFinderBytesToBeFreedLabel(Object size) {
    return '$size da liberare';
  }

  @override
  String duplicateFinderDeleteSelectedButton(Object count) {
    return 'Elimina selezionati ($count)';
  }

  @override
  String get vaultBrowserSwitchVaultTooltip => 'Cambia vault';

  @override
  String get vaultBrowserRootFolderLabel => 'Cartella radice';

  @override
  String vaultFilePickerTitle(Object vaultName) {
    return 'Seleziona file ($vaultName)';
  }

  @override
  String get vaultFilePickerEmptyMessage => 'La cartella è vuota';

  @override
  String vaultFilePickerConfirmButton(Object count) {
    return 'Seleziona $count file';
  }

  @override
  String vaultFolderPickerTitle(Object vaultName) {
    return 'Seleziona cartella ($vaultName)';
  }

  @override
  String get vaultFolderPickerEmptyMessage => 'Nessuna sottocartella qui';

  @override
  String get vaultFolderPickerRootLabel => 'Radice';

  @override
  String get vaultFolderPickerConfirmRootButton => 'Seleziona cartella radice';

  @override
  String vaultFolderPickerConfirmNamedButton(Object folderName) {
    return 'Seleziona \"$folderName\"';
  }

  @override
  String get singleFileCryptoSelectInputTitle => 'Seleziona file di input';

  @override
  String get singleFileCryptoFromDeviceTitle =>
      'Dall\'archiviazione del dispositivo';

  @override
  String get singleFileCryptoFromDeviceSubtitle =>
      'Scegli i file dal dispositivo usando il selettore file di sistema';

  @override
  String get singleFileCryptoFromVaultTitle => 'Da un vault montato';

  @override
  String get singleFileCryptoFromVaultSubtitle =>
      'Scegli i file da un contenitore cifrato aperto';

  @override
  String get singleFileCryptoSelectDestinationTitle =>
      'Seleziona cartella di destinazione';

  @override
  String get singleFileCryptoDeviceFolderTitle =>
      'Cartella nell\'archiviazione del dispositivo';

  @override
  String get singleFileCryptoDeviceFolderSubtitle =>
      'Salva l\'output in una cartella nell\'archiviazione del dispositivo';

  @override
  String get singleFileCryptoVaultFolderTitle => 'Cartella nel vault montato';

  @override
  String get singleFileCryptoVaultFolderSubtitle =>
      'Salva l\'output all\'interno di un contenitore cifrato aperto';

  @override
  String get toolsSectionBackupSync => 'Backup e sincronizzazione';

  @override
  String get toolVaultSyncTitle => 'Sincronizzazione vault';

  @override
  String get toolVaultSyncSubtitle =>
      'Confronta due vault e copia ciò che manca o è più recente';

  @override
  String get vaultSyncNoVaultsTitle => 'Nessun vault montato';

  @override
  String get vaultSyncNoVaultsMessage =>
      'Monta almeno un vault per confrontare e sincronizzare i suoi file.';

  @override
  String get vaultSyncLeftLabel => 'Sinistra';

  @override
  String get vaultSyncRightLabel => 'Destra';

  @override
  String get vaultSyncTapToSelect =>
      'Tocca per selezionare un vault e una cartella';

  @override
  String get vaultSyncSwapTooltip => 'Scambia sinistra e destra';

  @override
  String get vaultSyncSameLocationWarning =>
      'Sinistra e Destra devono essere cartelle diverse.';

  @override
  String get vaultSyncIntroTitle => 'Confronta due vault';

  @override
  String get vaultSyncIntroSubtitle =>
      'Scegli un vault a Sinistra e uno a Destra (o due cartelle nello stesso vault) per vedere cosa manca, è stato modificato o è più recente su ciascun lato.';

  @override
  String get vaultSyncCompareButton => 'Confronta';

  @override
  String get vaultSyncComparingLabel => 'Confronto dei vault…';

  @override
  String vaultSyncCompareStatsLabel(Object dirs, Object entries) {
    return 'Cartelle analizzate: $dirs | Differenze trovate: $entries';
  }

  @override
  String get vaultSyncCancelCompareButton => 'Annulla';

  @override
  String get vaultSyncInSyncTitle => 'Già sincronizzati';

  @override
  String vaultSyncInSyncMessage(num count) {
    return 'Tutti i $count file corrispondenti sono identici su entrambi i lati.';
  }

  @override
  String get vaultSyncRecompareButton => 'Confronta di nuovo';

  @override
  String vaultSyncDifferencesFoundLabel(num count) {
    return '$count differenze trovate';
  }

  @override
  String vaultSyncInSyncCountLabel(num count) {
    return '$count file già corrispondono su entrambi i lati';
  }

  @override
  String vaultSyncBadgeOnlyLeft(Object count) {
    return '$count solo a sinistra';
  }

  @override
  String vaultSyncBadgeOnlyRight(Object count) {
    return '$count solo a destra';
  }

  @override
  String vaultSyncBadgeLeftNewer(Object count) {
    return '$count più recenti a sinistra';
  }

  @override
  String vaultSyncBadgeRightNewer(Object count) {
    return '$count più recenti a destra';
  }

  @override
  String vaultSyncBadgeConflicts(num count) {
    return '$count da rivedere';
  }

  @override
  String get vaultSyncDirectionLabel => 'Direzione di sincronizzazione';

  @override
  String get vaultSyncDirectionTwoWay => 'Bidirezionale (consigliato)';

  @override
  String get vaultSyncDirectionTwoWaySubtitle =>
      'Copia ogni file sul lato in cui manca o ha una copia più vecchia';

  @override
  String get vaultSyncDirectionLeftToRight =>
      'Sinistra → Destra (monodirezionale)';

  @override
  String get vaultSyncDirectionLeftToRightSubtitle =>
      'Trasferisce i file nuovi e aggiornati da Sinistra a Destra; non modifica mai Sinistra';

  @override
  String get vaultSyncDirectionRightToLeft =>
      'Destra → Sinistra (monodirezionale)';

  @override
  String get vaultSyncDirectionRightToLeftSubtitle =>
      'Trasferisce i file nuovi e aggiornati da Destra a Sinistra; non modifica mai Destra';

  @override
  String get vaultSyncSearchHint => 'Cerca differenze';

  @override
  String get vaultSyncStatusOnlyLeft => 'Solo sinistra';

  @override
  String get vaultSyncStatusOnlyRight => 'Solo destra';

  @override
  String get vaultSyncStatusLeftNewer => 'Più recente a sinistra';

  @override
  String get vaultSyncStatusRightNewer => 'Più recente a destra';

  @override
  String get vaultSyncStatusConflict => 'Da rivedere';

  @override
  String get vaultSyncStatusTypeMismatch => 'Tipo non corrispondente';

  @override
  String get vaultSyncFolderOnlyLeftDetail => 'Cartella — solo a sinistra';

  @override
  String get vaultSyncFolderOnlyRightDetail => 'Cartella — solo a destra';

  @override
  String vaultSyncBothSidesDetail(
    Object leftSize,
    Object leftDate,
    Object rightSize,
    Object rightDate,
  ) {
    return 'S: $leftSize · $leftDate  →  D: $rightSize · $rightDate';
  }

  @override
  String get vaultSyncTypeMismatchTooltip =>
      'Un file su un lato e una cartella sull\'altro — risolvi manualmente nel browser dei file';

  @override
  String get vaultSyncChangeActionTooltip =>
      'Cambia azione di sincronizzazione';

  @override
  String get vaultSyncActionCopyToRight => 'Copia → Destra';

  @override
  String get vaultSyncActionCopyToLeft => 'Copia → Sinistra';

  @override
  String get vaultSyncActionSkip => 'Salta';

  @override
  String vaultSyncChangesQueuedLabel(num count) {
    return '$count modifiche in coda';
  }

  @override
  String get vaultSyncSyncNowButton => 'Sincronizza ora';

  @override
  String get vaultSyncConfirmTitle => 'Avviare la sincronizzazione?';

  @override
  String vaultSyncConfirmMessage(num count, Object bytes) {
    return 'Questo copierà $count elementi ($bytes totali) tra i due lati. I file esistenti con lo stesso nome verranno sovrascritti.';
  }

  @override
  String vaultSyncStartedMessage(num count) {
    return 'Sincronizzazione avviata — $count elementi in coda';
  }

  @override
  String vaultSyncPickLocationTitle(Object side) {
    return 'Seleziona vault e cartella $side';
  }

  @override
  String get vaultSyncReadOnlyBadge => 'Sola lettura';

  @override
  String get vaultSyncReadOnlyTooltip =>
      'Questo vault è montato in sola lettura — non è possibile copiarvi file';

  @override
  String get vaultSyncSyncingButton => 'Sincronizzazione…';

  @override
  String get vaultSyncNotEnoughSpaceTitle => 'Spazio insufficiente';

  @override
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  ) {
    return 'Spazio insufficiente su $side — servono $required, disponibili solo $free.';
  }

  @override
  String get removeMasterPasswordTitle => 'Rimuovi password principale';

  @override
  String get confirmRemoveMasterPasswordMessage =>
      'Inserisci la tua password principale attuale per confermare la rimozione:';

  @override
  String get authenticateToRemoveMasterPassword =>
      'Autenticati per rimuovere la password principale';

  @override
  String get incorrectPassword => 'Password errata';

  @override
  String get rememberPerFolderLayoutLabel => 'Remember Per-Folder Layout';

  @override
  String get rememberPerFolderLayoutDesc =>
      'Save separate view layout (list, grid, masonry) for each folder';

  @override
  String get fileInfoAction => 'Info';

  @override
  String get automationScreenTitle => 'Automation (Tasker / MacroDroid)';

  @override
  String get automationUsbUnsupportedMessage =>
      'Automation isn\'t available yet for USB-attached vaults.';

  @override
  String get automationThisVaultSectionHeader => 'This vault';

  @override
  String get automationAccessLabel => 'Automation access';

  @override
  String get automationPasswordSectionHeader => 'Automation password';

  @override
  String get automationPasswordStoredHint =>
      'A password is stored for unattended UNLOCK_VAULT calls. Save a new one to replace it, or save an empty field to clear it — automation can also supply a password directly in the broadcast instead of relying on this.';

  @override
  String get automationPasswordNotStoredHint =>
      'Optional. Without a stored password, automation must supply one with every UNLOCK_VAULT broadcast.';

  @override
  String get automationNewPasswordFieldLabel => 'New password';

  @override
  String get automationPasswordFieldLabel => 'Password';

  @override
  String get automationClearPasswordButton => 'Clear stored password';

  @override
  String get automationSavePasswordButton => 'Save password';

  @override
  String get automationTokenSectionHeader => 'API token';

  @override
  String get automationTokenDescription =>
      'Shared by every vault with automation access enabled. Automation sends this back on every broadcast; a wrong or missing token gets silently ignored, not an error.';

  @override
  String get automationRegenerateTokenButton => 'Regenerate token';

  @override
  String get automationRegenerateTokenDialogTitle => 'Regenerate token?';

  @override
  String get automationRegenerateTokenDialogMessage =>
      'Any Tasker profile or MacroDroid macro using the current token will stop working silently until you update it with the new one.';

  @override
  String get automationRegenerateConfirmLabel => 'Regenerate';

  @override
  String get automationTokenRegeneratedMessage => 'Token regenerated.';

  @override
  String get automationRegenerateTokenFailedMessage =>
      'Could not regenerate the token.';

  @override
  String get automationUpdateSettingsFailedMessage =>
      'Could not update automation settings.';

  @override
  String get automationSavePasswordFailedMessage =>
      'Could not save the automation password.';

  @override
  String get automationPasswordClearedMessage => 'Automation password cleared.';

  @override
  String get automationPasswordSavedMessage => 'Automation password saved.';

  @override
  String get automationConfigSectionHeader => 'Configuration strings';

  @override
  String get automationConfigIntro =>
      'Tap any value below to copy it. In Tasker, use a \"Send Intent\" action; in MacroDroid, use an \"Intent\" action with Intent Type set to Broadcast — not Activity or Service, which fails with \"unable to find explicit activity class\".';

  @override
  String get automationConfigPackageLabel => 'Package name';

  @override
  String get automationConfigClassLabel => 'Receiver class';

  @override
  String get automationConfigVaultUriLabel => 'This vault\'s URI';

  @override
  String get automationConfigActionsSectionHeader => 'Broadcast actions';

  @override
  String get automationActionUnlockLabel => 'Unlock vault';

  @override
  String get automationActionLockLabel => 'Lock vault';

  @override
  String get automationActionImportLabel => 'Import file';

  @override
  String get automationActionExportLabel => 'Export file';

  @override
  String get automationActionWipeLabel => 'Wipe file';

  @override
  String get automationDocCommentFootnote =>
      'Full extras and the result-broadcast contract are documented in VaultAutomationReceiver.kt.';

  @override
  String get automationTierOffLabel => 'Off';

  @override
  String get automationTierOffSubtitle => 'Automation cannot touch this vault';

  @override
  String get automationTierLifecycleLabel => 'Unlock / lock only';

  @override
  String get automationTierLifecycleSubtitle =>
      'Automation may unlock and lock this vault, nothing else';

  @override
  String get automationTierFullLabel => 'Unlock / lock + file import-export';

  @override
  String get automationTierFullSubtitle =>
      'Automation may also import and export files while this vault is unlocked';

  @override
  String get automationTutorialLinkLabel =>
      'Read the full step-by-step tutorial';

  @override
  String get showHiddenFilesLabel => 'Show Hidden Files';

  @override
  String get showHiddenFilesDesc => 'Display dotfiles and system folders';

  @override
  String get dontAskAgain => 'Don\'t ask again';

  @override
  String get deleteAfterImportLabel => 'Delete files after import';

  @override
  String get deleteAfterImportModeAsk => 'Ask every time';

  @override
  String get deleteAfterImportModeAskSubtitle =>
      'Prompt whether to delete original files after importing';

  @override
  String get deleteAfterImportModeKeep => 'Keep originals (do not delete)';

  @override
  String get deleteAfterImportModeKeepSubtitle =>
      'Never delete original files and do not ask';

  @override
  String get deleteAfterImportModeDelete => 'Delete originals automatically';

  @override
  String get deleteAfterImportModeDeleteSubtitle =>
      'Automatically delete original files from device after import';

  @override
  String get sectionKeyStorageIntegration => 'Key Storage & System Access';

  @override
  String get sectionMaskMode => 'Mask Mode';

  @override
  String get advancedOptionsTitle => 'Advanced Options';
}
