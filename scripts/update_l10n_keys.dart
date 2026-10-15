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
  'audioRecordingQualityLabel': 'Audio recording quality',
  '@audioRecordingQualityLabel': {
    'description': 'Settings label for the picker that chooses how audio recordings made in a vault are encoded (bitrate / file size)',
  },
  'audioRecordingQualityVoice': 'Voice',
  '@audioRecordingQualityVoice': {
    'description': 'Audio recording quality preset: lowest bitrate, smallest files, meant for speech',
  },
  'audioRecordingQualityStandard': 'Standard',
  '@audioRecordingQualityStandard': {
    'description': 'Audio recording quality preset: medium bitrate, the default',
  },
  'audioRecordingQualityHigh': 'High',
  '@audioRecordingQualityHigh': {
    'description': 'Audio recording quality preset: highest bitrate, for music and ambient sound',
  },
  'audioRecordingQualityDetails': 'AAC · {bitrate} kbps · {sampleRate} kHz · mono',
  '@audioRecordingQualityDetails': {
    'description': 'Technical description of an audio recording quality preset in the picker: codec, bitrate in kbps, sample rate in kHz and channel layout (always mono). Keep the unit symbols; translate only "mono".',
    'placeholders': {
      'bitrate': {'type': 'String'},
      'sampleRate': {'type': 'String'},
    },
  },
  'audioEditorCompressTitle': 'File size',
  '@audioEditorCompressTitle': {
    'description': "Heading above the file-size choices in the audio editor's export sheet",
  },
  'audioEditorCompressOriginal': 'Original',
  '@audioEditorCompressOriginal': {
    'description': 'Export-sheet choice meaning keep the original audio data (no re-encoding, no size reduction)',
  },
  'audioEditorCompressEstimate': 'Estimated size: about {size}',
  '@audioEditorCompressEstimate': {
    'description': "Estimated size of the exported audio shown under the file-size choices in the audio editor's export sheet",
    'placeholders': {
      'size': {'type': 'String'},
    },
  },
  'audioEditorCompressNote': "The audio is re-encoded to AAC at a lower bitrate, so the file is smaller but quality is reduced. Cuts land exactly where you set them. Tags and cover art aren't carried over.",
  '@audioEditorCompressNote': {
    'description': "Explanation at the bottom of the audio editor's export sheet when a lower bitrate is chosen and the audio will be re-encoded to AAC",
  },
  // Volume-creation wizards: "Add randomness" step (touch-movement entropy).
  'entropyStepTitle': 'Add randomness',
  '@entropyStepTitle': {
    'description': "Title of the wizard step where the user moves a finger over a pad to add randomness to the new volume's keys",
  },
  'entropyIntro': 'Drag your finger around the pad in unpredictable, varied strokes. Your movements are stirred into the encryption keys and salts in addition to the device’s secure random generator, never instead of it.',
  '@entropyIntro': {
    'description': "Explanation at the top of the randomness step: finger movement is mixed into the keys and salts in addition to (never instead of) the device's secure random generator",
  },
  'entropyPadHint': 'Draw here with your finger',
  '@entropyPadHint': {
    'description': 'Hint shown inside the empty touch pad of the randomness step',
  },
  'entropyPadSemantics': 'Randomness pad. Drag your finger over it to collect random movement.',
  '@entropyPadSemantics': {
    'description': 'Accessibility label of the touch pad of the randomness step',
  },
  'entropyProgress': 'Collecting randomness… {percent}%',
  '@entropyProgress': {
    'description': 'Progress text of the randomness step while movement is being collected',
    'placeholders': {
      'percent': {'type': 'int'},
    },
  },
  'entropyComplete': 'Enough randomness collected. Keep moving to add more, or continue.',
  '@entropyComplete': {
    'description': 'Status text of the randomness step once enough movement was collected',
  },
  'entropySkippedStatus': 'Skipped. Only the device’s secure random generator will be used. Draw on the pad to add randomness again.',
  '@entropySkippedStatus': {
    'description': 'Status text of the randomness step after the user skipped it',
  },
  'entropyPoolLabel': 'Random pool',
  '@entropyPoolLabel': {
    'description': 'Caption above the live hex display of the random pool in the randomness step',
  },
  'entropySkip': 'Skip and use the device generator only',
  '@entropySkip': {
    'description': "Button that skips the randomness step and uses only the device's secure random generator",
  },
  'entropyReviewLabel': 'Randomness',
  '@entropyReviewLabel': {
    'description': 'Row label in the wizard review summary for the randomness setting',
  },
  'entropyReviewUserAdded': 'Touch movement + device generator',
  '@entropyReviewUserAdded': {
    'description': "Review summary value: finger movement was mixed in on top of the device's generator",
  },
  'entropyReviewDeviceOnly': 'Device generator only',
  '@entropyReviewDeviceOnly': {
    'description': "Review summary value: only the device's secure random generator is used",
  },
};

