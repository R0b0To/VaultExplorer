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
  'securityKeyUnlockHintNfc':
      'This vault is protected by a security key. Tap Unlock, then hold your key against the back of the phone or plug it in. Touch it if it blinks.',
  'securityKeyUnlockHintUsb':
      'This vault is protected by a security key. Tap Unlock, then plug in your key. Touch it if it blinks.',
  'securityKeyPinFieldLabel':
      'Security key PIN',
  'securityKeyWaiting':
      'Waiting for your security key…',
  'securityKeyErrorTimeout':
      'No security key was detected in time. Try again.',
  'securityKeyErrorPinRequired':
      'Enter your security key PIN.',
  'securityKeyErrorPinInvalid':
      'Incorrect security key PIN.',
  'securityKeyErrorPinBlocked':
      'The security key PIN is blocked. Unplug and reconnect the key, or reset it.',
  'securityKeyErrorPinNotSet':
      'This security key has no PIN set. Set one first, or turn off the PIN requirement.',
  'securityKeyErrorNoCredential':
      'This isn\'t the security key used for this vault. Try another key.',
  'securityKeyErrorUnsupported':
      'This security key can\'t be used here. It needs FIDO2 with the hmac-secret extension and PIN verification.',
  'securityKeyErrorTouch':
      'The security key wasn\'t touched in time. Try again.',
  'securityKeyErrorGeneric':
      'The security key operation failed. Try again.',
  'securityKeyCreateTitle':
      'Protect with a security key',
  'securityKeyCreateSubtitle':
      'Use a FIDO2 key such as a YubiKey instead of a password. Compatible with gocryptfs -fido2.',
  'securityKeyCreateHint':
      'Tap Create, then hold your key against the back of the phone or plug it in. Touch it if it blinks. Without this key (and its PIN, if required) the vault cannot be opened and there is no password to fall back on.',
  'securityKeyRequirePinTitle':
      'Require the key\'s PIN',
  'securityKeyRequirePinSubtitle':
      'Ask for the PIN on every unlock. The key must already have a PIN set.',
  'wizardSummarySecurityKeyValue':
      'Security key',
};

