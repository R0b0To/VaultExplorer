// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Fechar';

  @override
  String get search => 'Pesquisar';

  @override
  String get goBack => 'Voltar';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => 'Ir para a página';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return 'Número da página (1 - $pageCount)';
  }

  @override
  String get pdfViewerPageLabel => 'Página';

  @override
  String get pdfViewerGoButton => 'Ir';

  @override
  String get pdfViewerSearchHint => 'Pesquisar no documento';

  @override
  String get pdfViewerNoMatches => 'Nenhum resultado';

  @override
  String get pdfViewerPreviousMatch => 'Resultado anterior';

  @override
  String get pdfViewerNextMatch => 'Próximo resultado';

  @override
  String get pdfViewerCloseSearch => 'Fechar pesquisa';

  @override
  String get pdfViewerPrintTooltip => 'Imprimir documento';

  @override
  String get pdfViewerLoadingDocument => 'Carregando documento…';

  @override
  String get pdfViewerCannotOpenTitle => 'Não foi possível abrir o PDF';

  @override
  String get pdfViewerFailedToLoad => 'Falha ao carregar o PDF';

  @override
  String get pdfViewerEditTooltip => 'Editar';

  @override
  String get pdfViewerDoneEditingTooltip => 'Concluir edição';

  @override
  String get pdfViewerSaveFailed =>
      'Não foi possível salvar as alterações neste PDF';

  @override
  String get pdfViewerEditUnavailable =>
      'A edição não está disponível para este documento';

  @override
  String get paste => 'Colar';

  @override
  String get clear => 'Limpar';

  @override
  String get clipboardVerbMove => 'Mover';

  @override
  String get clipboardVerbCopy => 'Copiar';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb ($count) — Toque para detalhes, toque e segure para colar';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb ($count) — Detalhes da área de transferência';
  }

  @override
  String clipboardSourceLabel(String source) {
    return 'Origem: $source';
  }

  @override
  String get clipboardDefaultSourceName => 'Cofre';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '1 item',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count itens a mais',
      one: '+1 item a mais',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => 'Parâmetros avançados';

  @override
  String get pimFieldLabel => 'PIM  (deixe em branco para o padrão)';

  @override
  String get encryptionAlgorithmLabel => 'Algoritmo de criptografia';

  @override
  String get hashAlgorithmLabel => 'Algoritmo de hash';

  @override
  String get clipboardVerbMoving => 'Movendo';

  @override
  String get clipboardVerbCopying => 'Copiando';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '1 item',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return ' de \"$source\"';
  }

  @override
  String get clipboardOpenContainerToPaste => 'Abra um contêiner para colar';

  @override
  String get keyfilesOptionalLabel => 'Arquivos-chave (opcional)';

  @override
  String get addFile => 'Adicionar arquivo';

  @override
  String get noKeyfilesAttached => 'Nenhum arquivo-chave anexado';

  @override
  String get completed => 'Concluído';

  @override
  String get dismiss => 'Dispensar';

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
      other: '$count transferências',
      one: '1 transferência',
    );
    return '$_temp0';
  }

  @override
  String multiOpSublabel(String summary) {
    return '$summary · toque para ver tudo';
  }

  @override
  String get thumbnailSizeResolutionLabel => 'Tamanho da miniatura (resolução)';

  @override
  String get jpegCompressionQualityLabel => 'Qualidade de compressão JPEG';

  @override
  String get done => 'Concluído';

  @override
  String get confirm => 'Confirmar';

  @override
  String get couldNotPickKeyfiles =>
      'Não foi possível selecionar os arquivos-chave';

  @override
  String get filesystemLabelEncryptedVault => 'este cofre criptografado';

  @override
  String get filesystemLabelThisContainer => 'este contêiner';

  @override
  String get nounFile => 'arquivo';

  @override
  String get nounFolder => 'pasta';

  @override
  String get nounFileCapitalized => 'Arquivo';

  @override
  String get nounFolderCapitalized => 'Pasta';

  @override
  String get unitBytes => 'bytes';

  @override
  String get unitCharacters => 'caracteres';

  @override
  String get validationEmptyName => 'O nome não pode ficar vazio.';

  @override
  String validationReservedNavName(String name, String noun) {
    return '\"$name\" é um nome de navegação reservado e não pode ser usado como nome de $noun.';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return '\"$char\" na posição $position não é permitido em um nome em $fsLabel.';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return 'A posição $position contém um caractere de controle não imprimível (código $code), o que não é permitido em $fsLabel.';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '\"$name\" é um nome de dispositivo reservado em $fsLabel (corresponde a CON, PRN, AUX, NUL, COM0–9 ou LPT0–9) e não pode ser usado, com ou sem extensão de arquivo.';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return 'Nomes de $noun não podem terminar com um espaço em $fsLabel';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return 'Nomes de $noun não podem terminar com um \".\" em $fsLabel';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return 'Este nome tem $length $unit; $fsLabel permite no máximo $maxLength $unit por nome de $noun.';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return 'O caminho completo tem $length caracteres; $fsLabel permite no máximo $maxLength.';
  }

  @override
  String conflictSameType(String noun, String name) {
    return 'Já existe aqui um $noun chamado \"$name\".';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return 'Já existe aqui um $existingNoun chamado \"$name\" — ele não pode compartilhar o nome com um $candidateNoun.';
  }

  @override
  String get readOnlyContainerWarning =>
      'Este contêiner está montado somente leitura.';

  @override
  String get hiddenVolumeProtectionTriggeredWarning =>
      'Uma gravação neste volume externo teria danificado o volume oculto, então ela foi bloqueada. Este contêiner foi alternado para somente leitura pelo restante desta sessão.';

  @override
  String get protectHiddenVolumeToggleTitle => 'Proteger volume oculto';

  @override
  String get protectHiddenVolumeToggleSubtitle =>
      'Evitar danos causados pela gravação no volume externo';

  @override
  String get protectHiddenVolumeCredentialsRequired =>
      'É necessária uma senha ou arquivo-chave do volume oculto para protegê-lo';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir $count itens?',
      one: 'Excluir 1 item?',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning =>
      'Estes itens serão excluídos permanentemente, incluindo todo o conteúdo de quaisquer pastas selecionadas.';

  @override
  String get deleteFilesWarning =>
      'Estes itens serão apagados permanentemente do seu volume criptografado.';

  @override
  String get delete => 'Excluir';

  @override
  String get remove => 'Remover';

  @override
  String get create => 'Criar';

  @override
  String get rename => 'Renomear';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Renomear $count itens',
      one: 'Renomear 1 item',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => 'Nova pasta';

  @override
  String get newTextFileTitle => 'Novo arquivo de texto';

  @override
  String get folderNameHint => 'Nome da pasta';

  @override
  String get filenameHint => 'nomedoarquivo.txt';

  @override
  String get newNameHint => 'Novo nome';

  @override
  String get baseNameHint => 'Nome base';

  @override
  String couldntCreateItem(String name) {
    return 'Não foi possível criar \"$name\" — verifique se o contêiner ainda está montado';
  }

  @override
  String couldntRenameSingle(String name) {
    return 'Não foi possível renomear \"$name\" — pode já existir um item com esse nome';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Não foi possível renomear $count itens: $reason',
      one: 'Não foi possível renomear 1 item: $reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Não foi possível renomear $count itens',
      one: 'Não foi possível renomear 1 item',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize =>
      'Insira um tamanho oculto válido maior que 0';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter =>
      'O tamanho do volume oculto deve ser menor que o do volume externo';

  @override
  String get hiddenVolumeErrorTooLargeForContainer =>
      'O tamanho do volume oculto é muito grande para o tamanho deste contêiner';

  @override
  String get hiddenVolumeErrorCredentialsRequired =>
      'É necessária uma senha oculta ou arquivo-chave ao criar um volume oculto';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      'As credenciais do volume oculto (senha, PIM e arquivos-chave) não podem ser idênticas às credenciais do volume externo.';

  @override
  String get vaultItemTypePassword => 'Senha';

  @override
  String get vaultItemTypePaymentCard => 'Cartão de Pagamento';

  @override
  String get vaultItemTypeIdentity => 'Identidade';

  @override
  String get vaultItemTypeSecureNote => 'Nota Segura';

  @override
  String get vaultItemTypeBankAccount => 'Conta Bancária';

  @override
  String get vaultItemTypeSoftwareLicense => 'Licença de Software';

  @override
  String get fieldUsernameEmail => 'Usuário / E-mail';

  @override
  String get fieldPassword => 'Senha';

  @override
  String get fieldWebsiteUrl => 'URL do Site';

  @override
  String get fieldTotpSecret => 'Segredo TOTP (2FA)';

  @override
  String get fieldNotes => 'Notas';

  @override
  String get fieldCardholderName => 'Nome do Titular';

  @override
  String get fieldCardNumber => 'Número do Cartão';

  @override
  String get fieldExpiryMMYY => 'Validade (MM/AA)';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldIssuingBank => 'Banco Emissor';

  @override
  String get fieldFullName => 'Nome Completo';

  @override
  String get fieldDateOfBirth => 'Data de Nascimento';

  @override
  String get fieldNationality => 'Nacionalidade';

  @override
  String get fieldPassportNumber => 'Número do Passaporte';

  @override
  String get fieldPassportExpiry => 'Validade do Passaporte';

  @override
  String get fieldNationalIdSsn => 'Identidade Nacional / CPF';

  @override
  String get fieldDriversLicense => 'Carteira de Motorista';

  @override
  String get fieldAddress => 'Endereço';

  @override
  String get fieldPhone => 'Telefone';

  @override
  String get fieldEmail => 'E-mail';

  @override
  String get fieldNote => 'Nota';

  @override
  String get fieldBankName => 'Nome do Banco';

  @override
  String get fieldAccountHolder => 'Titular da Conta';

  @override
  String get fieldAccountNumber => 'Número da Conta';

  @override
  String get fieldRoutingSortCode => 'Código de Roteamento / Código Bancário';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => 'Tipo de Conta';

  @override
  String get fieldProductName => 'Nome do Produto';

  @override
  String get fieldLicenseKey => 'Chave de Licença';

  @override
  String get fieldRegisteredTo => 'Registrado Para';

  @override
  String get fieldPurchaseDate => 'Data de Compra';

  @override
  String get fieldExpiryRenewalDate => 'Data de Expiração / Renovação';

  @override
  String get fieldDownloadUrl => 'URL de Download';

  @override
  String get fieldRegistrationEmail => 'E-mail de Registro';

  @override
  String get titleRequired => 'O título é obrigatório';

  @override
  String newTypeTitle(String typeLabel) {
    return 'Novo $typeLabel';
  }

  @override
  String editItemTitle(String title) {
    return 'Editar $title';
  }

  @override
  String get save => 'Salvar';

  @override
  String typeNameHint(String typeLabel) {
    return 'Nome do $typeLabel';
  }

  @override
  String get titleSectionLabel => 'Título';

  @override
  String get fieldsSectionLabel => 'Campos';

  @override
  String get encryptedStorageHint =>
      'Todos os campos são armazenados criptografados dentro do contêiner.';

  @override
  String copiedSuffix(String fieldLabel) {
    return '$fieldLabel copiado';
  }

  @override
  String get copy => 'Copiar';

  @override
  String get failedToSaveCheckMounted =>
      'Falha ao salvar — verifique se o contêiner ainda está montado';

  @override
  String get discardChangesTitle => 'Descartar alterações?';

  @override
  String get discardChangesMessage =>
      'Suas alterações não salvas serão perdidas.';

  @override
  String get discard => 'Descartar';

  @override
  String get keepEditing => 'Continuar editando';

  @override
  String get deleteItemTitle => 'Excluir item?';

  @override
  String deleteItemMessage(String title) {
    return '\"$title\" será permanentemente excluído do cofre.';
  }

  @override
  String get removeFromBookmarks => 'Remover dos favoritos';

  @override
  String get addToBookmarks => 'Adicionar aos favoritos';

  @override
  String get edit => 'Editar';

  @override
  String labelCopiedToClipboard(String label) {
    return '$label copiado para a área de transferência';
  }

  @override
  String get noFieldsFilledIn =>
      'Nenhum campo preenchido.\nToque em Editar para adicionar detalhes.';

  @override
  String get sectionLabelDetails => 'Detalhes';

  @override
  String get sectionLabelInfo => 'Informações';

  @override
  String get metaLabelType => 'Tipo';

  @override
  String get metaLabelCreated => 'Criado';

  @override
  String get metaLabelModified => 'Modificado';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return 'Copiar $fieldLabel';
  }

  @override
  String get readOnlyCantAddItemsTooltip =>
      'Somente leitura — não é possível adicionar itens';

  @override
  String get extractArchive => 'Extrair Arquivo Compactado';

  @override
  String get newItemTooltip => 'Novo item';

  @override
  String get camera => 'Câmera';

  @override
  String get importFiles => 'Importar Arquivos';

  @override
  String get importFolder => 'Importar Pasta';

  @override
  String get secureItem => 'Item Seguro';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archive Explorer';

  @override
  String get archiveExplorerPermissionTitle =>
      'Acesso ao armazenamento necessário';

  @override
  String get archiveExplorerPermissionMessage =>
      'Permita o acesso aos seus arquivos para navegar e extrair arquivos .zip da pasta Downloads.';

  @override
  String get archiveExplorerGrantAccess => 'Conceder Acesso';

  @override
  String get archiveExplorerEmptyTitle =>
      'Nenhum arquivo compactado encontrado';

  @override
  String get archiveExplorerEmptyMessage =>
      'Os arquivos zip que você baixar aparecerão aqui.';

  @override
  String get archiveExplorerRefreshTooltip => 'Atualizar';

  @override
  String archiveExplorerEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get archiveExplorerExtractAll => 'Extrair Tudo';

  @override
  String get archiveExplorerExtracting => 'Extraindo…';

  @override
  String archiveExplorerExtractSuccess(int count, String name) {
    return '$count arquivos extraídos para Download/Extracted/$name';
  }

  @override
  String get archiveExplorerExtractFailed =>
      'Não foi possível extrair esse arquivo compactado.';

  @override
  String get archiveExplorerOpenFailed =>
      'Não foi possível abrir esse arquivo compactado.';

  @override
  String get archiveExplorerOpenArchive => 'Abrir arquivo compactado…';

  @override
  String get archiveExplorerUnresolvedPath =>
      'Não foi possível acessar esse arquivo diretamente. Tente escolher um da pasta Downloads.';

  @override
  String get archiveExplorerExtractTo => 'Extrair para…';

  @override
  String get archiveExplorerPreview => 'Visualizar';

  @override
  String get archiveExplorerChoosingDestination => 'Escolhendo destino…';

  @override
  String get archiveExplorerNoDestinationChosen => 'Nenhum destino escolhido.';

  @override
  String archiveExplorerExtractSuccessTo(int count, String path) {
    return '$count arquivos extraídos para $path';
  }

  @override
  String get archiveBrowserEmptyTitle => 'Pasta vazia';

  @override
  String get archiveBrowserEmptyMessage =>
      'Esta pasta não contém nenhum arquivo.';

  @override
  String get archiveBrowserRoot => 'Arquivo';

  @override
  String get archiveBrowserOpenFileFailed =>
      'Não foi possível abrir esse arquivo.';

  @override
  String get fileAssocInAppTextEditor => 'Editor de Texto Integrado';

  @override
  String get fileAssocInAppMediaViewer => 'Visualizador de Mídia Integrado';

  @override
  String fileAssocAppPrefix(String name) {
    return 'App: $name';
  }

  @override
  String get fileAssocExternalApp => 'App Externo';

  @override
  String get appSettingsTitle => 'Configurações do App';

  @override
  String get sectionSecurityPrivacy => 'Segurança e Privacidade';

  @override
  String get sectionAppearanceInterface => 'Aparência e Interface';

  @override
  String get sectionVaultFileHandling => 'Cofre e Gerenciamento de Arquivos';

  @override
  String get masterPasswordTitle => 'Senha Mestra';

  @override
  String get masterPasswordActiveSubtitle =>
      'Ativa — toque no interruptor para remover';

  @override
  String get masterPasswordInactiveSubtitle =>
      'Exigir uma senha para abrir o app';

  @override
  String get newPasswordLabel => 'Nova Senha';

  @override
  String get masterPasswordFieldLabel => 'Senha mestra';

  @override
  String get confirmPasswordLabel => 'Confirmar senha';

  @override
  String get update => 'Atualizar';

  @override
  String get setPassword => 'Definir Senha';

  @override
  String get biometricUnlockTitle => 'Desbloqueio Biométrico';

  @override
  String get biometricUnlockSubtitle =>
      'Autentique-se para montar o contêiner com segurança';

  @override
  String get changeMasterPasswordTitle => 'Alterar Senha Mestra';

  @override
  String get changeMasterPasswordSubtitle =>
      'Atualizar as credenciais da senha mestra';

  @override
  String get autoLockContainersTitle => 'Bloqueio Automático de Contêineres';

  @override
  String get autoLockContainersSubtitle =>
      'Bloquear automaticamente os cofres abertos após inatividade';

  @override
  String get autoLockTimeoutLabel => 'Tempo para Bloqueio Automático';

  @override
  String get immediately => 'Imediatamente';

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
  String get blockScreenshotsTitle => 'Bloquear Capturas de Tela';

  @override
  String get blockScreenshotsSubtitle =>
      'Impedir capturas de tela e ocultar a pré-visualização em apps recentes';

  @override
  String get keepVaultsRunningInBackgroundTitle =>
      'Manter Cofres Ativos em Segundo Plano';

  @override
  String get keepVaultsRunningInBackgroundSubtitle =>
      'Exibir uma notificação e manter os cofres abertos disponíveis após sair do app. As chaves do cofre permanecem na memória até serem bloqueadas.';

  @override
  String get notificationPermissionDeniedMessage =>
      'Permissão de notificação negada. Os cofres continuarão abertos, mas a notificação contínua não será exibida.';

  @override
  String get discreteModeTitle => 'Modo Disfarce';

  @override
  String get discreteModeActiveSubtitle =>
      'Ativo — o app atualmente aparece como \"Archive Explorer\"';

  @override
  String get discreteModeInactiveSubtitle =>
      'Disfarçar este app como um navegador de arquivos zip na tela inicial';

  @override
  String get enableDiscreteModeTitle => 'Ativar Modo Disfarce?';

  @override
  String get disableDiscreteModeTitle => 'Desativar Modo Disfarce?';

  @override
  String get enableDiscreteModeMessage =>
      'O ícone e o nome do app na sua tela inicial mudarão para \"Archive Explorer\". Ele funcionará como um navegador e extrator de arquivos zip.\n\nPara acessar seu cofre, abra o Archive Explorer e mantenha o dedo sobre o título por 2 segundos.';

  @override
  String get disableDiscreteModeMessage =>
      'O ícone e o nome do app na sua tela inicial voltarão a ser \"Vault Explorer\".';

  @override
  String get enable => 'Ativar';

  @override
  String get disable => 'Desativar';

  @override
  String get discreteModeEnabledSnack =>
      'Modo Disfarce ativado. O app será fechado — reabra pelo novo ícone na tela inicial.';

  @override
  String get discreteModeDisabledSnack =>
      'Modo Disfarce desativado. O app será fechado — reabra pelo novo ícone na tela inicial.';

  @override
  String get failedToChangeDiscreteMode => 'Falha ao alterar o Modo Disfarce';

  @override
  String get cacheDerivedKeysTitle =>
      'Armazenar Chaves Derivadas em Cache por Padrão';

  @override
  String get cacheDerivedKeysSubtitle =>
      'Armazenar o material de chave derivada no Keystore para desbloqueios mais rápidos';

  @override
  String get appThemeLabel => 'Tema do App';

  @override
  String get systemDefault => 'Padrão do Sistema';

  @override
  String get lightTheme => 'Tema Claro';

  @override
  String get darkTheme => 'Tema Escuro';

  @override
  String get useMaterialYouTitle => 'Usar Material You';

  @override
  String get useMaterialYouSubtitle =>
      'Combinar as cores do app com seu papel de parede (Android 12+)';

  @override
  String get sortContainersByLabel => 'Ordenar Contêineres Por';

  @override
  String get swapCardSwipeActionsTitle =>
      'Inverter Ações de Deslizar do Cartão';

  @override
  String get swapCardSwipeActionsSubtitle =>
      'Mostrar Editar à esquerda e Remover à direita ao deslizar os cartões';

  @override
  String get swipeGestureHintTitle => 'Dica de Gesto de Deslizar';

  @override
  String get swipeGestureHintSubtitle =>
      'Mostrar animação de prévia no primeiro contêiner';

  @override
  String get autoOpenOnUnlockTitle => 'Abrir Automaticamente ao Desbloquear';

  @override
  String get autoOpenOnUnlockActiveSubtitle =>
      'Abrir automaticamente após desbloquear um cofre';

  @override
  String get autoOpenOnUnlockInactiveSubtitle =>
      'Apenas desbloquear o cofre e permanecer no painel';

  @override
  String get enableJsHtmlTitle => 'Ativar JavaScript no Visualizador HTML';

  @override
  String get jsEnabledSubtitle =>
      'JavaScript ativado para arquivos HTML locais';

  @override
  String get jsDisabledSubtitle =>
      'JavaScript desativado para arquivos HTML locais';

  @override
  String get fastStorageAccessTitle => 'Acesso Rápido ao Armazenamento';

  @override
  String get fastStorageAccessGrantedSubtitle =>
      'Acesso a Todos os Arquivos concedido (velocidade máxima)';

  @override
  String get fastStorageAccessNotGrantedSubtitle =>
      'Conceda Acesso a Todos os Arquivos nas Configurações do Sistema para velocidade ideal';

  @override
  String get enableFastStorageAccessTitle =>
      'Ativar Acesso Rápido ao Armazenamento';

  @override
  String get enableFastStorageAccessMessage =>
      'Conceder \"Acesso a Todos os Arquivos\" permite que o Vault Explorer realize operações de arquivo POSIX diretas, aumentando o desempenho de cofres de pasta em até 1000x.';

  @override
  String get disableStorageAccessTitle => 'Desativar Acesso ao Armazenamento';

  @override
  String get disableStorageAccessMessage =>
      'O Android exige que \"Acesso a Todos os Arquivos\" seja desativado nas Configurações do Sistema. Deseja abrir as Configurações para desativá-lo?';

  @override
  String get enableStoragePermissionLegacyTitle =>
      'Permitir Acesso ao Armazenamento';

  @override
  String get enableStoragePermissionLegacyMessage =>
      'O Vault Explorer precisa da permissão de armazenamento para realizar operações de arquivo diretas, acelerando o desempenho de cofres de pasta. O Android agora vai pedir sua confirmação.';

  @override
  String get disableStoragePermissionLegacyMessage =>
      'O Android exige que a permissão de armazenamento seja desativada nas Configurações do Sistema. Deseja abrir as Configurações para desativá-la?';

  @override
  String get openSettings => 'Abrir Configurações';

  @override
  String get androidFileProviderTitle => 'Provedor de Arquivos do Android';

  @override
  String get androidFileProviderSubtitle =>
      'Expor novos contêineres ao Seletor de Arquivos do Android por padrão';

  @override
  String get thumbnailCachingDefaultLabel => 'Cache de Miniaturas (padrão)';

  @override
  String get thumbnailQualityDefaultLabel =>
      'Qualidade das Miniaturas (padrão)';

  @override
  String get fileAssociationsHeader => 'Associações de Arquivos';

  @override
  String get noFileAssociationsYet =>
      'Nenhuma associação de arquivos memorizada ainda. Você será solicitado ao abrir arquivos.';

  @override
  String get defaultActionsHeader =>
      'Ações padrão ao abrir arquivos não convencionais:';

  @override
  String get removeAssociationTooltip => 'Remover associação';

  @override
  String get sectionBackupRestore => 'Backup';

  @override
  String get exportSettingsTitle => 'Exportar configurações';

  @override
  String get exportSettingsSubtitle =>
      'Salvar as configurações do app e o layout do gerenciador de arquivos em um arquivo';

  @override
  String get importSettingsTitle => 'Importar configurações';

  @override
  String get importSettingsSubtitle =>
      'Restaurar as configurações do app e o layout do gerenciador de arquivos a partir de um arquivo';

  @override
  String get importSettingsConfirmTitle => 'Importar configurações?';

  @override
  String get importSettingsConfirmMessage =>
      'Isso substituirá suas configurações atuais e o layout do gerenciador de arquivos. Isso não pode ser desfeito.';

  @override
  String get exportSettingsSuccessMessage => 'Configurações exportadas';

  @override
  String get importSettingsSuccessMessage => 'Configurações importadas';

  @override
  String get exportSettingsErrorMessage =>
      'Não foi possível exportar as configurações';

  @override
  String get importSettingsInvalidFileMessage =>
      'Esse arquivo não é uma exportação de configurações válida';

  @override
  String get sectionDebug => 'Depuração';

  @override
  String get debugLoggingTitle => 'Registro de depuração';

  @override
  String get debugLoggingSubtitle =>
      'Registrar logs de diagnóstico detalhados para operações de contêiner';

  @override
  String get logcatTitle => 'Logcat';

  @override
  String get logcatSubtitle => 'Ver e salvar logs do dispositivo';

  @override
  String logcatSavedMessage(String path) {
    return 'Log salvo em $path';
  }

  @override
  String get logcatSaveErrorMessage => 'Falha ao salvar o log';

  @override
  String get logcatCopiedMessage => 'Log copiado para a área de transferência';

  @override
  String get logcatUnavailableMessage =>
      'O Logcat não está disponível neste dispositivo';

  @override
  String get logcatEmptyMessage => 'Aguardando linhas de log…';

  @override
  String get logcatClearTooltip => 'Limpar log';

  @override
  String get logcatSaveTooltip => 'Salvar log';

  @override
  String get logcatFilterAppOnly => 'Somente App';

  @override
  String get logcatFilterAll => 'Todos os Logs';

  @override
  String get logcatSearchHint => 'Pesquisar logs…';

  @override
  String get logcatClearedMessage => 'Logs limpos';

  @override
  String get logcatCopyTooltip => 'Copiar log';

  @override
  String get retryButton => 'Tentar novamente';

  @override
  String get aboutAppTitle => 'Sobre o VaultExplorer';

  @override
  String versionInfoSubtitle(String version) {
    return 'Versão $version · Licenças de código aberto e detalhes';
  }

  @override
  String get failedToSaveSettings => 'Falha ao salvar as configurações';

  @override
  String get masterPasswordSetSnack => 'Senha mestra definida';

  @override
  String get passwordCannotBeEmpty => 'A senha não pode ficar vazia';

  @override
  String get atLeast4CharsRequired => 'São necessários pelo menos 4 caracteres';

  @override
  String get passwordsDoNotMatch => 'As senhas não coincidem';

  @override
  String get failedToHashPassword =>
      'Falha ao gerar o hash da senha — tente novamente';

  @override
  String get languageLabel => 'Idioma';

  @override
  String get biometricNotAvailable =>
      'Biometria não disponível neste dispositivo';

  @override
  String get unlockVaultExplorerReason => 'Desbloquear o VaultExplorer';

  @override
  String biometricErrorWithCode(String code) {
    return 'Erro biométrico: $code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds segundos',
      one: '1 segundo',
    );
    return 'Muitas tentativas malsucedidas. Tente novamente em $_temp0.';
  }

  @override
  String get enterMasterPasswordPrompt => 'Digite sua senha mestra';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts tentativas malsucedidas',
      one: '1 tentativa malsucedida',
    );
    return 'Senha incorreta. Bloqueado por ${seconds}s devido a $_temp0.';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts tentativas malsucedidas',
      one: '1 tentativa malsucedida',
    );
    return 'Senha incorreta ($_temp0).';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle => 'Digite sua senha mestra para continuar';

  @override
  String get masterPasswordFieldLabelTitleCase => 'Senha Mestra';

  @override
  String get unlock => 'Desbloquear';

  @override
  String get useBiometric => 'Usar Biometria';

  @override
  String get connectAtLeast4Dots => 'Conecte pelo menos 4 pontos';

  @override
  String get patternsDontMatch => 'Os padrões não coincidem — tente novamente';

  @override
  String get drawUnlockPatternTitle => 'Desenhar Padrão de Desbloqueio';

  @override
  String get confirmPatternTitle => 'Confirme seu padrão';

  @override
  String get drawSamePatternAgain => 'Desenhe o mesmo padrão novamente';

  @override
  String get enterAtLeast4Digits => 'Digite pelo menos 4 dígitos';

  @override
  String get pinsDontMatch => 'Os PINs não coincidem — tente novamente';

  @override
  String get createUnlockPinTitle => 'Crie seu PIN de desbloqueio';

  @override
  String get confirmPinTitle => 'Confirme seu PIN';

  @override
  String get enterSamePinAgain => 'Digite o mesmo PIN novamente';

  @override
  String get enterUnlockPinTitle => 'Digite o PIN de Desbloqueio';

  @override
  String get wrongPinTryAgain => 'PIN incorreto — tente novamente';

  @override
  String get enterYourPinSequence => 'Digite seu PIN';

  @override
  String get enterPinToMount => 'Digite seu PIN para montar';

  @override
  String get noPinConfiguredMessage =>
      'Nenhum PIN configurado. Digite a senha manualmente.';

  @override
  String pinLockedForSeconds(int seconds) {
    return 'Muitas tentativas malsucedidas. Bloqueado por ${seconds}s.';
  }

  @override
  String get initSecureCredsPinMessage =>
      'Inicializando credenciais seguras. Desbloqueie manualmente uma vez para autorizar o acesso por PIN.';

  @override
  String get setPinButton => 'Definir PIN';

  @override
  String get changePinButton => 'Alterar PIN';

  @override
  String get pinSetupRequiredBeforeSaving =>
      'Configure um PIN antes de salvar.';

  @override
  String get pinSetupRequiredAboveBeforeSaving =>
      'Configure um PIN acima antes de salvar.';

  @override
  String get verifyPinTitle => 'Verificar PIN';

  @override
  String get incorrectPinError => 'PIN incorreto';

  @override
  String removedFromListSnack(String name) {
    return '\"$name\" removido da lista';
  }

  @override
  String get clearRecentHistoryTitle => 'Limpar Histórico Recente?';

  @override
  String get clearRecentHistoryMessage =>
      'Isso removerá todos os documentos recentes da sua lista. Os arquivos reais no seu dispositivo não serão afetados.';

  @override
  String get clearAll => 'Limpar Tudo';

  @override
  String get recentHistoryClearedSnack => 'Histórico recente limpo';

  @override
  String get moreOptionsTooltip => 'Mais opções';

  @override
  String get clearHistoryMenuItem => 'Limpar histórico';

  @override
  String get openPdfFile => 'Abrir Arquivo PDF';

  @override
  String get noDocumentsYetTitle => 'Nenhum documento ainda';

  @override
  String get openPdfToStartMessage =>
      'Abra um PDF do seu dispositivo para começar a ler.';

  @override
  String get removeFromListMenuItem => 'Remover da lista';

  @override
  String get justNow => 'Agora mesmo';

  @override
  String minutesAgo(int count) {
    return 'há $count min';
  }

  @override
  String hoursAgo(int count) {
    return 'há $count h';
  }

  @override
  String daysAgo(int count) {
    return 'há $count d';
  }

  @override
  String get usbDriveDisconnectedLocked =>
      'Unidade USB desconectada — contêiner bloqueado';

  @override
  String get containerAlreadyMounted => 'Este contêiner já está montado.';

  @override
  String get noVaultFolderFormatDetected =>
      'Nenhum masterkey.cryptomator, gocryptfs.conf ou cryfs.config encontrado nessa pasta.';

  @override
  String get savedContainerSettingsNotFound =>
      'As configurações salvas para este contêiner não puderam ser encontradas.';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return 'Não foi possível atualizar o local do contêiner: $error';
  }

  @override
  String filePickerFailed(String error) {
    return 'Falha no seletor de arquivos: $error';
  }

  @override
  String get selectContainerFirst => 'Selecione um contêiner primeiro';

  @override
  String get passwordOrKeyfilesRequired =>
      'Senha ou arquivos-chave necessários';

  @override
  String get slowPerformanceWarningTitle => 'Aviso de Desempenho Lento';

  @override
  String get slowPerformanceWarningMessage =>
      'O Acesso Direto ao Armazenamento está atualmente desativado.\n\nO CryFS armazena arquivos distribuídos em milhares de pequenos blocos. Abrir cofres CryFS não vazios via SAF do Android será muito lento.\n\nDeseja abrir as Configurações para conceder \"Acesso a Todos os Arquivos\" para maior velocidade?';

  @override
  String get unlockAnyway => 'Desbloquear Mesmo Assim';

  @override
  String get defaultVaultName => 'Cofre';

  @override
  String get defaultContainerName => 'Contêiner';

  @override
  String get incorrectPasswordOrInvalidVault =>
      'Senha incorreta ou cofre inválido';

  @override
  String get incorrectPasswordOrInvalidContainer =>
      'Senha incorreta ou contêiner inválido';

  @override
  String get genericUnknownError => 'Erro desconhecido';

  @override
  String get decryptingLabel => 'Descriptografando…';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return 'Tentando slot de chave $attempted de $total…';
  }

  @override
  String get luksKeyslotProgressUnknown => 'Tentando slot de chave…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return 'Verificando credencial $attempted de $total…';
  }

  @override
  String get bitlockerCredentialProgressUnknown => 'Verificando credencial…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return 'Tentando $algo ($slotName)…';
  }

  @override
  String get unlockContainerLabel => 'Desbloquear Contêiner';

  @override
  String get mountContainerTitle => 'Montar Contêiner';

  @override
  String get containerFileSegmentLabel => 'Arquivo Contêiner';

  @override
  String get folderVaultSegmentLabel => 'Cofre de Pasta';

  @override
  String formatContainerLabel(String format) {
    return 'Contêiner $format';
  }

  @override
  String formatVaultLabel(String format) {
    return 'Cofre $format';
  }

  @override
  String formatDriveLabel(String format) {
    return 'Unidade $format';
  }

  @override
  String get encryptedContainerLabel => 'Contêiner Criptografado';

  @override
  String get tapToSelectVaultFolder =>
      'Toque para selecionar a pasta do cofre…';

  @override
  String get tapToSelectContainerFile =>
      'Toque para selecionar o arquivo contêiner…';

  @override
  String get containerMissingTitle => 'Contêiner Ausente';

  @override
  String get filePathCouldNotBeResolved =>
      'Não foi possível resolver o caminho do arquivo';

  @override
  String get containerMissingExplanation =>
      'O arquivo do contêiner pode ter sido movido, excluído, ou seu armazenamento de origem está desconectado no momento.';

  @override
  String get retryButtonLabel => 'Tentar novamente';

  @override
  String get locateFileButtonLabel => 'Localizar Arquivo';

  @override
  String get authenticateToMountSubtitle =>
      'Autentique-se para montar o contêiner com segurança';

  @override
  String get usePasswordButtonLabel => 'Usar Senha';

  @override
  String get authenticateButtonLabel => 'Autenticar';

  @override
  String get drawUnlockPatternCardTitle => 'Desenhar Padrão de Desbloqueio';

  @override
  String get wrongPatternTryAgain => 'Padrão incorreto — tente novamente';

  @override
  String get connectYourPatternSequence => 'Conecte sua sequência de padrão';

  @override
  String get usePasswordInsteadButtonLabel => 'Usar Senha em vez disso';

  @override
  String get passwordHintFolderVault => 'Digite a senha do cofre';

  @override
  String get passwordHintBitlocker =>
      'Digite a senha ou a chave de recuperação';

  @override
  String get passwordHintContainer => 'Digite a senha do contêiner';

  @override
  String get usingSavedPasswordTooltip => 'Usando senha salva';

  @override
  String get luksKeyfileReplacesPasswordNote =>
      'Para contêineres LUKS, o arquivo-chave substitui a senha.';

  @override
  String get readOnlyModeUsbSubtitle =>
      'Montar sem permitir alterações nesta unidade';

  @override
  String get readOnlyModeContainerSubtitle =>
      'Montar sem permitir alterações neste contêiner';

  @override
  String get rememberContainerLabel => 'Lembrar contêiner';

  @override
  String get rememberContainerSubtitle =>
      'Fixar o contêiner no painel para acesso rápido';

  @override
  String get cancelUnlockButtonLabel => 'Cancelar Desbloqueio';

  @override
  String get biometricSubjectContainer => 'contêiner';

  @override
  String get biometricSubjectUsbDrive => 'unidade USB';

  @override
  String get usbNoSavedCredentialsMessage =>
      'Nenhuma senha salva encontrada. Digite-a manualmente.';

  @override
  String get decryptingDriveLabel => 'Descriptografando unidade…';

  @override
  String get usbDeviceAlreadyActiveMounted =>
      'Este dispositivo USB já está ativo e montado.';

  @override
  String reconnectUsbDriveTitle(String label) {
    return 'Reconectar \"$label\"';
  }

  @override
  String get unlockUsbDriveTitle => 'Desbloquear Unidade USB';

  @override
  String get noUsbStorageDetectedTitle => 'Nenhum Armazenamento USB Detectado';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return 'Autentique-se para desbloquear $subject';
  }

  @override
  String get noPatternConfiguredMessage =>
      'Nenhum padrão configurado. Digite a senha manualmente.';

  @override
  String patternLockedForSeconds(int seconds) {
    return 'Muitas tentativas malsucedidas. Bloqueado por ${seconds}s.';
  }

  @override
  String get initSecureCredsBiometricMessage =>
      'Inicializando credenciais seguras. Desbloqueie manualmente uma vez para autorizar o acesso biométrico.';

  @override
  String get initSecureCredsPatternMessage =>
      'Inicializando credenciais seguras. Desbloqueie manualmente uma vez para autorizar o acesso por padrão.';

  @override
  String get mountExistingContainerTitle => 'Montar contêiner existente';

  @override
  String get mountExistingContainerSubtitle =>
      'Desbloquear um contêiner de arquivo que você já possui';

  @override
  String get mountSplitContainerTitle => 'Montar contêiner dividido';

  @override
  String get mountSplitContainerSubtitle =>
      'Desbloquear um contêiner dividido diretamente, sem uni-lo antes';

  @override
  String get mountUsbDriveTitle => 'Montar Unidade USB';

  @override
  String get mountUsbDriveSubtitle =>
      'Desbloquear um contêiner em uma unidade flash OTG';

  @override
  String get formatUsbDriveTitle => 'Formatar unidade USB';

  @override
  String get formatUsbDriveSubtitle =>
      'Apagar uma unidade e criar um novo contêiner criptografado nela';

  @override
  String get createNewContainerTitle => 'Criar novo contêiner';

  @override
  String get createNewContainerSubtitle =>
      'Formatar um cofre criptografado totalmente novo';

  @override
  String get lockBeforeRemovingWarning =>
      'Bloqueie o contêiner antes de removê-lo.';

  @override
  String get settingsTooltip => 'Configurações';

  @override
  String get addVaultFabLabel => 'Adicionar cofre';

  @override
  String removedLabelUndo(String label) {
    return '\"$label\" removido';
  }

  @override
  String get undo => 'Desfazer';

  @override
  String get pdfViewerNoSourceProvided => 'Nenhuma fonte de PDF fornecida.';

  @override
  String get pdfViewerFileEmpty => 'O arquivo PDF está vazio ou ilegível.';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return 'Falha ao verificar o tamanho do arquivo PDF: $error';
  }

  @override
  String get pdfViewerErrorLoadingTitle => 'Erro ao carregar o PDF';

  @override
  String get pdfViewerNoDocumentLoaded => 'Nenhum documento PDF carregado.';

  @override
  String get add => 'Adicionar';

  @override
  String get reset => 'Redefinir';

  @override
  String couldNotExpose(String name) {
    return 'Não foi possível expor \"$name\".';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return '\"$name\" agora está disponível para outros apps.';
  }

  @override
  String couldNotUnmount(String name) {
    return 'Não foi possível desmontar \"$name\".';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens fixados',
      one: '1 item fixado',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens desafixados',
      one: '1 item desafixado',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning =>
      'Montagem somente leitura — as miniaturas serão exibidas, mas não serão salvas dentro do contêiner nesta sessão.';

  @override
  String failedLoadingFolder(String type) {
    return 'Falha ao carregar a pasta: $type';
  }

  @override
  String failedToReadArchive(String type) {
    return 'Falha ao ler o arquivo compactado: $type';
  }

  @override
  String archiveFormatNotSupported(String ext) {
    return 'O formato de arquivo .$ext ainda não é suportado';
  }

  @override
  String get failedToReadFileFromArchive =>
      'Falha ao ler o arquivo do pacote compactado';

  @override
  String failedToExtractFile(String type) {
    return 'Falha ao extrair o arquivo: $type';
  }

  @override
  String get failedToReadSecureItem => 'Falha ao ler o item seguro';

  @override
  String get openFileDialogTitle => 'Abrir Arquivo';

  @override
  String chooseHowToOpen(String name) {
    return 'Escolha como abrir \"$name\":';
  }

  @override
  String get playVideoAudioViewImageInApp =>
      'Reproduzir vídeo/áudio ou visualizar imagem no app';

  @override
  String get viewEditTextMarkdownCode =>
      'Visualizar/editar texto, markdown, código';

  @override
  String get sendFileToThirdPartyApp =>
      'Enviar arquivo para um app de terceiros';

  @override
  String get openAsEllipsis => 'Abrir Como…';

  @override
  String get chooseFileTypeToOpenAs =>
      'Escolha o tipo de arquivo para abrir como';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return 'Sempre lembrar a escolha para arquivos .$ext';
  }

  @override
  String get alwaysRememberChoiceNoExt =>
      'Sempre lembrar a escolha para arquivos sem extensão';

  @override
  String get openAsDialogTitle => 'Abrir Como';

  @override
  String get mimeTypeText => 'Texto';

  @override
  String get mimeTypeImage => 'Imagem';

  @override
  String get mimeTypeVideo => 'Vídeo';

  @override
  String get mimeTypeAudio => 'Áudio';

  @override
  String get mimeTypeArchive => 'Arquivo Compactado';

  @override
  String get mimeTypeOther => 'Outro';

  @override
  String get scanningSubfoldersForMedia =>
      'Verificando subpastas em busca de mídia…';

  @override
  String get noMediaFilesFoundRecursive =>
      'Nenhum arquivo de mídia encontrado nesta pasta ou em suas subpastas';

  @override
  String failedToScanSubfolders(String error) {
    return 'Falha ao verificar subpastas: $error';
  }

  @override
  String get noAppFoundForFileType =>
      'Nenhum app encontrado para este tipo de arquivo';

  @override
  String couldNotOpenFile(String name) {
    return 'Não foi possível abrir \"$name\"';
  }

  @override
  String get readOnlyCantMove =>
      'Este contêiner está montado somente leitura — os itens não podem ser movidos daqui.';

  @override
  String get readOnlyCantPaste =>
      'Este contêiner está montado somente leitura — os itens não podem ser colados aqui.';

  @override
  String get clipboardSourceInvalid =>
      'A origem da área de transferência é inválida';

  @override
  String get crossContainerPasteNotConfigured =>
      'A colagem entre contêineres não está configurada.';

  @override
  String get crossContainerPasteRequiresBothMounted =>
      'A colagem entre contêineres exige que ambos permaneçam montados.';

  @override
  String get readOnlyCantDelete =>
      'Este contêiner está montado somente leitura — os itens não podem ser excluídos.';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens excluídos',
      one: '1 item excluído',
    );
    return '$_temp0';
  }

  @override
  String deletedWithFailures(int deleted, int failed) {
    return '$deleted excluídos · $failed com falha';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos exportados',
      one: '1 arquivo exportado',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed => 'Exportação cancelada ou com falha';

  @override
  String exportError(String type) {
    return 'Erro de exportação: $type';
  }

  @override
  String get deleteOriginalTitle => 'Excluir original?';

  @override
  String get deleteOriginalFolderMessage =>
      'Excluir a pasta original do seu dispositivo agora que ela foi importada?';

  @override
  String get deleteOriginalFilesMessage =>
      'Excluir o(s) arquivo(s) original(is) do seu dispositivo agora que foram importados?';

  @override
  String get keepOriginal => 'Manter original';

  @override
  String get deleteOriginalButton => 'Excluir original';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens originais excluídos',
      one: '1 item original excluído',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals =>
      'Não foi possível excluir o(s) original(is)';

  @override
  String get videoCapturedEncrypted => 'Vídeo capturado e criptografado';

  @override
  String get photoCapturedEncrypted => 'Foto capturada e criptografada';

  @override
  String cameraCaptureFailed(String type) {
    return 'Falha na captura da câmera: $type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return 'Extrair todos os arquivos para a pasta \"$folder\"?';
  }

  @override
  String get extract => 'Extrair';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos extraídos',
      one: '1 arquivo extraído',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return 'Falha ao extrair: $type';
  }

  @override
  String get closeSearchTooltip => 'Fechar pesquisa';

  @override
  String get searchInThisFolderTooltip => 'Pesquisar nesta pasta';

  @override
  String get playMediaHereTooltip => 'Reproduzir mídia aqui';

  @override
  String get rootFolderLabel => 'Raiz';

  @override
  String folderPickerFailed(String error) {
    return 'Falha no seletor de pasta: $error';
  }

  @override
  String get addAVaultTitle => 'Adicionar um cofre';

  @override
  String get selectEmptyDestinationFolderFirst =>
      'Selecione primeiro uma pasta de destino vazia';

  @override
  String get passwordRequired => 'É necessária uma senha';

  @override
  String get vaultCreatedSuccessfully => 'Cofre criado com sucesso.';

  @override
  String get vaultCreationFailedEmptyFolder =>
      'Falha na criação do cofre — verifique se a pasta selecionada está vazia.';

  @override
  String get unknownErrorOccurred => 'Ocorreu um erro desconhecido';

  @override
  String get containerNameRequired => 'O nome do contêiner é obrigatório';

  @override
  String get enterValidSizeGreaterThanZero =>
      'Insira um tamanho válido maior que 0';

  @override
  String get passwordOrKeyfileRequired =>
      'É necessária uma senha ou pelo menos um arquivo-chave';

  @override
  String get standardVolumePasswordsDoNotMatch =>
      'As senhas do volume padrão não coincidem';

  @override
  String get hiddenVolumePasswordsDoNotMatch =>
      'As senhas do volume oculto não coincidem';

  @override
  String get containerFileCreatedSuccessfully =>
      'Arquivo contêiner criado com sucesso.';

  @override
  String get containerCreationCancelledOrFailed =>
      'Criação do contêiner cancelada ou com falha.';

  @override
  String insufficientSpaceForContainer(String needed, String available) {
    return 'Not enough free space at the destination. Need $needed, only $available available.';
  }

  @override
  String get vaultKindContainerFile => 'Arquivo Contêiner';

  @override
  String get vaultKindFolderVault => 'Cofre de Pasta';

  @override
  String get formatFileSystemLabel => 'Formatar Sistema de Arquivos';

  @override
  String get standardVolumeHeader => 'Volume Padrão';

  @override
  String get containerFormatLabel => 'Formato do Contêiner';

  @override
  String get fileNameLabel => 'Nome do Arquivo';

  @override
  String get containerSizeLabel => 'Tamanho do Contêiner';

  @override
  String get unitLabel => 'Unidade';

  @override
  String get passwordFieldLabel => 'Senha';

  @override
  String get confirmPasswordFieldLabelTitleCase => 'Confirmar Senha';

  @override
  String get hiddenVolumeHeader => 'Volume Oculto';

  @override
  String get createHiddenVolumeToggleTitle => 'Criar Volume Oculto';

  @override
  String get createInvisibleSecondaryVolume =>
      'Criar um volume secundário invisível';

  @override
  String get setOuterPasswordFirstToEnable =>
      'Defina a senha ou os arquivos-chave externos primeiro para ativar';

  @override
  String get hiddenPasswordLabel => 'Senha Oculta';

  @override
  String get confirmHiddenPasswordLabel => 'Confirmar Senha Oculta';

  @override
  String get hiddenSizeLabel => 'Tamanho Oculto';

  @override
  String get unitMbMegabytes => 'MB (Megabytes)';

  @override
  String get unitGbGigabytes => 'GB (Gigabytes)';

  @override
  String get hiddenFileSystemLabel => 'Sistema de Arquivos Oculto';

  @override
  String get vaultFormatLabel => 'Formato do Cofre';

  @override
  String get gocryptfsCipherLabel => 'Cifra de Conteúdo';

  @override
  String get cryfsCipherLabel => 'Cifra de Conteúdo';

  @override
  String get cryfsBlockSizeLabel => 'Tamanho do Bloco';

  @override
  String get destinationFolderLabel => 'Pasta de Destino';

  @override
  String get selectEmptyFolderLabel => 'Selecione uma pasta vazia';

  @override
  String get tapToChooseVaultLocation =>
      'Toque para escolher onde o cofre será criado…';

  @override
  String get folderVaultLimitationsNote =>
      'Cofres de pasta não suportam arquivos-chave, PIM, volumes ocultos, nem a escolha de cifras VeraCrypt/LUKS.';

  @override
  String get createVaultButton => 'Criar Cofre';

  @override
  String get createContainerButton => 'Criar Contêiner';

  @override
  String get vaultCreationInProgressWait =>
      'Criação do cofre em andamento. Aguarde.';

  @override
  String get containerCreationInProgressWait =>
      'Criação do contêiner em andamento. Aguarde.';

  @override
  String get createEncryptedVaultTitle => 'Criar Cofre Criptografado';

  @override
  String get createEncryptedContainerTitle => 'Criar Contêiner Criptografado';

  @override
  String get unitMbShort => 'MB';

  @override
  String get unitGbShort => 'GB';

  @override
  String failedToListUsbDevices(String error) {
    return 'Falha ao listar dispositivos USB: $error';
  }

  @override
  String get usbPermissionDenied => 'Permissão USB negada';

  @override
  String get couldNotReadDriveCapacity =>
      'Não foi possível ler a capacidade da unidade — insira o tamanho manualmente.';

  @override
  String get selectUsbDriveFirst => 'Selecione uma unidade USB primeiro';

  @override
  String eraseDeviceTitle(String name) {
    return 'Apagar \"$name\"?';
  }

  @override
  String get eraseDeviceMessage =>
      'Isso apagará permanentemente tudo o que está nesta unidade USB e o substituirá por um novo contêiner criptografado. Isso não pode ser desfeito.';

  @override
  String get eraseAndCreateButton => 'Apagar e Criar';

  @override
  String get usbPermissionRequiredToContinue =>
      'A permissão USB é necessária para continuar';

  @override
  String get usbContainerCreatedSnack =>
      'Contêiner USB criado. Use \"Montar unidade USB\" para desbloqueá-lo.';

  @override
  String get usbContainerCreationFailed => 'Falha na criação do contêiner USB.';

  @override
  String get usbStandardVolumeSectionHeader => 'Unidade USB e Volume Padrão';

  @override
  String get formattingErasesEverythingWarning =>
      'A formatação apaga tudo o que está atualmente na unidade selecionada.';

  @override
  String get selectUsbDriveLabel => 'Selecionar Unidade USB';

  @override
  String get noUsbStorageDetected => 'Nenhum armazenamento USB detectado';

  @override
  String get connectOtgDriveToFormat => 'Conecte uma unidade OTG para formatar';

  @override
  String get refreshListButton => 'Atualizar lista';

  @override
  String get readyToFormat => 'Pronto para formatar';

  @override
  String get permissionRequired => 'Permissão necessária';

  @override
  String get readingDriveCapacity => 'Lendo a capacidade da unidade…';

  @override
  String get mustNotExceedDriveCapacity =>
      'Não deve exceder a capacidade real da unidade.';

  @override
  String get quickFormatTitle => 'Formatação Rápida';

  @override
  String get quickFormatDescription =>
      'Ignora o preenchimento com zeros da unidade. Mais rápido, mas não apaga os dados antigos com segurança.';

  @override
  String get eraseAndCreateContainerButton => 'Apagar e Criar Contêiner';

  @override
  String get usbContainerCreationInProgressWait =>
      'Criação do contêiner em andamento. Aguarde.';

  @override
  String get formatUsbDriveScreenTitle => 'Formatar Unidade USB';

  @override
  String get playlistTransitionAnimationLabel =>
      'Animação de Transição da Lista de Reprodução';

  @override
  String get playlistTransitionSlideLabel => 'Deslizar (Padrão)';

  @override
  String get playlistTransitionFadeLabel => 'Esmaecer';

  @override
  String get playlistTransitionZoomLabel => 'Zoom e Escala';

  @override
  String get playlistTransitionDepthLabel => 'Pilha em Profundidade';

  @override
  String get playlistTransitionCubeLabel => 'Cubo 3D';

  @override
  String get playlistTransitionFlipLabel => 'Virada 3D';

  @override
  String get unlockVaultTitle => 'Desbloquear Cofre';

  @override
  String get openContainerTitle => 'Abrir Contêiner';

  @override
  String get selectContainerFileOrFolder => 'Selecionar Arquivo ou Pasta';

  @override
  String get readOnlyModeLabel => 'Modo somente leitura';

  @override
  String get readOnlyModeSubtitle =>
      'Impede qualquer operação de escrita ou modificação no cofre';

  @override
  String get selectUsbDeviceLabel => 'Selecionar Dispositivo USB';

  @override
  String get noUsbDevicesFound =>
      'Nenhum dispositivo de armazenamento USB compatível encontrado';

  @override
  String get containerConfigTitle => 'Configuração do Cofre';

  @override
  String get changePasswordTitle => 'Alterar Senha';

  @override
  String get confirmNewPasswordLabel => 'Confirmar Nova Senha';

  @override
  String get cameraCaptureTitle => 'Câmera do Cofre';

  @override
  String get takingPhoto => 'Capturando foto…';

  @override
  String get savingToVault => 'Salvando no cofre…';

  @override
  String get noVaultSelected => 'Nenhum cofre selecionado';

  @override
  String get mediaDiagnosticsTitle => 'Diagnóstico de Mídia';

  @override
  String get advancedViewerSettingsTitle => 'Configurações do Visualizador';

  @override
  String get textEditorSaveConfirmTitle => 'Alterações Não Salvas';

  @override
  String get textEditorSaveConfirmMessage =>
      'Deseja salvar suas alterações antes de fechar?';

  @override
  String get saveAndClose => 'Salvar e Fechar';

  @override
  String get discardChanges => 'Descartar Alterações';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens selecionados',
      one: '1 item selecionado',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'Selecionar Tudo';

  @override
  String get deselectAll => 'Desmarcar Tudo';

  @override
  String get sortOptionsTitle => 'Ordenar Arquivos';

  @override
  String get layoutModeList => 'Visualização em Lista';

  @override
  String get layoutModeGrid => 'Visualização em Grade';

  @override
  String get layoutModeMasonry => 'Mosaico';

  @override
  String get fileOperationsTitle => 'Operações de Arquivo';

  @override
  String get conflictResolutionTitle => 'Conflito de Arquivo';

  @override
  String get replaceExistingFile => 'Substituir arquivo existente';

  @override
  String get keepBothFiles => 'Manter ambos (renomear novo arquivo)';

  @override
  String get skipFile => 'Ignorar este arquivo';

  @override
  String get noVaultsFoundTitle => 'Nenhum Cofre Encontrado';

  @override
  String get noVaultsFoundSubtitle =>
      'Crie um novo contêiner criptografado ou adicione um cofre existente para começar.';

  @override
  String get addExistingVaultButton => 'Adicionar Cofre Existente';

  @override
  String get sortContainersModeManual => 'Manual (arraste para reordenar)';

  @override
  String get sortContainersModeUnlockStatus =>
      'Status de desbloqueio (desbloqueados primeiro)';

  @override
  String get sortContainersModeNameAZ => 'Nome (A–Z)';

  @override
  String get sortContainersModeNameZA => 'Nome (Z–A)';

  @override
  String get sortContainersModeNewest => 'Mais recentes primeiro';

  @override
  String get sortContainersModeOldest => 'Mais antigos primeiro';

  @override
  String get thumbnailCacheAppCacheLabel => 'Cache do app';

  @override
  String get thumbnailCacheAppCacheDesc =>
      'Armazenado criptografado no cache do app. Rápido; limpo automaticamente sob pressão de armazenamento.';

  @override
  String get thumbnailCacheInContainerLabel => 'Dentro do contêiner';

  @override
  String get thumbnailCacheInContainerDesc =>
      'Armazenado dentro do contêiner criptografado. Protegido pelo próprio contêiner, mas a gravação é mais lenta.';

  @override
  String get thumbnailCacheDisabledLabel => 'Desativado';

  @override
  String get thumbnailCacheDisabledDesc =>
      'Sem cache em disco. As miniaturas são regeneradas a cada carregamento.';

  @override
  String get unlockContainerTitle => 'Desbloquear Contêiner';

  @override
  String get containerFileSegment => 'Arquivo Contêiner';

  @override
  String get folderVaultSegment => 'Cofre de Pasta';

  @override
  String get enableButtonLabel => 'Ativar';

  @override
  String get retryButtonLabelShort => 'Tentar novamente';

  @override
  String get locateFileButton => 'Localizar Arquivo';

  @override
  String get authenticateButton => 'Autenticar';

  @override
  String get cancelUnlockButton => 'Cancelar Desbloqueio';

  @override
  String tryingKeyslotProgress(int attempted, int total) {
    return 'Tentando slot de chave $attempted de $total…';
  }

  @override
  String get tryingKeyslotSingle => 'Tentando slot de chave…';

  @override
  String verifyingCredentialProgress(int attempted, int total) {
    return 'Verificando credencial $attempted de $total…';
  }

  @override
  String get verifyingCredentialSingle => 'Verificando credencial…';

  @override
  String tryingAlgoSlot(String algo, String slotName) {
    return 'Tentando $algo ($slotName)…';
  }

  @override
  String get hiddenVolumeSlotName => 'Volume Oculto';

  @override
  String get standardVolumeSlotName => 'Volume Padrão';

  @override
  String get containerMissingSubtitle =>
      'Não foi possível resolver o caminho do arquivo';

  @override
  String get containerMissingBody =>
      'O arquivo do contêiner pode ter sido movido, excluído, ou seu armazenamento de origem está desconectado no momento.';

  @override
  String get connectPatternSequence => 'Conecte sua sequência de padrão';

  @override
  String get passwordLabel => 'Senha';

  @override
  String get enterVaultPasswordHint => 'Digite a senha do cofre';

  @override
  String get enterBitlockerPasswordHint =>
      'Digite a senha ou a chave de recuperação';

  @override
  String get enterContainerPasswordHint => 'Digite a senha do contêiner';

  @override
  String get readOnlyModeUsbSubtitleDrive =>
      'Montar sem permitir alterações nesta unidade';

  @override
  String get rememberDriveLabel => 'Lembrar unidade';

  @override
  String get rememberDriveSubtitle =>
      'Fixar a unidade no painel para acesso rápido';

  @override
  String get unlockVaultButtonLabel => 'Desbloquear Cofre';

  @override
  String get cryfsStorageAccessWarning =>
      'Cofres CryFS usam milhares de pequenos arquivos de blocos. Sem o Acesso Direto ao Armazenamento, o desempenho será significativamente mais lento.';

  @override
  String get folderVaultStorageAccessWarning =>
      'O Acesso Direto ao Armazenamento está desativado. Abrir e ler arquivos em cofres de pasta pode ser mais lento.';

  @override
  String get requestingPermission => 'Solicitando permissão…';

  @override
  String get unlockAndMountButton => 'Desbloquear e Montar';

  @override
  String get unlockDriveButton => 'Desbloquear Unidade';

  @override
  String couldntFindDevice(String deviceName) {
    return 'Não foi possível encontrar \"$deviceName\"';
  }

  @override
  String get plugDriveBackInRetry =>
      'Conecte a unidade novamente e toque em Tentar Novamente, ou selecione-a abaixo se ela aparecer com um nome diferente.';

  @override
  String get retryConnectionButton => 'Tentar Conexão Novamente';

  @override
  String get refreshDevicesButton => 'Atualizar Dispositivos';

  @override
  String get connectOtgDriveToMount =>
      'Conecte uma unidade flash OTG para montar';

  @override
  String get alreadyActive => 'Já ativo';

  @override
  String get active => 'Ativo';

  @override
  String get readyToUnlock => 'Pronto para desbloquear';

  @override
  String get enterUsbPartitionPassword => 'Digite a senha da partição USB';

  @override
  String get biometricAuthenticationTitle => 'Autenticação Biométrica';

  @override
  String get biometricAuthUsbSubtitle =>
      'Autentique-se para desbloquear e montar este dispositivo USB';

  @override
  String get connectPatternSequenceToMount =>
      'Conecte sua sequência de padrão para montar';

  @override
  String get selectAllAction => 'Selecionar Tudo';

  @override
  String get clearSelectionAction => 'Limpar Seleção';

  @override
  String get clearSelectionTooltip => 'Limpar seleção';

  @override
  String get selectionOptionsTooltip => 'Opções de seleção';

  @override
  String get readOnlyContainerTooltip => 'Contêiner somente leitura';

  @override
  String get copyAction => 'Copiar';

  @override
  String get moveAction => 'Mover';

  @override
  String get renameAction => 'Renomear';

  @override
  String get exportToDeviceAction => 'Exportar para o dispositivo';

  @override
  String get openWithAppAction => 'Abrir com App';

  @override
  String get pinAction => 'Fixar';

  @override
  String get pinSelectedAction => 'Fixar selecionados';

  @override
  String get unpinAction => 'Desafixar';

  @override
  String get unpinSelectedAction => 'Desafixar selecionados';

  @override
  String get documentProviderSettingsMenu =>
      'Configurações do Provedor de Documentos';

  @override
  String get exposeAsDocumentProviderMenu =>
      'Expor como Provedor de Documentos';

  @override
  String get moreOptionsTooltipShort => 'Mais opções';

  @override
  String get copyTooltip => 'Copiar';

  @override
  String get searchInThisFolderHint => 'Pesquisar nesta pasta…';

  @override
  String get clearTooltip => 'Limpar';

  @override
  String get backToDashboardTooltip => 'Voltar ao painel';

  @override
  String get cancelPasteButton => 'Cancelar colagem';

  @override
  String get cancelImportButton => 'Cancelar importação';

  @override
  String get continueButton => 'Continuar';

  @override
  String get skipButton => 'Ignorar';

  @override
  String get keepBothButton => 'Manter ambos';

  @override
  String get clearAllButton => 'Limpar tudo';

  @override
  String get autoMountWhenUnlocksTitle =>
      'Montar automaticamente ao desbloquear o contêiner';

  @override
  String get autoMountWhenUnlocksSubtitle =>
      'Expor esta pasta automaticamente novamente na próxima vez';

  @override
  String get unmountButton => 'Desmontar';

  @override
  String get filtersMenuItem => 'Filtros';

  @override
  String get settingsMenuItem => 'Configurações';

  @override
  String get sortOptionsTooltip => 'Opções de ordenação';

  @override
  String get layoutOptionsTooltip => 'Opções de layout';

  @override
  String get lockContainerTooltip => 'Bloquear contêiner';

  @override
  String get renameTooltip => 'Renomear';

  @override
  String get cancelUpdatingPasswordTooltip => 'Cancelar atualização da senha';

  @override
  String get unlockSettingsButton => 'Configurações de Desbloqueio';

  @override
  String get updateSavedCredentialsButton => 'Atualizar Credenciais Salvas';

  @override
  String get verifyCredentialsTitle => 'Verificar Credenciais';

  @override
  String get verifyButton => 'Verificar';

  @override
  String get displayNameTitle => 'Nome de Exibição';

  @override
  String get containerNameHint => 'Nome do contêiner';

  @override
  String get deleteFileDialogTitle => 'Excluir arquivo?';

  @override
  String get deleteFilePermanentWarning =>
      'Esta ação é permanente e não pode ser desfeita.';

  @override
  String get unsavedChangesTitle => 'Alterações Não Salvas';

  @override
  String get unsavedChangesMessage =>
      'Você tem alterações não salvas. Deseja salvá-las antes de fechar?';

  @override
  String get discardButton => 'Descartar';

  @override
  String get decryptingFileContent =>
      'Descriptografando o conteúdo do arquivo...';

  @override
  String get cannotOpenFile => 'Não é possível abrir o arquivo';

  @override
  String get changesSavedSuccessfully => 'Alterações salvas com sucesso';

  @override
  String saveFailedWithError(String error) {
    return 'Falha ao salvar: $error';
  }

  @override
  String linesCount(int count) {
    return 'Linhas: $count';
  }

  @override
  String charsCount(int count) {
    return 'Caracteres: $count';
  }

  @override
  String get unsavedChangesLabel => 'Alterações Não Salvas';

  @override
  String get savedToVault => 'Salvo no cofre';

  @override
  String get saveChangesTooltip => 'Salvar alterações';

  @override
  String get textEditorDecryptFailedMessage =>
      'Falha ao descriptografar o arquivo do cofre.';

  @override
  String get textEditorInvalidTextFileMessage =>
      'O arquivo não parece ser um arquivo de texto válido.';

  @override
  String get textEditorWriteBackFailedMessage =>
      'Falha ao regravar o arquivo no cofre.';

  @override
  String get backTooltip => 'Voltar';

  @override
  String get forwardTooltip => 'Avançar';

  @override
  String get reloadTooltip => 'Recarregar';

  @override
  String get optionsTooltip => 'Opções';

  @override
  String get htmlViewerErrorTitle => 'Não é possível exibir esta página';

  @override
  String get htmlViewerLoadFailedMessage => 'Falha ao carregar o arquivo';

  @override
  String get enableJavaScriptDialogTitle => 'Ativar JavaScript?';

  @override
  String get enableJavaScriptDialogMessage =>
      'A página poderá executar seus próprios scripts locais. Ela ainda não tem acesso à rede — nada neste cofre pode ser enviado ou recebido pela internet.';

  @override
  String get disableJavaScriptMenu => 'Desativar JavaScript';

  @override
  String get enableJavaScriptMenu => 'Ativar JavaScript';

  @override
  String get enterFullscreenMenu => 'Entrar em Tela Cheia';

  @override
  String failedToOpenExternalApp(String error) {
    return 'Falha ao abrir em app externo: $error';
  }

  @override
  String get thisFolderMenu => 'Esta Pasta';

  @override
  String get allInclSubfoldersMenu => 'Tudo (Incl. Subpastas)';

  @override
  String get disableShuffleMenu => 'Desativar Aleatório';

  @override
  String get shufflePlaylistMenu => 'Reproduzir Lista Aleatoriamente';

  @override
  String get playlistOptionsTooltip => 'Opções da Lista de Reprodução';

  @override
  String get enablePlaylistTooltip => 'Ativar Lista de Reprodução';

  @override
  String get moreActionsTooltip => 'Mais Ações';

  @override
  String get forcePortraitMenu => 'Forçar Retrato';

  @override
  String get forceLandscapeMenu => 'Forçar Paisagem';

  @override
  String get autoRotateSensorMenu => 'Rotação Automática (Sensor)';

  @override
  String get screenOrientationMenu => 'Orientação da Tela';

  @override
  String get playlistTransitionMenu => 'Transição da Lista de Reprodução';

  @override
  String get renameFileMenu => 'Renomear Arquivo';

  @override
  String get deleteFileMenu => 'Excluir Arquivo';

  @override
  String get thumbnailCarouselTooltip => 'Carrossel de Miniaturas';

  @override
  String get advancedSettingsTooltip => 'Configurações Avançadas';

  @override
  String get previousTooltip => 'Anterior';

  @override
  String get nextTooltip => 'Próximo';

  @override
  String get diagnosticsCopiedToClipboard =>
      'Diagnóstico copiado para a área de transferência';

  @override
  String get diagnosticsTitle => 'Diagnóstico';

  @override
  String get copyDiagnosticsTooltip => 'Copiar diagnóstico';

  @override
  String get closeTooltip => 'Fechar';

  @override
  String get diagnosticsPlaybackSection => 'Reprodução';

  @override
  String get diagnosticsEngineSection => 'Mecanismo';

  @override
  String get diagnosticsStateLabel => 'Estado';

  @override
  String get diagnosticsResolutionLabel => 'Resolução';

  @override
  String get diagnosticsAspectRatioLabel => 'Proporção';

  @override
  String get diagnosticsPositionLabel => 'Posição';

  @override
  String get diagnosticsDurationLabel => 'Duração';

  @override
  String get diagnosticsErrorLabel => 'Erro';

  @override
  String get diagnosticsPlayerLabel => 'Player';

  @override
  String get diagnosticsDecodingLabel => 'Decodificação';

  @override
  String get diagnosticsExoPlayerValue => 'ExoPlayer (Android)';

  @override
  String get diagnosticsHardwareAcceleratedValue => 'Acelerado por hardware';

  @override
  String get diagnosticsUnknownValue => 'Desconhecido';

  @override
  String get diagnosticsStateBuffering => 'Armazenando em buffer';

  @override
  String get diagnosticsStatePlaying => 'Reproduzindo';

  @override
  String get diagnosticsStatePaused => 'Pausado';

  @override
  String get diagnosticsDurationUnavailable => '--:--';

  @override
  String get rotate90Label => 'Girar 90°';

  @override
  String get imageFitModeLabel => 'Modo de Ajuste da Imagem';

  @override
  String get slideshowDelayLabel => 'Atraso da Apresentação de Slides';

  @override
  String get playbackSpeedLabel => 'Velocidade de Reprodução';

  @override
  String get subtitlesLabel => 'Legendas';

  @override
  String get imageSettingsTitle => 'Configurações de Imagem';

  @override
  String get playbackSettingsTitle => 'Configurações de Reprodução';

  @override
  String get imageFitContain => 'Conter';

  @override
  String get imageFitWidth => 'Ajustar à Largura';

  @override
  String get imageFitHeight => 'Ajustar à Altura';

  @override
  String nSecondsDelay(int n) {
    return '$n segundos';
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
  String get settingsTooltipShort => 'Configurações';

  @override
  String get sourceCodeTooltip => 'Código-fonte';

  @override
  String get donateTooltip => 'Doar';

  @override
  String get shareAppTooltip => 'Compartilhar App';

  @override
  String get resetToDefaultsTooltip => 'Redefinir para o padrão';

  @override
  String get usbUnlockContainerTitle => 'Desbloquear Contêiner USB';

  @override
  String get usbMountContainerTitle => 'Montar Unidade USB';

  @override
  String get staticLabel => 'Estático';

  @override
  String get unmuteTooltip => 'Ativar som';

  @override
  String get muteTooltip => 'Sem som';

  @override
  String get playOnceDisabledTooltip =>
      'Reproduzir Uma Vez (Avanço Automático Desativado)';

  @override
  String get playAndAdvanceTooltip => 'Reproduzir e Avançar para o Próximo';

  @override
  String get loopCurrentVideoTooltip => 'Repetir Vídeo Atual';

  @override
  String get clearThumbnailCacheDialogTitle => 'Limpar Cache de Miniaturas?';

  @override
  String get clearThumbnailCacheDialogMessage =>
      'Isso excluirá as miniaturas em cache deste cofre. Elas serão regeneradas na próxima vez que você navegar pela mídia.';

  @override
  String get clearCacheButton => 'Limpar Cache';

  @override
  String get appCacheClearedUnlockMessage =>
      'Cache do app limpo. Desbloqueie o contêiner para limpar o cache interno.';

  @override
  String get allThumbnailCachesClearedMessage =>
      'Todos os caches de miniaturas foram limpos com sucesso.';

  @override
  String get appCacheClearedContainerFailedMessage =>
      'Cache do app limpo, mas falhou ao limpar dentro do contêiner.';

  @override
  String get failedToClearThumbnailCachesMessage =>
      'Falha ao limpar os caches de miniaturas.';

  @override
  String get authenticateToModifySettingsPrompt =>
      'Autentique-se para modificar as configurações';

  @override
  String get usbVaultSettingsTitle => 'Configurações do Cofre USB';

  @override
  String get vaultSettingsTitle => 'Configurações do Cofre';

  @override
  String get generalSectionHeader => 'Geral';

  @override
  String get securityCredentialsSectionHeader => 'Segurança e Credenciais';

  @override
  String get securityOptionsLockedTitle => 'Opções de Segurança Bloqueadas';

  @override
  String get authenticateOriginalCredentialsMessage =>
      'Autentique-se com as credenciais originais do contêiner para modificar as configurações de segurança.';

  @override
  String get unlockCredentialsLabel => 'Credenciais de Desbloqueio';

  @override
  String get unavailableSuffixLabel => '(Indisponível)';

  @override
  String get patternSetupRequiredBeforeSaving =>
      'Configure um padrão antes de salvar.';

  @override
  String get passwordKeystoreEncryptedHelperText =>
      'A senha é criptografada usando o Android Keystore. Deixe em branco se estiver usando apenas arquivos-chave.';

  @override
  String get changePatternButton => 'Alterar Padrão';

  @override
  String get setPatternButton => 'Definir Padrão';

  @override
  String get cacheDerivedKeyLabel => 'Armazenar Chave Derivada em Cache';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      'Ignorar o KDF scrypt do CryFS na próxima vez (chave mantida no Android Keystore)';

  @override
  String get reuseKeyMaterialKeystoreSubtitle =>
      'Reutilizar material de chave no Android Keystore';

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle =>
      'Fixar algoritmo para pular a detecção automática ao desbloquear.';

  @override
  String get changeContainerPasswordTitle => 'Alterar Senha do Contêiner';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      'As credenciais do BitLocker não podem ser alteradas dentro do app. Use \"Gerenciar BitLocker\" no Windows.';

  @override
  String get systemIntegrationSectionHeader => 'Sistema e Integração';

  @override
  String get autoLockDurationLabel => 'Duração do Bloqueio Automático';

  @override
  String get neverAutoLockOption => 'Nunca';

  @override
  String get exposeContentToFilePickerSubtitle =>
      'Expor o conteúdo ao Seletor de Arquivos do Sistema quando desbloqueado';

  @override
  String get thumbnailStorageSectionHeader => 'Armazenamento de Miniaturas';

  @override
  String get cacheModeLabel => 'Modo de Cache';

  @override
  String get useGlobalDefaultSubtitle => 'Usar padrão global';

  @override
  String get thumbnailQualityLabel => 'Qualidade das Miniaturas';

  @override
  String get clearThumbnailCacheTitle => 'Limpar Cache de Miniaturas';

  @override
  String get removeCachedThumbnailsSubtitle =>
      'Remover miniaturas de imagem e vídeo em cache';

  @override
  String get vaultInformationSectionHeader => 'Informações do Cofre';

  @override
  String get vaultInformationTileTitle => 'Ver Detalhes do Cofre';

  @override
  String get vaultInformationTileSubtitle =>
      'Cifra, formato e outros detalhes técnicos';

  @override
  String get vaultInfoLocationLabel => 'Localização';

  @override
  String get vaultInfoRequiresUnlockTitle => 'Desbloqueio Necessário';

  @override
  String get vaultInfoRequiresUnlockMessage =>
      'Desbloqueie este cofre para ver seus detalhes técnicos.';

  @override
  String get vaultInfoLoadFailedTitle =>
      'Não Foi Possível Carregar as Informações do Cofre';

  @override
  String get vaultInfoLoadFailedMessage =>
      'Algo deu errado ao ler os detalhes deste cofre.';

  @override
  String get vaultInfoVolumeSizeLabel => 'Tamanho do Volume';

  @override
  String get vaultInfoFileSystemLabel => 'File System';

  @override
  String get vaultInfoHiddenVolumeLabel => 'Volume Oculto';

  @override
  String get vaultInfoReadOnlyLabel => 'Somente Leitura';

  @override
  String get vaultInfoLuksVersionLabel => 'Versão do LUKS';

  @override
  String get vaultInfoSectorSizeLabel => 'Tamanho do Setor';

  @override
  String get vaultInfoVaultFormatLabel => 'Formato do Cofre';

  @override
  String get vaultInfoCipherComboLabel => 'Combinação de Cifras';

  @override
  String get vaultInfoShorteningThresholdLabel =>
      'Limite de Encurtamento de Nome de Arquivo';

  @override
  String get vaultInfoFormatVersionLabel => 'Versão do Formato';

  @override
  String get vaultInfoContentCipherLabel => 'Cifra de Conteúdo';

  @override
  String get vaultInfoFilenameEncryptionLabel => 'Nomes de Arquivos';

  @override
  String get vaultInfoPlaintextNamesValue => 'Não criptografados';

  @override
  String get vaultInfoEncryptedNamesValue => 'Criptografados';

  @override
  String get vaultInfoBlockCipherLabel => 'Cifra de Bloco';

  @override
  String get vaultInfoBlockSizeLabel => 'Tamanho do Bloco';

  @override
  String get vaultInfoCreatedWithVersionLabel => 'Criado Com';

  @override
  String get vaultInfoLastOpenedWithVersionLabel => 'Última Abertura Com';

  @override
  String get vaultInfoYesValue => 'Sim';

  @override
  String get vaultInfoNoValue => 'Não';

  @override
  String get vaultInfoBitlockerNote =>
      'Este app não analisa os próprios metadados de cabeçalho do BitLocker, portanto os detalhes de cifra e versão não estão disponíveis aqui.';

  @override
  String get patternSetupRequiredAboveBeforeSaving =>
      'Configure um padrão acima antes de salvar.';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      'É necessária uma senha ou \"Armazenar Chave Derivada em Cache\" com arquivos-chave para este método de desbloqueio.';

  @override
  String get saveConfigurationButton => 'Salvar Configuração';

  @override
  String get incorrectPatternError => 'Padrão incorreto';

  @override
  String get verifyPatternTitle => 'Verificar Padrão';

  @override
  String get incorrectPasswordError => 'Senha incorreta';

  @override
  String get verificationFailedError => 'Falha na verificação';

  @override
  String get incorrectCredentialsError => 'Credenciais incorretas';

  @override
  String get containerPasswordOptionalLabel =>
      'Senha do contêiner (opcional para apenas arquivo-chave)';

  @override
  String get pimOptionalLabel => 'PIM (opcional)';

  @override
  String get usbDriveLockedLabel => 'Unidade USB · Bloqueada';

  @override
  String get lockedContainerLabel => 'Contêiner bloqueado';

  @override
  String get operationInProgressWaitMessage =>
      'Uma operação está em andamento. Aguarde antes de bloquear.';

  @override
  String get reconnectUsbTooltip => 'Reconectar USB';

  @override
  String get unlockContainerTooltip => 'Desbloquear contêiner';

  @override
  String lockFailedMessage(String errorType) {
    return 'Falha ao bloquear: $errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired =>
      'É necessária uma nova senha ou arquivos-chave.';

  @override
  String get newPasswordsDoNotMatch => 'As novas senhas não coincidem.';

  @override
  String get passwordChangedSuccessfullyMessage =>
      'Senha alterada com sucesso.';

  @override
  String get failedToChangePasswordMessage =>
      'Falha ao alterar a senha. Verifique as credenciais antigas.';

  @override
  String get currentCredentialsSectionHeader => 'Credenciais Atuais';

  @override
  String get oldPasswordLabel => 'Senha Antiga';

  @override
  String get oldPimOptionalLabel => 'PIM Antigo (Opcional)';

  @override
  String get newCredentialsSectionHeader => 'Novas Credenciais';

  @override
  String get newPimOptionalLabel => 'Novo PIM (Opcional)';

  @override
  String get noContainersYetTitle => 'Nenhum contêiner ainda';

  @override
  String get dashboardEmptyStateMessage =>
      'Monte um contêiner VeraCrypt, conecte uma unidade USB ou crie um cofre criptografado totalmente novo para começar.';

  @override
  String get sortFieldName => 'Nome';

  @override
  String get sortFieldSize => 'Tamanho';

  @override
  String get sortFieldType => 'Tipo';

  @override
  String get sortFieldDate => 'Data';

  @override
  String get layoutModeDetailedList => 'Lista Detalhada';

  @override
  String get layoutModeCompactList => 'Lista Compacta';

  @override
  String get layoutModeGalleryGrid => 'Grade de Galeria';

  @override
  String get readOnlyCantDeleteTooltip =>
      'Somente leitura — não é possível excluir';

  @override
  String get readOnlyCantMoveTooltip =>
      'Somente leitura — não é possível mover';

  @override
  String get readOnlyCantRenameTooltip =>
      'Somente leitura — não é possível renomear';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes (calculando…)';
  }

  @override
  String get sizeCalculatingLabel => 'calculando…';

  @override
  String get editSecureItemsToRenameMessage =>
      'Edite itens seguros para renomeá-los';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage =>
      'Itens do cofre não podem ser abertos em apps externos';

  @override
  String get mountedReadOnlyTooltip => 'Montado somente leitura';

  @override
  String get readOnlyBadgeAbbreviation => 'SL';

  @override
  String freeSpaceLabel(String bytes) {
    return '$bytes livres';
  }

  @override
  String get filteredLabel => 'filtrado';

  @override
  String get statsStorageSectionHeader => 'ARMAZENAMENTO';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pastas',
      one: '1 pasta',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos',
      one: '1 arquivo',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => 'Todos os Arquivos';

  @override
  String get filterImagesOption => 'Imagens';

  @override
  String get filterVideosOption => 'Vídeos';

  @override
  String get filterAudioOption => 'Áudio';

  @override
  String get filterDocumentsOption => 'Documentos';

  @override
  String get folderExposedAsStorageExplanation =>
      'Esta pasta é exposta como seu próprio local de armazenamento, para que outros apps possam navegar e abrir seus arquivos diretamente.';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens já existem',
      one: '1 item já existe',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle =>
      'Escolha o que acontece com cada item, ou aplique uma escolha a todos.';

  @override
  String get skipAllChipLabel => 'Ignorar todos';

  @override
  String get overwriteAllChipLabel => 'Substituir todos';

  @override
  String get overwriteItemDropdownLabel => 'Substituir';

  @override
  String get overwriteFolderDropdownLabel => 'Substituir pasta';

  @override
  String get fileOpsTransfersInProgressTitle => 'Transferências em andamento';

  @override
  String get fileOpsRecentTransfersTitle => 'Transferências recentes';

  @override
  String get fileOpsNoRecentTransfersMessage => 'Nenhuma transferência recente';

  @override
  String get fileOpsNoRecentTransfersSubtitle =>
      'Cópias, movimentações e exclusões aparecerão aqui enquanto estiverem em execução.';

  @override
  String fileOpsShowDetailsLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get fileOpsCancelTooltip => 'Cancelar';

  @override
  String get fileOpsDismissTooltip => 'Dismiss';

  @override
  String get fileOpsRootDestinationLabel => 'Raiz';

  @override
  String get fileOpsCancelledStatusLabel => 'Cancelado';

  @override
  String fileOpsItemsFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens falharam:',
      one: '1 item falhou:',
    );
    return '$_temp0';
  }

  @override
  String fileOpsMoreItemsLabel(num count) {
    return '+ $count mais';
  }

  @override
  String get transferActivityTooltip => 'Transferências';

  @override
  String fileOpsSpeedLabel(String speed) {
    return '$speed/s';
  }

  @override
  String fileOpsEtaLabel(String time) {
    return '~$time restante';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return 'Erro ao ler o arquivo: $error';
  }

  @override
  String get archivePreviewNotAvailableMessage =>
      'Visualização não disponível para este tipo de arquivo.';

  @override
  String get avifFailedToRenderMessage => 'Falha ao renderizar AVIF';

  @override
  String get encryptedImageLoadFailedMessage =>
      'Falha ao carregar imagem criptografada';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return 'Falha ao carregar imagem criptografada: $error';
  }

  @override
  String get invalidOrCorruptedImageMessage =>
      'Formato de imagem inválido ou corrompido.';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '$current de $total';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '$current de $total  ·  verificando…';
  }

  @override
  String get mediaViewerScanningLabel => 'Verificando…';

  @override
  String get mediaFileDeletedMessage => 'Arquivo excluído com sucesso';

  @override
  String get mediaFileDeleteFailedMessage => 'Falha ao excluir o arquivo';

  @override
  String get mediaFileRenamedMessage => 'Arquivo renomeado com sucesso';

  @override
  String get aboutScreenTitle => 'Sobre';

  @override
  String get couldNotOpenLinkMessage => 'Não foi possível abrir o link';

  @override
  String get fileManagerSettingsTitle =>
      'Configurações do Gerenciador de Arquivos';

  @override
  String get showMediaThumbnailsLabel => 'Mostrar Miniaturas de Mídia';

  @override
  String get showMediaThumbnailsDesc =>
      'Exibir prévias em miniatura para imagens e vídeos na visualização em lista';

  @override
  String get showFileNamesLabel => 'Mostrar Nomes de Arquivos';

  @override
  String get showFileNamesDesc =>
      'Exibir rótulos de texto sob os itens na visualização em grade';

  @override
  String get showBreadcrumbBarLabel => 'Mostrar Barra de Navegação';

  @override
  String get showBreadcrumbBarDesc =>
      'Barra de navegação de caminho na parte superior do navegador';

  @override
  String get showStatsBarLabel => 'Mostrar Barra de Estatísticas';

  @override
  String get showStatsBarDesc =>
      'Banner com contagem de arquivos e espaço livre';

  @override
  String get autoStartPlaylistModeLabel =>
      'Iniciar Modo de Lista Automaticamente';

  @override
  String get autoStartPlaylistModeDesc =>
      'Iniciar automaticamente no modo de lista de reprodução ao abrir um item de mídia';

  @override
  String get showPlaylistCarouselLabel =>
      'Mostrar Carrossel da Lista de Reprodução';

  @override
  String get showPlaylistCarouselDesc =>
      'Mostrar botão do carrossel de miniaturas ao visualizar listas de reprodução de mídia';

  @override
  String get videoPlaybackSliderLabel =>
      'Controle deslizante de posição de reprodução de vídeo';

  @override
  String get longPressPlaybackDiagnosticsHint =>
      'Toque e segure para diagnóstico de reprodução';

  @override
  String get staticImageModeLabel => 'Modo de imagem estática';

  @override
  String slideshowModeActiveLabel(int seconds) {
    return 'Modo de apresentação de slides ativo com $seconds segundos de atraso';
  }

  @override
  String videoPlaybackModeLabel(String mode) {
    return 'Modo de reprodução de vídeo: $mode';
  }

  @override
  String get pauseLabel => 'Pausar';

  @override
  String get playLabel => 'Reproduzir';

  @override
  String get emptyFolderTitle => 'Pasta Vazia';

  @override
  String get emptyFolderMessage =>
      'Use a ação Adicionar para criar arquivos ou importar do dispositivo.';

  @override
  String get noResultsTitle => 'Nenhum resultado';

  @override
  String noResultsForQueryMessage(String query) {
    return 'Nada nesta pasta corresponde a \"$query\".';
  }

  @override
  String get closeCarouselTooltip => 'Fechar Carrossel';

  @override
  String get playlistScrollModeMenu => 'Modo de Rolagem da Lista de Reprodução';

  @override
  String get playlistScrollHorizontalLabel => 'Horizontal';

  @override
  String get playlistScrollVerticalPageLabel => 'Vertical Paginado';

  @override
  String get playlistScrollVerticalContinuousLabel => 'Vertical Contínuo';

  @override
  String get undoTooltip => 'Desfazer';

  @override
  String get redoTooltip => 'Refazer';

  @override
  String get autosavingLabel => 'Salvando automaticamente…';

  @override
  String get savingLabel => 'Salvando…';

  @override
  String autosavedAtLabel(String time) {
    return 'Salvo automaticamente às $time';
  }

  @override
  String cameraDisconnectedError(String message) {
    return 'Câmera desconectada: $message';
  }

  @override
  String get unknownErrorFallback => 'erro desconhecido';

  @override
  String get cameraPermissionsRequiredMessage =>
      'As permissões de câmera e microfone são necessárias para usar a câmera.';

  @override
  String cameraErrorMessage(String error) {
    return 'Erro na câmera: $error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage => 'Falha ao capturar a foto';

  @override
  String get cameraRecordingFailedMessage => 'Falha na gravação';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return 'Falha na gravação: $error';
  }

  @override
  String get cameraRecordingTooShortMessage =>
      'A gravação foi muito curta para ser salva';

  @override
  String get cameraCouldNotSaveRecordingMessage =>
      'Não foi possível salvar a gravação';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return 'Não foi possível salvar a gravação: $error';
  }

  @override
  String get cameraCouldNotSwitchLensMessage =>
      'Não foi possível trocar a lente';

  @override
  String get cameraEncryptingPhotoLabel => 'Criptografando foto…';

  @override
  String get cameraEncryptingVideoLabel => 'Criptografando vídeo…';

  @override
  String get aboutApplicationSectionHeader => 'Aplicativo';

  @override
  String get aboutTagline =>
      'Gratuito · Código Aberto · Cofre Criptografado Offline';

  @override
  String get aboutVersionTitle => 'Versão';

  @override
  String aboutVersionSubtitle(String version) {
    return 'v$version · Toque para copiar informações da versão para relatórios de bugs';
  }

  @override
  String get aboutWhatsNewTitle => 'Novidades';

  @override
  String get aboutWhatsNewSubtitle =>
      'Veja as mudanças recentes e notas de versão';

  @override
  String get aboutPrivacySecurityTitle => 'Privacidade e Segurança';

  @override
  String get aboutPrivacySecuritySubtitle =>
      'Sem acesso à rede, nada não criptografado é gravado no disco';

  @override
  String get aboutSupportedFormatsSectionHeader => 'Formatos Suportados';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt e LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      'Volumes padrão e ocultos, PIM personalizado, arquivos-chave, xts-plain64, Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker e BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle =>
      'Suporte a senhas de usuário e chave de recuperação numérica de 48 dígitos';

  @override
  String get aboutDirectoryVaultsTitle => 'Cofres de Pasta';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator (v7/v8 SIV_GCM e SIV_CTRMAC), gocryptfs (v2 AES-GCM e XChaCha20), CryFS (v0.10+ XChaCha20 e AES)';

  @override
  String get aboutVhdTitle => 'Discos Rígidos Virtuais (VHD / VHDX)';

  @override
  String get aboutVhdSubtitle =>
      'Tradução BAT para imagens de disco fixas e dinâmicas expansíveis';

  @override
  String get aboutNativeCoreEngineSectionHeader => 'Mecanismo Nativo Principal';

  @override
  String get aboutCompiledLibrariesTitle => 'Bibliotecas C++ Compiladas';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.0 (Criptografia por Hardware ARMv8 e SHA-2)\n• libavif e libgav1 (Decodificador Nativo de Imagem AVIF)\n• ChaN FatFs v4.0.4 (FAT12/16/32 e exFAT)\n• Tuxera NTFS-3G e mkntfs embutido\n• e2fsprogs v1.47.4 libext2fs (ext2/ext3/ext4)\n• Dislocker Virtual I/O (BitLocker FVE / To Go)\n• VeraCrypt 1.26.29 (Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id/i)\n• cJSON v1.7.18 (metadados LUKS2 e Cryptomator)';

  @override
  String get aboutCommunitySectionHeader => 'Comunidade e Código Aberto';

  @override
  String get aboutReportIssueTitle => 'Relatar um Problema';

  @override
  String get aboutReportIssueSubtitle =>
      'Encontrou um bug? Envie um relato no GitHub';

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
  String get aboutContributorsTitle => 'Contribuidores';

  @override
  String get aboutContributorsSubtitle =>
      'Pessoas que ajudaram a construir o VaultExplorer';

  @override
  String get aboutLicensesTitle => 'Licenças de Código Aberto';

  @override
  String get aboutLicensesSubtitle =>
      'Bibliotecas de terceiros usadas neste app';

  @override
  String get aboutFooterMadeWithLove => 'Feito com ❤ pela privacidade.';

  @override
  String get aboutVersionCopiedMessage =>
      'Informações da versão copiadas — útil para relatórios de bugs';

  @override
  String aboutVersionClipboardText(String version) {
    return 'VaultExplorer v$version (Android)';
  }

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer — um cofre gratuito, de código aberto e offline para Android.\n\nArmazene senhas, notas e arquivos dentro de um contêiner criptografado (VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs, CryFS).\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage =>
      'Link compartilhável copiado para a área de transferência';

  @override
  String get aboutPrivacySheetTitle => 'Privacidade e Segurança de Dados';

  @override
  String get aboutPrivacySheetSubtitle =>
      'Design de segurança 100% offline, com memória local';

  @override
  String get privacyPointNoNetworkTitle => 'Nenhum acesso à rede necessário';

  @override
  String get privacyPointNoNetworkBody =>
      'O VaultExplorer não solicita a permissão android.permission.INTERNET no Android. Ele não pode se comunicar por nenhuma rede.';

  @override
  String get privacyPointNoDiskLeaksTitle =>
      'Zero vazamentos não criptografados em disco';

  @override
  String get privacyPointNoDiskLeaksBody =>
      'A descriptografia e a recriptografia ocorrem inteiramente na memória do sistema. Arquivos temporários não criptografados nunca são salvos no armazenamento do dispositivo.';

  @override
  String get privacyPointNoAnalyticsTitle => 'Sem análises ou telemetria';

  @override
  String get privacyPointNoAnalyticsBody =>
      'Não há relatório de falhas, rastreamento de uso ou SDK de terceiros coletando dados sobre você ou seu dispositivo.';

  @override
  String get privacyPointKeystoreTitle =>
      'Segredos permanecem no Android Keystore';

  @override
  String get privacyPointKeystoreBody =>
      'Senhas memorizadas, padrões e chaves derivadas em cache são selados usando AES-256-GCM no Android Keystore protegido por hardware.';

  @override
  String get privacyPointPosixTitle =>
      'Aceleração POSIX e Acesso ao Armazenamento';

  @override
  String get privacyPointPosixBody =>
      'Arquivos dentro de cofres de pasta são lidos e gravados diretamente sempre que possível, contornando a camada SAF mais lenta do Android para pastas grandes.';

  @override
  String get privacyPointScreenClipboardTitle =>
      'Proteção de Tela e Área de Transferência';

  @override
  String get privacyPointScreenClipboardBody =>
      'Bloqueio de prévia em capturas de tela/alternador de tarefas (FLAG_SECURE), além de sanitização automática de área de transferência corrompida ao focar a janela. Senhas copiadas do Cofre de Itens são marcadas como sensíveis no Android 13+ e apagadas automaticamente após 30 segundos se não forem usadas.';

  @override
  String get privacyPointMaskModeTitle => 'Modo Disfarce';

  @override
  String get privacyPointMaskModeBody =>
      'Disfarça opcionalmente o app como um navegador de arquivos zip funcional, com um ícone e nome diferentes. Mantenha o título pressionado por 2 segundos para acessar seu cofre real.';

  @override
  String get privacyPointExternalLinksTitle =>
      'Links externos abrem no navegador';

  @override
  String get privacyPointExternalLinksBody =>
      'Tocar em links transfere a solicitação para o seu aplicativo de navegador padrão, que a processa.';

  @override
  String get truncatedListingWarning =>
      'Mostrando os primeiros 50.000 itens — esta pasta tem mais arquivos.';

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '$size px · qualidade $quality%';
  }

  @override
  String holdToSpeedIndicatorLabel(String speed) {
    return 'Velocidade $speed×';
  }

  @override
  String get toolbarLayoutSectionHeader => 'Layout da Barra de Ferramentas';

  @override
  String get listViewOptionsSectionHeader => 'Opções de Visualização em Lista';

  @override
  String get detailedListViewColumnsSectionHeader =>
      'Colunas da Lista Detalhada';

  @override
  String get galleryGridViewSectionHeader => 'Visualização em Grade de Galeria';

  @override
  String get browserLayoutSectionHeader => 'Layout do Navegador';

  @override
  String get mediaViewerSectionHeader => 'Visualizador de Mídia';

  @override
  String get viewModeAction => 'Modo de exibição';

  @override
  String get sortAction => 'Ordenar';

  @override
  String get playMediaAction => 'Reproduzir mídia';

  @override
  String containerSpaceSummary(String free, String total) {
    return '$free livres · $total no total';
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
      'Senha/arquivos-chave incorretos ou unidade não suportada';

  @override
  String driveUsableCapacity(int mb) {
    return 'Capacidade utilizável da unidade: $mb MB. Não deve ser excedida.';
  }

  @override
  String get unlockMethodManualPassword => 'Senha Manual';

  @override
  String get unlockMethodRememberPassword => 'Lembrar Senha';

  @override
  String get unlockMethodBiometrics => 'Desbloqueio Biométrico';

  @override
  String get unlockMethodPattern => 'Desbloqueio por Padrão';

  @override
  String get unlockMethodPin => 'Desbloqueio por PIN';

  @override
  String get unlockMethodSubtitlePassword => 'Digitar a senha toda vez';

  @override
  String get unlockMethodSubtitleRememberPassword =>
      'Armazenada com segurança no Android Keystore';

  @override
  String get unlockMethodSubtitleBiometrics =>
      'Usar impressão digital ou rosto para desbloquear';

  @override
  String get unlockMethodSubtitlePattern =>
      'Desenhar um padrão para desbloquear';

  @override
  String get unlockMethodSubtitlePin => 'Digitar um PIN para desbloquear';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError =>
      'Decodificador de vídeo indisponível — conflito de codec de hardware';

  @override
  String get mediaStreamInitFailedError =>
      'Falha na inicialização do fluxo de mídia';

  @override
  String get invalidAvifImage => 'Imagem AVIF inválida';

  @override
  String get verbImport => 'Importar';

  @override
  String get verbExport => 'Export';

  @override
  String get verbMove => 'Mover';

  @override
  String get verbCopy => 'Copiar';

  @override
  String get verbDelete => 'Excluir';

  @override
  String get verbImported => 'Importado';

  @override
  String get verbExported => 'Exported';

  @override
  String get verbMoved => 'Movido';

  @override
  String get verbCopied => 'Copiado';

  @override
  String get verbDeleted => 'Excluído';

  @override
  String get verbImporting => 'Importando';

  @override
  String get verbExporting => 'Exporting';

  @override
  String get verbMoving => 'Movendo';

  @override
  String get verbCopying => 'Copiando';

  @override
  String get verbDeleting => 'Excluindo';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens $verb',
      one: '1 item $verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return '$count ignorados';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return '$count com falha';
  }

  @override
  String get statusCancelled => 'Cancelado';

  @override
  String get statusFailed => 'Falhou';

  @override
  String get statusCompleted => 'Concluído';

  @override
  String get fileOpCheckingSpace => 'Verificando espaço disponível…';

  @override
  String get fileOpResolvingConflicts => 'Resolvendo conflitos…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return 'Espaço insuficiente — necessário $required, apenas $free livres';
  }

  @override
  String get fileOpDiskFullPartialRemoved =>
      'Disco cheio — arquivos parciais removidos';

  @override
  String get fileOpMoveFailed => 'Falha ao mover';

  @override
  String get fileOpCopyFailed => 'Falha ao copiar';

  @override
  String get fileOpDeleteFailed => 'Falha ao excluir';

  @override
  String get fileOpDiskFull => 'Disco cheio';

  @override
  String get fileOpImporting => 'Importando…';

  @override
  String get fileOpExporting => 'Exporting…';

  @override
  String fileOpImportingName(String name) {
    return 'Importando $name…';
  }

  @override
  String fileOpExportingName(String name) {
    return 'Exporting $name…';
  }

  @override
  String fileOpMovingName(String name) {
    return 'Movendo $name…';
  }

  @override
  String fileOpCopyingName(String name) {
    return 'Copiando $name…';
  }

  @override
  String get fileOpDeleting => 'Excluindo…';

  @override
  String fileOpDeletingName(String name) {
    return 'Excluindo $name…';
  }

  @override
  String fileOpDeletedSoFar(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens removidos',
      one: '1 item removido',
    );
    return '$_temp0';
  }

  @override
  String get searchInSubfoldersHint => 'Pesquisar em todas as subpastas…';

  @override
  String get deepSearchEnabledTooltip =>
      'Pesquisando subpastas — toque para pesquisar apenas na pasta atual';

  @override
  String get deepSearchDisabledTooltip =>
      'Pesquisando na pasta atual — toque para pesquisar subpastas';

  @override
  String get filterAction => 'Filtrar';

  @override
  String get bookmarkAction => 'Adicionar aos favoritos';

  @override
  String get unbookmarkAction => 'Remover dos favoritos';

  @override
  String get bookmarkSelectedAction => 'Adicionar selecionados aos favoritos';

  @override
  String get unbookmarkSelectedAction => 'Remover selecionados dos favoritos';

  @override
  String bookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens adicionados aos favoritos',
      one: '1 item adicionado aos favoritos',
    );
    return '$_temp0';
  }

  @override
  String unbookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens removidos dos favoritos',
      one: '1 item removido dos favoritos',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => 'Mostrar Barra de Favoritos';

  @override
  String get showBookmarkBarDesc =>
      'Exibir itens favoritos em uma barra ou barra lateral de favoritos';

  @override
  String get bookmarkBarSectionHeader => 'Barra de Favoritos';

  @override
  String get noBookmarksYet => 'Nenhum item adicionado aos favoritos ainda';

  @override
  String get reorderBookmarksTitle => 'Reorganizar Favoritos';

  @override
  String get reorderBookmarksDesc =>
      'Arraste os itens para reordená-los na barra de favoritos';

  @override
  String get navBarVaultsLabel => 'Cofres';

  @override
  String get navBarToolsLabel => 'Ferramentas';

  @override
  String get toolsScreenTitle => 'Ferramentas';

  @override
  String get toolsSectionContainerUtilities => 'Utilitários de Contêiner';

  @override
  String get toolsSectionFileCryptography => 'Criptografia de Arquivos';

  @override
  String get toolsSectionStorageDiagnostics => 'Armazenamento e Diagnóstico';

  @override
  String get toolContainerSplitterTitle => 'Dividir e Unir';

  @override
  String get toolContainerSplitterSubtitle =>
      'Dividir um contêiner em partes, ou reuni-las';

  @override
  String get toolContainerRepairTitle => 'Verificar e Reparar';

  @override
  String get toolContainerRepairSubtitle =>
      'Diagnosticar problemas de cabeçalho ou sistema de arquivos';

  @override
  String get toolSingleFileCryptoTitle =>
      'Criptografar / Descriptografar Arquivos';

  @override
  String get toolSingleFileCryptoSubtitle =>
      'Proteger um ou mais arquivos sem um contêiner completo';

  @override
  String get toolStorageAnalyzerTitle => 'Analisador de Armazenamento';

  @override
  String get toolStorageAnalyzerSubtitle =>
      'Veja o que está ocupando espaço em um cofre montado';

  @override
  String get toolDuplicateFinderTitle => 'Localizador de Arquivos Duplicados';

  @override
  String get toolDuplicateFinderSubtitle =>
      'Encontre e remova arquivos duplicados idênticos byte a byte para recuperar espaço';

  @override
  String get toolHashVerifierTitle =>
      'Verificador de Checksum e Hash de Arquivos';

  @override
  String get toolHashVerifierSubtitle =>
      'Verifique se arquivos grandes não foram corrompidos usando checksums MD5/SHA';

  @override
  String get hashVerifierModeCompute => 'Calcular';

  @override
  String get hashVerifierModeVerify => 'Verificar';

  @override
  String get hashVerifierSelectSourceTitle => 'Selecionar Origem do Arquivo';

  @override
  String get hashVerifierAlgorithmsLabel => 'Algoritmos';

  @override
  String get hashVerifierNoAlgorithmSelected =>
      'Selecione pelo menos um algoritmo';

  @override
  String get hashVerifierFilesLabel => 'Arquivos para Hash';

  @override
  String hashVerifierFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos selecionados',
      one: '1 arquivo selecionado',
      zero: 'Nenhum arquivo selecionado',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierComputeButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Calcular $count Hashes',
      one: 'Calcular Hash',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCancelButton => 'Cancelar';

  @override
  String hashVerifierBatchProgressLabel(Object current, Object total) {
    return 'Arquivo $current de $total';
  }

  @override
  String get hashVerifierCancelledMessage => 'Cancelado.';

  @override
  String hashVerifierComputeErrorsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos falharam ao gerar hash',
      one: '1 arquivo falhou ao gerar hash',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCopiedMessage =>
      'Copiado para a área de transferência';

  @override
  String get hashVerifierExportManifestButton => 'Exportar como Manifesto';

  @override
  String get hashVerifierExportAlgorithmLabel => 'Algoritmo do manifesto';

  @override
  String hashVerifierExportSuccessMessage(Object path) {
    return 'Salvo em $path';
  }

  @override
  String hashVerifierExportFailedMessage(Object error) {
    return 'Falha na exportação: $error';
  }

  @override
  String get hashVerifierLoadManifestButton => 'Carregar Manifesto';

  @override
  String get hashVerifierChangeManifestButton => 'Alterar';

  @override
  String get hashVerifierManifestLabel => 'Arquivo de Manifesto';

  @override
  String hashVerifierManifestEntryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entradas',
      one: '1 entrada',
      zero: 'Nenhuma entrada',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierAutoAddFolderButton =>
      'Adicionar Todos os Arquivos Desta Pasta';

  @override
  String get hashVerifierAddFilesToVerifyButton =>
      'Adicionar Arquivos para Verificar';

  @override
  String get hashVerifierVerifyAllButton => 'Verificar Tudo';

  @override
  String hashVerifierVerifyProgressLabel(Object current, Object total) {
    return 'Verificando arquivo $current de $total';
  }

  @override
  String hashVerifierSummaryMessage(
    Object ok,
    Object mismatch,
    Object missing,
  ) {
    return '$ok correspondem, $mismatch não correspondem, $missing ausentes';
  }

  @override
  String get hashVerifierStatusMatch => 'Corresponde';

  @override
  String get hashVerifierStatusMismatch => 'Não corresponde';

  @override
  String get hashVerifierStatusMissing => 'Arquivo não adicionado';

  @override
  String get hashVerifierStatusPending => 'Ainda não verificado';

  @override
  String get hashVerifierExpectedLabel => 'Esperado';

  @override
  String get hashVerifierActualLabel => 'Real';

  @override
  String hashVerifierExtraFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos extras não listados no manifesto',
      one: '1 arquivo extra não listado no manifesto',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierNoManifestLoadedMessage =>
      'Carregue um arquivo de manifesto para começar';

  @override
  String get hashVerifierManifestParseEmptyMessage =>
      'Nenhuma entrada de checksum encontrada neste arquivo';

  @override
  String hashVerifierLoadManifestFailedMessage(Object error) {
    return 'Não foi possível ler o manifesto: $error';
  }

  @override
  String hashVerifierAutoAddedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos adicionados da pasta do cofre',
      one: '1 arquivo adicionado da pasta do cofre',
      zero: 'Nenhum arquivo novo encontrado',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierModeVault => 'Cofre';

  @override
  String get hashVerifierVaultPickerLabel => 'Cofre';

  @override
  String get hashVerifierVaultNoVaultsMessage =>
      'Nenhum cofre está montado no momento';

  @override
  String get hashVerifierCheckEntireVaultButton => 'Verificar Cofre Inteiro';

  @override
  String get hashVerifierVaultScanningLabel => 'Verificando cofre…';

  @override
  String hashVerifierVaultFilesDiscoveredLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos encontrados',
      one: '1 arquivo encontrado',
      zero: 'Nenhum arquivo encontrado ainda',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmTitle => 'Verificar todo o cofre?';

  @override
  String hashVerifierVaultConfirmFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos',
      one: '1 arquivo',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmWarning =>
      'Todos os arquivos deste cofre serão lidos.';

  @override
  String get hashVerifierVaultEmptyMessage =>
      'Este cofre não tem arquivos para verificar';

  @override
  String get hashVerifierVaultStartButton => 'Iniciar Verificação';

  @override
  String hashVerifierVaultHashingProgressLabel(Object current, Object total) {
    return 'Verificando $current / $total';
  }

  @override
  String get hashVerifierVaultCompleteTitle => 'Verificação do Cofre Concluída';

  @override
  String hashVerifierVaultCompleteFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos verificados',
      one: '1 arquivo verificado',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteBytesLabel(Object size) {
    return '$size processados';
  }

  @override
  String hashVerifierVaultCompleteSucceededLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count com sucesso',
      one: '1 com sucesso',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count com falha',
      one: '1 com falha',
      zero: '0 com falha',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultElapsedLabel(Object time) {
    return 'Tempo decorrido: $time';
  }

  @override
  String get hashVerifierVaultCancelledMessage =>
      'Verificação do cofre cancelada.';

  @override
  String hashVerifierVaultFailedMessage(Object error) {
    return 'Falha na verificação do cofre: $error';
  }

  @override
  String get hashVerifierVaultNewCheckButton => 'Nova Verificação';

  @override
  String get hashVerifierVaultActionComputeTitle => 'Calcular Cofre Inteiro';

  @override
  String get hashVerifierVaultActionComputeSubtitle =>
      'Gerar hash de todos os arquivos de um cofre';

  @override
  String get hashVerifierVaultActionVerifyTitle => 'Verificar Cofre Inteiro';

  @override
  String get hashVerifierVaultActionVerifySubtitle =>
      'Verificar todos os arquivos de um cofre contra um manifesto carregado';

  @override
  String get hashVerifierVaultChangeActionButton => 'Alterar';

  @override
  String get hashVerifierVaultVerifyButton => 'Verificar Cofre Inteiro';

  @override
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage =>
      'Verificar um cofre inteiro requer um manifesto carregado de dentro de um cofre.';

  @override
  String get duplicateFinderTargetLabel => 'Cofre de Destino';

  @override
  String get duplicateFinderTargetAllVaults => 'Todos os Cofres Abertos';

  @override
  String get duplicateFinderStartScan => 'Iniciar Verificação';

  @override
  String get duplicateFinderCancelScan => 'Cancelar Verificação';

  @override
  String get duplicateFinderRescan => 'Verificar Novamente';

  @override
  String get duplicateFinderScanningStage1 =>
      'Etapa 1: Indexando e agrupando por tamanho...';

  @override
  String get duplicateFinderScanningStage2 =>
      'Etapa 2: Verificando cabeçalhos parciais dos arquivos...';

  @override
  String get duplicateFinderScanningStage3 =>
      'Etapa 3: Verificando hashes completos de bytes...';

  @override
  String get duplicateFinderScanComplete => 'Verificação Concluída';

  @override
  String get duplicateFinderNoDuplicatesTitle =>
      'Nenhum Arquivo Duplicado Encontrado';

  @override
  String get duplicateFinderNoDuplicatesMessage =>
      'Todos os arquivos do(s) cofre(s) verificado(s) contêm conteúdo de bytes exclusivo.';

  @override
  String get duplicateFinderSelectRedundant => 'Selecionar Redundantes';

  @override
  String get duplicateFinderSelectAll => 'Selecionar Tudo';

  @override
  String get duplicateFinderDeselectAll => 'Desmarcar Tudo';

  @override
  String get duplicateFinderOriginalLabel => 'Original';

  @override
  String get duplicateFinderDuplicateLabel => 'Duplicado';

  @override
  String get duplicateFinderConfirmDeleteTitle =>
      'Excluir Arquivos Duplicados?';

  @override
  String get duplicateFinderSearchHint =>
      'Pesquisar duplicados por nome de arquivo ou caminho...';

  @override
  String get toolNotImplementedYetMessage =>
      'Esta ferramenta ainda não está conectada ao mecanismo nativo — verifique novamente em uma atualização futura.';

  @override
  String get splitJoinModeSplit => 'Dividir';

  @override
  String get splitJoinModeJoin => 'Unir';

  @override
  String get splitSourceFileLabel => 'Arquivo de Origem';

  @override
  String get splitDestinationFolderLabel => 'Pasta de Destino';

  @override
  String get splitChunkSizeLabel => 'Tamanho da Parte';

  @override
  String get splitChunkSizeCustomLabel => 'Tamanho personalizado (MB)';

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
  String get splitContainerButton => 'Dividir Contêiner';

  @override
  String get joinFirstPartLabel => 'Primeira Parte';

  @override
  String get joinOutputFileNameLabel => 'Nome do Arquivo de Saída';

  @override
  String get joinContainerButton => 'Unir Arquivos';

  @override
  String get chooseFileButton => 'Escolher Arquivo';

  @override
  String get chooseFolderButton => 'Escolher Pasta';

  @override
  String get noFileSelectedLabel => 'Nenhum arquivo selecionado';

  @override
  String get noFolderSelectedLabel => 'Nenhuma pasta selecionada';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage => 'Contêiner dividido com sucesso';

  @override
  String get joinContainerSuccessMessage => 'Arquivos unidos com sucesso';

  @override
  String get cryptoDirectionEncrypt => 'Criptografar';

  @override
  String get cryptoDirectionDecrypt => 'Descriptografar';

  @override
  String get singleFileCryptoInputFileLabel => 'Arquivos de Entrada';

  @override
  String get singleFileCryptoCipherLabel => 'Cifra';

  @override
  String get singleFileCryptoDeleteOriginalLabel =>
      'Excluir arquivos originais após a criptografia';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Criptografar $count Arquivos',
      one: 'Criptografar Arquivo',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Descriptografar $count Arquivos',
      one: 'Descriptografar Arquivo',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Concluído — $count arquivos processados',
      one: 'Concluído',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return '$succeeded de $total arquivos processados — $failed falharam';
  }

  @override
  String get singleFileCryptoAddFilesButton => 'Adicionar Arquivos';

  @override
  String get singleFileCryptoClearFilesButton => 'Limpar';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count arquivos selecionados',
      one: '1 arquivo selecionado',
      zero: 'Nenhum arquivo selecionado',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return 'Arquivo $current de $total';
  }

  @override
  String get repairTargetStepTitle => 'Escolha um Alvo';

  @override
  String get repairTargetUnmountedFileOption => 'Arquivo Não Montado';

  @override
  String get repairTargetUnmountedFileSubtitle =>
      'Restaurar um cabeçalho de backup em um contêiner que você não abriu';

  @override
  String get repairTargetMountedVolumeSubtitle =>
      'Executar uma verificação do sistema de arquivos em um cofre já aberto';

  @override
  String get repairNoMountedVolumes => 'Nenhum cofre está montado no momento';

  @override
  String get repairScanButton => 'Executar Verificação de Diagnóstico';

  @override
  String get repairChangeTargetButton => 'Alterar Alvo';

  @override
  String get repairDiagnosisHealthy => 'Nenhum problema encontrado';

  @override
  String get repairDiagnosisHeaderCorrupted => 'Cabeçalho Corrompido';

  @override
  String get repairDiagnosisFilesystemDirty =>
      'Sistema de Arquivos Instável / Desmontagem Incorreta';

  @override
  String get repairRestoreBackupHeaderButton => 'Restaurar Cabeçalho de Backup';

  @override
  String get repairRunFilesystemCheckButton =>
      'Executar Verificação e Correção do Sistema de Arquivos';

  @override
  String get repairActionSucceededMessage => 'Reparo concluído com sucesso';

  @override
  String get repairActionFailedMessage =>
      'A ação de reparo não foi bem-sucedida';

  @override
  String get storageAnalyzerTargetLabel => 'Volume';

  @override
  String get storageAnalyzerNoTargetsTitle => 'Nada para Analisar';

  @override
  String get storageAnalyzerNoTargetsMessage =>
      'Monte um cofre primeiro e depois volte aqui para ver a distribuição de armazenamento.';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return '$used de $total usados';
  }

  @override
  String get storageAnalyzerHeaviestFilesHeader => 'Arquivos Mais Pesados';

  @override
  String get storageAnalyzerBreakdownHeader => 'Por Tipo de Arquivo';

  @override
  String get storageAnalyzerScanningMessage => 'Verificando volume…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return 'A verificação parou antecipadamente após $count arquivos — os resultados podem estar incompletos.';
  }

  @override
  String get storageAnalyzerNoFilesFound => 'Nenhum arquivo encontrado';

  @override
  String get storageCategoryImages => 'Imagens';

  @override
  String get storageCategoryVideos => 'Vídeos';

  @override
  String get storageCategoryAudio => 'Áudio';

  @override
  String get storageCategoryDocuments => 'Documentos';

  @override
  String get storageCategoryArchives => 'Arquivos Compactados';

  @override
  String get storageCategoryOther => 'Outro';

  @override
  String get keyfilePassphraseGeneratorTitle =>
      'Gerador de Arquivo-chave e Frase-senha';

  @override
  String get keyfilePassphraseGeneratorSubtitle =>
      'Gere frases-senha Diceware, senhas personalizadas e arquivos-chave de alta entropia';

  @override
  String get tabPassphrase => 'Frase-senha';

  @override
  String get tabKeyfile => 'Arquivo-chave';

  @override
  String get modeDiceware => 'Frase-senha Diceware';

  @override
  String get modeCustomPassword => 'Senha Personalizada';

  @override
  String get keyfileTypeBinary => 'Arquivo-chave Binário (.key)';

  @override
  String get keyfileTypeImage => 'Arquivo-chave de Imagem de Ruído (.png)';

  @override
  String get copyPassphraseSuccess =>
      'Frase-senha copiada para a área de transferência sensível';

  @override
  String get copyFingerprintSuccess =>
      'Impressão digital SHA-256 copiada para a área de transferência';

  @override
  String get saveKeyfileToVault => 'Salvar em Cofre Montado';

  @override
  String get exportKeyfileToStorage =>
      'Exportar para Armazenamento do Dispositivo';

  @override
  String get keyfileNoOpenVaultsMessage =>
      'Nenhum cofre aberto disponível. Monte um cofre primeiro.';

  @override
  String get keyfileSelectDestinationVaultTitle =>
      'Selecionar Cofre de Destino';

  @override
  String keyfileVolumeIdLabel(Object volId) {
    return 'ID do Volume: $volId';
  }

  @override
  String keyfileExportSuccessMessage(Object path) {
    return 'Arquivo-chave exportado para $path';
  }

  @override
  String keyfileExportFailedMessage(Object error) {
    return 'Falha na exportação: $error';
  }

  @override
  String keyfileSavedToVaultMessage(Object vaultName, Object path) {
    return 'Arquivo-chave salvo em $vaultName: $path';
  }

  @override
  String get keyfileWriteFailedMessage =>
      'Falha ao gravar o arquivo-chave no cofre';

  @override
  String keyfileSaveErrorMessage(Object error) {
    return 'Erro ao salvar no cofre: $error';
  }

  @override
  String get passphraseGeneratedSecretLabel => 'Segredo Gerado';

  @override
  String get copyToClipboardTooltip => 'Copiar para a Área de Transferência';

  @override
  String get generateNewTooltip => 'Gerar Novo';

  @override
  String get passphraseStrengthWeak => 'Fraca';

  @override
  String get passphraseStrengthGood => 'Boa';

  @override
  String get passphraseStrengthStrong => 'Forte';

  @override
  String get passphraseStrengthUnbreakable => 'Inquebrável';

  @override
  String get passphraseCrackTimeInstant => '< 1 segundo';

  @override
  String get passphraseCrackTimeShort => 'Alguns dias / meses';

  @override
  String get passphraseCrackTimeCenturies => 'Vários séculos';

  @override
  String get passphraseCrackTimeMillionsOfYears => 'Milhões de anos';

  @override
  String passphraseStrengthLabel(Object label) {
    return 'Força: $label';
  }

  @override
  String passphraseEntropyBitsLabel(Object bits) {
    return '$bits bits de entropia';
  }

  @override
  String passphraseCrackTimeLabel(Object crackTime) {
    return 'Tempo estimado para quebrar: $crackTime';
  }

  @override
  String get dicewareOptionsTitle => 'Opções Diceware EFF';

  @override
  String dicewareWordCountLabel(Object count) {
    return 'Número de Palavras: $count palavras';
  }

  @override
  String dicewareWordCountBitsLabel(Object bits) {
    return '$bits bits';
  }

  @override
  String dicewareWordCountSliderLabel(Object count) {
    return '$count palavras';
  }

  @override
  String get dicewareWordSeparatorLabel => 'Separador de Palavras';

  @override
  String get dicewareSeparatorHyphen => 'Hífen ( - )';

  @override
  String get dicewareSeparatorSpace => 'Espaço (   )';

  @override
  String get dicewareSeparatorUnderscore => 'Sublinhado ( _ )';

  @override
  String get dicewareSeparatorDot => 'Ponto ( . )';

  @override
  String get dicewareSeparatorSlash => 'Barra ( / )';

  @override
  String get dicewareWordCasingLabel => 'Capitalização das Palavras';

  @override
  String get dicewareCasingLowercase => 'minúsculas';

  @override
  String get dicewareCasingTitleCase => 'Primeira Letra Maiúscula';

  @override
  String get dicewareCasingUppercase => 'MAIÚSCULAS';

  @override
  String get dicewareAppendDigitLabel => 'Adicionar Dígito Aleatório (0-9)';

  @override
  String get dicewareAppendSymbolLabel =>
      'Adicionar Símbolo Aleatório (!@#\$%)';

  @override
  String get customPasswordOptionsTitle => 'Opções de Senha Personalizada';

  @override
  String customPasswordLengthLabel(Object length) {
    return 'Comprimento: $length caracteres';
  }

  @override
  String customPasswordLengthSliderLabel(Object length) {
    return '$length caracteres';
  }

  @override
  String get customPasswordUppercaseLabel => 'Letras Maiúsculas (A-Z)';

  @override
  String get customPasswordLowercaseLabel => 'Letras Minúsculas (a-z)';

  @override
  String get customPasswordNumbersLabel => 'Números (0-9)';

  @override
  String get customPasswordSymbolsLabel => 'Símbolos (!@#\$%^&*)';

  @override
  String get customPasswordExcludeAmbiguousLabel =>
      'Excluir Ambíguos (1, l, I, 0, O)';

  @override
  String get keyfileBinarySizeTitle => 'Tamanho do Arquivo-chave Binário';

  @override
  String get keyfileImageResolutionTitle => 'Resolução da Imagem de Ruído';

  @override
  String get keyfilePresetBytes64 => '64 Bytes (Padrão VeraCrypt)';

  @override
  String get keyfilePresetBytes256 => '256 Bytes';

  @override
  String get keyfilePresetBytes2048 => '2 KB';

  @override
  String get keyfilePresetBytes64kb => '64 KB';

  @override
  String get keyfilePresetBytes1mb => '1 MB (Limite Máximo)';

  @override
  String get keyfilePresetRes64 => '64 x 64 pixels (~16 KB)';

  @override
  String get keyfilePresetRes256 => '256 x 256 pixels (~256 KB)';

  @override
  String get keyfilePresetRes512 => '512 x 512 pixels (~1 MB)';

  @override
  String get keyfileGenerateNewTooltip => 'Gerar Novo Arquivo-chave';

  @override
  String keyfileSizeLabel(Object size) {
    return 'Tamanho: $size';
  }

  @override
  String get keyfileFingerprintLabel => 'Impressão Digital SHA-256';

  @override
  String get keyfileCopyFingerprintTooltip => 'Copiar Impressão Digital';

  @override
  String get duplicateFinderNoVaultsTitle => 'Nenhum Cofre Montado';

  @override
  String get duplicateFinderNoVaultsMessage =>
      'Desbloqueie e monte pelo menos um contêiner de cofre para procurar arquivos duplicados.';

  @override
  String duplicateFinderConfirmDeleteMessage(Object count, Object size) {
    return 'Tem certeza de que deseja excluir permanentemente $count arquivo(s) duplicado(s) ($size) do(s) seu(s) cofre(s)? Esta ação não pode ser desfeita.';
  }

  @override
  String get duplicateFinderDeletePermanentlyButton =>
      'Excluir Permanentemente';

  @override
  String duplicateFinderDeleteSuccessMessage(Object count) {
    return '$count arquivo(s) duplicado(s) excluído(s) com sucesso.';
  }

  @override
  String get duplicateFinderIntroTitle =>
      'Localizador de 3 Estágios por Correspondência de Bytes';

  @override
  String get duplicateFinderIntroSubtitle =>
      'Detecta conteúdo exatamente idêntico, independentemente dos nomes de arquivo.';

  @override
  String get duplicateFinderStagesDescription =>
      '• Estágio 1: Agrupamento por Tamanho (varredura instantânea de metadados)\n• Estágio 2: Verificação Parcial de Cabeçalho (cabeçalho SHA-256 de 16 KB)\n• Estágio 3: Verificação Completa de Hash (correspondência exata de bytes SHA-256)';

  @override
  String get duplicateFinderScanningVaultFallback => 'Verificando cofre...';

  @override
  String duplicateFinderProcessingFileLabel(Object fileName) {
    return 'Processando: $fileName';
  }

  @override
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  ) {
    return 'Arquivos verificados: $scanned | Duplicados encontrados: $groups grupos ($saved)';
  }

  @override
  String duplicateFinderGroupsFoundLabel(Object count) {
    return '$count Grupos de Duplicados Encontrados';
  }

  @override
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved) {
    return '$copies cópias encontradas • Economize $saved de espaço de armazenamento';
  }

  @override
  String duplicateFinderVaultsSelectedLabel(Object count) {
    return '$count cofres selecionados';
  }

  @override
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  ) {
    return 'Grupo $groupIndex: $size ($count cópias encontradas)';
  }

  @override
  String duplicateFinderRecoverableSpaceLabel(Object size) {
    return 'Espaço recuperável: $size';
  }

  @override
  String get duplicateFinderPreviewFileTooltip => 'Visualizar Arquivo';

  @override
  String duplicateFinderPreviewFailedMessage(Object fileName) {
    return 'Não foi possível abrir a visualização do arquivo $fileName';
  }

  @override
  String duplicateFinderPreviewErrorMessage(Object error) {
    return 'Erro ao visualizar o arquivo: $error';
  }

  @override
  String duplicateFinderFilesSelectedLabel(Object count) {
    return '$count arquivos selecionados';
  }

  @override
  String duplicateFinderBytesToBeFreedLabel(Object size) {
    return '$size a serem liberados';
  }

  @override
  String duplicateFinderDeleteSelectedButton(Object count) {
    return 'Excluir Selecionados ($count)';
  }

  @override
  String get vaultBrowserSwitchVaultTooltip => 'Trocar de Cofre';

  @override
  String get vaultBrowserRootFolderLabel => 'Pasta Raiz';

  @override
  String vaultFilePickerTitle(Object vaultName) {
    return 'Selecionar Arquivos ($vaultName)';
  }

  @override
  String get vaultFilePickerEmptyMessage => 'A pasta está vazia';

  @override
  String vaultFilePickerConfirmButton(Object count) {
    return 'Selecionar $count Arquivo(s)';
  }

  @override
  String vaultFolderPickerTitle(Object vaultName) {
    return 'Selecionar Pasta ($vaultName)';
  }

  @override
  String get vaultFolderPickerEmptyMessage => 'Nenhuma subpasta aqui';

  @override
  String get vaultFolderPickerRootLabel => 'Raiz';

  @override
  String get vaultFolderPickerConfirmRootButton => 'Selecionar Pasta Raiz';

  @override
  String vaultFolderPickerConfirmNamedButton(Object folderName) {
    return 'Selecionar \"$folderName\"';
  }

  @override
  String get singleFileCryptoSelectInputTitle =>
      'Selecionar Arquivos de Entrada';

  @override
  String get singleFileCryptoFromDeviceTitle =>
      'Do Armazenamento do Dispositivo';

  @override
  String get singleFileCryptoFromDeviceSubtitle =>
      'Escolher arquivos do dispositivo usando o seletor de arquivos do sistema';

  @override
  String get singleFileCryptoFromVaultTitle => 'De Cofre Montado';

  @override
  String get singleFileCryptoFromVaultSubtitle =>
      'Escolher arquivos de um contêiner criptografado aberto';

  @override
  String get singleFileCryptoSelectDestinationTitle =>
      'Selecionar Pasta de Destino';

  @override
  String get singleFileCryptoDeviceFolderTitle =>
      'Pasta de Armazenamento do Dispositivo';

  @override
  String get singleFileCryptoDeviceFolderSubtitle =>
      'Salvar a saída em uma pasta no armazenamento do dispositivo';

  @override
  String get singleFileCryptoVaultFolderTitle => 'Pasta de Cofre Montado';

  @override
  String get singleFileCryptoVaultFolderSubtitle =>
      'Salvar a saída dentro de um contêiner criptografado aberto';

  @override
  String get toolsSectionBackupSync => 'Backup e Sincronização';

  @override
  String get toolVaultSyncTitle => 'Sincronização de Cofres';

  @override
  String get toolVaultSyncSubtitle =>
      'Comparar dois cofres e copiar o que estiver faltando ou mais recente';

  @override
  String get vaultSyncNoVaultsTitle => 'Nenhum Cofre Montado';

  @override
  String get vaultSyncNoVaultsMessage =>
      'Monte pelo menos um cofre para comparar e sincronizar seus arquivos.';

  @override
  String get vaultSyncLeftLabel => 'Esquerda';

  @override
  String get vaultSyncRightLabel => 'Direita';

  @override
  String get vaultSyncTapToSelect => 'Toque para selecionar um cofre e pasta';

  @override
  String get vaultSyncSwapTooltip => 'Trocar Esquerda e Direita';

  @override
  String get vaultSyncSameLocationWarning =>
      'Esquerda e Direita devem ser pastas diferentes.';

  @override
  String get vaultSyncIntroTitle => 'Comparar Dois Cofres';

  @override
  String get vaultSyncIntroSubtitle =>
      'Escolha um cofre Esquerda e Direita (ou duas pastas no mesmo cofre) para ver o que está faltando, modificado ou mais recente em cada lado.';

  @override
  String get vaultSyncCompareButton => 'Comparar';

  @override
  String get vaultSyncComparingLabel => 'Comparando cofres…';

  @override
  String vaultSyncCompareStatsLabel(Object dirs, Object entries) {
    return 'Pastas verificadas: $dirs | Diferenças encontradas: $entries';
  }

  @override
  String get vaultSyncCancelCompareButton => 'Cancelar';

  @override
  String get vaultSyncInSyncTitle => 'Já Sincronizado';

  @override
  String vaultSyncInSyncMessage(Object count) {
    return 'Todos os $count arquivos correspondentes são idênticos em ambos os lados.';
  }

  @override
  String get vaultSyncRecompareButton => 'Comparar Novamente';

  @override
  String vaultSyncDifferencesFoundLabel(Object count) {
    return '$count Diferenças Encontradas';
  }

  @override
  String vaultSyncInSyncCountLabel(Object count) {
    return '$count arquivos já correspondem em ambos os lados';
  }

  @override
  String vaultSyncBadgeOnlyLeft(Object count) {
    return '$count apenas na Esquerda';
  }

  @override
  String vaultSyncBadgeOnlyRight(Object count) {
    return '$count apenas na Direita';
  }

  @override
  String vaultSyncBadgeLeftNewer(Object count) {
    return '$count mais recentes na Esquerda';
  }

  @override
  String vaultSyncBadgeRightNewer(Object count) {
    return '$count mais recentes na Direita';
  }

  @override
  String vaultSyncBadgeConflicts(Object count) {
    return '$count precisam de revisão';
  }

  @override
  String get vaultSyncDirectionLabel => 'Direção da Sincronização';

  @override
  String get vaultSyncDirectionTwoWay => 'Bidirecional (recomendado)';

  @override
  String get vaultSyncDirectionTwoWaySubtitle =>
      'Copia cada arquivo para o lado que não o possui ou tem uma cópia mais antiga';

  @override
  String get vaultSyncDirectionLeftToRight =>
      'Esquerda → Direita (unidirecional)';

  @override
  String get vaultSyncDirectionLeftToRightSubtitle =>
      'Envia arquivos novos e atualizados da Esquerda para a Direita; nunca altera a Esquerda';

  @override
  String get vaultSyncDirectionRightToLeft =>
      'Direita → Esquerda (unidirecional)';

  @override
  String get vaultSyncDirectionRightToLeftSubtitle =>
      'Envia arquivos novos e atualizados da Direita para a Esquerda; nunca altera a Direita';

  @override
  String get vaultSyncSearchHint => 'Pesquisar diferenças';

  @override
  String get vaultSyncStatusOnlyLeft => 'Apenas Esquerda';

  @override
  String get vaultSyncStatusOnlyRight => 'Apenas Direita';

  @override
  String get vaultSyncStatusLeftNewer => 'Esquerda Mais Recente';

  @override
  String get vaultSyncStatusRightNewer => 'Direita Mais Recente';

  @override
  String get vaultSyncStatusConflict => 'Requer Revisão';

  @override
  String get vaultSyncStatusTypeMismatch => 'Incompatibilidade de Tipo';

  @override
  String get vaultSyncFolderOnlyLeftDetail => 'Pasta — apenas na Esquerda';

  @override
  String get vaultSyncFolderOnlyRightDetail => 'Pasta — apenas na Direita';

  @override
  String vaultSyncBothSidesDetail(
    Object leftSize,
    Object leftDate,
    Object rightSize,
    Object rightDate,
  ) {
    return 'E: $leftSize · $leftDate  →  D: $rightSize · $rightDate';
  }

  @override
  String get vaultSyncTypeMismatchTooltip =>
      'Um arquivo de um lado e uma pasta do outro — resolva manualmente no navegador de arquivos';

  @override
  String get vaultSyncChangeActionTooltip => 'Alterar ação de sincronização';

  @override
  String get vaultSyncActionCopyToRight => 'Copiar → Direita';

  @override
  String get vaultSyncActionCopyToLeft => 'Copiar → Esquerda';

  @override
  String get vaultSyncActionSkip => 'Ignorar';

  @override
  String vaultSyncChangesQueuedLabel(Object count) {
    return '$count alterações na fila';
  }

  @override
  String get vaultSyncSyncNowButton => 'Sincronizar Agora';

  @override
  String get vaultSyncConfirmTitle => 'Iniciar Sincronização?';

  @override
  String vaultSyncConfirmMessage(Object count, Object bytes) {
    return 'Isso copiará $count itens ($bytes no total) entre os dois lados. Arquivos existentes com o mesmo nome serão substituídos.';
  }

  @override
  String vaultSyncStartedMessage(Object count) {
    return 'Sincronização iniciada — $count itens na fila';
  }

  @override
  String vaultSyncPickLocationTitle(Object side) {
    return 'Selecionar Cofre e Pasta ($side)';
  }

  @override
  String get vaultSyncReadOnlyBadge => 'Somente leitura';

  @override
  String get vaultSyncReadOnlyTooltip =>
      'Este cofre está montado somente leitura — os arquivos não podem ser copiados para ele';

  @override
  String get vaultSyncSyncingButton => 'Sincronizando…';

  @override
  String get vaultSyncNotEnoughSpaceTitle => 'Espaço Insuficiente';

  @override
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  ) {
    return 'Espaço insuficiente em $side — necessário $required, apenas $free livres.';
  }

  @override
  String get removeMasterPasswordTitle => 'Remover Senha Mestra';

  @override
  String get confirmRemoveMasterPasswordMessage =>
      'Digite sua Senha Mestra atual para confirmar a remoção:';

  @override
  String get authenticateToRemoveMasterPassword =>
      'Autentique-se para remover a Senha Mestra';

  @override
  String get incorrectPassword => 'Senha incorreta';

  @override
  String get rememberPerFolderLayoutLabel => 'Lembrar Layout por Pasta';

  @override
  String get rememberPerFolderLayoutDesc =>
      'Salvar um layout de exibição separado (lista, grade, mosaico) para cada pasta';

  @override
  String get fileInfoAction => 'Info';

  @override
  String get automationSectionHeader => 'Automation';

  @override
  String get automationTileTitle => 'Automation';

  @override
  String get automationTileSubtitle =>
      'Let automation unlock, lock, import, or export this vault';

  @override
  String get automationScreenTitle => 'Automação (Tasker / MacroDroid)';

  @override
  String get automationUsbUnsupportedMessage =>
      'A automação ainda não está disponível para cofres conectados via USB.';

  @override
  String get automationThisVaultSectionHeader => 'Este cofre';

  @override
  String get automationAccessLabel => 'Acesso à automação';

  @override
  String get automationPasswordSectionHeader => 'Senha de automação';

  @override
  String get automationPasswordStoredHint =>
      'Uma senha está armazenada para chamadas UNLOCK_VAULT não supervisionadas. Salve uma nova para substituí-la, ou salve um campo vazio para apagá-la — a automação também pode fornecer uma senha diretamente na transmissão em vez de depender desta.';

  @override
  String get automationPasswordNotStoredHint =>
      'Opcional. Sem uma senha armazenada, a automação deve fornecer uma a cada transmissão UNLOCK_VAULT.';

  @override
  String get automationNewPasswordFieldLabel => 'Nova senha';

  @override
  String get automationPasswordFieldLabel => 'Senha';

  @override
  String get automationClearPasswordButton => 'Apagar senha armazenada';

  @override
  String get automationSavePasswordButton => 'Salvar senha';

  @override
  String get automationTokenSectionHeader => 'Token de API';

  @override
  String get automationTokenDescription =>
      'Compartilhado por todos os cofres com acesso à automação ativado. A automação envia este token de volta em cada transmissão; um token errado ou ausente é ignorado silenciosamente, sem gerar erro.';

  @override
  String get automationRegenerateTokenButton => 'Regenerar token';

  @override
  String get automationRegenerateTokenDialogTitle => 'Regenerar token?';

  @override
  String get automationRegenerateTokenDialogMessage =>
      'Qualquer perfil do Tasker ou macro do MacroDroid que use o token atual deixará de funcionar silenciosamente até que você o atualize com o novo.';

  @override
  String get automationRegenerateConfirmLabel => 'Regenerar';

  @override
  String get automationTokenRegeneratedMessage => 'Token regenerado.';

  @override
  String get automationRegenerateTokenFailedMessage =>
      'Não foi possível regenerar o token.';

  @override
  String get automationUpdateSettingsFailedMessage =>
      'Não foi possível atualizar as configurações de automação.';

  @override
  String get automationSavePasswordFailedMessage =>
      'Não foi possível salvar a senha de automação.';

  @override
  String get automationPasswordClearedMessage => 'Senha de automação apagada.';

  @override
  String get automationPasswordSavedMessage => 'Senha de automação salva.';

  @override
  String get automationConfigSectionHeader => 'Strings de configuração';

  @override
  String get automationConfigIntro =>
      'Toque em qualquer valor abaixo para copiá-lo. No Tasker, use uma ação \"Send Intent\"; no MacroDroid, use uma ação \"Intent\" com o Tipo de Intent definido como Broadcast — não Activity ou Service, que falha com \"unable to find explicit activity class\".';

  @override
  String get automationConfigPackageLabel => 'Nome do pacote';

  @override
  String get automationConfigClassLabel => 'Classe do receptor';

  @override
  String get automationConfigVaultUriLabel => 'URI deste cofre';

  @override
  String get automationConfigActionsSectionHeader => 'Ações de transmissão';

  @override
  String get automationActionUnlockLabel => 'Desbloquear cofre';

  @override
  String get automationActionLockLabel => 'Bloquear cofre';

  @override
  String get automationActionImportLabel => 'Importar arquivo';

  @override
  String get automationActionExportLabel => 'Exportar arquivo';

  @override
  String get automationActionWipeLabel => 'Apagar arquivo';

  @override
  String get automationDocCommentFootnote =>
      'Os extras completos e o contrato de transmissão de resultados estão documentados em VaultAutomationReceiver.kt.';

  @override
  String get automationTierOffLabel => 'Desativado';

  @override
  String get automationTierOffSubtitle =>
      'A automação não pode acessar este cofre';

  @override
  String get automationTierLifecycleLabel => 'Somente desbloquear / bloquear';

  @override
  String get automationTierLifecycleSubtitle =>
      'A automação pode desbloquear e bloquear este cofre, nada além disso';

  @override
  String get automationTierFullLabel =>
      'Desbloquear / bloquear + importação-exportação de arquivos';

  @override
  String get automationTierFullSubtitle =>
      'A automação também pode importar e exportar arquivos enquanto este cofre estiver desbloqueado';

  @override
  String get automationTutorialLinkLabel =>
      'Ler o tutorial completo passo a passo';

  @override
  String get showHiddenFilesLabel => 'Mostrar Arquivos Ocultos';

  @override
  String get showHiddenFilesDesc =>
      'Exibir arquivos ocultos (dotfiles) e pastas do sistema';

  @override
  String get dontAskAgain => 'Não perguntar novamente';

  @override
  String get deleteAfterImportLabel => 'Excluir arquivos após a importação';

  @override
  String get deleteAfterImportModeAsk => 'Perguntar sempre';

  @override
  String get deleteAfterImportModeAskSubtitle =>
      'Perguntar se deseja excluir os arquivos originais após a importação';

  @override
  String get deleteAfterImportModeKeep => 'Manter originais (não excluir)';

  @override
  String get deleteAfterImportModeKeepSubtitle =>
      'Nunca excluir os arquivos originais e não perguntar';

  @override
  String get deleteAfterImportModeDelete => 'Excluir originais automaticamente';

  @override
  String get deleteAfterImportModeDeleteSubtitle =>
      'Excluir automaticamente os arquivos originais do dispositivo após a importação';

  @override
  String get wizardBackButton => 'Back';

  @override
  String get wizardNextButton => 'Next';

  @override
  String get wizardStepTypeTitle => 'Type';

  @override
  String get wizardStepBasicInfoTitle => 'Basic Info';

  @override
  String get wizardStepAdvancedTitle => 'Advanced';

  @override
  String get wizardStepReviewTitle => 'Review';

  @override
  String get wizardCreateTypePrompt => 'What would you like to create?';

  @override
  String get wizardChooseFormatPrompt => 'Choose a container format';

  @override
  String get wizardEncryptionDetailsRowTitle => 'Encryption Details';

  @override
  String get wizardHiddenVolumeRowSubtitleConfigured =>
      'Configured — tap to review';

  @override
  String get wizardHiddenVolumeRowSubtitleNeedsSetup => 'Tap to set up';

  @override
  String get wizardSummaryTitle => 'Summary';

  @override
  String get wizardSummaryPasswordLabel => 'Password';

  @override
  String get wizardPasswordSetValue => 'Set';

  @override
  String get wizardPasswordNotSetValue => 'Not set (using keyfiles)';

  @override
  String get wizardSummaryKeyfilesLabel => 'Keyfiles';

  @override
  String get wizardSummaryPimDefaultValue => 'Default';

  @override
  String get wizardSummaryPimLabel => 'PIM';

  @override
  String get wizardSummaryDriveLabel => 'USB Drive';

  @override
  String get sectionKeyStorageIntegration =>
      'Armazenamento de Chaves e Acesso ao Sistema';

  @override
  String get sectionMaskMode => 'Modo Disfarce';

  @override
  String get advancedOptionsTitle => 'Advanced Options';

  @override
  String get audioTrackTitle => 'Audio Track';

  @override
  String get noAudioTracksAvailable => 'No audio tracks available';

  @override
  String trackNumberLabel(int number) {
    return 'Track $number';
  }

  @override
  String subtitleTrackNumberLabel(int number) {
    return 'Subtitle $number';
  }

  @override
  String get offLabel => 'Off';

  @override
  String get externalSubtitlesLabel => 'External Subtitles (.srt/.vtt)';

  @override
  String get externalLabel => 'External';

  @override
  String get subtitleSizeLabel => 'Size';

  @override
  String get subtitleSizeSmall => 'S';

  @override
  String get subtitleSizeMedium => 'M';

  @override
  String get subtitleSizeLarge => 'L';

  @override
  String get subtitleSizeExtraLarge => 'XL';

  @override
  String get subtitlePositionLabel => 'Position';

  @override
  String get subtitlePositionBottom => 'Bottom';

  @override
  String get subtitlePositionLower => 'Lower';

  @override
  String get subtitlePositionCenter => 'Center';

  @override
  String get subtitlePositionTop => 'Top';

  @override
  String get editImageAction => 'Edit Image';

  @override
  String get imageEditorUnsupportedFormatMessage =>
      'This image format isn\'t supported for editing.';

  @override
  String get cropToolLabel => 'Crop';

  @override
  String get drawToolLabel => 'Draw';

  @override
  String get textToolLabel => 'Text';

  @override
  String get redactToolLabel => 'Redact';

  @override
  String get rotateLeftTooltip => 'Rotate left';

  @override
  String get rotateRightTooltip => 'Rotate right';

  @override
  String get cropAspectFreeLabel => 'Free';

  @override
  String get cropAspectSquareLabel => 'Square';

  @override
  String get cropAspectOriginalLabel => 'Original';

  @override
  String get applyCropTooltip => 'Apply crop';

  @override
  String get annotationColorTooltip => 'Color';

  @override
  String get annotationStrokeWidthTooltip => 'Stroke width';

  @override
  String get clearAnnotationsTooltip => 'Clear all annotations';

  @override
  String get resetImageTooltip => 'Reset to original';

  @override
  String get resetImageConfirmTitle => 'Reset image?';

  @override
  String get resetImageConfirmMessage =>
      'This discards every crop and drawing change made in this session.';

  @override
  String get addTextAnnotationTitle => 'Add text';

  @override
  String get addTextAnnotationHint => 'Type something…';

  @override
  String get textToolHint => 'Tap the image to add text';

  @override
  String get saveImageSheetTitle => 'Save changes';

  @override
  String get saveAsNewFileOption => 'Save as new file';

  @override
  String get saveAsNewFileDescription => 'Keeps the original untouched';

  @override
  String get overwriteOriginalOption => 'Overwrite original';

  @override
  String get overwriteOriginalDescription => 'Replaces the original file';

  @override
  String get newFileNameLabel => 'File name';

  @override
  String get imageEditorPngNoteMessage => 'Edited images are saved as PNG.';

  @override
  String get imageSavedMessage => 'Image saved';

  @override
  String imageSaveFailedMessage(String error) {
    return 'Couldn\'t save image: $error';
  }

  @override
  String get advancedRenameButton => 'Advanced';

  @override
  String get advancedRenameBatchTitle => 'Batch Rename';

  @override
  String get advancedRenameRulesTab => 'Rules';

  @override
  String advancedRenamePreviewTab(int count) {
    return 'Preview ($count)';
  }

  @override
  String get advancedRenameSearchReplaceTitle => 'Search & Replace';

  @override
  String get advancedRenameFindTextLabel => 'Find text';

  @override
  String get advancedRenameFindTextHint => 'Enter text or pattern to match...';

  @override
  String get advancedRenameReplaceWithLabel => 'Replace with';

  @override
  String get advancedRenameReplaceWithHint => 'New text or variables...';

  @override
  String get advancedRenameInsertVariableTooltip =>
      'Insert dynamic variable token';

  @override
  String get advancedRenameDateTimeTokens => 'DATE & TIME TOKENS';

  @override
  String advancedRenameStandardDate(String token) {
    return 'Standard Date ($token)';
  }

  @override
  String advancedRenameYearFourDigit(String token) {
    return 'Year 4-digit ($token)';
  }

  @override
  String advancedRenameMonth(String token) {
    return 'Month ($token)';
  }

  @override
  String advancedRenameDayOfMonth(String token) {
    return 'Day of month ($token)';
  }

  @override
  String advancedRenameTime(String token) {
    return 'Time ($token)';
  }

  @override
  String get advancedRenameDynamicIdentifiers => 'DYNAMIC IDENTIFIERS';

  @override
  String advancedRenameUniqueUuid(String token) {
    return 'Unique UUID v4 ($token)';
  }

  @override
  String get advancedRenameRandomAlphanumeric =>
      'Random Alphanumeric (8 chars)';

  @override
  String get advancedRenameRandomDigits => 'Random Digits (6 digits)';

  @override
  String get advancedRenameEmbeddedCounter => 'EMBEDDED COUNTER';

  @override
  String advancedRenamePaddedCounter(String token) {
    return 'Padded Counter ($token)';
  }

  @override
  String get advancedRenameRegex => 'Regex';

  @override
  String get advancedRenameMatchCase => 'Match Case';

  @override
  String get advancedRenameAllOccurrences => 'All Occurrences';

  @override
  String get advancedRenameScopeFormatting => 'Scope & Formatting';

  @override
  String get advancedRenameApplyChangesTo => 'Apply changes to';

  @override
  String get advancedRenameFilename => 'Filename';

  @override
  String get advancedRenameExtension => 'Extension';

  @override
  String get advancedRenameBoth => 'Both';

  @override
  String get advancedRenameCaseTransformation => 'Case transformation';

  @override
  String get advancedRenameNoChange => 'No change';

  @override
  String get advancedRenameLowercase => 'lowercase';

  @override
  String get advancedRenameUppercase => 'UPPERCASE';

  @override
  String get advancedRenameTitleCase => 'Title Case';

  @override
  String get advancedRenameCapitalize => 'Capitalize';

  @override
  String get advancedRenameSequentialCounter => 'Sequential Counter';

  @override
  String get advancedRenameCounterDescription =>
      'Append or prepend ordered numbers';

  @override
  String get advancedRenameSuffix => 'Suffix (end)';

  @override
  String get advancedRenamePrefix => 'Prefix (start)';

  @override
  String get advancedRenameStartAt => 'Start at';

  @override
  String get advancedRenameDigits => 'Digits';

  @override
  String get advancedRenameDigitsHint => 'e.g. 2 (01)';

  @override
  String get advancedRenameSeparator => 'Separator';

  @override
  String get advancedRenameSeparatorHint => '_ or -';

  @override
  String get advancedRenameLivePreview => 'Live Preview';

  @override
  String get advancedRenameDeselect => 'Deselect';

  @override
  String get advancedRenameSelectAll => 'Select All';

  @override
  String get advancedRenameNoFilesSelected => 'No files selected';

  @override
  String get advancedRenameNameConflictDetected => 'Name conflict detected';

  @override
  String get advancedRenameCheckPreviewToFix => 'Check the Preview tab to fix';

  @override
  String get advancedRenameReadyToRename => 'Ready to rename';

  @override
  String get advancedRenameErrorsDetected => 'Errors Detected';

  @override
  String advancedRenameApply(int count) {
    return 'Apply ($count)';
  }

  @override
  String get advancedRenameNameCollisionWithinBatch =>
      'Name collision within batch.';

  @override
  String get advancedRenameCollidesWithUnselectedFile =>
      'Collides with unselected file.';

  @override
  String advancedRenameReadyCount(int valid, int total) {
    return '$valid ready to rename ($total total)';
  }

  @override
  String advancedRenameReadyOfTotal(int valid, int total) {
    return '$valid of $total ready';
  }

  @override
  String advancedRenameRenamedItems(int succeeded, int failed) {
    return 'Renamed $succeeded items ($failed failed).';
  }

  @override
  String advancedRenameSuccessfullyRenamed(int count) {
    return 'Successfully renamed $count items.';
  }

  @override
  String get advancedRenameMonthsFull =>
      'January|February|March|April|May|June|July|August|September|October|November|December';

  @override
  String get advancedRenameMonthsAbbr =>
      'Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec';

  @override
  String get advancedRenameDaysFull =>
      'Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday';

  @override
  String get advancedRenameDaysAbbr => 'Mon|Tue|Wed|Thu|Fri|Sat|Sun';

  @override
  String get advancedRenameResolveConflicts =>
      'Resolve name conflicts before applying';

  @override
  String advancedRenameChangedCount(int changed, int total) {
    return '$changed of $total';
  }

  @override
  String get automationKeyfilesPimSectionHeader => 'Keyfiles & PIM';

  @override
  String get automationKeyfilesPimDescription =>
      'Stored alongside the automation password above and used the same way for UNLOCK_VAULT -- for a VeraCrypt/LUKS vault normally unlocked with a keyfile and/or a non-default PIM instead of just a password.';

  @override
  String get automationSavePimButton => 'Save PIM';

  @override
  String get automationCameraSectionHeader => 'Camera automation';

  @override
  String get automationCameraDescription =>
      'Lets automation trigger TAKE_PHOTO / START_RECORDING / STOP_RECORDING for this vault. Off by default even at Full access -- unlike file import/export, a photo needs no on-screen indication at all, so this is a separate, explicit opt-in.';

  @override
  String get automationAllowCameraCapture => 'Allow camera capture';

  @override
  String get automationPimSavedMessage => 'PIM saved';

  @override
  String get automationActionImportFolderLabel => 'Import folder';

  @override
  String get automationActionExportFolderLabel => 'Export folder';

  @override
  String get automationActionTakePhotoLabel => 'Take photo';

  @override
  String get automationActionStartRecordingLabel => 'Start recording';

  @override
  String get automationActionStopRecordingLabel => 'Stop recording';

  @override
  String get filePropertiesSectionHeader => 'FILE PROPERTIES';

  @override
  String get fullPathLabel => 'Full Path';

  @override
  String get sizeLabel => 'Size';

  @override
  String get modifiedLabel => 'Modified';

  @override
  String get vaultLabel => 'Vault';

  @override
  String get mediaDimensionsSectionHeader => 'MEDIA & DIMENSIONS';

  @override
  String get resolutionLabel => 'Resolution';

  @override
  String get aspectRatioLabel => 'Aspect Ratio';

  @override
  String get formatLabel => 'Format';

  @override
  String get exifCameraDataSectionHeader => 'EXIF & CAMERA DATA';

  @override
  String get cameraLabel => 'Camera';

  @override
  String get lensLabel => 'Lens';

  @override
  String get dateTakenLabel => 'Date Taken';

  @override
  String get shutterSpeedLabel => 'Shutter Speed';

  @override
  String get apertureLabel => 'Aperture';

  @override
  String get isoLabel => 'ISO';

  @override
  String get focalLengthLabel => 'Focal Length';

  @override
  String get flashLabel => 'Flash';

  @override
  String get softwareLabel => 'Software';

  @override
  String get gpsLocationLabel => 'GPS Location';

  @override
  String get integrityChecksumSectionHeader => 'INTEGRITY & CHECKSUM';

  @override
  String get computingHashMessage => 'Computing hash…';

  @override
  String get tapCalculateToVerifyMessage => 'Tap Calculate to verify';

  @override
  String get calculateButton => 'Calculate';

  @override
  String get copyDiagnosticsButton => 'Copy Diagnostics';

  @override
  String get closeButton => 'Close';

  @override
  String get hwAcceleratedBadge => 'HW ACCELERATED';

  @override
  String get swDecoderBadge => 'SW DECODER';

  @override
  String get videoDecoderHardwareSection => 'VIDEO DECODER & HARDWARE';

  @override
  String get decoderNameLabel => 'Decoder Name';

  @override
  String get accelerationLabel => 'Acceleration';

  @override
  String get hardwareGpuDirect => 'Hardware (GPU Direct)';

  @override
  String get softwareCpuFallback => 'Software (CPU Fallback)';

  @override
  String get unknownValue => 'Unknown';

  @override
  String get framerateLabel => 'Framerate';

  @override
  String get variableOrUnknown => 'Variable / Unknown';

  @override
  String get videoCodecLabel => 'Video Codec';

  @override
  String get autoDetected => 'Auto-detected';

  @override
  String get colorFormatLabel => 'Color Format';

  @override
  String get initLatencyLabel => 'Init Latency';

  @override
  String get audioEngineSection => 'AUDIO ENGINE';

  @override
  String get audioDecoderLabel => 'Audio Decoder';

  @override
  String get audioCodecLabel => 'Audio Codec';

  @override
  String get pipelineHealthSection => 'PIPELINE & HEALTH';

  @override
  String get playbackStateLabel => 'Playback State';

  @override
  String get decryptedBufferLabel => 'Decrypted Buffer';

  @override
  String secondsCached(String seconds) {
    return '$seconds s cached';
  }

  @override
  String get droppedFramesLabel => 'Dropped Frames';

  @override
  String nFrames(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frames',
      one: '1 frame',
    );
    return '$_temp0';
  }

  @override
  String get sourceStorageLabel => 'Source Storage';

  @override
  String directJniStreamSource(int volId) {
    return 'Direct C++ JNI Stream (volId=$volId)';
  }
}