/// Add translations for each supported language here.
/// If a translation for a key is omitted, it falls back to the English value.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    'audioRecordingQualityLabel': 'جودة تسجيل الصوت',
    'audioRecordingQualityVoice': 'كلام',
    'audioRecordingQualityStandard': 'قياسية',
    'audioRecordingQualityHigh': 'عالية',
    'audioRecordingQualityDetails': 'AAC · {bitrate} kbps · {sampleRate} kHz · أحادي',
    'audioEditorCompressTitle': 'حجم الملف',
    'audioEditorCompressOriginal': 'الأصلي',
    'audioEditorCompressEstimate': 'الحجم المقدّر: حوالي {size}',
    'audioEditorCompressNote': 'يُعاد ترميز الصوت إلى AAC بمعدل بت أقل، فيصغر حجم الملف لكن تقل الجودة. يقع القص عند النقطة التي حددتها بالضبط. لا تُنقل الوسوم وصورة الغلاف.',
    'entropyStepTitle': 'إضافة العشوائية',
    'entropyIntro': 'حرّك إصبعك على اللوحة بحركات متنوعة وغير متوقعة. تُدمج حركاتك في مفاتيح التشفير وقيم الملح (salt) إضافةً إلى مولّد الأرقام العشوائية الآمن في الجهاز، وليس بدلاً منه.',
    'entropyPadHint': 'ارسم هنا بإصبعك',
    'entropyPadSemantics': 'لوحة العشوائية. مرّر إصبعك عليها لجمع حركات عشوائية.',
    'entropyProgress': 'جارٍ جمع العشوائية… {percent}%',
    'entropyComplete': 'تم جمع عشوائية كافية. تابع التحريك لإضافة المزيد أو واصل.',
    'entropySkippedStatus': 'تم التخطي. سيُستخدم مولّد الأرقام العشوائية الآمن في الجهاز فقط. ارسم على اللوحة لإضافة العشوائية مجددًا.',
    'entropyPoolLabel': 'مجمّع العشوائية',
    'entropySkip': 'تخطَّ واستخدم مولّد الجهاز فقط',
    'entropyReviewLabel': 'العشوائية',
    'entropyReviewUserAdded': 'حركة اللمس + مولّد الجهاز',
    'entropyReviewDeviceOnly': 'مولّد الجهاز فقط',
  },
  'de': {
    'audioRecordingQualityLabel': 'Audioaufnahme-Qualität',
    'audioRecordingQualityVoice': 'Sprache',
    'audioRecordingQualityStandard': 'Standard',
    'audioRecordingQualityHigh': 'Hoch',
    'audioRecordingQualityDetails': 'AAC · {bitrate} kbps · {sampleRate} kHz · Mono',
    'audioEditorCompressTitle': 'Dateigröße',
    'audioEditorCompressOriginal': 'Original',
    'audioEditorCompressEstimate': 'Geschätzte Größe: etwa {size}',
    'audioEditorCompressNote': 'Das Audio wird mit niedrigerer Bitrate in AAC neu kodiert. Die Datei wird kleiner, die Qualität sinkt aber. Schnitte sitzen genau an deiner Markierung. Tags und Titelbilder werden nicht übernommen.',
    'entropyStepTitle': 'Zufall hinzufügen',
    'entropyIntro': 'Ziehe deinen Finger in unregelmäßigen, abwechslungsreichen Bewegungen über das Feld. Deine Bewegungen werden zusätzlich zum sicheren Zufallsgenerator des Geräts in Schlüssel und Salts eingemischt – nie anstelle davon.',
    'entropyPadHint': 'Hier mit dem Finger zeichnen',
    'entropyPadSemantics': 'Zufallsfeld. Ziehe den Finger darüber, um zufällige Bewegungen zu sammeln.',
    'entropyProgress': 'Zufall wird gesammelt … {percent} %',
    'entropyComplete': 'Genug Zufall gesammelt. Bewege den Finger weiter, um mehr hinzuzufügen, oder fahre fort.',
    'entropySkippedStatus': 'Übersprungen. Es wird nur der sichere Zufallsgenerator des Geräts verwendet. Zeichne auf dem Feld, um wieder Zufall hinzuzufügen.',
    'entropyPoolLabel': 'Zufallspool',
    'entropySkip': 'Überspringen und nur den Geräte-Generator verwenden',
    'entropyReviewLabel': 'Zufall',
    'entropyReviewUserAdded': 'Fingerbewegung + Geräte-Generator',
    'entropyReviewDeviceOnly': 'Nur Geräte-Generator',
  },
  'es': {
    'audioRecordingQualityLabel': 'Calidad de grabación de audio',
    'audioRecordingQualityVoice': 'Voz',
    'audioRecordingQualityStandard': 'Estándar',
    'audioRecordingQualityHigh': 'Alta',
    'audioRecordingQualityDetails': 'AAC · {bitrate} kbps · {sampleRate} kHz · mono',
    'audioEditorCompressTitle': 'Tamaño del archivo',
    'audioEditorCompressOriginal': 'Original',
    'audioEditorCompressEstimate': 'Tamaño estimado: unos {size}',
    'audioEditorCompressNote': 'El audio se recodifica a AAC con una tasa de bits menor, así que el archivo es más pequeño pero la calidad baja. Los cortes caen justo donde los marcas. Las etiquetas y la carátula no se conservan.',
    'entropyStepTitle': 'Añadir aleatoriedad',
    'entropyIntro': 'Desliza el dedo por el panel con trazos variados e impredecibles. Tus movimientos se mezclan en las claves de cifrado y en los valores salt, además del generador aleatorio seguro del dispositivo, nunca en su lugar.',
    'entropyPadHint': 'Dibuja aquí con el dedo',
    'entropyPadSemantics': 'Panel de aleatoriedad. Desliza el dedo sobre él para recoger movimiento aleatorio.',
    'entropyProgress': 'Recogiendo aleatoriedad… {percent} %',
    'entropyComplete': 'Aleatoriedad suficiente. Sigue moviendo el dedo para añadir más o continúa.',
    'entropySkippedStatus': 'Omitido. Solo se usará el generador aleatorio seguro del dispositivo. Dibuja en el panel para volver a añadir aleatoriedad.',
    'entropyPoolLabel': 'Reserva aleatoria',
    'entropySkip': 'Omitir y usar solo el generador del dispositivo',
    'entropyReviewLabel': 'Aleatoriedad',
    'entropyReviewUserAdded': 'Movimiento táctil + generador del dispositivo',
    'entropyReviewDeviceOnly': 'Solo generador del dispositivo',
  },
  'fr': {
    'audioRecordingQualityLabel': "Qualité d'enregistrement audio",
    'audioRecordingQualityVoice': 'Voix',
    'audioRecordingQualityStandard': 'Standard',
    'audioRecordingQualityHigh': 'Élevée',
    'audioRecordingQualityDetails': 'AAC · {bitrate} kbps · {sampleRate} kHz · mono',
    'audioEditorCompressTitle': 'Taille du fichier',
    'audioEditorCompressOriginal': 'Original',
    'audioEditorCompressEstimate': 'Taille estimée : environ {size}',
    'audioEditorCompressNote': "L'audio est réencodé en AAC avec un débit plus faible : le fichier est plus petit, mais la qualité diminue. Les coupes tombent exactement là où vous les placez. Les balises et la pochette ne sont pas conservées.",
    'entropyStepTitle': 'Ajouter de l’aléatoire',
    'entropyIntro': 'Faites glisser votre doigt sur la zone par des mouvements variés et imprévisibles. Vos mouvements sont mélangés aux clés de chiffrement et aux sels, en plus du générateur aléatoire sécurisé de l’appareil, jamais à sa place.',
    'entropyPadHint': 'Dessinez ici avec le doigt',
    'entropyPadSemantics': 'Zone d’aléatoire. Faites glisser le doigt dessus pour collecter des mouvements aléatoires.',
    'entropyProgress': 'Collecte de l’aléatoire… {percent} %',
    'entropyComplete': 'Assez d’aléatoire collecté. Continuez à bouger pour en ajouter, ou poursuivez.',
    'entropySkippedStatus': 'Ignoré. Seul le générateur aléatoire sécurisé de l’appareil sera utilisé. Dessinez sur la zone pour ajouter à nouveau de l’aléatoire.',
    'entropyPoolLabel': 'Réserve d’aléatoire',
    'entropySkip': 'Ignorer et utiliser uniquement le générateur de l’appareil',
    'entropyReviewLabel': 'Aléatoire',
    'entropyReviewUserAdded': 'Mouvement tactile + générateur de l’appareil',
    'entropyReviewDeviceOnly': 'Générateur de l’appareil uniquement',
  },
  'it': {
    'audioRecordingQualityLabel': 'Qualità di registrazione audio',
    'audioRecordingQualityVoice': 'Voce',
    'audioRecordingQualityStandard': 'Standard',
    'audioRecordingQualityHigh': 'Alta',
    'audioRecordingQualityDetails': 'AAC · {bitrate} kbps · {sampleRate} kHz · mono',
    'audioEditorCompressTitle': 'Dimensione del file',
    'audioEditorCompressOriginal': 'Originale',
    'audioEditorCompressEstimate': 'Dimensione stimata: circa {size}',
    'audioEditorCompressNote': "L'audio viene ricodificato in AAC con un bitrate inferiore: il file è più piccolo, ma la qualità diminuisce. I tagli cadono esattamente dove li imposti. Tag e copertina non vengono mantenuti.",
    'entropyStepTitle': 'Aggiungi casualità',
    'entropyIntro': 'Trascina il dito sull’area con movimenti vari e imprevedibili. I tuoi movimenti vengono mescolati alle chiavi di cifratura e ai salt, in aggiunta al generatore casuale sicuro del dispositivo, mai al suo posto.',
    'entropyPadHint': 'Disegna qui con il dito',
    'entropyPadSemantics': 'Area di casualità. Trascina il dito sopra per raccogliere movimento casuale.',
    'entropyProgress': 'Raccolta della casualità… {percent}%',
    'entropyComplete': 'Casualità sufficiente. Continua a muoverti per aggiungerne altra, oppure prosegui.',
    'entropySkippedStatus': 'Saltato. Verrà usato solo il generatore casuale sicuro del dispositivo. Disegna sull’area per aggiungere di nuovo casualità.',
    'entropyPoolLabel': 'Pool casuale',
    'entropySkip': 'Salta e usa solo il generatore del dispositivo',
    'entropyReviewLabel': 'Casualità',
    'entropyReviewUserAdded': 'Movimento touch + generatore del dispositivo',
    'entropyReviewDeviceOnly': 'Solo generatore del dispositivo',
  },
  'ja': {
    'audioRecordingQualityLabel': '音声録音の品質',
    'audioRecordingQualityVoice': '音声',
    'audioRecordingQualityStandard': '標準',
    'audioRecordingQualityHigh': '高',
    'audioRecordingQualityDetails': 'AAC · {bitrate} kbps · {sampleRate} kHz · モノラル',
    'audioEditorCompressTitle': 'ファイルサイズ',
    'audioEditorCompressOriginal': 'オリジナル',
    'audioEditorCompressEstimate': '推定サイズ: 約 {size}',
    'audioEditorCompressNote': 'オーディオはより低いビットレートで AAC に再エンコードされます。ファイルは小さくなりますが、音質は低下します。カットは設定した位置どおりになります。タグとカバーアートは引き継がれません。',
    'entropyStepTitle': 'ランダム性を追加',
    'entropyIntro': 'パッドの上で指を不規則にいろいろな方向へ動かしてください。動きは、端末の安全な乱数生成器に加えて（置き換えではなく）、暗号鍵とソルトに混ぜ合わされます。',
    'entropyPadHint': 'ここを指でなぞってください',
    'entropyPadSemantics': 'ランダム性パッド。指でなぞってランダムな動きを集めます。',
    'entropyProgress': 'ランダム性を収集中… {percent}%',
    'entropyComplete': '十分なランダム性を収集しました。さらに動かして追加するか、次へ進めます。',
    'entropySkippedStatus': 'スキップしました。端末の安全な乱数生成器のみを使用します。もう一度パッドをなぞると、ランダム性を追加できます。',
    'entropyPoolLabel': 'ランダムプール',
    'entropySkip': 'スキップして端末の生成器のみ使う',
    'entropyReviewLabel': 'ランダム性',
    'entropyReviewUserAdded': 'タッチ操作 + 端末の生成器',
    'entropyReviewDeviceOnly': '端末の生成器のみ',
  },
  'ko': {
    'audioRecordingQualityLabel': '오디오 녹음 품질',
    'audioRecordingQualityVoice': '음성',
    'audioRecordingQualityStandard': '표준',
    'audioRecordingQualityHigh': '높음',
    'audioRecordingQualityDetails': 'AAC · {bitrate} kbps · {sampleRate} kHz · 모노',
    'audioEditorCompressTitle': '파일 크기',
    'audioEditorCompressOriginal': '원본',
    'audioEditorCompressEstimate': '예상 크기: 약 {size}',
    'audioEditorCompressNote': '오디오가 더 낮은 비트레이트의 AAC로 다시 인코딩되어 파일은 작아지지만 음질은 낮아집니다. 컷은 지정한 위치 그대로 적용됩니다. 태그와 커버 아트는 유지되지 않습니다.',
    'entropyStepTitle': '무작위성 추가',
    'entropyIntro': '패드 위에서 손가락을 예측할 수 없게 다양한 방향으로 움직이세요. 움직임은 기기의 보안 난수 생성기에 더해(대체가 아님) 암호화 키와 솔트에 섞입니다.',
    'entropyPadHint': '여기에 손가락으로 그리세요',
    'entropyPadSemantics': '무작위성 패드. 손가락으로 문질러 무작위 움직임을 수집합니다.',
    'entropyProgress': '무작위성 수집 중… {percent}%',
    'entropyComplete': '충분한 무작위성이 수집되었습니다. 계속 움직여 더 추가하거나 다음으로 진행하세요.',
    'entropySkippedStatus': '건너뛰었습니다. 기기의 보안 난수 생성기만 사용합니다. 패드에 다시 그리면 무작위성을 추가할 수 있습니다.',
    'entropyPoolLabel': '난수 풀',
    'entropySkip': '건너뛰고 기기 생성기만 사용',
    'entropyReviewLabel': '무작위성',
    'entropyReviewUserAdded': '터치 움직임 + 기기 생성기',
    'entropyReviewDeviceOnly': '기기 생성기만 사용',
  },
  'pt': {
    'audioRecordingQualityLabel': 'Qualidade da gravação de áudio',
    'audioRecordingQualityVoice': 'Voz',
    'audioRecordingQualityStandard': 'Padrão',
    'audioRecordingQualityHigh': 'Alta',
    'audioRecordingQualityDetails': 'AAC · {bitrate} kbps · {sampleRate} kHz · mono',
    'audioEditorCompressTitle': 'Tamanho do arquivo',
    'audioEditorCompressOriginal': 'Original',
    'audioEditorCompressEstimate': 'Tamanho estimado: cerca de {size}',
    'audioEditorCompressNote': 'O áudio é recodificado para AAC com uma taxa de bits menor, então o arquivo fica menor, mas a qualidade diminui. Os cortes caem exatamente onde você os definiu. Tags e capa não são mantidas.',
    'entropyStepTitle': 'Adicionar Aleatoriedade',
    'entropyIntro': 'Deslize o dedo pela área com movimentos variados e imprevisíveis. Seus movimentos são misturados às chaves de criptografia e aos salts, além do gerador aleatório seguro do dispositivo, nunca no lugar dele.',
    'entropyPadHint': 'Desenhe aqui com o dedo',
    'entropyPadSemantics': 'Área de aleatoriedade. Deslize o dedo sobre ela para coletar movimento aleatório.',
    'entropyProgress': 'Coletando aleatoriedade… {percent}%',
    'entropyComplete': 'Aleatoriedade suficiente. Continue se movendo para adicionar mais ou prossiga.',
    'entropySkippedStatus': 'Ignorado. Somente o gerador aleatório seguro do dispositivo será usado. Desenhe na área para adicionar aleatoriedade novamente.',
    'entropyPoolLabel': 'Pool Aleatório',
    'entropySkip': 'Ignorar e usar somente o gerador do dispositivo',
    'entropyReviewLabel': 'Aleatoriedade',
    'entropyReviewUserAdded': 'Movimento do toque + gerador do dispositivo',
    'entropyReviewDeviceOnly': 'Somente gerador do dispositivo',
  },
  'uk': {
    'audioRecordingQualityLabel': 'Якість запису аудіо',
    'audioRecordingQualityVoice': 'Голос',
    'audioRecordingQualityStandard': 'Стандартна',
    'audioRecordingQualityHigh': 'Висока',
    'audioRecordingQualityDetails': 'AAC · {bitrate} kbps · {sampleRate} kHz · моно',
    'audioEditorCompressTitle': 'Розмір файлу',
    'audioEditorCompressOriginal': 'Оригінал',
    'audioEditorCompressEstimate': 'Орієнтовний розмір: приблизно {size}',
    'audioEditorCompressNote': 'Аудіо перекодовується в AAC із нижчим бітрейтом, тож файл стає меншим, але якість знижується. Розрізи припадають точно на задані вами точки. Теги й обкладинка не переносяться.',
    'entropyStepTitle': 'Додати випадковість',
    'entropyIntro': 'Проведіть пальцем по полю різними непередбачуваними рухами. Ваші рухи домішуються до ключів шифрування та солей на додачу до захищеного генератора випадкових чисел пристрою, а не замість нього.',
    'entropyPadHint': 'Малюйте тут пальцем',
    'entropyPadSemantics': 'Поле випадковості. Водіть по ньому пальцем, щоб зібрати випадкові рухи.',
    'entropyProgress': 'Збираємо випадковість… {percent}%',
    'entropyComplete': 'Випадковості достатньо. Продовжуйте рухатися, щоб додати більше, або переходьте далі.',
    'entropySkippedStatus': 'Пропущено. Буде використано лише захищений генератор випадкових чисел пристрою. Малюйте на полі, щоб знову додати випадковість.',
    'entropyPoolLabel': 'Пул випадковості',
    'entropySkip': 'Пропустити й використати лише генератор пристрою',
    'entropyReviewLabel': 'Випадковість',
    'entropyReviewUserAdded': 'Рух пальця + генератор пристрою',
    'entropyReviewDeviceOnly': 'Лише генератор пристрою',
  },
  'zh': {
    'audioRecordingQualityLabel': '音频录制质量',
    'audioRecordingQualityVoice': '语音',
    'audioRecordingQualityStandard': '标准',
    'audioRecordingQualityHigh': '高',
    'audioRecordingQualityDetails': 'AAC · {bitrate} kbps · {sampleRate} kHz · 单声道',
    'audioEditorCompressTitle': '文件大小',
    'audioEditorCompressOriginal': '原始',
    'audioEditorCompressEstimate': '预计大小：约 {size}',
    'audioEditorCompressNote': '音频会以更低的码率重新编码为 AAC，文件更小，但音质会有所下降。剪辑点会精确落在你设置的位置。标签和封面不会保留。',
    'entropyStepTitle': '添加随机性',
    'entropyIntro': '请在面板上以不规则、多样的方式滑动手指。你的滑动会与设备自带的安全随机数生成器一同混入加密密钥和盐值，而不是取代它。',
    'entropyPadHint': '在此用手指涂画',
    'entropyPadSemantics': '随机性面板。用手指在上面滑动以收集随机动作。',
    'entropyProgress': '正在收集随机性… {percent}%',
    'entropyComplete': '已收集足够的随机性。可继续滑动以增加更多，或直接继续。',
    'entropySkippedStatus': '已跳过。仅使用设备的安全随机数生成器。再次在面板上涂画即可重新添加随机性。',
    'entropyPoolLabel': '随机池',
    'entropySkip': '跳过，仅使用设备生成器',
    'entropyReviewLabel': '随机性',
    'entropyReviewUserAdded': '触摸动作 + 设备生成器',
    'entropyReviewDeviceOnly': '仅设备生成器',
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