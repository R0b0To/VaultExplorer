// tool/update_l10n_keys.dart
import 'dart:convert';
import 'dart:io';

/// Add your English keys and ARB metadata here.
/// Keys starting with '@' are metadata descriptions and are only added to app_en.arb.
///
/// Example:
///   'myKey': 'My English Value',
///   '@myKey': {
///     'description': 'Description for translators',
///   },
const Map<String, dynamic> enMetadataAndValues = {
  // 'exampleKey': 'Example value',
  // '@exampleKey': {
  //   'description': 'Context or description for this key',
  // },
  "cryptomatorBackupKeyFilesTitle": "Back up key files when unlocking",
  "@cryptomatorBackupKeyFilesTitle": {
    'description': "Title of the switch in a Cryptomator vault's settings that controls whether key-file backups are written when the vault is unlocked",
  },
  "cryptomatorBackupKeyFilesSubtitle": "Keeps a copy of masterkey.cryptomator and vault.cryptomator next to the originals, like Cryptomator on desktop. Applies from the next unlock. Read-only sessions never write.",
  "@cryptomatorBackupKeyFilesSubtitle": {
    'description': "Subtitle of the Cryptomator key-file backup switch: what is copied, that it applies from the next unlock, and that read-only sessions never write",
  },
  "cryptomatorUpgradeTitle": "Upgrade vault format",
  "@cryptomatorUpgradeTitle": {
    'description': "Title of the settings row (and screen) that upgrades a Cryptomator vault from the older format 7 to format 8",
  },
  "cryptomatorUpgradeSubtitle": "This vault uses the older format 7.",
  "@cryptomatorUpgradeSubtitle": {
    'description': "Subtitle of the upgrade row for a vault that is still Cryptomator format 7",
  },
  "cryptomatorUpgradeLockFirst": "Lock the vault to upgrade it",
  "@cryptomatorUpgradeLockFirst": {
    'description': "Subtitle of the disabled upgrade row while the vault is unlocked",
  },
  "cryptomatorUpgradeWarning": "Upgrading changes this vault to format 8. It cannot be undone, and Cryptomator versions older than 1.6 will no longer be able to open the vault afterwards.\n\nA copy of the current key file is kept as masterkey.cryptomator.<id>.bkup. If another app syncs this vault, let it finish syncing first.",
  "@cryptomatorUpgradeWarning": {
    'description': "Warning on the Cryptomator format upgrade screen: what changes, that it is one-way, that older Cryptomator cannot open the vault, where the key-file copy goes, and that sync must finish first",
  },
  "cryptomatorUpgradeConfirm": "I understand this can't be undone",
  "@cryptomatorUpgradeConfirm": {
    'description': "Checkbox on the Cryptomator upgrade screen the user must tick before the upgrade button works",
  },
  "cryptomatorUpgradeAction": "Upgrade",
  "@cryptomatorUpgradeAction": {
    'description': "Button that runs the Cryptomator vault format upgrade",
  },
  "cryptomatorUpgradedMessage": "Vault upgraded to format 8",
  "@cryptomatorUpgradedMessage": {
    'description': "Snackbar shown after a Cryptomator vault was upgraded to format 8",
  },
  "cryptomatorUpgradeUnlockedError": "Lock the vault first",
  "@cryptomatorUpgradeUnlockedError": {
    'description': "Error shown when the format upgrade is refused because the vault is unlocked",
  },
  "cryptomatorConfigMissingWarning": "vault.cryptomator is missing. If another app syncs this vault, wait for it to finish, then try again. Do not upgrade.",
  "@cryptomatorConfigMissingWarning": {
    'description': "Warning row for a Cryptomator vault whose vault.cryptomator is missing (usually not synced yet); the user must wait and must not upgrade",
  },
  "cryptomatorUpgradeFailedMessage": "Could not upgrade the vault",
  "@cryptomatorUpgradeFailedMessage": {
    'description': "Generic error when the Cryptomator format upgrade fails without a more specific message",
  },
};