/// Add translations for each supported language here.
/// If a translation for a key is omitted, it falls back to the English value.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    'securityKeyUnlockHintNfc':
        'هذه الخزنة محمية بمفتاح أمان. اضغط على «فتح القفل»، ثم قرّب المفتاح من الجزء الخلفي للهاتف أو وصّله. المس المفتاح إذا كان يومض.',
    'securityKeyUnlockHintUsb':
        'هذه الخزنة محمية بمفتاح أمان. اضغط على «فتح القفل»، ثم وصّل المفتاح. المس المفتاح إذا كان يومض.',
    'securityKeyPinFieldLabel':
        'رمز PIN لمفتاح الأمان',
    'securityKeyWaiting':
        'في انتظار مفتاح الأمان…',
    'securityKeyErrorTimeout':
        'لم يتم اكتشاف مفتاح أمان في الوقت المناسب. حاول مرة أخرى.',
    'securityKeyErrorPinRequired':
        'أدخل رمز PIN الخاص بمفتاح الأمان.',
    'securityKeyErrorPinInvalid':
        'رمز PIN لمفتاح الأمان غير صحيح.',
    'securityKeyErrorPinBlocked':
        'رمز PIN لمفتاح الأمان محظور. افصل المفتاح وأعد توصيله أو أعد ضبطه.',
    'securityKeyErrorPinNotSet':
        'لم يتم تعيين رمز PIN لمفتاح الأمان هذا. عيّن رمزًا أولًا أو أوقف اشتراط PIN.',
    'securityKeyErrorNoCredential':
        'هذا ليس مفتاح الأمان المستخدم لهذه الخزنة. جرّب مفتاحًا آخر.',
    'securityKeyErrorUnsupported':
        'لا يمكن استخدام مفتاح الأمان هذا هنا. يتطلب FIDO2 مع امتداد hmac-secret والتحقق برمز PIN.',
    'securityKeyErrorTouch':
        'لم يتم لمس مفتاح الأمان في الوقت المناسب. حاول مرة أخرى.',
    'securityKeyErrorGeneric':
        'فشلت العملية مع مفتاح الأمان. حاول مرة أخرى.',
    'securityKeyCreateTitle':
        'الحماية بمفتاح أمان',
    'securityKeyCreateSubtitle':
        'استخدم مفتاح FIDO2 مثل YubiKey بدلًا من كلمة المرور. متوافق مع gocryptfs -fido2.',
    'securityKeyCreateHint':
        'اضغط على «إنشاء»، ثم قرّب المفتاح من الجزء الخلفي للهاتف أو وصّله. المس المفتاح إذا كان يومض. بدون هذا المفتاح (ورمز PIN الخاص به إن كان مطلوبًا) لا يمكن فتح الخزنة ولا توجد كلمة مرور بديلة.',
    'securityKeyRequirePinTitle':
        'اشتراط رمز PIN للمفتاح',
    'securityKeyRequirePinSubtitle':
        'اطلب رمز PIN عند كل فتح للقفل. يجب أن يكون المفتاح قد عُيّن له رمز PIN مسبقًا.',
    'wizardSummarySecurityKeyValue':
        'مفتاح أمان',
  },
  'de': {
    'securityKeyUnlockHintNfc':
        'Dieser Tresor ist durch einen Sicherheitsschlüssel geschützt. Tippen Sie auf „Entsperren“ und halten Sie den Schlüssel an die Rückseite des Telefons oder stecken Sie ihn an. Berühren Sie ihn, falls er blinkt.',
    'securityKeyUnlockHintUsb':
        'Dieser Tresor ist durch einen Sicherheitsschlüssel geschützt. Tippen Sie auf „Entsperren“ und stecken Sie dann den Schlüssel an. Berühren Sie ihn, falls er blinkt.',
    'securityKeyPinFieldLabel':
        'PIN des Sicherheitsschlüssels',
    'securityKeyWaiting':
        'Warten auf den Sicherheitsschlüssel …',
    'securityKeyErrorTimeout':
        'Es wurde rechtzeitig kein Sicherheitsschlüssel erkannt. Versuchen Sie es erneut.',
    'securityKeyErrorPinRequired':
        'Geben Sie die PIN Ihres Sicherheitsschlüssels ein.',
    'securityKeyErrorPinInvalid':
        'Falsche PIN des Sicherheitsschlüssels.',
    'securityKeyErrorPinBlocked':
        'Die PIN des Sicherheitsschlüssels ist gesperrt. Ziehen Sie den Schlüssel ab und stecken Sie ihn erneut an oder setzen Sie ihn zurück.',
    'securityKeyErrorPinNotSet':
        'Für diesen Sicherheitsschlüssel ist keine PIN festgelegt. Legen Sie zuerst eine fest oder deaktivieren Sie die PIN-Pflicht.',
    'securityKeyErrorNoCredential':
        'Dies ist nicht der Sicherheitsschlüssel dieses Tresors. Versuchen Sie einen anderen Schlüssel.',
    'securityKeyErrorUnsupported':
        'Dieser Sicherheitsschlüssel kann hier nicht verwendet werden. Er benötigt FIDO2 mit der hmac-secret-Erweiterung und PIN-Verifizierung.',
    'securityKeyErrorTouch':
        'Der Sicherheitsschlüssel wurde nicht rechtzeitig berührt. Versuchen Sie es erneut.',
    'securityKeyErrorGeneric':
        'Der Vorgang mit dem Sicherheitsschlüssel ist fehlgeschlagen. Versuchen Sie es erneut.',
    'securityKeyCreateTitle':
        'Mit Sicherheitsschlüssel schützen',
    'securityKeyCreateSubtitle':
        'Verwenden Sie statt eines Passworts einen FIDO2-Schlüssel wie einen YubiKey. Kompatibel mit gocryptfs -fido2.',
    'securityKeyCreateHint':
        'Tippen Sie auf „Erstellen“ und halten Sie den Schlüssel an die Rückseite des Telefons oder stecken Sie ihn an. Berühren Sie ihn, falls er blinkt. Ohne diesen Schlüssel (und seine PIN, falls erforderlich) lässt sich der Tresor nicht öffnen – es gibt kein Passwort als Alternative.',
    'securityKeyRequirePinTitle':
        'PIN des Schlüssels verlangen',
    'securityKeyRequirePinSubtitle':
        'Bei jedem Entsperren nach der PIN fragen. Für den Schlüssel muss bereits eine PIN festgelegt sein.',
    'wizardSummarySecurityKeyValue':
        'Sicherheitsschlüssel',
  },
  'es': {
    'securityKeyUnlockHintNfc':
        'Esta bóveda está protegida con una llave de seguridad. Toca Desbloquear y acerca la llave a la parte trasera del teléfono o conéctala. Tócala si parpadea.',
    'securityKeyUnlockHintUsb':
        'Esta bóveda está protegida con una llave de seguridad. Toca Desbloquear y conecta la llave. Tócala si parpadea.',
    'securityKeyPinFieldLabel':
        'PIN de la llave de seguridad',
    'securityKeyWaiting':
        'Esperando la llave de seguridad…',
    'securityKeyErrorTimeout':
        'No se detectó ninguna llave de seguridad a tiempo. Inténtalo de nuevo.',
    'securityKeyErrorPinRequired':
        'Introduce el PIN de tu llave de seguridad.',
    'securityKeyErrorPinInvalid':
        'PIN de la llave de seguridad incorrecto.',
    'securityKeyErrorPinBlocked':
        'El PIN de la llave de seguridad está bloqueado. Desconecta y vuelve a conectar la llave, o restablécela.',
    'securityKeyErrorPinNotSet':
        'Esta llave de seguridad no tiene un PIN configurado. Configura uno primero o desactiva el requisito de PIN.',
    'securityKeyErrorNoCredential':
        'Esta no es la llave de seguridad de esta bóveda. Prueba con otra llave.',
    'securityKeyErrorUnsupported':
        'Esta llave de seguridad no se puede usar aquí. Necesita FIDO2 con la extensión hmac-secret y verificación por PIN.',
    'securityKeyErrorTouch':
        'No se tocó la llave de seguridad a tiempo. Inténtalo de nuevo.',
    'securityKeyErrorGeneric':
        'Falló la operación con la llave de seguridad. Inténtalo de nuevo.',
    'securityKeyCreateTitle':
        'Proteger con una llave de seguridad',
    'securityKeyCreateSubtitle':
        'Usa una llave FIDO2, como una YubiKey, en lugar de una contraseña. Compatible con gocryptfs -fido2.',
    'securityKeyCreateHint':
        'Toca Crear y acerca la llave a la parte trasera del teléfono o conéctala. Tócala si parpadea. Sin esta llave (y su PIN, si se exige) no se puede abrir la bóveda y no hay contraseña alternativa.',
    'securityKeyRequirePinTitle':
        'Exigir el PIN de la llave',
    'securityKeyRequirePinSubtitle':
        'Pide el PIN en cada desbloqueo. La llave debe tener ya un PIN configurado.',
    'wizardSummarySecurityKeyValue':
        'Llave de seguridad',
  },
  'fr': {
    'securityKeyUnlockHintNfc':
        'Ce coffre est protégé par une clé de sécurité. Appuyez sur Déverrouiller, puis approchez la clé de l\'arrière du téléphone ou branchez-la. Touchez-la si elle clignote.',
    'securityKeyUnlockHintUsb':
        'Ce coffre est protégé par une clé de sécurité. Appuyez sur Déverrouiller, puis branchez la clé. Touchez-la si elle clignote.',
    'securityKeyPinFieldLabel':
        'PIN de la clé de sécurité',
    'securityKeyWaiting':
        'En attente de votre clé de sécurité…',
    'securityKeyErrorTimeout':
        'Aucune clé de sécurité détectée à temps. Réessayez.',
    'securityKeyErrorPinRequired':
        'Saisissez le PIN de votre clé de sécurité.',
    'securityKeyErrorPinInvalid':
        'PIN de la clé de sécurité incorrect.',
    'securityKeyErrorPinBlocked':
        'Le PIN de la clé de sécurité est bloqué. Débranchez puis rebranchez la clé, ou réinitialisez-la.',
    'securityKeyErrorPinNotSet':
        'Aucun PIN n\'est défini sur cette clé de sécurité. Définissez-en un d\'abord ou désactivez l\'exigence de PIN.',
    'securityKeyErrorNoCredential':
        'Ce n\'est pas la clé de sécurité utilisée pour ce coffre. Essayez une autre clé.',
    'securityKeyErrorUnsupported':
        'Cette clé de sécurité ne peut pas être utilisée ici. Elle doit prendre en charge FIDO2 avec l\'extension hmac-secret et la vérification par PIN.',
    'securityKeyErrorTouch':
        'La clé de sécurité n\'a pas été touchée à temps. Réessayez.',
    'securityKeyErrorGeneric':
        'L\'opération avec la clé de sécurité a échoué. Réessayez.',
    'securityKeyCreateTitle':
        'Protéger avec une clé de sécurité',
    'securityKeyCreateSubtitle':
        'Utilisez une clé FIDO2, comme une YubiKey, au lieu d\'un mot de passe. Compatible avec gocryptfs -fido2.',
    'securityKeyCreateHint':
        'Appuyez sur Créer, puis approchez la clé de l\'arrière du téléphone ou branchez-la. Touchez-la si elle clignote. Sans cette clé (et son PIN, s\'il est exigé), le coffre ne peut pas être ouvert et il n\'existe aucun mot de passe de secours.',
    'securityKeyRequirePinTitle':
        'Exiger le PIN de la clé',
    'securityKeyRequirePinSubtitle':
        'Demande le PIN à chaque déverrouillage. Un PIN doit déjà être défini sur la clé.',
    'wizardSummarySecurityKeyValue':
        'Clé de sécurité',
  },
  'it': {
    'securityKeyUnlockHintNfc':
        'Questo vault è protetto da una chiave di sicurezza. Tocca Sblocca, poi avvicina la chiave al retro del telefono oppure collegala. Toccala se lampeggia.',
    'securityKeyUnlockHintUsb':
        'Questo vault è protetto da una chiave di sicurezza. Tocca Sblocca, poi collega la chiave. Toccala se lampeggia.',
    'securityKeyPinFieldLabel':
        'PIN della chiave di sicurezza',
    'securityKeyWaiting':
        'In attesa della chiave di sicurezza…',
    'securityKeyErrorTimeout':
        'Nessuna chiave di sicurezza rilevata in tempo. Riprova.',
    'securityKeyErrorPinRequired':
        'Inserisci il PIN della tua chiave di sicurezza.',
    'securityKeyErrorPinInvalid':
        'PIN della chiave di sicurezza errato.',
    'securityKeyErrorPinBlocked':
        'Il PIN della chiave di sicurezza è bloccato. Scollega e ricollega la chiave oppure reimpostala.',
    'securityKeyErrorPinNotSet':
        'Su questa chiave di sicurezza non è impostato alcun PIN. Impostane uno prima o disattiva l\'obbligo del PIN.',
    'securityKeyErrorNoCredential':
        'Questa non è la chiave di sicurezza usata per questo vault. Prova con un\'altra chiave.',
    'securityKeyErrorUnsupported':
        'Questa chiave di sicurezza non può essere usata qui. Richiede FIDO2 con l\'estensione hmac-secret e la verifica tramite PIN.',
    'securityKeyErrorTouch':
        'La chiave di sicurezza non è stata toccata in tempo. Riprova.',
    'securityKeyErrorGeneric':
        'L\'operazione con la chiave di sicurezza non è riuscita. Riprova.',
    'securityKeyCreateTitle':
        'Proteggi con una chiave di sicurezza',
    'securityKeyCreateSubtitle':
        'Usa una chiave FIDO2, come una YubiKey, al posto di una password. Compatibile con gocryptfs -fido2.',
    'securityKeyCreateHint':
        'Tocca Crea, poi avvicina la chiave al retro del telefono oppure collegala. Toccala se lampeggia. Senza questa chiave (e il suo PIN, se richiesto) il vault non può essere aperto e non esiste una password di riserva.',
    'securityKeyRequirePinTitle':
        'Richiedi il PIN della chiave',
    'securityKeyRequirePinSubtitle':
        'Chiede il PIN a ogni sblocco. Sulla chiave deve essere già impostato un PIN.',
    'wizardSummarySecurityKeyValue':
        'Chiave di sicurezza',
  },
  'ja': {
    'securityKeyUnlockHintNfc':
        'この保管庫はセキュリティキーで保護されています。「ロック解除」をタップし、キーをスマートフォンの背面に当てるか、接続してください。点滅している場合はキーに触れてください。',
    'securityKeyUnlockHintUsb':
        'この保管庫はセキュリティキーで保護されています。「ロック解除」をタップし、キーを接続してください。点滅している場合はキーに触れてください。',
    'securityKeyPinFieldLabel':
        'セキュリティキーのPIN',
    'securityKeyWaiting':
        'セキュリティキーを待っています…',
    'securityKeyErrorTimeout':
        '時間内にセキュリティキーが検出されませんでした。もう一度お試しください。',
    'securityKeyErrorPinRequired':
        'セキュリティキーのPINを入力してください。',
    'securityKeyErrorPinInvalid':
        'セキュリティキーのPINが正しくありません。',
    'securityKeyErrorPinBlocked':
        'セキュリティキーのPINがブロックされています。キーを抜き差しするか、リセットしてください。',
    'securityKeyErrorPinNotSet':
        'このセキュリティキーにはPINが設定されていません。先にPINを設定するか、PIN必須をオフにしてください。',
    'securityKeyErrorNoCredential':
        'この保管庫に使われているセキュリティキーではありません。別のキーをお試しください。',
    'securityKeyErrorUnsupported':
        'このセキュリティキーはここでは使用できません。hmac-secret拡張に対応したFIDO2とPIN認証が必要です。',
    'securityKeyErrorTouch':
        '時間内にセキュリティキーに触れませんでした。もう一度お試しください。',
    'securityKeyErrorGeneric':
        'セキュリティキーの操作に失敗しました。もう一度お試しください。',
    'securityKeyCreateTitle':
        'セキュリティキーで保護',
    'securityKeyCreateSubtitle':
        'パスワードの代わりにYubiKeyなどのFIDO2キーを使用します。gocryptfs -fido2と互換性があります。',
    'securityKeyCreateHint':
        '「作成」をタップし、キーをスマートフォンの背面に当てるか、接続してください。点滅している場合はキーに触れてください。このキー(必要な場合はPINも)がないと保管庫は開けず、代わりに使えるパスワードもありません。',
    'securityKeyRequirePinTitle':
        'キーのPINを必須にする',
    'securityKeyRequirePinSubtitle':
        'ロック解除のたびにPINを求めます。キーにあらかじめPINが設定されている必要があります。',
    'wizardSummarySecurityKeyValue':
        'セキュリティキー',
  },
  'ko': {
    'securityKeyUnlockHintNfc':
        '이 볼트는 보안 키로 보호됩니다. 잠금 해제를 탭한 다음 키를 휴대폰 뒷면에 대거나 연결하세요. 깜박이면 키를 터치하세요.',
    'securityKeyUnlockHintUsb':
        '이 볼트는 보안 키로 보호됩니다. 잠금 해제를 탭한 다음 키를 연결하세요. 깜박이면 키를 터치하세요.',
    'securityKeyPinFieldLabel':
        '보안 키 PIN',
    'securityKeyWaiting':
        '보안 키를 기다리는 중…',
    'securityKeyErrorTimeout':
        '제때 보안 키가 감지되지 않았습니다. 다시 시도하세요.',
    'securityKeyErrorPinRequired':
        '보안 키 PIN을 입력하세요.',
    'securityKeyErrorPinInvalid':
        '보안 키 PIN이 올바르지 않습니다.',
    'securityKeyErrorPinBlocked':
        '보안 키 PIN이 차단되었습니다. 키를 뺐다가 다시 연결하거나 초기화하세요.',
    'securityKeyErrorPinNotSet':
        '이 보안 키에는 PIN이 설정되어 있지 않습니다. 먼저 PIN을 설정하거나 PIN 필수 옵션을 끄세요.',
    'securityKeyErrorNoCredential':
        '이 볼트에 사용된 보안 키가 아닙니다. 다른 키를 사용해 보세요.',
    'securityKeyErrorUnsupported':
        '이 보안 키는 여기서 사용할 수 없습니다. hmac-secret 확장을 지원하는 FIDO2와 PIN 인증이 필요합니다.',
    'securityKeyErrorTouch':
        '제때 보안 키를 터치하지 않았습니다. 다시 시도하세요.',
    'securityKeyErrorGeneric':
        '보안 키 작업에 실패했습니다. 다시 시도하세요.',
    'securityKeyCreateTitle':
        '보안 키로 보호',
    'securityKeyCreateSubtitle':
        '비밀번호 대신 YubiKey 같은 FIDO2 키를 사용합니다. gocryptfs -fido2와 호환됩니다.',
    'securityKeyCreateHint':
        '만들기를 탭한 다음 키를 휴대폰 뒷면에 대거나 연결하세요. 깜박이면 키를 터치하세요. 이 키(필요한 경우 PIN 포함)가 없으면 볼트를 열 수 없으며 대신 사용할 비밀번호도 없습니다.',
    'securityKeyRequirePinTitle':
        '키 PIN 필수',
    'securityKeyRequirePinSubtitle':
        '잠금을 해제할 때마다 PIN을 요구합니다. 키에 PIN이 이미 설정되어 있어야 합니다.',
    'wizardSummarySecurityKeyValue':
        '보안 키',
  },
  'pt': {
    'securityKeyUnlockHintNfc':
        'Este cofre está protegido por uma chave de segurança. Toque em Desbloquear e aproxime a chave da parte traseira do telefone ou conecte-a. Toque nela se estiver piscando.',
    'securityKeyUnlockHintUsb':
        'Este cofre está protegido por uma chave de segurança. Toque em Desbloquear e conecte a chave. Toque nela se estiver piscando.',
    'securityKeyPinFieldLabel':
        'PIN da chave de segurança',
    'securityKeyWaiting':
        'Aguardando a chave de segurança…',
    'securityKeyErrorTimeout':
        'Nenhuma chave de segurança foi detectada a tempo. Tente novamente.',
    'securityKeyErrorPinRequired':
        'Digite o PIN da sua chave de segurança.',
    'securityKeyErrorPinInvalid':
        'PIN da chave de segurança incorreto.',
    'securityKeyErrorPinBlocked':
        'O PIN da chave de segurança está bloqueado. Desconecte e reconecte a chave ou redefina-a.',
    'securityKeyErrorPinNotSet':
        'Esta chave de segurança não tem PIN definido. Defina um primeiro ou desative a exigência de PIN.',
    'securityKeyErrorNoCredential':
        'Esta não é a chave de segurança usada neste cofre. Tente outra chave.',
    'securityKeyErrorUnsupported':
        'Esta chave de segurança não pode ser usada aqui. Ela precisa de FIDO2 com a extensão hmac-secret e verificação por PIN.',
    'securityKeyErrorTouch':
        'A chave de segurança não foi tocada a tempo. Tente novamente.',
    'securityKeyErrorGeneric':
        'A operação com a chave de segurança falhou. Tente novamente.',
    'securityKeyCreateTitle':
        'Proteger com uma chave de segurança',
    'securityKeyCreateSubtitle':
        'Use uma chave FIDO2, como uma YubiKey, em vez de uma senha. Compatível com gocryptfs -fido2.',
    'securityKeyCreateHint':
        'Toque em Criar e aproxime a chave da parte traseira do telefone ou conecte-a. Toque nela se estiver piscando. Sem esta chave (e o PIN, se exigido), o cofre não pode ser aberto e não há senha alternativa.',
    'securityKeyRequirePinTitle':
        'Exigir o PIN da chave',
    'securityKeyRequirePinSubtitle':
        'Pede o PIN a cada desbloqueio. A chave já deve ter um PIN definido.',
    'wizardSummarySecurityKeyValue':
        'Chave de segurança',
  },
  'uk': {
    'securityKeyUnlockHintNfc':
        'Це сховище захищене ключем безпеки. Торкніться «Розблокувати», потім прикладіть ключ до задньої панелі телефона або підключіть його. Торкніться ключа, якщо він блимає.',
    'securityKeyUnlockHintUsb':
        'Це сховище захищене ключем безпеки. Торкніться «Розблокувати», потім підключіть ключ. Торкніться ключа, якщо він блимає.',
    'securityKeyPinFieldLabel':
        'PIN-код ключа безпеки',
    'securityKeyWaiting':
        'Очікування ключа безпеки…',
    'securityKeyErrorTimeout':
        'Ключ безпеки не виявлено вчасно. Спробуйте ще раз.',
    'securityKeyErrorPinRequired':
        'Введіть PIN-код вашого ключа безпеки.',
    'securityKeyErrorPinInvalid':
        'Неправильний PIN-код ключа безпеки.',
    'securityKeyErrorPinBlocked':
        'PIN-код ключа безпеки заблоковано. Відключіть і знову підключіть ключ або скиньте його.',
    'securityKeyErrorPinNotSet':
        'Для цього ключа безпеки не встановлено PIN-код. Спершу встановіть його або вимкніть вимогу PIN-коду.',
    'securityKeyErrorNoCredential':
        'Це не той ключ безпеки, що використовується для цього сховища. Спробуйте інший ключ.',
    'securityKeyErrorUnsupported':
        'Цей ключ безпеки не можна використати тут. Потрібен FIDO2 з розширенням hmac-secret і перевіркою PIN-кодом.',
    'securityKeyErrorTouch':
        'До ключа безпеки не торкнулися вчасно. Спробуйте ще раз.',
    'securityKeyErrorGeneric':
        'Не вдалося виконати операцію з ключем безпеки. Спробуйте ще раз.',
    'securityKeyCreateTitle':
        'Захистити ключем безпеки',
    'securityKeyCreateSubtitle':
        'Використовуйте ключ FIDO2, наприклад YubiKey, замість пароля. Сумісно з gocryptfs -fido2.',
    'securityKeyCreateHint':
        'Торкніться «Створити», потім прикладіть ключ до задньої панелі телефона або підключіть його. Торкніться ключа, якщо він блимає. Без цього ключа (і його PIN-коду, якщо потрібен) сховище не відкрити, а запасного пароля немає.',
    'securityKeyRequirePinTitle':
        'Вимагати PIN-код ключа',
    'securityKeyRequirePinSubtitle':
        'Запитувати PIN-код під час кожного розблокування. На ключі вже має бути встановлено PIN-код.',
    'wizardSummarySecurityKeyValue':
        'Ключ безпеки',
  },
  'zh': {
    'securityKeyUnlockHintNfc':
        '此保险库受安全密钥保护。点击“解锁”，然后将密钥贴近手机背面或插入手机。如果密钥闪烁，请触摸它。',
    'securityKeyUnlockHintUsb':
        '此保险库受安全密钥保护。点击“解锁”，然后插入密钥。如果密钥闪烁，请触摸它。',
    'securityKeyPinFieldLabel':
        '安全密钥 PIN',
    'securityKeyWaiting':
        '正在等待安全密钥…',
    'securityKeyErrorTimeout':
        '未能及时检测到安全密钥。请重试。',
    'securityKeyErrorPinRequired':
        '请输入安全密钥的 PIN。',
    'securityKeyErrorPinInvalid':
        '安全密钥 PIN 不正确。',
    'securityKeyErrorPinBlocked':
        '安全密钥 PIN 已被锁定。请拔出并重新插入密钥，或将其重置。',
    'securityKeyErrorPinNotSet':
        '此安全密钥未设置 PIN。请先设置 PIN，或关闭 PIN 要求。',
    'securityKeyErrorNoCredential':
        '这不是此保险库所用的安全密钥。请尝试其他密钥。',
    'securityKeyErrorUnsupported':
        '此安全密钥无法在此使用。它需要支持 hmac-secret 扩展的 FIDO2 以及 PIN 验证。',
    'securityKeyErrorTouch':
        '未能及时触摸安全密钥。请重试。',
    'securityKeyErrorGeneric':
        '安全密钥操作失败。请重试。',
    'securityKeyCreateTitle':
        '使用安全密钥保护',
    'securityKeyCreateSubtitle':
        '使用 YubiKey 等 FIDO2 密钥代替密码。与 gocryptfs -fido2 兼容。',
    'securityKeyCreateHint':
        '点击“创建”，然后将密钥贴近手机背面或插入手机。如果密钥闪烁，请触摸它。没有此密钥（以及所需的 PIN），将无法打开保险库，也没有可替代的密码。',
    'securityKeyRequirePinTitle':
        '要求输入密钥 PIN',
    'securityKeyRequirePinSubtitle':
        '每次解锁都询问 PIN。密钥上必须已设置 PIN。',
    'wizardSummarySecurityKeyValue':
        '安全密钥',
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