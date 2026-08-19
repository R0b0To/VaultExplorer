// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Cerrar';

  @override
  String get search => 'Buscar';

  @override
  String get goBack => 'Volver';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => 'Ir a la página';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return 'Número de página (1 - $pageCount)';
  }

  @override
  String get pdfViewerPageLabel => 'Página';

  @override
  String get pdfViewerGoButton => 'Ir';

  @override
  String get pdfViewerSearchHint => 'Buscar en el documento';

  @override
  String get pdfViewerNoMatches => 'Sin coincidencias';

  @override
  String get pdfViewerPreviousMatch => 'Coincidencia anterior';

  @override
  String get pdfViewerNextMatch => 'Siguiente coincidencia';

  @override
  String get pdfViewerCloseSearch => 'Cerrar búsqueda';

  @override
  String get pdfViewerPrintTooltip => 'Imprimir documento';

  @override
  String get pdfViewerLoadingDocument => 'Cargando documento…';

  @override
  String get pdfViewerCannotOpenTitle => 'No se puede abrir el PDF';

  @override
  String get pdfViewerFailedToLoad => 'Error al cargar el PDF';

  @override
  String get pdfViewerEditTooltip => 'Editar';

  @override
  String get pdfViewerDoneEditingTooltip => 'Terminar edición';

  @override
  String get pdfViewerSaveFailed =>
      'No se pudieron guardar los cambios en este PDF';

  @override
  String get pdfViewerEditUnavailable =>
      'La edición no está disponible para este documento';

  @override
  String get paste => 'Pegar';

  @override
  String get clear => 'Borrar';

  @override
  String get clipboardVerbMove => 'Mover';

  @override
  String get clipboardVerbCopy => 'Copiar';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb ($count) — Toca para ver detalles, mantén pulsado para pegar';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb ($count) — Detalles del portapapeles';
  }

  @override
  String clipboardSourceLabel(String source) {
    return 'Origen: $source';
  }

  @override
  String get clipboardDefaultSourceName => 'Bóveda';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count elementos más',
      one: '+1 elemento más',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => 'Parámetros avanzados';

  @override
  String get pimFieldLabel =>
      'PIM  (déjalo en blanco para usar el valor predeterminado)';

  @override
  String get encryptionAlgorithmLabel => 'Algoritmo de cifrado';

  @override
  String get hashAlgorithmLabel => 'Algoritmo hash';

  @override
  String get clipboardVerbMoving => 'Moviendo';

  @override
  String get clipboardVerbCopying => 'Copiando';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return ' desde \"$source\"';
  }

  @override
  String get clipboardOpenContainerToPaste => 'Abre un contenedor para pegar';

  @override
  String get keyfilesOptionalLabel => 'Archivos clave (opcional)';

  @override
  String get addFile => 'Añadir archivo';

  @override
  String get noKeyfilesAttached => 'No hay archivos clave adjuntos';

  @override
  String get completed => 'Completado';

  @override
  String get dismiss => 'Descartar';

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
      other: '$count transferencias',
      one: '1 transferencia',
    );
    return '$_temp0';
  }

  @override
  String multiOpSublabel(String summary) {
    return '$summary · toca para ver todo';
  }

  @override
  String get thumbnailSizeResolutionLabel => 'Tamaño de miniatura (resolución)';

  @override
  String get jpegCompressionQualityLabel => 'Calidad de compresión JPEG';

  @override
  String get done => 'Hecho';

  @override
  String get confirm => 'Confirmar';

  @override
  String get couldNotPickKeyfiles =>
      'No se pudieron seleccionar los archivos clave';

  @override
  String get filesystemLabelEncryptedVault => 'esta bóveda cifrada';

  @override
  String get filesystemLabelThisContainer => 'este contenedor';

  @override
  String get nounFile => 'archivo';

  @override
  String get nounFolder => 'carpeta';

  @override
  String get nounFileCapitalized => 'Archivo';

  @override
  String get nounFolderCapitalized => 'Carpeta';

  @override
  String get unitBytes => 'bytes';

  @override
  String get unitCharacters => 'caracteres';

  @override
  String get validationEmptyName => 'El nombre no puede estar vacío.';

  @override
  String validationReservedNavName(String name, String noun) {
    return '\"$name\" es un nombre de navegación reservado y no se puede usar como nombre de $noun.';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return '\"$char\" en la posición $position no está permitido en un nombre en $fsLabel.';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return 'La posición $position contiene un carácter de control no imprimible (código $code), que no está permitido en $fsLabel.';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '\"$name\" es un nombre de dispositivo reservado en $fsLabel (coincide con CON, PRN, AUX, NUL, COM0–9 o LPT0–9) y no se puede usar, con o sin extensión de archivo.';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return 'Los nombres de $noun no pueden terminar con un espacio en $fsLabel';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return 'Los nombres de $noun no pueden terminar con un \".\" en $fsLabel';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return 'Este nombre tiene $length $unit; $fsLabel permite como máximo $maxLength $unit por nombre de $noun.';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return 'La ruta completa tiene $length caracteres; $fsLabel permite como máximo $maxLength.';
  }

  @override
  String conflictSameType(String noun, String name) {
    return 'Ya existe un $noun llamado \"$name\" aquí.';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return 'Ya existe un $existingNoun llamado \"$name\" aquí — no puede compartir nombre con un $candidateNoun.';
  }

  @override
  String get readOnlyContainerWarning =>
      'Este contenedor está montado en modo de solo lectura.';

  @override
  String get hiddenVolumeProtectionTriggeredWarning =>
      'Una escritura en este volumen externo habría dañado el volumen oculto, por lo que se bloqueó. Este contenedor ha pasado a modo de solo lectura durante el resto de la sesión.';

  @override
  String get protectHiddenVolumeToggleTitle => 'Proteger volumen oculto';

  @override
  String get protectHiddenVolumeToggleSubtitle =>
      'Evita daños causados al escribir en el volumen externo';

  @override
  String get protectHiddenVolumeCredentialsRequired =>
      'Se requiere una contraseña o archivo clave del volumen oculto para protegerlo';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¿Eliminar $count elementos?',
      one: '¿Eliminar 1 elemento?',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning =>
      'Estos elementos se eliminarán permanentemente, incluido todo el contenido de las carpetas seleccionadas.';

  @override
  String get deleteFilesWarning =>
      'Estos elementos se borrarán permanentemente de tu volumen cifrado.';

  @override
  String get delete => 'Eliminar';

  @override
  String get remove => 'Quitar';

  @override
  String get create => 'Crear';

  @override
  String get rename => 'Renombrar';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Renombrar $count elementos',
      one: 'Renombrar 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => 'Nueva carpeta';

  @override
  String get newTextFileTitle => 'Nuevo archivo de texto';

  @override
  String get folderNameHint => 'Nombre de la carpeta';

  @override
  String get filenameHint => 'archivo.txt';

  @override
  String get newNameHint => 'Nuevo nombre';

  @override
  String get baseNameHint => 'Nombre base';

  @override
  String couldntCreateItem(String name) {
    return 'No se pudo crear \"$name\" — comprueba que el contenedor siga montado';
  }

  @override
  String couldntRenameSingle(String name) {
    return 'No se pudo renombrar \"$name\" — puede que ya exista un elemento con ese nombre';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No se pudieron renombrar $count elementos: $reason',
      one: 'No se pudo renombrar 1 elemento: $reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No se pudieron renombrar $count elementos',
      one: 'No se pudo renombrar 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize =>
      'Introduce un tamaño oculto válido mayor que 0';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter =>
      'El tamaño del volumen oculto debe ser menor que el del volumen externo';

  @override
  String get hiddenVolumeErrorTooLargeForContainer =>
      'El tamaño del volumen oculto es demasiado grande para el tamaño de este contenedor';

  @override
  String get hiddenVolumeErrorCredentialsRequired =>
      'Se requiere una contraseña oculta o archivo clave al crear un volumen oculto';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      'Las credenciales del volumen oculto (contraseña, PIM y archivos clave) no pueden ser idénticas a las del volumen externo.';

  @override
  String get vaultItemTypePassword => 'Contraseña';

  @override
  String get vaultItemTypePaymentCard => 'Tarjeta de pago';

  @override
  String get vaultItemTypeIdentity => 'Identidad';

  @override
  String get vaultItemTypeSecureNote => 'Nota segura';

  @override
  String get vaultItemTypeBankAccount => 'Cuenta bancaria';

  @override
  String get vaultItemTypeSoftwareLicense => 'Licencia de software';

  @override
  String get fieldUsernameEmail => 'Usuario / Correo electrónico';

  @override
  String get fieldPassword => 'Contraseña';

  @override
  String get fieldWebsiteUrl => 'URL del sitio web';

  @override
  String get fieldTotpSecret => 'Secreto TOTP (2FA)';

  @override
  String get fieldNotes => 'Notas';

  @override
  String get fieldCardholderName => 'Nombre del titular';

  @override
  String get fieldCardNumber => 'Número de tarjeta';

  @override
  String get fieldExpiryMMYY => 'Vencimiento (MM/AA)';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldIssuingBank => 'Banco emisor';

  @override
  String get fieldFullName => 'Nombre completo';

  @override
  String get fieldDateOfBirth => 'Fecha de nacimiento';

  @override
  String get fieldNationality => 'Nacionalidad';

  @override
  String get fieldPassportNumber => 'Número de pasaporte';

  @override
  String get fieldPassportExpiry => 'Vencimiento del pasaporte';

  @override
  String get fieldNationalIdSsn => 'DNI / Documento nacional';

  @override
  String get fieldDriversLicense => 'Carné de conducir';

  @override
  String get fieldAddress => 'Dirección';

  @override
  String get fieldPhone => 'Teléfono';

  @override
  String get fieldEmail => 'Correo electrónico';

  @override
  String get fieldNote => 'Nota';

  @override
  String get fieldBankName => 'Nombre del banco';

  @override
  String get fieldAccountHolder => 'Titular de la cuenta';

  @override
  String get fieldAccountNumber => 'Número de cuenta';

  @override
  String get fieldRoutingSortCode => 'Código de ruta / código de sucursal';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => 'Tipo de cuenta';

  @override
  String get fieldProductName => 'Nombre del producto';

  @override
  String get fieldLicenseKey => 'Clave de licencia';

  @override
  String get fieldRegisteredTo => 'Registrado a nombre de';

  @override
  String get fieldPurchaseDate => 'Fecha de compra';

  @override
  String get fieldExpiryRenewalDate => 'Fecha de vencimiento / renovación';

  @override
  String get fieldDownloadUrl => 'URL de descarga';

  @override
  String get fieldRegistrationEmail => 'Correo de registro';

  @override
  String get titleRequired => 'Se requiere un título';

  @override
  String newTypeTitle(String typeLabel) {
    return 'Nuevo $typeLabel';
  }

  @override
  String editItemTitle(String title) {
    return 'Editar $title';
  }

  @override
  String get save => 'Guardar';

  @override
  String typeNameHint(String typeLabel) {
    return 'Nombre de $typeLabel';
  }

  @override
  String get titleSectionLabel => 'Título';

  @override
  String get fieldsSectionLabel => 'Campos';

  @override
  String get encryptedStorageHint =>
      'Todos los campos se almacenan cifrados dentro del contenedor.';

  @override
  String copiedSuffix(String fieldLabel) {
    return '$fieldLabel copiado';
  }

  @override
  String get copy => 'Copiar';

  @override
  String get failedToSaveCheckMounted =>
      'Error al guardar — comprueba que el contenedor siga montado';

  @override
  String get discardChangesTitle => '¿Descartar cambios?';

  @override
  String get discardChangesMessage => 'Se perderán los cambios no guardados.';

  @override
  String get discard => 'Descartar';

  @override
  String get keepEditing => 'Seguir editando';

  @override
  String get deleteItemTitle => '¿Eliminar elemento?';

  @override
  String deleteItemMessage(String title) {
    return '\"$title\" se eliminará permanentemente de la bóveda.';
  }

  @override
  String get removeFromBookmarks => 'Quitar de marcadores';

  @override
  String get addToBookmarks => 'Añadir a marcadores';

  @override
  String get edit => 'Editar';

  @override
  String labelCopiedToClipboard(String label) {
    return '$label copiado al portapapeles';
  }

  @override
  String get noFieldsFilledIn =>
      'No hay campos rellenados.\nToca Editar para añadir detalles.';

  @override
  String get sectionLabelDetails => 'Detalles';

  @override
  String get sectionLabelInfo => 'Info';

  @override
  String get metaLabelType => 'Tipo';

  @override
  String get metaLabelCreated => 'Creado';

  @override
  String get metaLabelModified => 'Modificado';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return 'Copiar $fieldLabel';
  }

  @override
  String get readOnlyCantAddItemsTooltip =>
      'Solo lectura — no se pueden añadir elementos';

  @override
  String get extractArchive => 'Extraer archivo';

  @override
  String get newItemTooltip => 'Nuevo elemento';

  @override
  String get camera => 'Cámara';

  @override
  String get importFiles => 'Importar archivos';

  @override
  String get importFolder => 'Importar carpeta';

  @override
  String get secureItem => 'Elemento seguro';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archive Explorer';

  @override
  String get archiveExplorerPermissionTitle =>
      'Se necesita acceso al almacenamiento';

  @override
  String get archiveExplorerPermissionMessage =>
      'Permite el acceso a tus archivos para explorar y extraer archivos .zip de Descargas.';

  @override
  String get archiveExplorerGrantAccess => 'Conceder acceso';

  @override
  String get archiveExplorerEmptyTitle => 'No se encontraron archivos';

  @override
  String get archiveExplorerEmptyMessage =>
      'Los archivos zip que descargues aparecerán aquí.';

  @override
  String get archiveExplorerRefreshTooltip => 'Actualizar';

  @override
  String archiveExplorerEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get archiveExplorerExtractAll => 'Extraer todo';

  @override
  String get archiveExplorerExtracting => 'Extrayendo…';

  @override
  String archiveExplorerExtractSuccess(int count, String name) {
    return 'Se extrajeron $count archivos a Download/Extracted/$name';
  }

  @override
  String get archiveExplorerExtractFailed => 'No se pudo extraer ese archivo.';

  @override
  String get archiveExplorerOpenFailed => 'No se pudo abrir ese archivo.';

  @override
  String get archiveExplorerOpenArchive => 'Abrir archivo…';

  @override
  String get archiveExplorerUnresolvedPath =>
      'No se pudo acceder directamente a ese archivo. Prueba a elegir uno desde Descargas.';

  @override
  String get archiveExplorerExtractTo => 'Extraer a…';

  @override
  String get archiveExplorerPreview => 'Vista previa';

  @override
  String get archiveExplorerChoosingDestination => 'Eligiendo destino…';

  @override
  String get archiveExplorerNoDestinationChosen =>
      'No se eligió ningún destino.';

  @override
  String archiveExplorerExtractSuccessTo(int count, String path) {
    return 'Se extrajeron $count archivos a $path';
  }

  @override
  String get archiveBrowserEmptyTitle => 'Carpeta vacía';

  @override
  String get archiveBrowserEmptyMessage => 'Esta carpeta no contiene archivos.';

  @override
  String get archiveBrowserRoot => 'Archivo';

  @override
  String get archiveBrowserOpenFileFailed => 'No se pudo abrir ese archivo.';

  @override
  String get fileAssocInAppTextEditor => 'Editor de texto integrado';

  @override
  String get fileAssocInAppMediaViewer => 'Visor de medios integrado';

  @override
  String fileAssocAppPrefix(String name) {
    return 'App: $name';
  }

  @override
  String get fileAssocExternalApp => 'App externa';

  @override
  String get appSettingsTitle => 'Ajustes de la app';

  @override
  String get sectionSecurityPrivacy => 'Seguridad y privacidad';

  @override
  String get sectionAppearanceInterface => 'Apariencia e interfaz';

  @override
  String get sectionVaultFileHandling => 'Bóveda y gestión de archivos';

  @override
  String get masterPasswordTitle => 'Contraseña maestra';

  @override
  String get masterPasswordActiveSubtitle =>
      'Activa — toca el interruptor para quitarla';

  @override
  String get masterPasswordInactiveSubtitle =>
      'Requiere una contraseña para abrir la app';

  @override
  String get newPasswordLabel => 'Nueva contraseña';

  @override
  String get masterPasswordFieldLabel => 'Contraseña maestra';

  @override
  String get confirmPasswordLabel => 'Confirmar contraseña';

  @override
  String get update => 'Actualizar';

  @override
  String get setPassword => 'Establecer contraseña';

  @override
  String get biometricUnlockTitle => 'Desbloqueo biométrico';

  @override
  String get biometricUnlockSubtitle =>
      'Autentícate para montar el contenedor de forma segura';

  @override
  String get changeMasterPasswordTitle => 'Cambiar contraseña maestra';

  @override
  String get changeMasterPasswordSubtitle =>
      'Actualizar las credenciales de la contraseña maestra';

  @override
  String get autoLockContainersTitle => 'Bloqueo automático de contenedores';

  @override
  String get autoLockContainersSubtitle =>
      'Bloquea automáticamente las bóvedas abiertas tras un período de inactividad';

  @override
  String get autoLockTimeoutLabel => 'Tiempo de bloqueo automático';

  @override
  String get immediately => 'Inmediatamente';

  @override
  String nMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutos',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get blockScreenshotsTitle => 'Bloquear capturas de pantalla';

  @override
  String get blockScreenshotsSubtitle =>
      'Evita las capturas de pantalla y oculta la vista previa en apps recientes';

  @override
  String get keepVaultsRunningInBackgroundTitle =>
      'Mantener contenedores abiertos en segundo plano';

  @override
  String get keepVaultsRunningInBackgroundSubtitle =>
      'Muestra una notificación y mantiene las bóvedas abiertas disponibles después de salir de la app. Las claves de la bóveda permanecen en memoria hasta que se bloqueen.';

  @override
  String get notificationPermissionDeniedMessage =>
      'Permiso de notificaciones denegado. Las bóvedas seguirán abiertas, pero no se mostrará la notificación persistente.';

  @override
  String get discreteModeTitle => 'Modo Máscara';

  @override
  String get discreteModeActiveSubtitle =>
      'Activo — la app aparece actualmente como \"Archive Explorer\"';

  @override
  String get discreteModeInactiveSubtitle =>
      'Disfraza esta app como un explorador de archivos zip en la pantalla de inicio';

  @override
  String get enableDiscreteModeTitle => '¿Activar el Modo Máscara?';

  @override
  String get disableDiscreteModeTitle => '¿Desactivar el Modo Máscara?';

  @override
  String get enableDiscreteModeMessage =>
      'El icono y el nombre de la app en tu pantalla de inicio cambiarán a \"Archive Explorer\". Funcionará como explorador y extractor de archivos zip.\n\nPara acceder a tu bóveda, abre Archive Explorer y mantén el dedo sobre el título durante 3 segundos.';

  @override
  String get disableDiscreteModeMessage =>
      'El icono y el nombre de la app en tu pantalla de inicio volverán a ser \"Vault Explorer\".';

  @override
  String get enable => 'Activar';

  @override
  String get disable => 'Desactivar';

  @override
  String get discreteModeEnabledSnack =>
      'Modo Máscara activado. La app se cerrará — vuelve a abrirla desde el nuevo icono del lanzador.';

  @override
  String get discreteModeDisabledSnack =>
      'Modo Máscara desactivado. La app se cerrará — vuelve a abrirla desde el nuevo icono del lanzador.';

  @override
  String get failedToChangeDiscreteMode => 'Error al cambiar el Modo Máscara';

  @override
  String get cacheDerivedKeysTitle =>
      'Guardar en caché claves derivadas por defecto';

  @override
  String get cacheDerivedKeysSubtitle =>
      'Almacena material de claves derivadas en Keystore para desbloqueos más rápidos';

  @override
  String get appThemeLabel => 'Tema de la app';

  @override
  String get systemDefault => 'Predeterminado del sistema';

  @override
  String get lightTheme => 'Tema claro';

  @override
  String get darkTheme => 'Tema oscuro';

  @override
  String get useMaterialYouTitle => 'Usar Material You';

  @override
  String get useMaterialYouSubtitle =>
      'Ajusta los colores de la app a tu fondo de pantalla (Android 12+)';

  @override
  String get sortContainersByLabel => 'Ordenar contenedores por';

  @override
  String get swapCardSwipeActionsTitle =>
      'Invertir acciones de deslizamiento de tarjetas';

  @override
  String get swapCardSwipeActionsSubtitle =>
      'Muestra Editar a la izquierda y Quitar a la derecha al deslizar tarjetas';

  @override
  String get swipeGestureHintTitle => 'Sugerencia de gesto de deslizamiento';

  @override
  String get swipeGestureHintSubtitle =>
      'Muestra la animación de vista previa de tarjeta en el primer contenedor';

  @override
  String get autoOpenOnUnlockTitle => 'Abrir automáticamente al desbloquear';

  @override
  String get autoOpenOnUnlockActiveSubtitle =>
      'Abre automáticamente tras desbloquear una bóveda';

  @override
  String get autoOpenOnUnlockInactiveSubtitle =>
      'Solo desbloquea la bóveda y permanece en el panel principal';

  @override
  String get enableJsHtmlTitle => 'Activar JavaScript en el visor HTML';

  @override
  String get jsEnabledSubtitle =>
      'JavaScript activado para archivos HTML locales';

  @override
  String get jsDisabledSubtitle =>
      'JavaScript desactivado para archivos HTML locales';

  @override
  String get fastStorageAccessTitle => 'Acceso rápido al almacenamiento';

  @override
  String get fastStorageAccessGrantedSubtitle =>
      'Acceso a todos los archivos concedido (velocidad máxima)';

  @override
  String get fastStorageAccessNotGrantedSubtitle =>
      'Concede el acceso a todos los archivos en los ajustes del sistema para obtener la velocidad óptima';

  @override
  String get enableFastStorageAccessTitle =>
      'Activar acceso rápido al almacenamiento';

  @override
  String get enableFastStorageAccessMessage =>
      'Conceder \"Acceso a todos los archivos\" permite a Vault Explorer realizar operaciones de archivo POSIX directas, acelerando el rendimiento de las bóvedas de carpeta hasta 1000 veces.';

  @override
  String get disableStorageAccessTitle => 'Desactivar acceso al almacenamiento';

  @override
  String get disableStorageAccessMessage =>
      'Android requiere que \"Acceso a todos los archivos\" se desactive en los ajustes del sistema. ¿Quieres abrir los ajustes para desactivarlo?';

  @override
  String get enableStoragePermissionLegacyTitle =>
      'Permitir acceso al almacenamiento';

  @override
  String get enableStoragePermissionLegacyMessage =>
      'Vault Explorer necesita permiso de almacenamiento para realizar operaciones de archivo directas, acelerando el rendimiento de las bóvedas de carpeta. Android te pedirá confirmación a continuación.';

  @override
  String get disableStoragePermissionLegacyMessage =>
      'Android requiere que el permiso de almacenamiento se desactive en los ajustes del sistema. ¿Quieres abrir los ajustes para desactivarlo?';

  @override
  String get openSettings => 'Abrir ajustes';

  @override
  String get androidFileProviderTitle => 'Proveedor de archivos de Android';

  @override
  String get androidFileProviderSubtitle =>
      'Exponer nuevos contenedores al selector de archivos de Android por defecto';

  @override
  String get thumbnailCachingDefaultLabel =>
      'Caché de miniaturas (predeterminado)';

  @override
  String get thumbnailQualityDefaultLabel =>
      'Calidad de miniaturas (predeterminado)';

  @override
  String get fileAssociationsHeader => 'Asociaciones de archivos';

  @override
  String get noFileAssociationsYet =>
      'Aún no hay asociaciones de archivos recordadas. Se te preguntará al abrir archivos.';

  @override
  String get defaultActionsHeader =>
      'Acciones predeterminadas al abrir archivos no estándar:';

  @override
  String get removeAssociationTooltip => 'Quitar asociación';

  @override
  String get sectionBackupRestore => 'Copia de seguridad';

  @override
  String get exportSettingsTitle => 'Exportar ajustes';

  @override
  String get exportSettingsSubtitle =>
      'Guarda los ajustes de la app y el diseño del gestor de archivos en un archivo';

  @override
  String get importSettingsTitle => 'Importar ajustes';

  @override
  String get importSettingsSubtitle =>
      'Restaura los ajustes de la app y el diseño del gestor de archivos desde un archivo';

  @override
  String get importSettingsConfirmTitle => '¿Importar ajustes?';

  @override
  String get importSettingsConfirmMessage =>
      'Esto reemplazará tus ajustes actuales de la app y el diseño del gestor de archivos. No se puede deshacer.';

  @override
  String get exportSettingsSuccessMessage => 'Ajustes exportados';

  @override
  String get importSettingsSuccessMessage => 'Ajustes importados';

  @override
  String get exportSettingsErrorMessage =>
      'No se pudieron exportar los ajustes';

  @override
  String get importSettingsInvalidFileMessage =>
      'Ese archivo no es una exportación de ajustes válida';

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
  String get retryButton => 'Reintentar';

  @override
  String get aboutAppTitle => 'Acerca de VaultExplorer';

  @override
  String versionInfoSubtitle(String version) {
    return 'Versión $version · Licencias de código abierto y detalles';
  }

  @override
  String get failedToSaveSettings => 'Error al guardar los ajustes';

  @override
  String get masterPasswordSetSnack => 'Contraseña maestra establecida';

  @override
  String get passwordCannotBeEmpty => 'La contraseña no puede estar vacía';

  @override
  String get atLeast4CharsRequired => 'Se requieren al menos 4 caracteres';

  @override
  String get passwordsDoNotMatch => 'Las contraseñas no coinciden';

  @override
  String get failedToHashPassword =>
      'Error al aplicar hash a la contraseña — inténtalo de nuevo';

  @override
  String get languageLabel => 'Idioma';

  @override
  String get biometricNotAvailable =>
      'La biometría no está disponible en este dispositivo';

  @override
  String get unlockVaultExplorerReason => 'Desbloquear VaultExplorer';

  @override
  String biometricErrorWithCode(String code) {
    return 'Error biométrico: $code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds segundos',
      one: '1 segundo',
    );
    return 'Demasiados intentos fallidos. Vuelve a intentarlo en $_temp0.';
  }

  @override
  String get enterMasterPasswordPrompt => 'Introduce tu contraseña maestra';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts intentos fallidos',
      one: '1 intento fallido',
    );
    return 'Contraseña incorrecta. Bloqueado durante ${seconds}s debido a $_temp0.';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts intentos fallidos',
      one: '1 intento fallido',
    );
    return 'Contraseña incorrecta ($_temp0).';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle =>
      'Introduce tu contraseña maestra para continuar';

  @override
  String get masterPasswordFieldLabelTitleCase => 'Contraseña maestra';

  @override
  String get unlock => 'Desbloquear';

  @override
  String get useBiometric => 'Usar biometría';

  @override
  String get connectAtLeast4Dots => 'Conecta al menos 4 puntos';

  @override
  String get patternsDontMatch =>
      'Los patrones no coinciden — inténtalo de nuevo';

  @override
  String get drawUnlockPatternTitle => 'Dibuja el patrón de desbloqueo';

  @override
  String get confirmPatternTitle => 'Confirma tu patrón';

  @override
  String get drawSamePatternAgain => 'Dibuja el mismo patrón otra vez';

  @override
  String removedFromListSnack(String name) {
    return 'Se quitó \"$name\" de la lista';
  }

  @override
  String get clearRecentHistoryTitle => '¿Borrar el historial reciente?';

  @override
  String get clearRecentHistoryMessage =>
      'Esto eliminará todos los documentos recientes de tu lista. Los archivos reales en tu dispositivo no se verán afectados.';

  @override
  String get clearAll => 'Borrar todo';

  @override
  String get recentHistoryClearedSnack => 'Historial reciente borrado';

  @override
  String get moreOptionsTooltip => 'Más opciones';

  @override
  String get clearHistoryMenuItem => 'Borrar historial';

  @override
  String get openPdfFile => 'Abrir archivo PDF';

  @override
  String get noDocumentsYetTitle => 'Aún no hay documentos';

  @override
  String get openPdfToStartMessage =>
      'Abre un PDF desde tu dispositivo para empezar a leer.';

  @override
  String get removeFromListMenuItem => 'Quitar de la lista';

  @override
  String get justNow => 'Justo ahora';

  @override
  String minutesAgo(int count) {
    return 'hace ${count}m';
  }

  @override
  String hoursAgo(int count) {
    return 'hace ${count}h';
  }

  @override
  String daysAgo(int count) {
    return 'hace ${count}d';
  }

  @override
  String get usbDriveDisconnectedLocked =>
      'Unidad USB desconectada — contenedor bloqueado';

  @override
  String get containerAlreadyMounted => 'Este contenedor ya está montado.';

  @override
  String get noVaultFolderFormatDetected =>
      'No se encontró masterkey.cryptomator, gocryptfs.conf ni cryfs.config en esa carpeta.';

  @override
  String get savedContainerSettingsNotFound =>
      'No se encontraron los ajustes guardados de este contenedor.';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return 'No se pudo actualizar la ubicación del contenedor: $error';
  }

  @override
  String filePickerFailed(String error) {
    return 'Error del selector de archivos: $error';
  }

  @override
  String get selectContainerFirst => 'Selecciona un contenedor primero';

  @override
  String get passwordOrKeyfilesRequired =>
      'Se requiere una contraseña o archivos clave';

  @override
  String get slowPerformanceWarningTitle => 'Advertencia de rendimiento lento';

  @override
  String get slowPerformanceWarningMessage =>
      'El acceso directo al almacenamiento está desactivado actualmente.\n\nCryFS almacena los archivos en miles de bloques pequeños. Abrir bóvedas CryFS no vacías mediante Android SAF será muy lento.\n\n¿Quieres abrir los ajustes para conceder \"Acceso a todos los archivos\" y obtener mayor velocidad?';

  @override
  String get unlockAnyway => 'Desbloquear de todos modos';

  @override
  String get defaultVaultName => 'Bóveda';

  @override
  String get defaultContainerName => 'Contenedor';

  @override
  String get incorrectPasswordOrInvalidVault =>
      'Contraseña incorrecta o bóveda no válida';

  @override
  String get incorrectPasswordOrInvalidContainer =>
      'Contraseña incorrecta o contenedor no válido';

  @override
  String get genericUnknownError => 'Error desconocido';

  @override
  String get decryptingLabel => 'Descifrando…';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return 'Probando ranura de clave $attempted de $total…';
  }

  @override
  String get luksKeyslotProgressUnknown => 'Probando ranura de clave…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return 'Verificando credencial $attempted de $total…';
  }

  @override
  String get bitlockerCredentialProgressUnknown => 'Verificando credencial…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return 'Probando $algo ($slotName)…';
  }

  @override
  String get unlockContainerLabel => 'Desbloquear contenedor';

  @override
  String get mountContainerTitle => 'Montar contenedor';

  @override
  String get containerFileSegmentLabel => 'Archivo contenedor';

  @override
  String get folderVaultSegmentLabel => 'Bóveda de carpeta';

  @override
  String formatContainerLabel(String format) {
    return 'Contenedor $format';
  }

  @override
  String formatVaultLabel(String format) {
    return 'Bóveda $format';
  }

  @override
  String formatDriveLabel(String format) {
    return 'Unidad $format';
  }

  @override
  String get encryptedContainerLabel => 'Contenedor cifrado';

  @override
  String get tapToSelectVaultFolder =>
      'Toca para seleccionar la carpeta de la bóveda…';

  @override
  String get tapToSelectContainerFile =>
      'Toca para seleccionar el archivo contenedor…';

  @override
  String get containerMissingTitle => 'Contenedor no encontrado';

  @override
  String get filePathCouldNotBeResolved =>
      'No se pudo resolver la ruta del archivo';

  @override
  String get containerMissingExplanation =>
      'Es posible que el archivo contenedor se haya movido, eliminado, o que su almacenamiento de origen esté desconectado actualmente.';

  @override
  String get retryButtonLabel => 'Reintentar';

  @override
  String get locateFileButtonLabel => 'Localizar archivo';

  @override
  String get authenticateToMountSubtitle =>
      'Autentícate para montar el contenedor de forma segura';

  @override
  String get usePasswordButtonLabel => 'Usar contraseña';

  @override
  String get authenticateButtonLabel => 'Autenticar';

  @override
  String get drawUnlockPatternCardTitle => 'Dibuja el patrón de desbloqueo';

  @override
  String get wrongPatternTryAgain => 'Patrón incorrecto — inténtalo de nuevo';

  @override
  String get connectYourPatternSequence => 'Conecta la secuencia de tu patrón';

  @override
  String get usePasswordInsteadButtonLabel => 'Usar contraseña en su lugar';

  @override
  String get passwordHintFolderVault => 'Introduce la contraseña de la bóveda';

  @override
  String get passwordHintBitlocker =>
      'Introduce la contraseña o la clave de recuperación';

  @override
  String get passwordHintContainer => 'Introduce la contraseña del contenedor';

  @override
  String get usingSavedPasswordTooltip => 'Usando contraseña guardada';

  @override
  String get luksKeyfileReplacesPasswordNote =>
      'En los contenedores LUKS, el archivo clave reemplaza a la contraseña.';

  @override
  String get readOnlyModeUsbSubtitle =>
      'Monta sin permitir cambios en esta unidad';

  @override
  String get readOnlyModeContainerSubtitle =>
      'Monta sin permitir cambios en este contenedor';

  @override
  String get rememberContainerLabel => 'Recordar contenedor';

  @override
  String get rememberContainerSubtitle =>
      'Fija el contenedor en el panel principal para acceso rápido';

  @override
  String get cancelUnlockButtonLabel => 'Cancelar desbloqueo';

  @override
  String get biometricSubjectContainer => 'contenedor';

  @override
  String get biometricSubjectUsbDrive => 'unidad USB';

  @override
  String get usbNoSavedCredentialsMessage =>
      'No se encontró ninguna contraseña guardada. Introdúcela manualmente.';

  @override
  String get decryptingDriveLabel => 'Descifrando unidad…';

  @override
  String get usbDeviceAlreadyActiveMounted =>
      'Este dispositivo USB ya está activo y montado.';

  @override
  String reconnectUsbDriveTitle(String label) {
    return 'Reconectar \"$label\"';
  }

  @override
  String get unlockUsbDriveTitle => 'Desbloquear unidad USB';

  @override
  String get noUsbStorageDetectedTitle => 'No se detectó almacenamiento USB';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return 'Autentícate para desbloquear $subject';
  }

  @override
  String get noPatternConfiguredMessage =>
      'No hay ningún patrón configurado. Introduce la contraseña manualmente.';

  @override
  String patternLockedForSeconds(int seconds) {
    return 'Demasiados intentos fallidos. Bloqueado durante ${seconds}s.';
  }

  @override
  String get initSecureCredsBiometricMessage =>
      'Inicializando credenciales seguras. Desbloquea manualmente una vez para autorizar el acceso biométrico.';

  @override
  String get initSecureCredsPatternMessage =>
      'Inicializando credenciales seguras. Desbloquea manualmente una vez para autorizar el acceso por patrón.';

  @override
  String get mountExistingContainerTitle => 'Montar contenedor existente';

  @override
  String get mountExistingContainerSubtitle =>
      'Desbloquea un archivo contenedor que ya tienes';

  @override
  String get mountSplitContainerTitle => 'Montar contenedor dividido';

  @override
  String get mountSplitContainerSubtitle =>
      'Desbloquea un contenedor dividido directamente, sin unirlo antes';

  @override
  String get mountUsbDriveTitle => 'Montar unidad USB';

  @override
  String get mountUsbDriveSubtitle =>
      'Desbloquea un contenedor en una unidad flash OTG';

  @override
  String get formatUsbDriveTitle => 'Formatear unidad USB';

  @override
  String get formatUsbDriveSubtitle =>
      'Borra una unidad y crea en ella un nuevo contenedor cifrado';

  @override
  String get createNewContainerTitle => 'Crear nuevo contenedor';

  @override
  String get createNewContainerSubtitle =>
      'Formatea una bóveda cifrada completamente nueva';

  @override
  String get lockBeforeRemovingWarning =>
      'Bloquea el contenedor antes de quitarlo.';

  @override
  String get settingsTooltip => 'Ajustes';

  @override
  String get addVaultFabLabel => 'Añadir bóveda';

  @override
  String removedLabelUndo(String label) {
    return 'Se quitó \"$label\"';
  }

  @override
  String get undo => 'Deshacer';

  @override
  String get pdfViewerNoSourceProvided =>
      'No se proporcionó ninguna fuente de PDF.';

  @override
  String get pdfViewerFileEmpty =>
      'El archivo PDF está vacío o no se puede leer.';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return 'Error al comprobar el tamaño del archivo PDF: $error';
  }

  @override
  String get pdfViewerErrorLoadingTitle => 'Error al cargar el PDF';

  @override
  String get pdfViewerNoDocumentLoaded =>
      'No hay ningún documento PDF cargado.';

  @override
  String get add => 'Añadir';

  @override
  String get reset => 'Restablecer';

  @override
  String couldNotExpose(String name) {
    return 'No se pudo exponer \"$name\".';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return '\"$name\" ya está disponible para otras apps.';
  }

  @override
  String couldNotUnmount(String name) {
    return 'No se pudo desmontar \"$name\".';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se fijaron $count elementos',
      one: 'Se fijó 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se desfijaron $count elementos',
      one: 'Se desfijó 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning =>
      'Montaje de solo lectura — las miniaturas se mostrarán pero no se guardarán dentro del contenedor durante esta sesión.';

  @override
  String failedLoadingFolder(String type) {
    return 'Error al cargar la carpeta: $type';
  }

  @override
  String failedToReadArchive(String type) {
    return 'Error al leer el archivo: $type';
  }

  @override
  String archiveFormatNotSupported(String ext) {
    return 'El formato de archivo .$ext aún no es compatible';
  }

  @override
  String get failedToReadFileFromArchive =>
      'Error al leer el archivo desde el paquete comprimido';

  @override
  String failedToExtractFile(String type) {
    return 'Error al extraer el archivo: $type';
  }

  @override
  String get failedToReadSecureItem => 'Error al leer el elemento seguro';

  @override
  String get openFileDialogTitle => 'Abrir archivo';

  @override
  String chooseHowToOpen(String name) {
    return 'Elige cómo abrir \"$name\":';
  }

  @override
  String get playVideoAudioViewImageInApp =>
      'Reproducir vídeo/audio o ver imagen en la app';

  @override
  String get viewEditTextMarkdownCode => 'Ver/editar texto, markdown, código';

  @override
  String get sendFileToThirdPartyApp => 'Enviar archivo a una app externa';

  @override
  String get openAsEllipsis => 'Abrir como…';

  @override
  String get chooseFileTypeToOpenAs =>
      'Elige el tipo de archivo para abrir como';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return 'Recordar siempre la elección para archivos .$ext';
  }

  @override
  String get alwaysRememberChoiceNoExt =>
      'Recordar siempre la elección para archivos sin extensión';

  @override
  String get openAsDialogTitle => 'Abrir como';

  @override
  String get mimeTypeText => 'Texto';

  @override
  String get mimeTypeImage => 'Imagen';

  @override
  String get mimeTypeVideo => 'Vídeo';

  @override
  String get mimeTypeAudio => 'Audio';

  @override
  String get mimeTypeArchive => 'Archivo comprimido';

  @override
  String get mimeTypeOther => 'Otro';

  @override
  String get scanningSubfoldersForMedia => 'Buscando medios en subcarpetas…';

  @override
  String get noMediaFilesFoundRecursive =>
      'No se encontraron archivos multimedia en esta carpeta ni en sus subcarpetas';

  @override
  String failedToScanSubfolders(String error) {
    return 'Error al buscar en las subcarpetas: $error';
  }

  @override
  String get noAppFoundForFileType =>
      'No se encontró ninguna app para este tipo de archivo';

  @override
  String couldNotOpenFile(String name) {
    return 'No se pudo abrir \"$name\"';
  }

  @override
  String get readOnlyCantMove =>
      'Este contenedor está montado en modo de solo lectura — los elementos no se pueden mover desde aquí.';

  @override
  String get readOnlyCantPaste =>
      'Este contenedor está montado en modo de solo lectura — los elementos no se pueden pegar aquí.';

  @override
  String get clipboardSourceInvalid =>
      'El origen del portapapeles no es válido';

  @override
  String get crossContainerPasteNotConfigured =>
      'El pegado entre contenedores no está configurado.';

  @override
  String get crossContainerPasteRequiresBothMounted =>
      'El pegado entre contenedores requiere que ambos contenedores permanezcan montados.';

  @override
  String get readOnlyCantDelete =>
      'Este contenedor está montado en modo de solo lectura — los elementos no se pueden eliminar.';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se eliminaron $count elementos',
      one: 'Se eliminó 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String deletedWithFailures(int deleted, int failed) {
    return '$deleted eliminados · $failed con errores';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se exportaron $count archivos',
      one: 'Se exportó 1 archivo',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed => 'Exportación cancelada o fallida';

  @override
  String exportError(String type) {
    return 'Error de exportación: $type';
  }

  @override
  String get deleteOriginalTitle => '¿Eliminar el original?';

  @override
  String get deleteOriginalFolderMessage =>
      '¿Eliminar la carpeta original de tu dispositivo ahora que se ha importado?';

  @override
  String get deleteOriginalFilesMessage =>
      '¿Eliminar los archivos originales de tu dispositivo ahora que se han importado?';

  @override
  String get keepOriginal => 'Conservar original';

  @override
  String get deleteOriginalButton => 'Eliminar original';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se eliminaron $count elementos originales',
      one: 'Se eliminó 1 elemento original',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals =>
      'No se pudieron eliminar los originales';

  @override
  String get videoCapturedEncrypted => 'Vídeo capturado y cifrado';

  @override
  String get photoCapturedEncrypted => 'Foto capturada y cifrada';

  @override
  String cameraCaptureFailed(String type) {
    return 'Error al capturar con la cámara: $type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return '¿Extraer todos los archivos a la carpeta \"$folder\"?';
  }

  @override
  String get extract => 'Extraer';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se extrajeron $count archivos',
      one: 'Se extrajo 1 archivo',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return 'Error al extraer: $type';
  }

  @override
  String get closeSearchTooltip => 'Cerrar búsqueda';

  @override
  String get searchInThisFolderTooltip => 'Buscar en esta carpeta';

  @override
  String get playMediaHereTooltip => 'Reproducir medios aquí';

  @override
  String get rootFolderLabel => 'Raíz';

  @override
  String folderPickerFailed(String error) {
    return 'Error del selector de carpetas: $error';
  }

  @override
  String get addAVaultTitle => 'Añadir una bóveda';

  @override
  String get selectEmptyDestinationFolderFirst =>
      'Selecciona primero una carpeta de destino vacía';

  @override
  String get passwordRequired => 'Se requiere una contraseña';

  @override
  String get vaultCreatedSuccessfully => 'Bóveda creada correctamente.';

  @override
  String get vaultCreationFailedEmptyFolder =>
      'Error al crear la bóveda — asegúrate de que la carpeta seleccionada esté vacía.';

  @override
  String get unknownErrorOccurred => 'Se produjo un error desconocido';

  @override
  String get containerNameRequired =>
      'Se requiere un nombre para el contenedor';

  @override
  String get enterValidSizeGreaterThanZero =>
      'Introduce un tamaño válido mayor que 0';

  @override
  String get passwordOrKeyfileRequired =>
      'Se requiere una contraseña o al menos un archivo clave';

  @override
  String get standardVolumePasswordsDoNotMatch =>
      'Las contraseñas del volumen estándar no coinciden';

  @override
  String get hiddenVolumePasswordsDoNotMatch =>
      'Las contraseñas del volumen oculto no coinciden';

  @override
  String get containerFileCreatedSuccessfully =>
      'Archivo contenedor creado correctamente.';

  @override
  String get containerCreationCancelledOrFailed =>
      'Creación del contenedor cancelada o fallida.';

  @override
  String get vaultKindContainerFile => 'Archivo contenedor';

  @override
  String get vaultKindFolderVault => 'Bóveda de carpeta';

  @override
  String get formatFileSystemLabel => 'Formatear sistema de archivos';

  @override
  String get standardVolumeHeader => 'Volumen estándar';

  @override
  String get containerFormatLabel => 'Formato del contenedor';

  @override
  String get fileNameLabel => 'Nombre del archivo';

  @override
  String get containerSizeLabel => 'Tamaño del contenedor';

  @override
  String get unitLabel => 'Unidad';

  @override
  String get passwordFieldLabel => 'Contraseña';

  @override
  String get confirmPasswordFieldLabelTitleCase => 'Confirmar contraseña';

  @override
  String get hiddenVolumeHeader => 'Volumen oculto';

  @override
  String get createHiddenVolumeToggleTitle => 'Crear volumen oculto';

  @override
  String get createInvisibleSecondaryVolume =>
      'Crea un volumen secundario invisible';

  @override
  String get setOuterPasswordFirstToEnable =>
      'Establece primero la contraseña o archivos clave externos para activarlo';

  @override
  String get hiddenPasswordLabel => 'Contraseña oculta';

  @override
  String get confirmHiddenPasswordLabel => 'Confirmar contraseña oculta';

  @override
  String get hiddenSizeLabel => 'Tamaño oculto';

  @override
  String get unitMbMegabytes => 'MB (Megabytes)';

  @override
  String get unitGbGigabytes => 'GB (Gigabytes)';

  @override
  String get hiddenFileSystemLabel => 'Sistema de archivos oculto';

  @override
  String get vaultFormatLabel => 'Formato de la bóveda';

  @override
  String get gocryptfsCipherLabel => 'Cifrado de contenido';

  @override
  String get cryfsCipherLabel => 'Cifrado de contenido';

  @override
  String get cryfsBlockSizeLabel => 'Tamaño de bloque';

  @override
  String get destinationFolderLabel => 'Carpeta de destino';

  @override
  String get selectEmptyFolderLabel => 'Selecciona una carpeta vacía';

  @override
  String get tapToChooseVaultLocation =>
      'Toca para elegir dónde se creará la bóveda…';

  @override
  String get folderVaultLimitationsNote =>
      'Las bóvedas de carpeta no admiten archivos clave, PIM, volúmenes ocultos ni elección de cifrado VeraCrypt/LUKS.';

  @override
  String get createVaultButton => 'Crear bóveda';

  @override
  String get createContainerButton => 'Crear contenedor';

  @override
  String get vaultCreationInProgressWait =>
      'Creación de la bóveda en curso. Espera un momento.';

  @override
  String get containerCreationInProgressWait =>
      'Creación del contenedor en curso. Espera un momento.';

  @override
  String get createEncryptedVaultTitle => 'Crear bóveda cifrada';

  @override
  String get createEncryptedContainerTitle => 'Crear contenedor cifrado';

  @override
  String get unitMbShort => 'MB';

  @override
  String get unitGbShort => 'GB';

  @override
  String failedToListUsbDevices(String error) {
    return 'Error al listar los dispositivos USB: $error';
  }

  @override
  String get usbPermissionDenied => 'Permiso USB denegado';

  @override
  String get couldNotReadDriveCapacity =>
      'No se pudo leer la capacidad de la unidad — introduce el tamaño manualmente.';

  @override
  String get selectUsbDriveFirst => 'Selecciona primero una unidad USB';

  @override
  String eraseDeviceTitle(String name) {
    return '¿Borrar \"$name\"?';
  }

  @override
  String get eraseDeviceMessage =>
      'Esto borrará permanentemente todo lo que hay actualmente en esta unidad USB y lo reemplazará con un nuevo contenedor cifrado. Esta acción no se puede deshacer.';

  @override
  String get eraseAndCreateButton => 'Borrar y crear';

  @override
  String get usbPermissionRequiredToContinue =>
      'Se requiere permiso USB para continuar';

  @override
  String get usbContainerCreatedSnack =>
      'Contenedor USB creado. Usa \"Montar unidad USB\" para desbloquearlo.';

  @override
  String get usbContainerCreationFailed => 'Error al crear el contenedor USB.';

  @override
  String get usbStandardVolumeSectionHeader => 'Unidad USB y volumen estándar';

  @override
  String get formattingErasesEverythingWarning =>
      'Formatear borra todo lo que hay actualmente en la unidad seleccionada.';

  @override
  String get selectUsbDriveLabel => 'Seleccionar unidad USB';

  @override
  String get noUsbStorageDetected => 'No se detectó almacenamiento USB';

  @override
  String get connectOtgDriveToFormat =>
      'Conecta una unidad OTG para formatearla';

  @override
  String get refreshListButton => 'Actualizar lista';

  @override
  String get readyToFormat => 'Listo para formatear';

  @override
  String get permissionRequired => 'Se requiere permiso';

  @override
  String get readingDriveCapacity => 'Leyendo la capacidad de la unidad…';

  @override
  String get mustNotExceedDriveCapacity =>
      'No debe superar la capacidad real de la unidad.';

  @override
  String get quickFormatTitle => 'Formato rápido';

  @override
  String get quickFormatDescription =>
      'Omite el relleno con ceros de la unidad. Más rápido, pero no borra de forma segura los datos anteriores.';

  @override
  String get eraseAndCreateContainerButton => 'Borrar y crear contenedor';

  @override
  String get usbContainerCreationInProgressWait =>
      'Creación del contenedor en curso. Espera un momento.';

  @override
  String get formatUsbDriveScreenTitle => 'Formatear unidad USB';

  @override
  String get playlistTransitionAnimationLabel =>
      'Animación de transición de la lista de reproducción';

  @override
  String get playlistTransitionSlideLabel => 'Deslizar (predeterminado)';

  @override
  String get playlistTransitionFadeLabel => 'Desvanecer';

  @override
  String get playlistTransitionZoomLabel => 'Zoom y escala';

  @override
  String get playlistTransitionDepthLabel => 'Pila de profundidad';

  @override
  String get playlistTransitionCubeLabel => 'Cubo 3D';

  @override
  String get playlistTransitionFlipLabel => 'Giro 3D';

  @override
  String get unlockVaultTitle => 'Desbloquear bóveda';

  @override
  String get openContainerTitle => 'Abrir contenedor';

  @override
  String get selectContainerFileOrFolder => 'Selecciona archivo o carpeta';

  @override
  String get readOnlyModeLabel => 'Modo de solo lectura';

  @override
  String get readOnlyModeSubtitle =>
      'Evita cualquier operación de escritura o modificación en la bóveda';

  @override
  String get selectUsbDeviceLabel => 'Seleccionar dispositivo USB';

  @override
  String get noUsbDevicesFound =>
      'No se encontraron dispositivos de almacenamiento USB compatibles';

  @override
  String get containerConfigTitle => 'Configuración de la bóveda';

  @override
  String get changePasswordTitle => 'Cambiar contraseña';

  @override
  String get confirmNewPasswordLabel => 'Confirmar nueva contraseña';

  @override
  String get cameraCaptureTitle => 'Cámara de la bóveda';

  @override
  String get takingPhoto => 'Capturando foto…';

  @override
  String get savingToVault => 'Guardando en la bóveda…';

  @override
  String get noVaultSelected => 'No se seleccionó ninguna bóveda';

  @override
  String get mediaDiagnosticsTitle => 'Diagnóstico de medios';

  @override
  String get advancedViewerSettingsTitle => 'Ajustes del visor';

  @override
  String get textEditorSaveConfirmTitle => 'Cambios no guardados';

  @override
  String get textEditorSaveConfirmMessage =>
      '¿Quieres guardar los cambios antes de cerrar?';

  @override
  String get saveAndClose => 'Guardar y cerrar';

  @override
  String get discardChanges => 'Descartar cambios';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos seleccionados',
      one: '1 elemento seleccionado',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'Seleccionar todo';

  @override
  String get deselectAll => 'Deseleccionar todo';

  @override
  String get sortOptionsTitle => 'Ordenar archivos';

  @override
  String get layoutModeList => 'Vista de lista';

  @override
  String get layoutModeGrid => 'Vista de cuadrícula';

  @override
  String get layoutModeMasonry => 'Mosaico';

  @override
  String get fileOperationsTitle => 'Operaciones de archivos';

  @override
  String get conflictResolutionTitle => 'Conflicto de archivo';

  @override
  String get replaceExistingFile => 'Reemplazar archivo existente';

  @override
  String get keepBothFiles => 'Conservar ambos (renombrar el nuevo archivo)';

  @override
  String get skipFile => 'Omitir este archivo';

  @override
  String get noVaultsFoundTitle => 'No se encontraron bóvedas';

  @override
  String get noVaultsFoundSubtitle =>
      'Crea un nuevo contenedor cifrado o añade una bóveda existente para empezar.';

  @override
  String get addExistingVaultButton => 'Añadir bóveda existente';

  @override
  String get sortContainersModeManual => 'Manual (arrastrar para reordenar)';

  @override
  String get sortContainersModeUnlockStatus =>
      'Estado de desbloqueo (desbloqueados primero)';

  @override
  String get sortContainersModeNameAZ => 'Nombre (A–Z)';

  @override
  String get sortContainersModeNameZA => 'Nombre (Z–A)';

  @override
  String get sortContainersModeNewest => 'Más recientes primero';

  @override
  String get sortContainersModeOldest => 'Más antiguos primero';

  @override
  String get thumbnailCacheAppCacheLabel => 'Caché de la app';

  @override
  String get thumbnailCacheAppCacheDesc =>
      'Almacenado cifrado en la caché de la app. Rápido; se borra automáticamente si hay poco espacio.';

  @override
  String get thumbnailCacheInContainerLabel => 'Dentro del contenedor';

  @override
  String get thumbnailCacheInContainerDesc =>
      'Almacenado dentro del contenedor cifrado. Protegido por el propio contenedor, pero las escrituras son más lentas.';

  @override
  String get thumbnailCacheDisabledLabel => 'Desactivado';

  @override
  String get thumbnailCacheDisabledDesc =>
      'Sin caché en disco. Las miniaturas se regeneran en cada carga.';

  @override
  String get unlockContainerTitle => 'Desbloquear contenedor';

  @override
  String get containerFileSegment => 'Archivo contenedor';

  @override
  String get folderVaultSegment => 'Bóveda de carpeta';

  @override
  String get enableButtonLabel => 'Activar';

  @override
  String get retryButtonLabelShort => 'Reintentar';

  @override
  String get locateFileButton => 'Localizar archivo';

  @override
  String get authenticateButton => 'Autenticar';

  @override
  String get cancelUnlockButton => 'Cancelar desbloqueo';

  @override
  String tryingKeyslotProgress(int attempted, int total) {
    return 'Probando ranura de clave $attempted de $total…';
  }

  @override
  String get tryingKeyslotSingle => 'Probando ranura de clave…';

  @override
  String verifyingCredentialProgress(int attempted, int total) {
    return 'Verificando credencial $attempted de $total…';
  }

  @override
  String get verifyingCredentialSingle => 'Verificando credencial…';

  @override
  String tryingAlgoSlot(String algo, String slotName) {
    return 'Probando $algo ($slotName)…';
  }

  @override
  String get hiddenVolumeSlotName => 'Volumen oculto';

  @override
  String get standardVolumeSlotName => 'Volumen estándar';

  @override
  String get containerMissingSubtitle =>
      'No se pudo resolver la ruta del archivo';

  @override
  String get containerMissingBody =>
      'Es posible que el archivo contenedor se haya movido, eliminado, o que su almacenamiento de origen esté desconectado actualmente.';

  @override
  String get connectPatternSequence => 'Conecta la secuencia de tu patrón';

  @override
  String get passwordLabel => 'Contraseña';

  @override
  String get enterVaultPasswordHint => 'Introduce la contraseña de la bóveda';

  @override
  String get enterBitlockerPasswordHint =>
      'Introduce la contraseña o la clave de recuperación';

  @override
  String get enterContainerPasswordHint =>
      'Introduce la contraseña del contenedor';

  @override
  String get readOnlyModeUsbSubtitleDrive =>
      'Monta sin permitir cambios en esta unidad';

  @override
  String get rememberDriveLabel => 'Recordar unidad';

  @override
  String get rememberDriveSubtitle =>
      'Fija la unidad en el panel principal para acceso rápido';

  @override
  String get unlockVaultButtonLabel => 'Desbloquear bóveda';

  @override
  String get cryfsStorageAccessWarning =>
      'Las bóvedas CryFS usan miles de archivos de bloque pequeños. Sin el acceso directo al almacenamiento, el rendimiento será considerablemente más lento.';

  @override
  String get folderVaultStorageAccessWarning =>
      'El acceso directo al almacenamiento está desactivado. Abrir y leer archivos en bóvedas de carpeta puede ser más lento.';

  @override
  String get requestingPermission => 'Solicitando permiso…';

  @override
  String get unlockAndMountButton => 'Desbloquear y montar';

  @override
  String get unlockDriveButton => 'Desbloquear unidad';

  @override
  String couldntFindDevice(String deviceName) {
    return 'No se pudo encontrar \"$deviceName\"';
  }

  @override
  String get plugDriveBackInRetry =>
      'Vuelve a conectar la unidad y toca Reintentar, o selecciónala abajo si aparece con otro nombre.';

  @override
  String get retryConnectionButton => 'Reintentar conexión';

  @override
  String get refreshDevicesButton => 'Actualizar dispositivos';

  @override
  String get connectOtgDriveToMount =>
      'Conecta una unidad flash OTG para montarla';

  @override
  String get alreadyActive => 'Ya está activo';

  @override
  String get active => 'Activo';

  @override
  String get readyToUnlock => 'Listo para desbloquear';

  @override
  String get enterUsbPartitionPassword =>
      'Introduce la contraseña de la partición USB';

  @override
  String get biometricAuthenticationTitle => 'Autenticación biométrica';

  @override
  String get biometricAuthUsbSubtitle =>
      'Autentícate para desbloquear y montar este dispositivo USB';

  @override
  String get connectPatternSequenceToMount =>
      'Conecta la secuencia de tu patrón para montar';

  @override
  String get selectAllAction => 'Seleccionar todo';

  @override
  String get clearSelectionAction => 'Borrar selección';

  @override
  String get clearSelectionTooltip => 'Borrar selección';

  @override
  String get selectionOptionsTooltip => 'Opciones de selección';

  @override
  String get readOnlyContainerTooltip => 'Contenedor de solo lectura';

  @override
  String get copyAction => 'Copiar';

  @override
  String get moveAction => 'Mover';

  @override
  String get renameAction => 'Renombrar';

  @override
  String get exportToDeviceAction => 'Exportar al dispositivo';

  @override
  String get openWithAppAction => 'Abrir con app';

  @override
  String get pinAction => 'Fijar';

  @override
  String get pinSelectedAction => 'Fijar seleccionados';

  @override
  String get unpinAction => 'Desfijar';

  @override
  String get unpinSelectedAction => 'Desfijar seleccionados';

  @override
  String get documentProviderSettingsMenu =>
      'Ajustes del proveedor de documentos';

  @override
  String get exposeAsDocumentProviderMenu =>
      'Exponer como proveedor de documentos';

  @override
  String get moreOptionsTooltipShort => 'Más opciones';

  @override
  String get copyTooltip => 'Copiar';

  @override
  String get searchInThisFolderHint => 'Buscar en esta carpeta…';

  @override
  String get clearTooltip => 'Borrar';

  @override
  String get backToDashboardTooltip => 'Volver al panel principal';

  @override
  String get cancelPasteButton => 'Cancelar pegado';

  @override
  String get continueButton => 'Continuar';

  @override
  String get skipButton => 'Omitir';

  @override
  String get keepBothButton => 'Conservar ambos';

  @override
  String get clearAllButton => 'Borrar todo';

  @override
  String get autoMountWhenUnlocksTitle =>
      'Montar automáticamente al desbloquear el contenedor';

  @override
  String get autoMountWhenUnlocksSubtitle =>
      'Exponer esta carpeta automáticamente de nuevo la próxima vez';

  @override
  String get unmountButton => 'Desmontar';

  @override
  String get filtersMenuItem => 'Filtros';

  @override
  String get settingsMenuItem => 'Ajustes';

  @override
  String get sortOptionsTooltip => 'Opciones de orden';

  @override
  String get layoutOptionsTooltip => 'Opciones de diseño';

  @override
  String get lockContainerTooltip => 'Bloquear contenedor';

  @override
  String get renameTooltip => 'Renombrar';

  @override
  String get cancelUpdatingPasswordTooltip =>
      'Cancelar actualización de contraseña';

  @override
  String get unlockSettingsButton => 'Ajustes de desbloqueo';

  @override
  String get updateSavedCredentialsButton =>
      'Actualizar credenciales guardadas';

  @override
  String get verifyCredentialsTitle => 'Verificar credenciales';

  @override
  String get verifyButton => 'Verificar';

  @override
  String get displayNameTitle => 'Nombre visible';

  @override
  String get containerNameHint => 'Nombre del contenedor';

  @override
  String get deleteFileDialogTitle => '¿Eliminar archivo?';

  @override
  String get deleteFilePermanentWarning =>
      'Esta acción es permanente y no se puede deshacer.';

  @override
  String get unsavedChangesTitle => 'Cambios no guardados';

  @override
  String get unsavedChangesMessage =>
      'Tienes cambios sin guardar. ¿Quieres guardarlos antes de cerrar?';

  @override
  String get discardButton => 'Descartar';

  @override
  String get decryptingFileContent => 'Descifrando el contenido del archivo...';

  @override
  String get cannotOpenFile => 'No se puede abrir el archivo';

  @override
  String get changesSavedSuccessfully => 'Cambios guardados correctamente';

  @override
  String saveFailedWithError(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String linesCount(int count) {
    return 'Líneas: $count';
  }

  @override
  String charsCount(int count) {
    return 'Caracteres: $count';
  }

  @override
  String get unsavedChangesLabel => 'Cambios no guardados';

  @override
  String get savedToVault => 'Guardado en la bóveda';

  @override
  String get saveChangesTooltip => 'Guardar cambios';

  @override
  String get textEditorDecryptFailedMessage =>
      'Error al descifrar el archivo de la bóveda.';

  @override
  String get textEditorInvalidTextFileMessage =>
      'El archivo no parece ser un archivo de texto válido.';

  @override
  String get textEditorWriteBackFailedMessage =>
      'Error al escribir el archivo de vuelta en la bóveda.';

  @override
  String get backTooltip => 'Atrás';

  @override
  String get forwardTooltip => 'Adelante';

  @override
  String get reloadTooltip => 'Recargar';

  @override
  String get optionsTooltip => 'Opciones';

  @override
  String get htmlViewerErrorTitle => 'No se puede mostrar esta página';

  @override
  String get htmlViewerLoadFailedMessage => 'Error al cargar el archivo';

  @override
  String get enableJavaScriptDialogTitle => '¿Activar JavaScript?';

  @override
  String get enableJavaScriptDialogMessage =>
      'Se permitirá que la página ejecute sus propios scripts locales. Sigue sin tener acceso a la red — nada de esta bóveda se puede enviar ni recibir por internet.';

  @override
  String get disableJavaScriptMenu => 'Desactivar JavaScript';

  @override
  String get enableJavaScriptMenu => 'Activar JavaScript';

  @override
  String get enterFullscreenMenu => 'Entrar en pantalla completa';

  @override
  String failedToOpenExternalApp(String error) {
    return 'Error al abrir en la app externa: $error';
  }

  @override
  String get thisFolderMenu => 'Esta carpeta';

  @override
  String get allInclSubfoldersMenu => 'Todo (incl. subcarpetas)';

  @override
  String get disableShuffleMenu => 'Desactivar aleatorio';

  @override
  String get shufflePlaylistMenu => 'Reproducir lista al azar';

  @override
  String get playlistOptionsTooltip => 'Opciones de la lista de reproducción';

  @override
  String get enablePlaylistTooltip => 'Activar lista de reproducción';

  @override
  String get moreActionsTooltip => 'Más acciones';

  @override
  String get forcePortraitMenu => 'Forzar vertical';

  @override
  String get forceLandscapeMenu => 'Forzar horizontal';

  @override
  String get autoRotateSensorMenu => 'Rotación automática (sensor)';

  @override
  String get screenOrientationMenu => 'Orientación de pantalla';

  @override
  String get playlistTransitionMenu => 'Transición de la lista de reproducción';

  @override
  String get renameFileMenu => 'Renombrar archivo';

  @override
  String get deleteFileMenu => 'Eliminar archivo';

  @override
  String get thumbnailCarouselTooltip => 'Carrusel de miniaturas';

  @override
  String get advancedSettingsTooltip => 'Ajustes avanzados';

  @override
  String get previousTooltip => 'Anterior';

  @override
  String get nextTooltip => 'Siguiente';

  @override
  String get diagnosticsCopiedToClipboard =>
      'Diagnóstico copiado al portapapeles';

  @override
  String get diagnosticsTitle => 'Diagnóstico';

  @override
  String get copyDiagnosticsTooltip => 'Copiar diagnóstico';

  @override
  String get closeTooltip => 'Cerrar';

  @override
  String get diagnosticsPlaybackSection => 'Reproducción';

  @override
  String get diagnosticsEngineSection => 'Motor';

  @override
  String get diagnosticsStateLabel => 'Estado';

  @override
  String get diagnosticsResolutionLabel => 'Resolución';

  @override
  String get diagnosticsAspectRatioLabel => 'Relación de aspecto';

  @override
  String get diagnosticsPositionLabel => 'Posición';

  @override
  String get diagnosticsDurationLabel => 'Duración';

  @override
  String get diagnosticsErrorLabel => 'Error';

  @override
  String get diagnosticsPlayerLabel => 'Reproductor';

  @override
  String get diagnosticsDecodingLabel => 'Decodificación';

  @override
  String get diagnosticsExoPlayerValue => 'ExoPlayer (Android)';

  @override
  String get diagnosticsHardwareAcceleratedValue => 'Acelerado por hardware';

  @override
  String get diagnosticsUnknownValue => 'Desconocido';

  @override
  String get diagnosticsStateBuffering => 'Cargando';

  @override
  String get diagnosticsStatePlaying => 'Reproduciendo';

  @override
  String get diagnosticsStatePaused => 'Pausado';

  @override
  String get diagnosticsDurationUnavailable => '--:--';

  @override
  String get rotate90Label => 'Girar 90°';

  @override
  String get imageFitModeLabel => 'Modo de ajuste de imagen';

  @override
  String get slideshowDelayLabel => 'Retardo de presentación';

  @override
  String get playbackSpeedLabel => 'Velocidad de reproducción';

  @override
  String get subtitlesLabel => 'Subtítulos';

  @override
  String get imageSettingsTitle => 'Ajustes de imagen';

  @override
  String get playbackSettingsTitle => 'Ajustes de reproducción';

  @override
  String get imageFitContain => 'Contener';

  @override
  String get imageFitWidth => 'Ajustar ancho';

  @override
  String get imageFitHeight => 'Ajustar alto';

  @override
  String nSecondsDelay(int n) {
    return '$n segundos';
  }

  @override
  String playbackSpeedNormal(String speed) {
    return '${speed}x (normal)';
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
  String get settingsTooltipShort => 'Ajustes';

  @override
  String get sourceCodeTooltip => 'Código fuente';

  @override
  String get donateTooltip => 'Donar';

  @override
  String get shareAppTooltip => 'Compartir app';

  @override
  String get resetToDefaultsTooltip => 'Restablecer valores predeterminados';

  @override
  String get usbUnlockContainerTitle => 'Desbloquear contenedor USB';

  @override
  String get usbMountContainerTitle => 'Montar unidad USB';

  @override
  String get staticLabel => 'Estático';

  @override
  String get unmuteTooltip => 'Activar sonido';

  @override
  String get muteTooltip => 'Silenciar';

  @override
  String get playOnceDisabledTooltip =>
      'Reproducir una vez (avance automático desactivado)';

  @override
  String get playAndAdvanceTooltip => 'Reproducir y avanzar al siguiente';

  @override
  String get loopCurrentVideoTooltip => 'Repetir vídeo actual';

  @override
  String get clearThumbnailCacheDialogTitle =>
      '¿Borrar la caché de miniaturas?';

  @override
  String get clearThumbnailCacheDialogMessage =>
      'Esto eliminará las miniaturas guardadas en caché para esta bóveda. Se regenerarán la próxima vez que explores los medios.';

  @override
  String get clearCacheButton => 'Borrar caché';

  @override
  String get appCacheClearedUnlockMessage =>
      'Caché de la app borrada. Desbloquea el contenedor para borrar la caché interna.';

  @override
  String get allThumbnailCachesClearedMessage =>
      'Todas las cachés de miniaturas se borraron correctamente.';

  @override
  String get appCacheClearedContainerFailedMessage =>
      'Se borró la caché de la app, pero no se pudo borrar la del interior del contenedor.';

  @override
  String get failedToClearThumbnailCachesMessage =>
      'Error al borrar las cachés de miniaturas.';

  @override
  String get authenticateToModifySettingsPrompt =>
      'Autentícate para modificar los ajustes';

  @override
  String get usbVaultSettingsTitle => 'Ajustes de la bóveda USB';

  @override
  String get vaultSettingsTitle => 'Ajustes de la bóveda';

  @override
  String get generalSectionHeader => 'General';

  @override
  String get securityCredentialsSectionHeader => 'Seguridad y credenciales';

  @override
  String get securityOptionsLockedTitle => 'Opciones de seguridad bloqueadas';

  @override
  String get authenticateOriginalCredentialsMessage =>
      'Autentícate con las credenciales originales del contenedor para modificar los ajustes de seguridad.';

  @override
  String get unlockCredentialsLabel => 'Credenciales de desbloqueo';

  @override
  String get unavailableSuffixLabel => '(No disponible)';

  @override
  String get patternSetupRequiredBeforeSaving =>
      'Configura un patrón antes de guardar.';

  @override
  String get passwordKeystoreEncryptedHelperText =>
      'La contraseña se cifra mediante Android Keystore. Déjala en blanco si solo usas archivos clave.';

  @override
  String get changePatternButton => 'Cambiar patrón';

  @override
  String get setPatternButton => 'Establecer patrón';

  @override
  String get cacheDerivedKeyLabel => 'Guardar clave derivada en caché';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      'Omitir la KDF scrypt de CryFS la próxima vez (la clave se guarda en Android Keystore)';

  @override
  String get reuseKeyMaterialKeystoreSubtitle =>
      'Reutilizar material de claves en Android Keystore';

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle =>
      'Fija el algoritmo para omitir la detección automática al desbloquear.';

  @override
  String get changeContainerPasswordTitle =>
      'Cambiar contraseña del contenedor';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      'Las credenciales de BitLocker no se pueden cambiar dentro de la app. Usa \"Administrar BitLocker\" en Windows.';

  @override
  String get systemIntegrationSectionHeader => 'Sistema e integración';

  @override
  String get autoLockDurationLabel => 'Duración del bloqueo automático';

  @override
  String get neverAutoLockOption => 'Nunca';

  @override
  String get exposeContentToFilePickerSubtitle =>
      'Exponer el contenido al selector de archivos del sistema cuando esté desbloqueado';

  @override
  String get thumbnailStorageSectionHeader => 'Almacenamiento de miniaturas';

  @override
  String get cacheModeLabel => 'Modo de caché';

  @override
  String get useGlobalDefaultSubtitle => 'Usar el valor predeterminado global';

  @override
  String get thumbnailQualityLabel => 'Calidad de miniaturas';

  @override
  String get clearThumbnailCacheTitle => 'Borrar caché de miniaturas';

  @override
  String get removeCachedThumbnailsSubtitle =>
      'Elimina las miniaturas de imagen y vídeo en caché';

  @override
  String get vaultInformationSectionHeader => 'Información de la bóveda';

  @override
  String get vaultInformationTileTitle => 'Ver detalles de la bóveda';

  @override
  String get vaultInformationTileSubtitle =>
      'Cifrado, formato y otros detalles técnicos';

  @override
  String get vaultInfoLocationLabel => 'Ubicación';

  @override
  String get vaultInfoRequiresUnlockTitle => 'Desbloqueo necesario';

  @override
  String get vaultInfoRequiresUnlockMessage =>
      'Desbloquea esta bóveda para ver sus detalles técnicos.';

  @override
  String get vaultInfoLoadFailedTitle =>
      'No se pudo cargar la información de la bóveda';

  @override
  String get vaultInfoLoadFailedMessage =>
      'Ocurrió un error al leer los detalles de esta bóveda.';

  @override
  String get vaultInfoVolumeSizeLabel => 'Tamaño del volumen';

  @override
  String get vaultInfoHiddenVolumeLabel => 'Volumen oculto';

  @override
  String get vaultInfoReadOnlyLabel => 'Solo lectura';

  @override
  String get vaultInfoLuksVersionLabel => 'Versión de LUKS';

  @override
  String get vaultInfoSectorSizeLabel => 'Tamaño de sector';

  @override
  String get vaultInfoVaultFormatLabel => 'Formato de la bóveda';

  @override
  String get vaultInfoCipherComboLabel => 'Combinación de cifrado';

  @override
  String get vaultInfoShorteningThresholdLabel =>
      'Umbral de acortamiento de nombres de archivo';

  @override
  String get vaultInfoFormatVersionLabel => 'Versión de formato';

  @override
  String get vaultInfoContentCipherLabel => 'Cifrado de contenido';

  @override
  String get vaultInfoFilenameEncryptionLabel => 'Nombres de archivo';

  @override
  String get vaultInfoPlaintextNamesValue => 'Sin cifrar';

  @override
  String get vaultInfoEncryptedNamesValue => 'Cifrados';

  @override
  String get vaultInfoBlockCipherLabel => 'Cifrado de bloque';

  @override
  String get vaultInfoBlockSizeLabel => 'Tamaño de bloque';

  @override
  String get vaultInfoCreatedWithVersionLabel => 'Creada con';

  @override
  String get vaultInfoLastOpenedWithVersionLabel =>
      'Abierta por última vez con';

  @override
  String get vaultInfoYesValue => 'Sí';

  @override
  String get vaultInfoNoValue => 'No';

  @override
  String get vaultInfoBitlockerNote =>
      'Esta app no analiza los metadatos de encabezado propios de BitLocker, por lo que los detalles de cifrado y versión no están disponibles aquí.';

  @override
  String get patternSetupRequiredAboveBeforeSaving =>
      'Configura un patrón arriba antes de guardar.';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      'Este método de desbloqueo requiere una contraseña o \"Guardar clave derivada en caché\" con archivos clave.';

  @override
  String get saveConfigurationButton => 'Guardar configuración';

  @override
  String get incorrectPatternError => 'Patrón incorrecto';

  @override
  String get verifyPatternTitle => 'Verificar patrón';

  @override
  String get incorrectPasswordError => 'Contraseña incorrecta';

  @override
  String get verificationFailedError => 'Error de verificación';

  @override
  String get incorrectCredentialsError => 'Credenciales incorrectas';

  @override
  String get containerPasswordOptionalLabel =>
      'Contraseña del contenedor (opcional si solo usas archivo clave)';

  @override
  String get pimOptionalLabel => 'PIM (opcional)';

  @override
  String get usbDriveLockedLabel => 'Unidad USB · Bloqueada';

  @override
  String get lockedContainerLabel => 'Contenedor bloqueado';

  @override
  String get operationInProgressWaitMessage =>
      'Hay una operación en curso. Espera antes de bloquear.';

  @override
  String get reconnectUsbTooltip => 'Reconectar USB';

  @override
  String get unlockContainerTooltip => 'Desbloquear contenedor';

  @override
  String lockFailedMessage(String errorType) {
    return 'Error al bloquear: $errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired =>
      'Se requiere una nueva contraseña o archivos clave.';

  @override
  String get newPasswordsDoNotMatch => 'Las nuevas contraseñas no coinciden.';

  @override
  String get passwordChangedSuccessfullyMessage =>
      'Contraseña cambiada correctamente.';

  @override
  String get failedToChangePasswordMessage =>
      'Error al cambiar la contraseña. Comprueba las credenciales anteriores.';

  @override
  String get currentCredentialsSectionHeader => 'Credenciales actuales';

  @override
  String get oldPasswordLabel => 'Contraseña anterior';

  @override
  String get oldPimOptionalLabel => 'PIM anterior (opcional)';

  @override
  String get newCredentialsSectionHeader => 'Nuevas credenciales';

  @override
  String get newPimOptionalLabel => 'Nuevo PIM (opcional)';

  @override
  String get noContainersYetTitle => 'Aún no hay contenedores';

  @override
  String get dashboardEmptyStateMessage =>
      'Monta un contenedor VeraCrypt, conecta una unidad USB o crea una nueva bóveda cifrada para empezar.';

  @override
  String get sortFieldName => 'Nombre';

  @override
  String get sortFieldSize => 'Tamaño';

  @override
  String get sortFieldType => 'Tipo';

  @override
  String get sortFieldDate => 'Fecha';

  @override
  String get layoutModeDetailedList => 'Lista detallada';

  @override
  String get layoutModeCompactList => 'Lista compacta';

  @override
  String get layoutModeGalleryGrid => 'Cuadrícula de galería';

  @override
  String get readOnlyCantDeleteTooltip => 'Solo lectura — no se puede eliminar';

  @override
  String get readOnlyCantMoveTooltip => 'Solo lectura — no se puede mover';

  @override
  String get readOnlyCantRenameTooltip =>
      'Solo lectura — no se puede renombrar';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes (calculando…)';
  }

  @override
  String get sizeCalculatingLabel => 'calculando…';

  @override
  String get editSecureItemsToRenameMessage =>
      'Edita los elementos seguros para renombrarlos';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage =>
      'Los elementos de la bóveda no se pueden abrir en apps externas';

  @override
  String get mountedReadOnlyTooltip => 'Montado en solo lectura';

  @override
  String get readOnlyBadgeAbbreviation => 'SL';

  @override
  String freeSpaceLabel(String bytes) {
    return '$bytes libres';
  }

  @override
  String get filteredLabel => 'filtrado';

  @override
  String get statsStorageSectionHeader => 'ALMACENAMIENTO';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carpetas',
      one: '1 carpeta',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos',
      one: '1 archivo',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => 'Todos los archivos';

  @override
  String get filterImagesOption => 'Imágenes';

  @override
  String get filterVideosOption => 'Vídeos';

  @override
  String get filterAudioOption => 'Audio';

  @override
  String get filterDocumentsOption => 'Documentos';

  @override
  String get folderExposedAsStorageExplanation =>
      'Esta carpeta se expone como su propia ubicación de almacenamiento, por lo que otras apps pueden explorar y abrir sus archivos directamente.';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ya existen $count elementos',
      one: 'Ya existe 1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle =>
      'Elige qué ocurre con cada elemento, o aplica una elección a todos.';

  @override
  String get skipAllChipLabel => 'Omitir todo';

  @override
  String get overwriteAllChipLabel => 'Sobrescribir todo';

  @override
  String get overwriteItemDropdownLabel => 'Sobrescribir';

  @override
  String get overwriteFolderDropdownLabel => 'Sobrescribir carpeta';

  @override
  String get fileOpsTransfersInProgressTitle => 'Transferencias en curso';

  @override
  String get fileOpsRecentTransfersTitle => 'Transferencias recientes';

  @override
  String get fileOpsNoRecentTransfersMessage =>
      'No hay transferencias recientes';

  @override
  String get fileOpsNoRecentTransfersSubtitle =>
      'Las copias, movimientos y eliminaciones aparecerán aquí mientras se ejecutan.';

  @override
  String fileOpsShowDetailsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String get fileOpsCancelTooltip => 'Cancelar';

  @override
  String get fileOpsRootDestinationLabel => 'Raíz';

  @override
  String get fileOpsCancelledStatusLabel => 'Cancelado';

  @override
  String fileOpsItemsFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos fallaron:',
      one: '1 elemento falló:',
    );
    return '$_temp0';
  }

  @override
  String fileOpsMoreItemsLabel(num count) {
    return '+ $count más';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return 'Error al leer el archivo: $error';
  }

  @override
  String get archivePreviewNotAvailableMessage =>
      'Vista previa no disponible para este tipo de archivo.';

  @override
  String get avifFailedToRenderMessage => 'Error al renderizar AVIF';

  @override
  String get encryptedImageLoadFailedMessage =>
      'Error al cargar la imagen cifrada';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return 'Error al cargar la imagen cifrada: $error';
  }

  @override
  String get invalidOrCorruptedImageMessage =>
      'Formato de imagen no válido o dañado.';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '$current de $total';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '$current de $total  ·  buscando…';
  }

  @override
  String get mediaViewerScanningLabel => 'Buscando…';

  @override
  String get mediaFileDeletedMessage => 'Archivo eliminado correctamente';

  @override
  String get mediaFileDeleteFailedMessage => 'Error al eliminar el archivo';

  @override
  String get mediaFileRenamedMessage => 'Archivo renombrado correctamente';

  @override
  String get aboutScreenTitle => 'Acerca de';

  @override
  String get couldNotOpenLinkMessage => 'No se pudo abrir el enlace';

  @override
  String get fileManagerSettingsTitle => 'Ajustes del gestor de archivos';

  @override
  String get showMediaThumbnailsLabel => 'Mostrar miniaturas de medios';

  @override
  String get showMediaThumbnailsDesc =>
      'Muestra vistas previas en miniatura para imágenes y vídeos en la vista de lista';

  @override
  String get showFileNamesLabel => 'Mostrar nombres de archivo';

  @override
  String get showFileNamesDesc =>
      'Muestra etiquetas de texto debajo de los elementos en la vista de cuadrícula';

  @override
  String get showBreadcrumbBarLabel => 'Mostrar barra de ruta';

  @override
  String get showBreadcrumbBarDesc =>
      'Barra de navegación de ruta en la parte superior del explorador';

  @override
  String get showStatsBarLabel => 'Mostrar barra de estadísticas';

  @override
  String get showStatsBarDesc =>
      'Banner con el número de archivos e información de espacio libre';

  @override
  String get autoStartPlaylistModeLabel =>
      'Iniciar automáticamente el modo lista de reproducción';

  @override
  String get autoStartPlaylistModeDesc =>
      'Inicia automáticamente en modo lista de reproducción al abrir un elemento multimedia';

  @override
  String get showPlaylistCarouselLabel =>
      'Mostrar carrusel de lista de reproducción';

  @override
  String get showPlaylistCarouselDesc =>
      'Muestra el botón de carrusel de miniaturas al ver listas de reproducción multimedia';

  @override
  String get videoPlaybackSliderLabel =>
      'Control deslizante de posición de reproducción de vídeo';

  @override
  String get longPressPlaybackDiagnosticsHint =>
      'Mantén pulsado para ver el diagnóstico de reproducción';

  @override
  String get staticImageModeLabel => 'Modo de imagen estática';

  @override
  String slideshowModeActiveLabel(int seconds) {
    return 'Modo presentación activo con un retardo de $seconds segundos';
  }

  @override
  String videoPlaybackModeLabel(String mode) {
    return 'Modo de reproducción de vídeo: $mode';
  }

  @override
  String get pauseLabel => 'Pausar';

  @override
  String get playLabel => 'Reproducir';

  @override
  String get emptyFolderTitle => 'Carpeta vacía';

  @override
  String get emptyFolderMessage =>
      'Usa la acción Añadir para crear archivos o importar desde el dispositivo.';

  @override
  String get noResultsTitle => 'Sin resultados';

  @override
  String noResultsForQueryMessage(String query) {
    return 'Nada en esta carpeta coincide con \"$query\".';
  }

  @override
  String get closeCarouselTooltip => 'Cerrar carrusel';

  @override
  String get playlistScrollModeMenu =>
      'Modo de desplazamiento de la lista de reproducción';

  @override
  String get playlistScrollHorizontalLabel => 'Horizontal';

  @override
  String get playlistScrollVerticalPageLabel => 'Vertical por páginas';

  @override
  String get playlistScrollVerticalContinuousLabel => 'Vertical continuo';

  @override
  String get undoTooltip => 'Deshacer';

  @override
  String get redoTooltip => 'Rehacer';

  @override
  String get autosavingLabel => 'Autoguardando…';

  @override
  String get savingLabel => 'Guardando…';

  @override
  String autosavedAtLabel(String time) {
    return 'Autoguardado a las $time';
  }

  @override
  String cameraDisconnectedError(String message) {
    return 'Cámara desconectada: $message';
  }

  @override
  String get unknownErrorFallback => 'error desconocido';

  @override
  String get cameraPermissionsRequiredMessage =>
      'Se requieren permisos de cámara y micrófono para usar la cámara.';

  @override
  String cameraErrorMessage(String error) {
    return 'Error de cámara: $error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage => 'Error al capturar la foto';

  @override
  String get cameraRecordingFailedMessage => 'Error en la grabación';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return 'Error en la grabación: $error';
  }

  @override
  String get cameraRecordingTooShortMessage =>
      'La grabación fue demasiado corta para guardarse';

  @override
  String get cameraCouldNotSaveRecordingMessage =>
      'No se pudo guardar la grabación';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return 'No se pudo guardar la grabación: $error';
  }

  @override
  String get cameraCouldNotSwitchLensMessage => 'No se pudo cambiar de lente';

  @override
  String get cameraEncryptingPhotoLabel => 'Cifrando foto…';

  @override
  String get cameraEncryptingVideoLabel => 'Cifrando vídeo…';

  @override
  String get aboutApplicationSectionHeader => 'Aplicación';

  @override
  String get aboutTagline =>
      'Gratis · Código abierto · Bóveda cifrada sin conexión';

  @override
  String get aboutVersionTitle => 'Versión';

  @override
  String aboutVersionSubtitle(String version) {
    return 'v$version · Toca para copiar la información de versión para informes de errores';
  }

  @override
  String get aboutWhatsNewTitle => 'Novedades';

  @override
  String get aboutWhatsNewSubtitle =>
      'Consulta los cambios recientes y las notas de la versión';

  @override
  String get aboutPrivacySecurityTitle => 'Privacidad y seguridad';

  @override
  String get aboutPrivacySecuritySubtitle =>
      'Sin acceso a la red, nada sin cifrar se escribe jamás en el disco';

  @override
  String get aboutSupportedFormatsSectionHeader => 'Formatos compatibles';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt y LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      'Volúmenes estándar y ocultos, PIM personalizado, archivos clave, xts-plain64, Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker y BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle =>
      'Compatibilidad con frases de contraseña de usuario y clave de recuperación numérica de 48 dígitos';

  @override
  String get aboutDirectoryVaultsTitle => 'Bóvedas de directorio';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator (v7/v8 SIV_GCM y SIV_CTRMAC), gocryptfs (v2 AES-GCM y XChaCha20), CryFS (v0.10+ XChaCha20 y AES)';

  @override
  String get aboutVhdTitle => 'Discos duros virtuales (VHD / VHDX)';

  @override
  String get aboutVhdSubtitle =>
      'Traducción de BAT para imágenes de disco fijas y dinámicas expandibles';

  @override
  String get aboutNativeCoreEngineSectionHeader => 'Motor nativo principal';

  @override
  String get aboutCompiledLibrariesTitle => 'Bibliotecas C++ compiladas';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.0 (criptografía por hardware ARMv8 y SHA-2)\n• libavif y libgav1 (decodificador nativo de imágenes AVIF)\n• ChaN FatFs v4.0.4 (FAT12/16/32 y exFAT)\n• Tuxera NTFS-3G y mkntfs integrado\n• e2fsprogs v1.47.4 libext2fs (ext2/ext3/ext4)\n• E/S virtual de Dislocker (BitLocker FVE / To Go)\n• VeraCrypt 1.26.29 (Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id/i)\n• cJSON v1.7.18 (metadatos de LUKS2 y Cryptomator)';

  @override
  String get aboutCommunitySectionHeader => 'Comunidad y código abierto';

  @override
  String get aboutReportIssueTitle => 'Informar de un problema';

  @override
  String get aboutReportIssueSubtitle =>
      '¿Encontraste un error? Envía un informe en GitHub';

  @override
  String get aboutContributorsTitle => 'Colaboradores';

  @override
  String get aboutContributorsSubtitle =>
      'Personas que ayudaron a construir VaultExplorer';

  @override
  String get aboutLicensesTitle => 'Licencias de código abierto';

  @override
  String get aboutLicensesSubtitle =>
      'Bibliotecas de terceros usadas en esta app';

  @override
  String get aboutFooterMadeWithLove => 'Hecho con ❤ por la privacidad.';

  @override
  String get aboutVersionCopiedMessage =>
      'Información de versión copiada — útil para informes de errores';

  @override
  String aboutVersionClipboardText(String version) {
    return 'VaultExplorer v$version (Android)';
  }

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer — una bóveda gratuita, de código abierto y sin conexión para Android.\n\nGuarda contraseñas, notas y archivos dentro de un contenedor cifrado (VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs, CryFS).\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage =>
      'Se copió un enlace para compartir en tu portapapeles';

  @override
  String get aboutPrivacySheetTitle => 'Privacidad y seguridad de datos';

  @override
  String get aboutPrivacySheetSubtitle =>
      '100% sin conexión, diseño de seguridad en memoria local';

  @override
  String get privacyPointNoNetworkTitle => 'No requiere acceso a la red';

  @override
  String get privacyPointNoNetworkBody =>
      'VaultExplorer no solicita el permiso android.permission.INTERNET en Android. No puede comunicarse por ninguna red.';

  @override
  String get privacyPointNoDiskLeaksTitle =>
      'Cero filtraciones sin cifrar al disco';

  @override
  String get privacyPointNoDiskLeaksBody =>
      'El descifrado y el recifrado ocurren completamente en la memoria del sistema. Los archivos temporales sin cifrar nunca se guardan en el almacenamiento del dispositivo.';

  @override
  String get privacyPointNoAnalyticsTitle => 'Sin análisis ni telemetría';

  @override
  String get privacyPointNoAnalyticsBody =>
      'No hay ningún informe de fallos, seguimiento de uso ni SDK de terceros que recopile datos sobre ti o tu dispositivo.';

  @override
  String get privacyPointKeystoreTitle =>
      'Los secretos permanecen en Android Keystore';

  @override
  String get privacyPointKeystoreBody =>
      'Las contraseñas recordadas, los patrones y las claves derivadas en caché se sellan con AES-256-GCM en el Android Keystore respaldado por hardware.';

  @override
  String get privacyPointPosixTitle =>
      'Aceleración POSIX y acceso al almacenamiento';

  @override
  String get privacyPointPosixBody =>
      'Los archivos dentro de las bóvedas de directorio se leen y escriben directamente cuando es posible, evitando la capa SAF más lenta de Android en carpetas grandes.';

  @override
  String get privacyPointScreenClipboardTitle =>
      'Protección de pantalla y portapapeles';

  @override
  String get privacyPointScreenClipboardBody =>
      'Bloqueo de vista previa de capturas de pantalla/selector de tareas (FLAG_SECURE) y limpieza automática del portapapeles corrupto al recuperar el foco de la ventana.';

  @override
  String get privacyPointMaskModeTitle => 'Modo Máscara';

  @override
  String get privacyPointMaskModeBody =>
      'Disfraza opcionalmente la app como un explorador de archivos zip funcional, con un icono y nombre distintos. Mantén pulsado el título durante 3 segundos para acceder a tu bóveda real.';

  @override
  String get privacyPointExternalLinksTitle =>
      'Los enlaces externos se abren en el navegador';

  @override
  String get privacyPointExternalLinksBody =>
      'Al tocar los enlaces, se pasa la solicitud a tu app de navegador predeterminada, que se encarga de gestionarla.';

  @override
  String get truncatedListingWarning =>
      'Mostrando los primeros 50 000 elementos — esta carpeta tiene más archivos.';

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '$size px · calidad $quality%';
  }

  @override
  String holdToSpeedIndicatorLabel(String speed) {
    return 'Velocidad $speed×';
  }

  @override
  String get toolbarLayoutSectionHeader => 'Diseño de la barra de herramientas';

  @override
  String get listViewOptionsSectionHeader => 'Opciones de vista de lista';

  @override
  String get detailedListViewColumnsSectionHeader =>
      'Columnas de la vista de lista detallada';

  @override
  String get galleryGridViewSectionHeader => 'Vista de cuadrícula de galería';

  @override
  String get browserLayoutSectionHeader => 'Diseño del explorador';

  @override
  String get mediaViewerSectionHeader => 'Visor de medios';

  @override
  String get viewModeAction => 'Modo de vista';

  @override
  String get sortAction => 'Ordenar';

  @override
  String get playMediaAction => 'Reproducir medios';

  @override
  String containerSpaceSummary(String free, String total) {
    return '$free libres · $total en total';
  }

  @override
  String volMountedSummary(int volId) {
    return 'Vol $volId · Montado';
  }

  @override
  String vaultOccupiedSpaceSummary(String used) {
    return '$used usados';
  }

  @override
  String get incorrectPasswordOrKeyfilesDriveError =>
      'Contraseña/archivos clave incorrectos o unidad no compatible';

  @override
  String driveUsableCapacity(int mb) {
    return 'Capacidad útil de la unidad: $mb MB. No debe superarse.';
  }

  @override
  String get unlockMethodManualPassword => 'Contraseña manual';

  @override
  String get unlockMethodRememberPassword => 'Recordar contraseña';

  @override
  String get unlockMethodBiometrics => 'Desbloqueo biométrico';

  @override
  String get unlockMethodPattern => 'Desbloqueo por patrón';

  @override
  String get unlockMethodSubtitlePassword => 'Escribe la contraseña cada vez';

  @override
  String get unlockMethodSubtitleRememberPassword =>
      'Almacenada de forma segura en Android Keystore';

  @override
  String get unlockMethodSubtitleBiometrics =>
      'Usa la huella o el rostro para desbloquear';

  @override
  String get unlockMethodSubtitlePattern => 'Dibuja un patrón para desbloquear';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError =>
      'Decodificador de vídeo no disponible — conflicto de codec por hardware';

  @override
  String get mediaStreamInitFailedError =>
      'Error al inicializar el flujo multimedia';

  @override
  String get invalidAvifImage => 'Imagen AVIF no válida';

  @override
  String get verbImport => 'Importar';

  @override
  String get verbMove => 'Mover';

  @override
  String get verbCopy => 'Copiar';

  @override
  String get verbDelete => 'Eliminar';

  @override
  String get verbImported => 'Importado';

  @override
  String get verbMoved => 'Movido';

  @override
  String get verbCopied => 'Copiado';

  @override
  String get verbDeleted => 'Eliminado';

  @override
  String get verbImporting => 'Importando';

  @override
  String get verbMoving => 'Moviendo';

  @override
  String get verbCopying => 'Copiando';

  @override
  String get verbDeleting => 'Eliminando';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '1 elemento',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos $verb',
      one: '1 elemento $verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return '$count omitidos';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return '$count fallidos';
  }

  @override
  String get statusCancelled => 'Cancelado';

  @override
  String get statusFailed => 'Fallido';

  @override
  String get statusCompleted => 'Completado';

  @override
  String get fileOpCheckingSpace => 'Comprobando el espacio disponible…';

  @override
  String get fileOpResolvingConflicts => 'Resolviendo conflictos…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return 'No hay espacio suficiente — se necesitan $required, solo hay $free libres';
  }

  @override
  String get fileOpDiskFullPartialRemoved =>
      'Disco lleno — se eliminaron los archivos parciales';

  @override
  String get fileOpMoveFailed => 'Error al mover';

  @override
  String get fileOpCopyFailed => 'Error al copiar';

  @override
  String get fileOpDeleteFailed => 'Error al eliminar';

  @override
  String get fileOpDiskFull => 'Disco lleno';

  @override
  String get fileOpImporting => 'Importando…';

  @override
  String fileOpImportingName(String name) {
    return 'Importando $name…';
  }

  @override
  String fileOpMovingName(String name) {
    return 'Moviendo $name…';
  }

  @override
  String fileOpCopyingName(String name) {
    return 'Copiando $name…';
  }

  @override
  String get fileOpDeleting => 'Eliminando…';

  @override
  String fileOpDeletingName(String name) {
    return 'Eliminando $name…';
  }

  @override
  String fileOpDeletedSoFar(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos eliminados',
      one: '1 elemento eliminado',
    );
    return '$_temp0';
  }

  @override
  String get searchInSubfoldersHint => 'Buscar en todas las subcarpetas…';

  @override
  String get deepSearchEnabledTooltip =>
      'Buscando en subcarpetas — toca para buscar solo en la carpeta actual';

  @override
  String get deepSearchDisabledTooltip =>
      'Buscando en la carpeta actual — toca para buscar en subcarpetas';

  @override
  String get filterAction => 'Filtrar';

  @override
  String get bookmarkAction => 'Añadir a marcadores';

  @override
  String get unbookmarkAction => 'Quitar de marcadores';

  @override
  String get bookmarkSelectedAction => 'Añadir seleccionados a marcadores';

  @override
  String get unbookmarkSelectedAction => 'Quitar seleccionados de marcadores';

  @override
  String bookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se añadieron $count elementos a marcadores',
      one: 'Se añadió 1 elemento a marcadores',
    );
    return '$_temp0';
  }

  @override
  String unbookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se quitaron $count elementos de marcadores',
      one: 'Se quitó 1 elemento de marcadores',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => 'Mostrar barra de marcadores';

  @override
  String get showBookmarkBarDesc =>
      'Muestra los elementos marcados en una barra de marcadores o panel lateral';

  @override
  String get bookmarkBarSectionHeader => 'Barra de marcadores';

  @override
  String get noBookmarksYet => 'Aún no hay elementos marcados';

  @override
  String get reorderBookmarksTitle => 'Reordenar marcadores';

  @override
  String get reorderBookmarksDesc =>
      'Arrastra los elementos para reordenarlos en la barra de marcadores';

  @override
  String get navBarVaultsLabel => 'Bóvedas';

  @override
  String get navBarToolsLabel => 'Herramientas';

  @override
  String get toolsScreenTitle => 'Herramientas';

  @override
  String get toolsSectionContainerUtilities => 'Utilidades de contenedor';

  @override
  String get toolsSectionFileCryptography => 'Criptografía de archivos';

  @override
  String get toolsSectionStorageDiagnostics => 'Almacenamiento y diagnóstico';

  @override
  String get toolContainerSplitterTitle => 'Dividir y unir';

  @override
  String get toolContainerSplitterSubtitle =>
      'Divide un contenedor en partes, o vuelve a unirlas';

  @override
  String get toolContainerRepairTitle => 'Comprobar y reparar';

  @override
  String get toolContainerRepairSubtitle =>
      'Diagnostica problemas de cabecera o del sistema de archivos';

  @override
  String get toolSingleFileCryptoTitle => 'Cifrar / descifrar archivos';

  @override
  String get toolSingleFileCryptoSubtitle =>
      'Protege uno o varios archivos sin necesidad de un contenedor completo';

  @override
  String get toolStorageAnalyzerTitle => 'Analizador de almacenamiento';

  @override
  String get toolStorageAnalyzerSubtitle =>
      'Consulta qué está ocupando espacio en una bóveda montada';

  @override
  String get toolDuplicateFinderTitle => 'Buscador de archivos duplicados';

  @override
  String get toolDuplicateFinderSubtitle =>
      'Encuentra y elimina archivos duplicados idénticos byte a byte para liberar espacio';

  @override
  String get toolHashVerifierTitle =>
      'Verificador de suma de comprobación y hash';

  @override
  String get toolHashVerifierSubtitle =>
      'Verifica que los archivos grandes no se hayan dañado usando sumas de comprobación MD5/SHA';

  @override
  String get hashVerifierModeCompute => 'Calcular';

  @override
  String get hashVerifierModeVerify => 'Verificar';

  @override
  String get hashVerifierSelectSourceTitle => 'Seleccionar origen de archivos';

  @override
  String get hashVerifierAlgorithmsLabel => 'Algoritmos';

  @override
  String get hashVerifierNoAlgorithmSelected =>
      'Selecciona al menos un algoritmo';

  @override
  String get hashVerifierFilesLabel => 'Archivos para calcular hash';

  @override
  String hashVerifierFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos seleccionados',
      one: '1 archivo seleccionado',
      zero: 'Ningún archivo seleccionado',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierComputeButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Calcular $count hashes',
      one: 'Calcular hash',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCancelButton => 'Cancelar';

  @override
  String hashVerifierBatchProgressLabel(Object current, Object total) {
    return 'Archivo $current de $total';
  }

  @override
  String get hashVerifierCancelledMessage => 'Cancelado.';

  @override
  String hashVerifierComputeErrorsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Error al calcular el hash de $count archivos',
      one: 'Error al calcular el hash de 1 archivo',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCopiedMessage => 'Copiado al portapapeles';

  @override
  String get hashVerifierExportManifestButton => 'Exportar como manifiesto';

  @override
  String get hashVerifierExportAlgorithmLabel => 'Algoritmo del manifiesto';

  @override
  String hashVerifierExportSuccessMessage(Object path) {
    return 'Guardado en $path';
  }

  @override
  String hashVerifierExportFailedMessage(Object error) {
    return 'Error al exportar: $error';
  }

  @override
  String get hashVerifierLoadManifestButton => 'Cargar manifiesto';

  @override
  String get hashVerifierChangeManifestButton => 'Cambiar';

  @override
  String get hashVerifierManifestLabel => 'Archivo de manifiesto';

  @override
  String hashVerifierManifestEntryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entradas',
      one: '1 entrada',
      zero: 'Sin entradas',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierAutoAddFolderButton =>
      'Añadir todos los archivos de esta carpeta';

  @override
  String get hashVerifierAddFilesToVerifyButton =>
      'Añadir archivos para verificar';

  @override
  String get hashVerifierVerifyAllButton => 'Verificar todo';

  @override
  String hashVerifierVerifyProgressLabel(Object current, Object total) {
    return 'Verificando archivo $current de $total';
  }

  @override
  String hashVerifierSummaryMessage(
    Object ok,
    Object mismatch,
    Object missing,
  ) {
    return '$ok coinciden, $mismatch no coinciden, $missing faltan';
  }

  @override
  String get hashVerifierStatusMatch => 'Coincide';

  @override
  String get hashVerifierStatusMismatch => 'No coincide';

  @override
  String get hashVerifierStatusMissing => 'Archivo no añadido';

  @override
  String get hashVerifierStatusPending => 'Aún no verificado';

  @override
  String get hashVerifierExpectedLabel => 'Esperado';

  @override
  String get hashVerifierActualLabel => 'Actual';

  @override
  String hashVerifierExtraFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos adicionales no incluidos en el manifiesto',
      one: '1 archivo adicional no incluido en el manifiesto',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierNoManifestLoadedMessage =>
      'Carga un archivo de manifiesto para empezar';

  @override
  String get hashVerifierManifestParseEmptyMessage =>
      'No se encontraron entradas de suma de comprobación en este archivo';

  @override
  String hashVerifierLoadManifestFailedMessage(Object error) {
    return 'No se pudo leer el manifiesto: $error';
  }

  @override
  String hashVerifierAutoAddedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se añadieron $count archivos de la carpeta de la bóveda',
      one: 'Se añadió 1 archivo de la carpeta de la bóveda',
      zero: 'No se encontraron archivos nuevos',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierModeVault => 'Bóveda';

  @override
  String get hashVerifierVaultPickerLabel => 'Bóveda';

  @override
  String get hashVerifierVaultNoVaultsMessage =>
      'No hay ninguna bóveda montada actualmente';

  @override
  String get hashVerifierCheckEntireVaultButton => 'Comprobar toda la bóveda';

  @override
  String get hashVerifierVaultScanningLabel => 'Analizando bóveda…';

  @override
  String hashVerifierVaultFilesDiscoveredLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos encontrados',
      one: '1 archivo encontrado',
      zero: 'Aún no se han encontrado archivos',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmTitle => '¿Comprobar toda la bóveda?';

  @override
  String hashVerifierVaultConfirmFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos',
      one: '1 archivo',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmWarning =>
      'Se leerá cada archivo de esta bóveda.';

  @override
  String get hashVerifierVaultEmptyMessage =>
      'Esta bóveda no tiene archivos que comprobar';

  @override
  String get hashVerifierVaultStartButton => 'Iniciar comprobación';

  @override
  String hashVerifierVaultHashingProgressLabel(Object current, Object total) {
    return 'Comprobando $current / $total';
  }

  @override
  String get hashVerifierVaultCompleteTitle =>
      'Comprobación de la bóveda completada';

  @override
  String hashVerifierVaultCompleteFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos comprobados',
      one: '1 archivo comprobado',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteBytesLabel(Object size) {
    return '$size procesados';
  }

  @override
  String hashVerifierVaultCompleteSucceededLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correctos',
      one: '1 correcto',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fallidos',
      one: '1 fallido',
      zero: '0 fallidos',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultElapsedLabel(Object time) {
    return 'Tiempo transcurrido: $time';
  }

  @override
  String get hashVerifierVaultCancelledMessage =>
      'Comprobación de la bóveda cancelada.';

  @override
  String hashVerifierVaultFailedMessage(Object error) {
    return 'Error en la comprobación de la bóveda: $error';
  }

  @override
  String get hashVerifierVaultNewCheckButton => 'Nueva comprobación';

  @override
  String get hashVerifierVaultActionComputeTitle => 'Calcular toda la bóveda';

  @override
  String get hashVerifierVaultActionComputeSubtitle =>
      'Calcula el hash de cada archivo de una bóveda';

  @override
  String get hashVerifierVaultActionVerifyTitle => 'Verificar toda la bóveda';

  @override
  String get hashVerifierVaultActionVerifySubtitle =>
      'Comprueba cada archivo de una bóveda contra un manifiesto cargado';

  @override
  String get hashVerifierVaultChangeActionButton => 'Cambiar';

  @override
  String get hashVerifierVaultVerifyButton => 'Verificar toda la bóveda';

  @override
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage =>
      'Verificar toda una bóveda requiere un manifiesto cargado desde dentro de una bóveda.';

  @override
  String get duplicateFinderTargetLabel => 'Bóveda de destino';

  @override
  String get duplicateFinderTargetAllVaults => 'Todas las bóvedas abiertas';

  @override
  String get duplicateFinderStartScan => 'Iniciar análisis';

  @override
  String get duplicateFinderCancelScan => 'Cancelar análisis';

  @override
  String get duplicateFinderRescan => 'Volver a analizar';

  @override
  String get duplicateFinderScanningStage1 =>
      'Etapa 1: Indexación y agrupación por tamaño...';

  @override
  String get duplicateFinderScanningStage2 =>
      'Etapa 2: Comprobando cabeceras parciales de archivo...';

  @override
  String get duplicateFinderScanningStage3 =>
      'Etapa 3: Verificando hashes completos por bytes...';

  @override
  String get duplicateFinderScanComplete => 'Análisis completado';

  @override
  String get duplicateFinderNoDuplicatesTitle =>
      'No se encontraron archivos duplicados';

  @override
  String get duplicateFinderNoDuplicatesMessage =>
      'Todos los archivos de las bóvedas analizadas contienen contenido de bytes único.';

  @override
  String get duplicateFinderSelectRedundant => 'Seleccionar redundantes';

  @override
  String get duplicateFinderSelectAll => 'Seleccionar todo';

  @override
  String get duplicateFinderDeselectAll => 'Deseleccionar todo';

  @override
  String get duplicateFinderOriginalLabel => 'Original';

  @override
  String get duplicateFinderDuplicateLabel => 'Duplicado';

  @override
  String get duplicateFinderConfirmDeleteTitle =>
      '¿Eliminar archivos duplicados?';

  @override
  String get duplicateFinderSearchHint =>
      'Buscar duplicados por nombre de archivo o ruta...';

  @override
  String get toolNotImplementedYetMessage =>
      'Esta herramienta aún no está conectada al motor nativo — vuelve a comprobarlo en una futura actualización.';

  @override
  String get splitJoinModeSplit => 'Dividir';

  @override
  String get splitJoinModeJoin => 'Unir';

  @override
  String get splitSourceFileLabel => 'Archivo de origen';

  @override
  String get splitDestinationFolderLabel => 'Carpeta de destino';

  @override
  String get splitChunkSizeLabel => 'Tamaño de fragmento';

  @override
  String get splitChunkSizeCustomLabel => 'Tamaño personalizado (MB)';

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
  String get splitChunkSizeCustom => 'Personalizado';

  @override
  String get splitContainerButton => 'Dividir contenedor';

  @override
  String get joinFirstPartLabel => 'Primera parte';

  @override
  String get joinOutputFileNameLabel => 'Nombre del archivo de salida';

  @override
  String get joinContainerButton => 'Unir archivos';

  @override
  String get chooseFileButton => 'Elegir archivo';

  @override
  String get chooseFolderButton => 'Elegir carpeta';

  @override
  String get noFileSelectedLabel => 'Ningún archivo seleccionado';

  @override
  String get noFolderSelectedLabel => 'Ninguna carpeta seleccionada';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage =>
      'Contenedor dividido correctamente';

  @override
  String get joinContainerSuccessMessage => 'Archivos unidos correctamente';

  @override
  String get cryptoDirectionEncrypt => 'Cifrar';

  @override
  String get cryptoDirectionDecrypt => 'Descifrar';

  @override
  String get singleFileCryptoInputFileLabel => 'Archivos de entrada';

  @override
  String get singleFileCryptoCipherLabel => 'Cifrado';

  @override
  String get singleFileCryptoDeleteOriginalLabel =>
      'Eliminar archivos originales tras el cifrado';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Cifrar $count archivos',
      one: 'Cifrar archivo',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Descifrar $count archivos',
      one: 'Descifrar archivo',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Listo — $count archivos procesados',
      one: 'Listo',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return '$succeeded de $total archivos procesados — $failed fallaron';
  }

  @override
  String get singleFileCryptoAddFilesButton => 'Añadir archivos';

  @override
  String get singleFileCryptoClearFilesButton => 'Borrar';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos seleccionados',
      one: '1 archivo seleccionado',
      zero: 'Ningún archivo seleccionado',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return 'Archivo $current de $total';
  }

  @override
  String get repairTargetStepTitle => 'Elige un objetivo';

  @override
  String get repairTargetUnmountedFileOption => 'Archivo no montado';

  @override
  String get repairTargetUnmountedFileSubtitle =>
      'Restaura una cabecera de respaldo en un contenedor que no has abierto';

  @override
  String get repairTargetMountedVolumeSubtitle =>
      'Ejecuta una comprobación del sistema de archivos en una bóveda ya abierta';

  @override
  String get repairNoMountedVolumes =>
      'No hay ninguna bóveda montada actualmente';

  @override
  String get repairScanButton => 'Ejecutar análisis de diagnóstico';

  @override
  String get repairChangeTargetButton => 'Cambiar objetivo';

  @override
  String get repairDiagnosisHealthy => 'No se encontraron problemas';

  @override
  String get repairDiagnosisHeaderCorrupted => 'Cabecera dañada';

  @override
  String get repairDiagnosisFilesystemDirty =>
      'Sistema de archivos sucio / desmontaje incorrecto';

  @override
  String get repairRestoreBackupHeaderButton =>
      'Restaurar cabecera de respaldo';

  @override
  String get repairRunFilesystemCheckButton =>
      'Ejecutar comprobación y reparación del sistema de archivos';

  @override
  String get repairActionSucceededMessage =>
      'Reparación completada correctamente';

  @override
  String get repairActionFailedMessage =>
      'La acción de reparación no tuvo éxito';

  @override
  String get storageAnalyzerTargetLabel => 'Volumen';

  @override
  String get storageAnalyzerNoTargetsTitle => 'Nada que analizar';

  @override
  String get storageAnalyzerNoTargetsMessage =>
      'Monta primero una bóveda y vuelve aquí para ver su desglose de almacenamiento.';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return '$used de $total usados';
  }

  @override
  String get storageAnalyzerHeaviestFilesHeader => 'Archivos más pesados';

  @override
  String get storageAnalyzerBreakdownHeader => 'Por tipo de archivo';

  @override
  String get storageAnalyzerScanningMessage => 'Analizando volumen…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return 'El análisis se detuvo antes de tiempo tras $count archivos — los resultados pueden estar incompletos.';
  }

  @override
  String get storageAnalyzerNoFilesFound => 'No se encontraron archivos';

  @override
  String get storageCategoryImages => 'Imágenes';

  @override
  String get storageCategoryVideos => 'Vídeos';

  @override
  String get storageCategoryAudio => 'Audio';

  @override
  String get storageCategoryDocuments => 'Documentos';

  @override
  String get storageCategoryArchives => 'Archivos comprimidos';

  @override
  String get storageCategoryOther => 'Otro';

  @override
  String get keyfilePassphraseGeneratorTitle =>
      'Generador de archivos clave y frases de contraseña';

  @override
  String get keyfilePassphraseGeneratorSubtitle =>
      'Genera frases de contraseña Diceware, contraseñas personalizadas y archivos clave de alta entropía';

  @override
  String get tabPassphrase => 'Frase de contraseña';

  @override
  String get tabKeyfile => 'Archivo clave';

  @override
  String get modeDiceware => 'Frase de contraseña Diceware';

  @override
  String get modeCustomPassword => 'Contraseña personalizada';

  @override
  String get keyfileTypeBinary => 'Archivo clave binario (.key)';

  @override
  String get keyfileTypeImage => 'Archivo clave de imagen de ruido (.png)';

  @override
  String get copyPassphraseSuccess =>
      'Frase de contraseña copiada al portapapeles seguro';

  @override
  String get copyFingerprintSuccess => 'Huella SHA-256 copiada al portapapeles';

  @override
  String get saveKeyfileToVault => 'Guardar en la bóveda montada';

  @override
  String get exportKeyfileToStorage =>
      'Exportar al almacenamiento del dispositivo';

  @override
  String get keyfileNoOpenVaultsMessage =>
      'No hay ninguna bóveda abierta disponible. Monta primero una bóveda.';

  @override
  String get keyfileSelectDestinationVaultTitle =>
      'Seleccionar bóveda de destino';

  @override
  String keyfileVolumeIdLabel(Object volId) {
    return 'ID de volumen: $volId';
  }

  @override
  String keyfileExportSuccessMessage(Object path) {
    return 'Archivo clave exportado a $path';
  }

  @override
  String keyfileExportFailedMessage(Object error) {
    return 'Error al exportar: $error';
  }

  @override
  String keyfileSavedToVaultMessage(Object vaultName, Object path) {
    return 'Archivo clave guardado en $vaultName: $path';
  }

  @override
  String get keyfileWriteFailedMessage =>
      'Error al escribir el archivo clave en la bóveda';

  @override
  String keyfileSaveErrorMessage(Object error) {
    return 'Error al guardar en la bóveda: $error';
  }

  @override
  String get passphraseGeneratedSecretLabel => 'Secreto generado';

  @override
  String get copyToClipboardTooltip => 'Copiar al portapapeles';

  @override
  String get generateNewTooltip => 'Generar nuevo';

  @override
  String get passphraseStrengthWeak => 'Débil';

  @override
  String get passphraseStrengthGood => 'Buena';

  @override
  String get passphraseStrengthStrong => 'Fuerte';

  @override
  String get passphraseStrengthUnbreakable => 'Irrompible';

  @override
  String get passphraseCrackTimeInstant => '< 1 segundo';

  @override
  String get passphraseCrackTimeShort => 'Unos días o meses';

  @override
  String get passphraseCrackTimeCenturies => 'Varios siglos';

  @override
  String get passphraseCrackTimeMillionsOfYears => 'Millones de años';

  @override
  String passphraseStrengthLabel(Object label) {
    return 'Fortaleza: $label';
  }

  @override
  String passphraseEntropyBitsLabel(Object bits) {
    return '$bits bits de entropía';
  }

  @override
  String passphraseCrackTimeLabel(Object crackTime) {
    return 'Tiempo estimado de descifrado: $crackTime';
  }

  @override
  String get dicewareOptionsTitle => 'Opciones de Diceware de la EFF';

  @override
  String dicewareWordCountLabel(Object count) {
    return 'Número de palabras: $count palabras';
  }

  @override
  String dicewareWordCountBitsLabel(Object bits) {
    return '$bits bits';
  }

  @override
  String dicewareWordCountSliderLabel(Object count) {
    return '$count palabras';
  }

  @override
  String get dicewareWordSeparatorLabel => 'Separador de palabras';

  @override
  String get dicewareSeparatorHyphen => 'Guion ( - )';

  @override
  String get dicewareSeparatorSpace => 'Espacio (   )';

  @override
  String get dicewareSeparatorUnderscore => 'Guion bajo ( _ )';

  @override
  String get dicewareSeparatorDot => 'Punto ( . )';

  @override
  String get dicewareSeparatorSlash => 'Barra ( / )';

  @override
  String get dicewareWordCasingLabel => 'Uso de mayúsculas';

  @override
  String get dicewareCasingLowercase => 'minúsculas';

  @override
  String get dicewareCasingTitleCase => 'Tipo Título';

  @override
  String get dicewareCasingUppercase => 'MAYÚSCULAS';

  @override
  String get dicewareAppendDigitLabel => 'Añadir dígito aleatorio (0-9)';

  @override
  String get dicewareAppendSymbolLabel => 'Añadir símbolo aleatorio (!@#\$%)';

  @override
  String get customPasswordOptionsTitle =>
      'Opciones de contraseña personalizada';

  @override
  String customPasswordLengthLabel(Object length) {
    return 'Longitud: $length caracteres';
  }

  @override
  String customPasswordLengthSliderLabel(Object length) {
    return '$length caracteres';
  }

  @override
  String get customPasswordUppercaseLabel => 'Letras mayúsculas (A-Z)';

  @override
  String get customPasswordLowercaseLabel => 'Letras minúsculas (a-z)';

  @override
  String get customPasswordNumbersLabel => 'Números (0-9)';

  @override
  String get customPasswordSymbolsLabel => 'Símbolos (!@#\$%^&*)';

  @override
  String get customPasswordExcludeAmbiguousLabel =>
      'Excluir ambiguos (1, l, I, 0, O)';

  @override
  String get keyfileBinarySizeTitle => 'Tamaño del archivo clave binario';

  @override
  String get keyfileImageResolutionTitle => 'Resolución de la imagen de ruido';

  @override
  String get keyfilePresetBytes64 => '64 bytes (estándar VeraCrypt)';

  @override
  String get keyfilePresetBytes256 => '256 bytes';

  @override
  String get keyfilePresetBytes2048 => '2 KB';

  @override
  String get keyfilePresetBytes64kb => '64 KB';

  @override
  String get keyfilePresetBytes1mb => '1 MB (límite máximo)';

  @override
  String get keyfilePresetRes64 => '64 x 64 píxeles (~16 KB)';

  @override
  String get keyfilePresetRes256 => '256 x 256 píxeles (~256 KB)';

  @override
  String get keyfilePresetRes512 => '512 x 512 píxeles (~1 MB)';

  @override
  String get keyfileGenerateNewTooltip => 'Generar nuevo archivo clave';

  @override
  String keyfileSizeLabel(Object size) {
    return 'Tamaño: $size';
  }

  @override
  String get keyfileFingerprintLabel => 'Huella SHA-256';

  @override
  String get keyfileCopyFingerprintTooltip => 'Copiar huella';

  @override
  String get duplicateFinderNoVaultsTitle => 'No hay bóvedas montadas';

  @override
  String get duplicateFinderNoVaultsMessage =>
      'Desbloquea y monta al menos una bóveda para buscar archivos duplicados.';

  @override
  String duplicateFinderConfirmDeleteMessage(Object count, Object size) {
    return '¿Seguro que quieres eliminar permanentemente $count archivo(s) duplicado(s) ($size) de tus bóvedas? Esta acción no se puede deshacer.';
  }

  @override
  String get duplicateFinderDeletePermanentlyButton =>
      'Eliminar permanentemente';

  @override
  String duplicateFinderDeleteSuccessMessage(Object count) {
    return 'Se eliminaron correctamente $count archivo(s) duplicado(s).';
  }

  @override
  String get duplicateFinderIntroTitle =>
      'Buscador de duplicados exactos en 3 etapas';

  @override
  String get duplicateFinderIntroSubtitle =>
      'Detecta contenido idéntico exacto sin importar los nombres de archivo.';

  @override
  String get duplicateFinderStagesDescription =>
      '• Etapa 1: Agrupación por tamaño (recorrido de metadatos instantáneo)\n• Etapa 2: Comprobación de cabecera parcial (cabecera SHA-256 de 16 KB)\n• Etapa 3: Verificación de hash completo (coincidencia exacta de bytes SHA-256)';

  @override
  String get duplicateFinderScanningVaultFallback => 'Analizando bóveda...';

  @override
  String duplicateFinderProcessingFileLabel(Object fileName) {
    return 'Procesando: $fileName';
  }

  @override
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  ) {
    return 'Archivos analizados: $scanned | Duplicados encontrados: $groups grupos ($saved)';
  }

  @override
  String duplicateFinderGroupsFoundLabel(Object count) {
    return '$count grupos de duplicados encontrados';
  }

  @override
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved) {
    return '$copies copias encontradas • Ahorra $saved de espacio de almacenamiento';
  }

  @override
  String duplicateFinderVaultsSelectedLabel(Object count) {
    return '$count bóvedas seleccionadas';
  }

  @override
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  ) {
    return 'Grupo $groupIndex: $size ($count copias encontradas)';
  }

  @override
  String duplicateFinderRecoverableSpaceLabel(Object size) {
    return 'Espacio recuperable: $size';
  }

  @override
  String get duplicateFinderPreviewFileTooltip => 'Vista previa del archivo';

  @override
  String duplicateFinderPreviewFailedMessage(Object fileName) {
    return 'No se pudo abrir la vista previa del archivo para $fileName';
  }

  @override
  String duplicateFinderPreviewErrorMessage(Object error) {
    return 'Error al previsualizar el archivo: $error';
  }

  @override
  String duplicateFinderFilesSelectedLabel(Object count) {
    return '$count archivos seleccionados';
  }

  @override
  String duplicateFinderBytesToBeFreedLabel(Object size) {
    return '$size que se liberarán';
  }

  @override
  String duplicateFinderDeleteSelectedButton(Object count) {
    return 'Eliminar seleccionados ($count)';
  }

  @override
  String get vaultBrowserSwitchVaultTooltip => 'Cambiar de bóveda';

  @override
  String get vaultBrowserRootFolderLabel => 'Carpeta raíz';

  @override
  String vaultFilePickerTitle(Object vaultName) {
    return 'Seleccionar archivos ($vaultName)';
  }

  @override
  String get vaultFilePickerEmptyMessage => 'La carpeta está vacía';

  @override
  String vaultFilePickerConfirmButton(Object count) {
    return 'Seleccionar $count archivo(s)';
  }

  @override
  String vaultFolderPickerTitle(Object vaultName) {
    return 'Seleccionar carpeta ($vaultName)';
  }

  @override
  String get vaultFolderPickerEmptyMessage => 'No hay subcarpetas aquí';

  @override
  String get vaultFolderPickerRootLabel => 'Raíz';

  @override
  String get vaultFolderPickerConfirmRootButton => 'Seleccionar carpeta raíz';

  @override
  String vaultFolderPickerConfirmNamedButton(Object folderName) {
    return 'Seleccionar \"$folderName\"';
  }

  @override
  String get singleFileCryptoSelectInputTitle =>
      'Seleccionar archivos de entrada';

  @override
  String get singleFileCryptoFromDeviceTitle =>
      'Desde el almacenamiento del dispositivo';

  @override
  String get singleFileCryptoFromDeviceSubtitle =>
      'Elige archivos del dispositivo con el selector de archivos del sistema';

  @override
  String get singleFileCryptoFromVaultTitle => 'Desde una bóveda montada';

  @override
  String get singleFileCryptoFromVaultSubtitle =>
      'Elige archivos de un contenedor cifrado abierto';

  @override
  String get singleFileCryptoSelectDestinationTitle =>
      'Seleccionar carpeta de destino';

  @override
  String get singleFileCryptoDeviceFolderTitle =>
      'Carpeta de almacenamiento del dispositivo';

  @override
  String get singleFileCryptoDeviceFolderSubtitle =>
      'Guarda el resultado en una carpeta del almacenamiento del dispositivo';

  @override
  String get singleFileCryptoVaultFolderTitle => 'Carpeta de bóveda montada';

  @override
  String get singleFileCryptoVaultFolderSubtitle =>
      'Guarda el resultado dentro de un contenedor cifrado abierto';

  @override
  String get toolsSectionBackupSync => 'Copia de seguridad y sincronización';

  @override
  String get toolVaultSyncTitle => 'Sincronización de bóvedas';

  @override
  String get toolVaultSyncSubtitle =>
      'Compara dos bóvedas y copia lo que falte o sea más reciente';

  @override
  String get vaultSyncNoVaultsTitle => 'No hay bóvedas montadas';

  @override
  String get vaultSyncNoVaultsMessage =>
      'Monta al menos una bóveda para comparar y sincronizar sus archivos.';

  @override
  String get vaultSyncLeftLabel => 'Izquierda';

  @override
  String get vaultSyncRightLabel => 'Derecha';

  @override
  String get vaultSyncTapToSelect =>
      'Toca para seleccionar una bóveda y carpeta';

  @override
  String get vaultSyncSwapTooltip => 'Intercambiar izquierda y derecha';

  @override
  String get vaultSyncSameLocationWarning =>
      'Izquierda y Derecha deben ser carpetas diferentes.';

  @override
  String get vaultSyncIntroTitle => 'Comparar dos bóvedas';

  @override
  String get vaultSyncIntroSubtitle =>
      'Elige una bóveda Izquierda y otra Derecha (o dos carpetas en la misma bóveda) para ver qué falta, se modificó o es más reciente en cada lado.';

  @override
  String get vaultSyncCompareButton => 'Comparar';

  @override
  String get vaultSyncComparingLabel => 'Comparando bóvedas…';

  @override
  String vaultSyncCompareStatsLabel(Object dirs, Object entries) {
    return 'Carpetas analizadas: $dirs | Diferencias encontradas: $entries';
  }

  @override
  String get vaultSyncCancelCompareButton => 'Cancelar';

  @override
  String get vaultSyncInSyncTitle => 'Ya sincronizadas';

  @override
  String vaultSyncInSyncMessage(num count) {
    return 'Los $count archivos coincidentes son idénticos en ambos lados.';
  }

  @override
  String get vaultSyncRecompareButton => 'Volver a comparar';

  @override
  String vaultSyncDifferencesFoundLabel(num count) {
    return '$count diferencias encontradas';
  }

  @override
  String vaultSyncInSyncCountLabel(num count) {
    return '$count archivos ya coinciden en ambos lados';
  }

  @override
  String vaultSyncBadgeOnlyLeft(Object count) {
    return '$count solo en Izquierda';
  }

  @override
  String vaultSyncBadgeOnlyRight(Object count) {
    return '$count solo en Derecha';
  }

  @override
  String vaultSyncBadgeLeftNewer(Object count) {
    return '$count más recientes en Izquierda';
  }

  @override
  String vaultSyncBadgeRightNewer(Object count) {
    return '$count más recientes en Derecha';
  }

  @override
  String vaultSyncBadgeConflicts(num count) {
    return '$count necesitan revisión';
  }

  @override
  String get vaultSyncDirectionLabel => 'Dirección de sincronización';

  @override
  String get vaultSyncDirectionTwoWay => 'Bidireccional (recomendado)';

  @override
  String get vaultSyncDirectionTwoWaySubtitle =>
      'Copia cada archivo al lado donde falte o tenga una copia más antigua';

  @override
  String get vaultSyncDirectionLeftToRight =>
      'Izquierda → Derecha (unidireccional)';

  @override
  String get vaultSyncDirectionLeftToRightSubtitle =>
      'Envía archivos nuevos y actualizados de Izquierda a Derecha; nunca modifica Izquierda';

  @override
  String get vaultSyncDirectionRightToLeft =>
      'Derecha → Izquierda (unidireccional)';

  @override
  String get vaultSyncDirectionRightToLeftSubtitle =>
      'Envía archivos nuevos y actualizados de Derecha a Izquierda; nunca modifica Derecha';

  @override
  String get vaultSyncSearchHint => 'Buscar diferencias';

  @override
  String get vaultSyncStatusOnlyLeft => 'Solo Izquierda';

  @override
  String get vaultSyncStatusOnlyRight => 'Solo Derecha';

  @override
  String get vaultSyncStatusLeftNewer => 'Izquierda más reciente';

  @override
  String get vaultSyncStatusRightNewer => 'Derecha más reciente';

  @override
  String get vaultSyncStatusConflict => 'Necesita revisión';

  @override
  String get vaultSyncStatusTypeMismatch => 'Tipos no coinciden';

  @override
  String get vaultSyncFolderOnlyLeftDetail => 'Carpeta — solo en Izquierda';

  @override
  String get vaultSyncFolderOnlyRightDetail => 'Carpeta — solo en Derecha';

  @override
  String vaultSyncBothSidesDetail(
    Object leftSize,
    Object leftDate,
    Object rightSize,
    Object rightDate,
  ) {
    return 'I: $leftSize · $leftDate  →  D: $rightSize · $rightDate';
  }

  @override
  String get vaultSyncTypeMismatchTooltip =>
      'Un archivo en un lado y una carpeta en el otro — resuélvelo manualmente en el explorador de archivos';

  @override
  String get vaultSyncChangeActionTooltip => 'Cambiar acción de sincronización';

  @override
  String get vaultSyncActionCopyToRight => 'Copiar → Derecha';

  @override
  String get vaultSyncActionCopyToLeft => 'Copiar → Izquierda';

  @override
  String get vaultSyncActionSkip => 'Omitir';

  @override
  String vaultSyncChangesQueuedLabel(num count) {
    return '$count cambios en cola';
  }

  @override
  String get vaultSyncSyncNowButton => 'Sincronizar ahora';

  @override
  String get vaultSyncConfirmTitle => '¿Iniciar sincronización?';

  @override
  String vaultSyncConfirmMessage(num count, Object bytes) {
    return 'Esto copiará $count elementos ($bytes en total) entre ambos lados. Los archivos existentes con el mismo nombre se sobrescribirán.';
  }

  @override
  String vaultSyncStartedMessage(num count) {
    return 'Sincronización iniciada — $count elementos en cola';
  }

  @override
  String vaultSyncPickLocationTitle(Object side) {
    return 'Seleccionar bóveda y carpeta de $side';
  }

  @override
  String get vaultSyncReadOnlyBadge => 'Solo lectura';

  @override
  String get vaultSyncReadOnlyTooltip =>
      'Esta bóveda está montada en modo de solo lectura — no se pueden copiar archivos en ella';

  @override
  String get vaultSyncSyncingButton => 'Sincronizando…';

  @override
  String get vaultSyncNotEnoughSpaceTitle => 'Espacio insuficiente';

  @override
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  ) {
    return 'No hay suficiente espacio en $side — se necesitan $required, solo hay $free libres.';
  }

  @override
  String get removeMasterPasswordTitle => 'Quitar contraseña maestra';

  @override
  String get confirmRemoveMasterPasswordMessage =>
      'Introduce tu contraseña maestra actual para confirmar la eliminación:';

  @override
  String get authenticateToRemoveMasterPassword =>
      'Autenticar para quitar la contraseña maestra';

  @override
  String get incorrectPassword => 'Contraseña incorrecta';

  @override
  String get rememberPerFolderLayoutLabel => 'Remember Per-Folder Layout';

  @override
  String get rememberPerFolderLayoutDesc =>
      'Save separate view layout (list, grid, masonry) for each folder';
}