/// Add translations for each supported language here.
/// If a translation for a key is omitted, it falls back to the English value.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    "cryptomatorBackupKeyFilesTitle": "نسخ احتياطي لملفات المفاتيح عند فتح القفل",
    "cryptomatorBackupKeyFilesSubtitle": "يحتفظ بنسخة من masterkey.cryptomator وvault.cryptomator بجوار الملفات الأصلية، كما يفعل Cryptomator على سطح المكتب. يسري من عملية الفتح التالية. جلسات القراءة فقط لا تكتب أي شيء أبدًا.",
    "cryptomatorUpgradeTitle": "ترقية تنسيق الخزنة",
    "cryptomatorUpgradeSubtitle": "تستخدم هذه الخزنة التنسيق 7 الأقدم.",
    "cryptomatorUpgradeLockFirst": "اقفل الخزنة لترقيتها",
    "cryptomatorUpgradeWarning": "تؤدي الترقية إلى تحويل هذه الخزنة إلى التنسيق 8. لا يمكن التراجع عنها، ولن تتمكن إصدارات Cryptomator الأقدم من 1.6 من فتح الخزنة بعد ذلك.\n\nيُحتفظ بنسخة من ملف المفتاح الحالي باسم masterkey.cryptomator.<id>.bkup. إذا كان تطبيق آخر يزامن هذه الخزنة، فدعه ينهي المزامنة أولًا.",
    "cryptomatorUpgradeConfirm": "أفهم أنه لا يمكن التراجع عن هذا",
    "cryptomatorUpgradeAction": "ترقية",
    "cryptomatorUpgradedMessage": "تمت ترقية الخزنة إلى التنسيق 8",
    "cryptomatorUpgradeUnlockedError": "اقفل الخزنة أولًا",
    "cryptomatorConfigMissingWarning": "الملف vault.cryptomator مفقود. إذا كان تطبيق آخر يزامن هذه الخزنة، فانتظر حتى تنتهي المزامنة ثم حاول مرة أخرى. لا تقم بالترقية.",
    "cryptomatorUpgradeFailedMessage": "تعذرت ترقية الخزنة",
  },
  'de': {
    "cryptomatorBackupKeyFilesTitle": "Schlüsseldateien beim Entsperren sichern",
    "cryptomatorBackupKeyFilesSubtitle": "Legt neben den Originalen eine Kopie von masterkey.cryptomator und vault.cryptomator ab, wie Cryptomator am Computer. Gilt ab dem nächsten Entsperren. Schreibgeschützte Sitzungen schreiben nie.",
    "cryptomatorUpgradeTitle": "Tresorformat aktualisieren",
    "cryptomatorUpgradeSubtitle": "Dieser Tresor verwendet das ältere Format 7.",
    "cryptomatorUpgradeLockFirst": "Tresor zum Aktualisieren sperren",
    "cryptomatorUpgradeWarning": "Beim Aktualisieren wird dieser Tresor auf Format 8 umgestellt. Das lässt sich nicht rückgängig machen, und Cryptomator-Versionen vor 1.6 können den Tresor danach nicht mehr öffnen.\n\nEine Kopie der aktuellen Schlüsseldatei bleibt als masterkey.cryptomator.<id>.bkup erhalten. Wenn eine andere App diesen Tresor synchronisiert, lassen Sie die Synchronisierung zuerst abschließen.",
    "cryptomatorUpgradeConfirm": "Mir ist klar, dass sich das nicht rückgängig machen lässt",
    "cryptomatorUpgradeAction": "Aktualisieren",
    "cryptomatorUpgradedMessage": "Tresor auf Format 8 aktualisiert",
    "cryptomatorUpgradeUnlockedError": "Sperren Sie zuerst den Tresor",
    "cryptomatorConfigMissingWarning": "vault.cryptomator fehlt. Wenn eine andere App diesen Tresor synchronisiert, warten Sie, bis sie fertig ist, und versuchen Sie es dann erneut. Nicht aktualisieren.",
    "cryptomatorUpgradeFailedMessage": "Tresor konnte nicht aktualisiert werden",
  },
  'es': {
    "cryptomatorBackupKeyFilesTitle": "Copia de seguridad de los archivos de clave al desbloquear",
    "cryptomatorBackupKeyFilesSubtitle": "Guarda una copia de masterkey.cryptomator y vault.cryptomator junto a los originales, como Cryptomator en el ordenador. Se aplica desde el próximo desbloqueo. Las sesiones de solo lectura nunca escriben.",
    "cryptomatorUpgradeTitle": "Actualizar el formato de la bóveda",
    "cryptomatorUpgradeSubtitle": "Esta bóveda usa el formato 7, más antiguo.",
    "cryptomatorUpgradeLockFirst": "Bloquea la bóveda para actualizarla",
    "cryptomatorUpgradeWarning": "Al actualizar, esta bóveda pasa al formato 8. No se puede deshacer, y las versiones de Cryptomator anteriores a la 1.6 ya no podrán abrir la bóveda.\n\nSe conserva una copia del archivo de clave actual como masterkey.cryptomator.<id>.bkup. Si otra aplicación sincroniza esta bóveda, deja que termine de sincronizar antes.",
    "cryptomatorUpgradeConfirm": "Entiendo que no se puede deshacer",
    "cryptomatorUpgradeAction": "Actualizar",
    "cryptomatorUpgradedMessage": "Bóveda actualizada al formato 8",
    "cryptomatorUpgradeUnlockedError": "Bloquea primero la bóveda",
    "cryptomatorConfigMissingWarning": "Falta vault.cryptomator. Si otra aplicación sincroniza esta bóveda, espera a que termine y vuelve a intentarlo. No actualices.",
    "cryptomatorUpgradeFailedMessage": "No se pudo actualizar la bóveda",
  },
  'fr': {
    "cryptomatorBackupKeyFilesTitle": "Sauvegarder les fichiers de clé au déverrouillage",
    "cryptomatorBackupKeyFilesSubtitle": "Conserve une copie de masterkey.cryptomator et de vault.cryptomator à côté des originaux, comme Cryptomator sur ordinateur. S’applique dès le prochain déverrouillage. Les sessions en lecture seule n’écrivent jamais.",
    "cryptomatorUpgradeTitle": "Mettre à niveau le format du coffre",
    "cryptomatorUpgradeSubtitle": "Ce coffre utilise l’ancien format 7.",
    "cryptomatorUpgradeLockFirst": "Verrouillez le coffre pour le mettre à niveau",
    "cryptomatorUpgradeWarning": "La mise à niveau convertit ce coffre au format 8. Elle est irréversible, et les versions de Cryptomator antérieures à la 1.6 ne pourront plus ouvrir le coffre ensuite.\n\nUne copie du fichier de clé actuel est conservée sous le nom masterkey.cryptomator.<id>.bkup. Si une autre application synchronise ce coffre, laissez-la d’abord terminer la synchronisation.",
    "cryptomatorUpgradeConfirm": "Je comprends que c’est irréversible",
    "cryptomatorUpgradeAction": "Mettre à niveau",
    "cryptomatorUpgradedMessage": "Coffre mis à niveau au format 8",
    "cryptomatorUpgradeUnlockedError": "Verrouillez d’abord le coffre",
    "cryptomatorConfigMissingWarning": "vault.cryptomator est manquant. Si une autre application synchronise ce coffre, attendez la fin de la synchronisation, puis réessayez. Ne lancez pas la mise à niveau.",
    "cryptomatorUpgradeFailedMessage": "Impossible de mettre à niveau le coffre",
  },
  'it': {
    "cryptomatorBackupKeyFilesTitle": "Esegui il backup dei file chiave allo sblocco",
    "cryptomatorBackupKeyFilesSubtitle": "Conserva una copia di masterkey.cryptomator e vault.cryptomator accanto agli originali, come Cryptomator sul computer. Vale dal prossimo sblocco. Le sessioni in sola lettura non scrivono mai.",
    "cryptomatorUpgradeTitle": "Aggiorna il formato della cassaforte",
    "cryptomatorUpgradeSubtitle": "Questa cassaforte usa il vecchio formato 7.",
    "cryptomatorUpgradeLockFirst": "Blocca la cassaforte per aggiornarla",
    "cryptomatorUpgradeWarning": "L’aggiornamento converte questa cassaforte al formato 8. Non si può annullare e le versioni di Cryptomator precedenti alla 1.6 non potranno più aprirla.\n\nUna copia del file chiave attuale viene conservata come masterkey.cryptomator.<id>.bkup. Se un’altra app sincronizza questa cassaforte, lascia prima che finisca la sincronizzazione.",
    "cryptomatorUpgradeConfirm": "Capisco che non si può annullare",
    "cryptomatorUpgradeAction": "Aggiorna",
    "cryptomatorUpgradedMessage": "Cassaforte aggiornata al formato 8",
    "cryptomatorUpgradeUnlockedError": "Blocca prima la cassaforte",
    "cryptomatorConfigMissingWarning": "Manca vault.cryptomator. Se un’altra app sincronizza questa cassaforte, attendi che finisca e riprova. Non aggiornare.",
    "cryptomatorUpgradeFailedMessage": "Impossibile aggiornare la cassaforte",
  },
  'ja': {
    "cryptomatorBackupKeyFilesTitle": "ロック解除時にキーファイルをバックアップ",
    "cryptomatorBackupKeyFilesSubtitle": "デスクトップ版 Cryptomator と同様に、masterkey.cryptomator と vault.cryptomator のコピーを元のファイルの隣に保存します。次回のロック解除から有効です。読み取り専用のセッションでは書き込みません。",
    "cryptomatorUpgradeTitle": "保管庫の形式をアップグレード",
    "cryptomatorUpgradeSubtitle": "この保管庫は古い形式 7 を使用しています。",
    "cryptomatorUpgradeLockFirst": "アップグレードするには保管庫をロックしてください",
    "cryptomatorUpgradeWarning": "アップグレードすると、この保管庫は形式 8 に変更されます。元に戻すことはできず、その後は 1.6 より前のバージョンの Cryptomator ではこの保管庫を開けなくなります。\n\n現在のキーファイルのコピーは masterkey.cryptomator.<id>.bkup として保持されます。別のアプリがこの保管庫を同期している場合は、先に同期が完了するまで待ってください。",
    "cryptomatorUpgradeConfirm": "元に戻せないことを理解しました",
    "cryptomatorUpgradeAction": "アップグレード",
    "cryptomatorUpgradedMessage": "保管庫を形式 8 にアップグレードしました",
    "cryptomatorUpgradeUnlockedError": "先に保管庫をロックしてください",
    "cryptomatorConfigMissingWarning": "vault.cryptomator が見つかりません。別のアプリがこの保管庫を同期している場合は、同期が完了するまで待ってから、もう一度お試しください。アップグレードしないでください。",
    "cryptomatorUpgradeFailedMessage": "保管庫をアップグレードできませんでした",
  },
  'ko': {
    "cryptomatorBackupKeyFilesTitle": "잠금 해제 시 키 파일 백업",
    "cryptomatorBackupKeyFilesSubtitle": "데스크톱 Cryptomator처럼 masterkey.cryptomator와 vault.cryptomator의 사본을 원본 옆에 보관합니다. 다음 잠금 해제부터 적용됩니다. 읽기 전용 세션에서는 아무것도 쓰지 않습니다.",
    "cryptomatorUpgradeTitle": "보관함 형식 업그레이드",
    "cryptomatorUpgradeSubtitle": "이 보관함은 이전 형식인 7을 사용합니다.",
    "cryptomatorUpgradeLockFirst": "업그레이드하려면 보관함을 잠그세요",
    "cryptomatorUpgradeWarning": "업그레이드하면 이 보관함이 형식 8로 변경됩니다. 되돌릴 수 없으며, 이후에는 1.6 이전 버전의 Cryptomator로 이 보관함을 열 수 없습니다.\n\n현재 키 파일의 사본은 masterkey.cryptomator.<id>.bkup로 보관됩니다. 다른 앱이 이 보관함을 동기화하고 있다면 먼저 동기화가 끝날 때까지 기다리세요.",
    "cryptomatorUpgradeConfirm": "되돌릴 수 없음을 이해합니다",
    "cryptomatorUpgradeAction": "업그레이드",
    "cryptomatorUpgradedMessage": "보관함을 형식 8로 업그레이드했습니다",
    "cryptomatorUpgradeUnlockedError": "먼저 보관함을 잠그세요",
    "cryptomatorConfigMissingWarning": "vault.cryptomator가 없습니다. 다른 앱이 이 보관함을 동기화하고 있다면 동기화가 끝날 때까지 기다린 후 다시 시도하세요. 업그레이드하지 마세요.",
    "cryptomatorUpgradeFailedMessage": "보관함을 업그레이드하지 못했습니다",
  },
  'pt': {
    "cryptomatorBackupKeyFilesTitle": "Fazer backup dos arquivos de chave ao desbloquear",
    "cryptomatorBackupKeyFilesSubtitle": "Mantém uma cópia de masterkey.cryptomator e vault.cryptomator ao lado dos originais, como o Cryptomator no computador. Vale a partir do próximo desbloqueio. Sessões somente leitura nunca gravam.",
    "cryptomatorUpgradeTitle": "Atualizar o formato do cofre",
    "cryptomatorUpgradeSubtitle": "Este cofre usa o formato 7, mais antigo.",
    "cryptomatorUpgradeLockFirst": "Bloqueie o cofre para atualizá-lo",
    "cryptomatorUpgradeWarning": "A atualização converte este cofre para o formato 8. Não é possível desfazê-la, e versões do Cryptomator anteriores à 1.6 não conseguirão mais abrir o cofre.\n\nUma cópia do arquivo de chave atual é mantida como masterkey.cryptomator.<id>.bkup. Se outro aplicativo sincroniza este cofre, deixe-o terminar a sincronização antes.",
    "cryptomatorUpgradeConfirm": "Entendo que não é possível desfazer",
    "cryptomatorUpgradeAction": "Atualizar",
    "cryptomatorUpgradedMessage": "Cofre atualizado para o formato 8",
    "cryptomatorUpgradeUnlockedError": "Bloqueie o cofre primeiro",
    "cryptomatorConfigMissingWarning": "vault.cryptomator está ausente. Se outro aplicativo sincroniza este cofre, aguarde o término e tente novamente. Não atualize.",
    "cryptomatorUpgradeFailedMessage": "Não foi possível atualizar o cofre",
  },
  'uk': {
    "cryptomatorBackupKeyFilesTitle": "Резервне копіювання файлів ключів під час розблокування",
    "cryptomatorBackupKeyFilesSubtitle": "Зберігає копію masterkey.cryptomator і vault.cryptomator поруч з оригіналами, як Cryptomator на комп’ютері. Діє з наступного розблокування. Сеанси лише для читання нічого не записують.",
    "cryptomatorUpgradeTitle": "Оновити формат сховища",
    "cryptomatorUpgradeSubtitle": "Це сховище використовує старіший формат 7.",
    "cryptomatorUpgradeLockFirst": "Заблокуйте сховище, щоб оновити його",
    "cryptomatorUpgradeWarning": "Оновлення змінює формат цього сховища на 8. Це не можна скасувати, і версії Cryptomator, старіші за 1.6, більше не зможуть відкрити це сховище.\n\nКопія поточного файлу ключа зберігається як masterkey.cryptomator.<id>.bkup. Якщо інший застосунок синхронізує це сховище, спершу дочекайтеся завершення синхронізації.",
    "cryptomatorUpgradeConfirm": "Я розумію, що це не можна скасувати",
    "cryptomatorUpgradeAction": "Оновити",
    "cryptomatorUpgradedMessage": "Сховище оновлено до формату 8",
    "cryptomatorUpgradeUnlockedError": "Спершу заблокуйте сховище",
    "cryptomatorConfigMissingWarning": "Файл vault.cryptomator відсутній. Якщо інший застосунок синхронізує це сховище, дочекайтеся завершення й спробуйте ще раз. Не оновлюйте.",
    "cryptomatorUpgradeFailedMessage": "Не вдалося оновити сховище",
  },
  'zh': {
    "cryptomatorBackupKeyFilesTitle": "解锁时备份密钥文件",
    "cryptomatorBackupKeyFilesSubtitle": "与桌面版 Cryptomator 一样，在原文件旁保留 masterkey.cryptomator 和 vault.cryptomator 的副本。从下次解锁起生效。只读会话不会写入。",
    "cryptomatorUpgradeTitle": "升级保险库格式",
    "cryptomatorUpgradeSubtitle": "此保险库使用较旧的格式 7。",
    "cryptomatorUpgradeLockFirst": "请先锁定保险库再升级",
    "cryptomatorUpgradeWarning": "升级会将此保险库更改为格式 8。此操作无法撤销，之后低于 1.6 的 Cryptomator 版本将无法再打开该保险库。\n\n当前密钥文件的副本会以 masterkey.cryptomator.<id>.bkup 的名称保留。如果有其他应用正在同步此保险库，请先等待同步完成。",
    "cryptomatorUpgradeConfirm": "我了解此操作无法撤销",
    "cryptomatorUpgradeAction": "升级",
    "cryptomatorUpgradedMessage": "保险库已升级到格式 8",
    "cryptomatorUpgradeUnlockedError": "请先锁定保险库",
    "cryptomatorConfigMissingWarning": "缺少 vault.cryptomator。如果有其他应用正在同步此保险库，请等待同步完成后再试。请勿升级。",
    "cryptomatorUpgradeFailedMessage": "无法升级保险库",
  },
};

void main() async {
  if (enMetadataAndValues.isEmpty) {
    print('No keys defined in "enMetadataAndValues". Nothing to update.');
    return;
  }

  final l10nDir = _findL10nDirectory();
  if (l10nDir == null) {
    stderr.writeln('Error: Could not find directory containing app_en.arb.');
    exit(1);
  }

  print('Targeting l10n directory: ${l10nDir.path}');

  // 1. Update primary language: app_en.arb
  final enFile = File('${l10nDir.path}/app_en.arb');
  if (enFile.existsSync()) {
    _updateArb(enFile, enMetadataAndValues);
    print('Updated: app_en.arb');
  } else {
    stderr.writeln('Error: Main language file app_en.arb not found in ${l10nDir.path}');
    exit(1);
  }

  // 2. Update secondary languages configured in localizedValues
  for (final lang in localizedValues.keys) {
    final file = File('${l10nDir.path}/app_$lang.arb');
    if (!file.existsSync()) {
      print('Notice: app_$lang.arb not found at ${file.path}, skipping.');
      continue;
    }

    final translations = localizedValues[lang] ?? {};
    final Map<String, dynamic> toInsert = {};

    for (final entry in enMetadataAndValues.entries) {
      if (entry.key.startsWith('@')) continue; // Metadata belongs only in app_en.arb
      toInsert[entry.key] = translations[entry.key] ?? entry.value;
    }

    _updateArb(file, toInsert);
    print('Updated: app_$lang.arb');
  }

  print('\nARB files updated successfully.');
  print('Run "flutter gen-l10n" to regenerate localization Dart bindings.');
}

Directory? _findL10nDirectory() {
  final candidates = [
    Directory('lib/l10n'),
    Directory('l10n'),
    Directory('../lib/l10n'),
  ];
  for (final dir in candidates) {
    if (dir.existsSync() && File('${dir.path}/app_en.arb').existsSync()) {
      return dir;
    }
  }
  return null;
}

void _updateArb(File file, Map<String, dynamic> newEntries) {
  final content = file.readAsStringSync();
  final Map<String, dynamic> jsonMap = json.decode(content);

  bool modified = false;
  for (final entry in newEntries.entries) {
    if (jsonMap[entry.key] != entry.value) {
      jsonMap[entry.key] = entry.value;
      modified = true;
    }
  }

  if (modified) {
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(jsonMap)}\n');
  }
}