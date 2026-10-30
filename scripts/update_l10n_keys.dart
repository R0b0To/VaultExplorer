// scripts/update_l10n_keys.dart
import 'dart:convert';
import 'dart:io';

/// Add your English keys and ARB metadata here.
/// Keys starting with '@' are metadata descriptions and are only added to app_en.arb.
const Map<String, dynamic> enMetadataAndValues = {
  'skinTokenGroupAccent': 'Accent colors',
  'skinTokenGroupStatus': 'Status and errors',
  'skinTokenSurfacePanel': 'Panels',
  'skinTokenSurfacePanelHint':
      'Cards made from the standard card widget, bookmark bar, grid cells and info sheets.',
  'skinTokenChromeBar': 'Bars and tab strips',
  'skinTokenChromeBarHint':
      'Action bars, tab strips, selection bar and bottom bars.',
  'skinTokenAccentPrimary': 'Accent',
  'skinTokenAccentPrimaryHint':
      'Highlights, links in text, small accent icons and badges.',
  'skinTokenAccentSecondary': 'Secondary accent',
  'skinTokenAccentSecondaryHint': 'Secondary highlights and tags.',
  'skinTokenAccentTertiary': 'Tertiary accent',
  'skinTokenAccentTertiaryHint': 'Tertiary highlights and tags.',
  'skinTokenAccentTertiaryContainer': 'Tertiary accent fill',
  'skinTokenAccentTertiaryContainerHint': 'Fill behind tertiary highlights.',
  'skinTokenAccentOnTertiaryContainer': 'Tertiary accent fill text',
  'skinTokenAccentOnTertiaryContainerHint':
      'Text and icons on the tertiary fill.',
  'skinTokenStatusDanger': 'Errors and delete',
  'skinTokenStatusDangerHint': 'Error text, delete actions and error borders.',
  'skinTokenStatusOnDanger': 'Text on error color',
  'skinTokenStatusOnDangerHint': 'Text and icons drawn on the error color.',
  'skinTokenStatusDangerContainer': 'Error message fill',
  'skinTokenStatusDangerContainerHint': 'Fill of error messages and banners.',
  'skinTokenStatusOnDangerContainer': 'Error message text',
  'skinTokenStatusOnDangerContainerHint': 'Text and icons in error messages.',
  'skinTokenStatusInfo': 'Info message fill',
  'skinTokenStatusInfoHint': 'Fill of info banners.',
  'skinTokenStatusOnInfo': 'Info message text',
  'skinTokenStatusOnInfoHint': 'Text and icons in info banners.',
};

/// Add translations for each supported language here.
/// If a translation for a key is omitted, it falls back to the English value.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    'skinTokenGroupAccent': 'ألوان التمييز',
    'skinTokenGroupStatus': 'الحالة والأخطاء',
    'skinTokenSurfacePanel': 'اللوحات',
    'skinTokenSurfacePanelHint':
        'البطاقات المكونة من عنصر البطاقة القياسي، وشريط الإشارات المرجعية، وخلايا الشبكة، وصفائح المعلومات.',
    'skinTokenChromeBar': 'الأشرطة وشرائط علامات التبويب',
    'skinTokenChromeBarHint':
        'أشرطة الإجراءات، وشرائط التبويب، وشريط التحديد، والأشرطة السفلية.',
    'skinTokenAccentPrimary': 'لون التمييز',
    'skinTokenAccentPrimaryHint':
        'العناصر المميزة، والروابط داخل النصوص، وأيقونات التمييز الصغيرة، والشارات.',
    'skinTokenAccentSecondary': 'لون التمييز الثانوي',
    'skinTokenAccentSecondaryHint': 'العناصر المميزة الثانوية والوسوم.',
    'skinTokenAccentTertiary': 'لون التمييز الثالثي',
    'skinTokenAccentTertiaryHint': 'العناصر المميزة والوسوم الثالثية.',
    'skinTokenAccentTertiaryContainer': 'تعبئة التمييز الثالثي',
    'skinTokenAccentTertiaryContainerHint':
        'التعبئة خلف عناصر التمييز الثالثية.',
    'skinTokenAccentOnTertiaryContainer': 'نص تعبئة التمييز الثالثي',
    'skinTokenAccentOnTertiaryContainerHint':
        'النص والأيقونات على تعبئة التمييز الثالثي.',
    'skinTokenStatusDanger': 'الأخطاء والحذف',
    'skinTokenStatusDangerHint':
        'نصوص الأخطاء، وإجراءات الحذف، وحدود الأخطاء.',
    'skinTokenStatusOnDanger': 'النص على لون الخطأ',
    'skinTokenStatusOnDangerHint':
        'النص والأيقونات المعروضة على لون الخطأ.',
    'skinTokenStatusDangerContainer': 'تعبئة رسالة الخطأ',
    'skinTokenStatusDangerContainerHint': 'تعبئة رسائل الأخطاء واللافتات.',
    'skinTokenStatusOnDangerContainer': 'نص رسالة الخطأ',
    'skinTokenStatusOnDangerContainerHint': 'النص والأيقونات في رسائل الأخطاء.',
    'skinTokenStatusInfo': 'تعبئة رسالة المعلومات',
    'skinTokenStatusInfoHint': 'تعبئة لافتات المعلومات.',
    'skinTokenStatusOnInfo': 'نص رسالة المعلومات',
    'skinTokenStatusOnInfoHint': 'النص والأيقونات في لافتات المعلومات.',
  },
  'de': {
    'skinTokenGroupAccent': 'Akzentfarben',
    'skinTokenGroupStatus': 'Status und Fehler',
    'skinTokenSurfacePanel': 'Bedienfelder',
    'skinTokenSurfacePanelHint':
        'Karten aus dem Standard-Karten-Widget, Lesezeichenleiste, Rasterzellen und Info-Sheets.',
    'skinTokenChromeBar': 'Leisten und Tab-Leisten',
    'skinTokenChromeBarHint':
        'Aktionsleisten, Tab-Leisten, Auswählleiste und untere Leisten.',
    'skinTokenAccentPrimary': 'Akzent',
    'skinTokenAccentPrimaryHint':
        'Hervorhebungen, Links im Text, kleine Akzentsymbole und Badges.',
    'skinTokenAccentSecondary': 'Sekundärer Akzent',
    'skinTokenAccentSecondaryHint': 'Sekundäre Hervorhebungen und Tags.',
    'skinTokenAccentTertiary': 'Tertiärer Akzent',
    'skinTokenAccentTertiaryHint': 'Tertiäre Hervorhebungen und Tags.',
    'skinTokenAccentTertiaryContainer': 'Tertiäre Akzentfüllung',
    'skinTokenAccentTertiaryContainerHint':
        'Füllung hinter tertiären Hervorhebungen.',
    'skinTokenAccentOnTertiaryContainer': 'Text auf tertiärer Akzentfüllung',
    'skinTokenAccentOnTertiaryContainerHint':
        'Text und Symbole auf der tertiären Füllung.',
    'skinTokenStatusDanger': 'Fehler und Löschen',
    'skinTokenStatusDangerHint':
        'Fehlertext, Löschaktionen und Fehlerränder.',
    'skinTokenStatusOnDanger': 'Text auf Fehlerfarbe',
    'skinTokenStatusOnDangerHint': 'Text und Symbole auf der Fehlerfarbe.',
    'skinTokenStatusDangerContainer': 'Füllung von Fehlermeldungen',
    'skinTokenStatusDangerContainerHint':
        'Füllung von Fehlermeldungen und Bannern.',
    'skinTokenStatusOnDangerContainer': 'Text von Fehlermeldungen',
    'skinTokenStatusOnDangerContainerHint':
        'Text und Symbole in Fehlermeldungen.',
    'skinTokenStatusInfo': 'Füllung von Infomeldungen',
    'skinTokenStatusInfoHint': 'Füllung von Info-Bannern.',
    'skinTokenStatusOnInfo': 'Text von Infomeldungen',
    'skinTokenStatusOnInfoHint': 'Text und Symbole in Info-Bannern.',
  },
  'es': {
    'skinTokenGroupAccent': 'Colores de énfasis',
    'skinTokenGroupStatus': 'Estado y errores',
    'skinTokenSurfacePanel': 'Paneles',
    'skinTokenSurfacePanelHint':
        'Tarjetas creadas con el widget de tarjeta estándar, barra de marcadores, celdas de cuadrícula y hojas de información.',
    'skinTokenChromeBar': 'Barras y tiras de pestañas',
    'skinTokenChromeBarHint':
        'Barras de acciones, tiras de pestañas, barra de selección y barras inferiores.',
    'skinTokenAccentPrimary': 'Énfasis',
    'skinTokenAccentPrimaryHint':
        'Destacados, enlaces en texto, iconos pequeños de énfasis y distintivos.',
    'skinTokenAccentSecondary': 'Énfasis secundario',
    'skinTokenAccentSecondaryHint': 'Destacados secundarios y etiquetas.',
    'skinTokenAccentTertiary': 'Énfasis terciario',
    'skinTokenAccentTertiaryHint': 'Destacados terciarios y etiquetas.',
    'skinTokenAccentTertiaryContainer': 'Relleno de énfasis terciario',
    'skinTokenAccentTertiaryContainerHint':
        'Relleno detrás de destacados terciarios.',
    'skinTokenAccentOnTertiaryContainer':
        'Texto de relleno de énfasis terciario',
    'skinTokenAccentOnTertiaryContainerHint':
        'Texto e iconos en el relleno terciario.',
    'skinTokenStatusDanger': 'Errores y eliminación',
    'skinTokenStatusDangerHint':
        'Texto de error, acciones de eliminación y bordes de error.',
    'skinTokenStatusOnDanger': 'Texto sobre color de error',
    'skinTokenStatusOnDangerHint':
        'Texto e iconos dibujados sobre el color de error.',
    'skinTokenStatusDangerContainer': 'Relleno de mensaje de error',
    'skinTokenStatusDangerContainerHint':
        'Relleno de mensajes de error y carteles.',
    'skinTokenStatusOnDangerContainer': 'Texto de mensaje de error',
    'skinTokenStatusOnDangerContainerHint':
        'Texto e iconos en mensajes de error.',
    'skinTokenStatusInfo': 'Relleno de mensaje de información',
    'skinTokenStatusInfoHint': 'Relleno de carteles informativos.',
    'skinTokenStatusOnInfo': 'Texto de mensaje de información',
    'skinTokenStatusOnInfoHint': 'Texto e iconos en carteles informativos.',
  },
  'fr': {
    'skinTokenGroupAccent': 'Couleurs d\'accentuation',
    'skinTokenGroupStatus': 'État et erreurs',
    'skinTokenSurfacePanel': 'Panneaux',
    'skinTokenSurfacePanelHint':
        'Cartes créées à partir du widget de carte standard, barre de favoris, cellules de grille et volets d\'informations.',
    'skinTokenChromeBar': 'Barres et onglets',
    'skinTokenChromeBarHint':
        'Barres d\'actions, barres d\'onglets, barre de sélection et barres inférieures.',
    'skinTokenAccentPrimary': 'Accentuation',
    'skinTokenAccentPrimaryHint':
        'Mises en évidence, liens dans le texte, petites icônes d\'accentuation et badges.',
    'skinTokenAccentSecondary': 'Accentuation secondaire',
    'skinTokenAccentSecondaryHint':
        'Mises en évidence secondaires et étiquettes.',
    'skinTokenAccentTertiary': 'Accentuation tertiaire',
    'skinTokenAccentTertiaryHint':
        'Mises en évidence tertiaires et étiquettes.',
    'skinTokenAccentTertiaryContainer':
        'Remplissage d\'accentuation tertiaire',
    'skinTokenAccentTertiaryContainerHint':
        'Remplissage derrière les mises en évidence tertiaires.',
    'skinTokenAccentOnTertiaryContainer':
        'Texte sur remplissage d\'accentuation tertiaire',
    'skinTokenAccentOnTertiaryContainerHint':
        'Texte et icônes sur le remplissage tertiaire.',
    'skinTokenStatusDanger': 'Erreurs et suppression',
    'skinTokenStatusDangerHint':
        'Texte d\'erreur, actions de suppression et bordures d\'erreur.',
    'skinTokenStatusOnDanger': 'Texte sur couleur d\'erreur',
    'skinTokenStatusOnDangerHint':
        'Texte et icônes tracés sur la couleur d\'erreur.',
    'skinTokenStatusDangerContainer': 'Remplissage de message d\'erreur',
    'skinTokenStatusDangerContainerHint':
        'Remplissage des messages d\'erreur et des bannières.',
    'skinTokenStatusOnDangerContainer': 'Texte de message d\'erreur',
    'skinTokenStatusOnDangerContainerHint':
        'Texte et icônes dans les messages d\'erreur.',
    'skinTokenStatusInfo': 'Remplissage de message d\'information',
    'skinTokenStatusInfoHint': 'Remplissage des bannières d\'information.',
    'skinTokenStatusOnInfo': 'Texte de message d\'information',
    'skinTokenStatusOnInfoHint':
        'Texte et icônes dans les bannières d\'information.',
  },
  'it': {
    'skinTokenGroupAccent': 'Colori di accento',
    'skinTokenGroupStatus': 'Stato ed errori',
    'skinTokenSurfacePanel': 'Pannelli',
    'skinTokenSurfacePanelHint':
        'Schede create dal widget scheda standard, barra dei segnalibri, celle della griglia e fogli informativi.',
    'skinTokenChromeBar': 'Barre e schede',
    'skinTokenChromeBarHint':
        'Barre delle azioni, barre delle schede, barra di selezione e barre inferiori.',
    'skinTokenAccentPrimary': 'Accento',
    'skinTokenAccentPrimaryHint':
        'Elementi in risalto, collegamenti nel testo, piccole icone di accento e badge.',
    'skinTokenAccentSecondary': 'Accento secondario',
    'skinTokenAccentSecondaryHint': 'Elementi in risalto secondari ed etichette.',
    'skinTokenAccentTertiary': 'Accento terziario',
    'skinTokenAccentTertiaryHint': 'Elementi in risalto terziari ed etichette.',
    'skinTokenAccentTertiaryContainer': 'Riempimento accento terziario',
    'skinTokenAccentTertiaryContainerHint':
        'Riempimento dietro gli elementi in risalto terziari.',
    'skinTokenAccentOnTertiaryContainer':
        'Testo riempimento accento terziario',
    'skinTokenAccentOnTertiaryContainerHint':
        'Testo e icone sul riempimento terziario.',
    'skinTokenStatusDanger': 'Errori ed eliminazione',
    'skinTokenStatusDangerHint':
        'Testo di errore, azioni di eliminazione e bordi di errore.',
    'skinTokenStatusOnDanger': 'Testo su colore di errore',
    'skinTokenStatusOnDangerHint':
        'Testo e icone disegnati sul colore di errore.',
    'skinTokenStatusDangerContainer': 'Riempimento messaggio di errore',
    'skinTokenStatusDangerContainerHint':
        'Riempimento di messaggi di errore e banner.',
    'skinTokenStatusOnDangerContainer': 'Testo messaggio di errore',
    'skinTokenStatusOnDangerContainerHint':
        'Testo e icone nei messaggi di errore.',
    'skinTokenStatusInfo': 'Riempimento messaggio informativo',
    'skinTokenStatusInfoHint': 'Riempimento dei banner informativi.',
    'skinTokenStatusOnInfo': 'Testo messaggio informativo',
    'skinTokenStatusOnInfoHint': 'Testo e icone nei banner informativi.',
  },
  'ja': {
    'skinTokenGroupAccent': 'アクセントカラー',
    'skinTokenGroupStatus': 'ステータスとエラー',
    'skinTokenSurfacePanel': 'パネル',
    'skinTokenSurfacePanelHint':
        '標準カードウィジェット、ブックマークバー、グリッドセル、情報シート。',
    'skinTokenChromeBar': 'バーとタブストリップ',
    'skinTokenChromeBarHint':
        'アクションバー、タブストリップ、選択バー、下部バー。',
    'skinTokenAccentPrimary': 'アクセント',
    'skinTokenAccentPrimaryHint':
        'ハイライト、テキスト内のリンク、小さなアクセントアイコン、バッジ。',
    'skinTokenAccentSecondary': 'セカンダリアクセント',
    'skinTokenAccentSecondaryHint': 'セカンダリのハイライトとタグ。',
    'skinTokenAccentTertiary': 'ターシャリアクセント',
    'skinTokenAccentTertiaryHint': 'ターシャリのハイライトとタグ。',
    'skinTokenAccentTertiaryContainer': 'ターシャリアクセントの塗りつぶし',
    'skinTokenAccentTertiaryContainerHint':
        'ターシャリハイライトの背景の塗りつぶし。',
    'skinTokenAccentOnTertiaryContainer':
        'ターシャリアクセント塗りつぶしのテキスト',
    'skinTokenAccentOnTertiaryContainerHint':
        'ターシャリ塗りつぶし上のテキストとアイコン。',
    'skinTokenStatusDanger': 'エラーと削除',
    'skinTokenStatusDangerHint':
        'エラーテキスト、削除アクション、エラー枠線。',
    'skinTokenStatusOnDanger': 'エラーカラー上のテキスト',
    'skinTokenStatusOnDangerHint':
        'エラーカラー上に描画されるテキストとアイコン。',
    'skinTokenStatusDangerContainer': 'エラーメッセージの塗りつぶし',
    'skinTokenStatusDangerContainerHint':
        'エラーメッセージやバナーの塗りつぶし。',
    'skinTokenStatusOnDangerContainer': 'エラーメッセージのテキスト',
    'skinTokenStatusOnDangerContainerHint':
        'エラーメッセージ内のテキストとアイコン。',
    'skinTokenStatusInfo': '情報メッセージの塗りつぶし',
    'skinTokenStatusInfoHint': '情報バナーの塗りつぶし。',
    'skinTokenStatusOnInfo': '情報メッセージのテキスト',
    'skinTokenStatusOnInfoHint': '情報バナー内のテキストとアイコン。',
  },
  'ko': {
    'skinTokenGroupAccent': '강조 색상',
    'skinTokenGroupStatus': '상태 및 오류',
    'skinTokenSurfacePanel': '패널',
    'skinTokenSurfacePanelHint':
        '표준 카드 위젯, 북마크 바, 그리드 셀 및 정보 시트입니다.',
    'skinTokenChromeBar': '바 및 탭 스트립',
    'skinTokenChromeBarHint':
        '작업 표시줄, 탭 스트립, 선택 바 및 하단 바입니다.',
    'skinTokenAccentPrimary': '강조',
    'skinTokenAccentPrimaryHint':
        '하이라이트, 본문 내 링크, 작은 강조 아이콘 및 배지입니다.',
    'skinTokenAccentSecondary': '보조 강조',
    'skinTokenAccentSecondaryHint': '보조 하이라이트 및 태그입니다.',
    'skinTokenAccentTertiary': '3차 강조',
    'skinTokenAccentTertiaryHint': '3차 하이라이트 및 태그입니다.',
    'skinTokenAccentTertiaryContainer': '3차 강조 채우기',
    'skinTokenAccentTertiaryContainerHint':
        '3차 하이라이트 배경의 채우기 색상입니다.',
    'skinTokenAccentOnTertiaryContainer': '3차 강조 채우기 텍스트',
    'skinTokenAccentOnTertiaryContainerHint':
        '3차 채우기 위의 텍스트와 아이콘입니다.',
    'skinTokenStatusDanger': '오류 및 삭제',
    'skinTokenStatusDangerHint': '오류 텍스트, 삭제 작업 및 오류 테두리입니다.',
    'skinTokenStatusOnDanger': '오류 색상 위 텍스트',
    'skinTokenStatusOnDangerHint':
        '오류 색상 위에 표시되는 텍스트와 아이콘입니다.',
    'skinTokenStatusDangerContainer': '오류 메시지 채우기',
    'skinTokenStatusDangerContainerHint':
        '오류 메시지 및 배너의 채우기 색상입니다.',
    'skinTokenStatusOnDangerContainer': '오류 메시지 텍스트',
    'skinTokenStatusOnDangerContainerHint':
        '오류 메시지 내의 텍스트와 아이콘입니다.',
    'skinTokenStatusInfo': '안내 메시지 채우기',
    'skinTokenStatusInfoHint': '안내 배너의 채우기 색상입니다.',
    'skinTokenStatusOnInfo': '안내 메시지 텍스트',
    'skinTokenStatusOnInfoHint': '안내 배너 내의 텍스트와 아이콘입니다.',
  },
  'pt': {
    'skinTokenGroupAccent': 'Cores de destaque',
    'skinTokenGroupStatus': 'Status e erros',
    'skinTokenSurfacePanel': 'Painéis',
    'skinTokenSurfacePanelHint':
        'Cartões criados a partir do widget de cartão padrão, barra de favoritos, células de grade e painéis informativos.',
    'skinTokenChromeBar': 'Barras e abas',
    'skinTokenChromeBarHint':
        'Barras de ação, barras de abas, barra de seleção e barras inferiores.',
    'skinTokenAccentPrimary': 'Destaque',
    'skinTokenAccentPrimaryHint':
        'Destaques, links em texto, pequenos ícones de destaque e emblemas.',
    'skinTokenAccentSecondary': 'Destaque secundário',
    'skinTokenAccentSecondaryHint': 'Destaques secundários e etiquetas.',
    'skinTokenAccentTertiary': 'Destaque terciário',
    'skinTokenAccentTertiaryHint': 'Destaques terciários e etiquetas.',
    'skinTokenAccentTertiaryContainer': 'Preenchimento de destaque terciário',
    'skinTokenAccentTertiaryContainerHint':
        'Preenchimento atrás de destaques terciários.',
    'skinTokenAccentOnTertiaryContainer':
        'Texto do preenchimento de destaque terciário',
    'skinTokenAccentOnTertiaryContainerHint':
        'Texto e ícones no preenchimento terciário.',
    'skinTokenStatusDanger': 'Erros e exclusão',
    'skinTokenStatusDangerHint':
        'Texto de erro, ações de exclusão e bordas de erro.',
    'skinTokenStatusOnDanger': 'Texto na cor de erro',
    'skinTokenStatusOnDangerHint': 'Texto e ícones sobre a cor de erro.',
    'skinTokenStatusDangerContainer': 'Preenchimento de mensagem de erro',
    'skinTokenStatusDangerContainerHint':
        'Preenchimento de mensagens de erro e banners.',
    'skinTokenStatusOnDangerContainer': 'Texto da mensagem de erro',
    'skinTokenStatusOnDangerContainerHint':
        'Texto e ícones em mensagens de erro.',
    'skinTokenStatusInfo': 'Preenchimento de mensagem informativa',
    'skinTokenStatusInfoHint': 'Preenchimento de banners informativos.',
    'skinTokenStatusOnInfo': 'Texto da mensagem informativa',
    'skinTokenStatusOnInfoHint':
        'Texto e ícones em banners informativos.',
  },
  'uk': {
    'skinTokenGroupAccent': 'Акцентні кольори',
    'skinTokenGroupStatus': 'Стан та помилки',
    'skinTokenSurfacePanel': 'Панелі',
    'skinTokenSurfacePanelHint':
        'Картки зі стандартного віджета карток, панель закладок, клітинки сітки та інформаційні панелі.',
    'skinTokenChromeBar': 'Панелі та смуги вкладок',
    'skinTokenChromeBarHint':
        'Панелі дій, смуги вкладок, панель вибору та нижні панелі.',
    'skinTokenAccentPrimary': 'Акцент',
    'skinTokenAccentPrimaryHint':
        'Виділення, посилання в тексті, невеликі акцентні іконки та значки.',
    'skinTokenAccentSecondary': 'Вторинний акцент',
    'skinTokenAccentSecondaryHint': 'Вторинні виділення та теги.',
    'skinTokenAccentTertiary': 'Третинний акцент',
    'skinTokenAccentTertiaryHint': 'Третинні виділення та теги.',
    'skinTokenAccentTertiaryContainer': 'Заливка третинного акценту',
    'skinTokenAccentTertiaryContainerHint':
        'Заливка позаду третинних виділень.',
    'skinTokenAccentOnTertiaryContainer':
        'Текст заливки третинного акценту',
    'skinTokenAccentOnTertiaryContainerHint':
        'Текст та іконки на третинній заливці.',
    'skinTokenStatusDanger': 'Помилки та видалення',
    'skinTokenStatusDangerHint':
        'Текст помилки, дії видалення та межі помилок.',
    'skinTokenStatusOnDanger': 'Текст на кольорі помилки',
    'skinTokenStatusOnDangerHint':
        'Текст та іконки, відображені на кольорі помилки.',
    'skinTokenStatusDangerContainer': 'Заливка повідомлення про помилку',
    'skinTokenStatusDangerContainerHint':
        'Заливка повідомлень про помилки та банерів.',
    'skinTokenStatusOnDangerContainer': 'Текст повідомлення про помилку',
    'skinTokenStatusOnDangerContainerHint':
        'Текст та іконки в повідомленнях про помилки.',
    'skinTokenStatusInfo': 'Заливка інформаційного повідомлення',
    'skinTokenStatusInfoHint': 'Заливка інформаційних банерів.',
    'skinTokenStatusOnInfo': 'Текст інформаційного повідомлення',
    'skinTokenStatusOnInfoHint':
        'Текст та іконки в інформаційних банерах.',
  },
  'zh': {
    'skinTokenGroupAccent': '强调色',
    'skinTokenGroupStatus': '状态与错误',
    'skinTokenSurfacePanel': '面板',
    'skinTokenSurfacePanelHint':
        '由标准卡片小部件制成的卡片、书签栏、网格单元格和信息表。',
    'skinTokenChromeBar': '栏与标签条',
    'skinTokenChromeBarHint': '操作栏、标签条、选择栏和底部栏。',
    'skinTokenAccentPrimary': '强调',
    'skinTokenAccentPrimaryHint':
        '高亮、文本中的链接、微型强调图标和角标。',
    'skinTokenAccentSecondary': '次要强调',
    'skinTokenAccentSecondaryHint': '次要高亮和标签。',
    'skinTokenAccentTertiary': '三级强调',
    'skinTokenAccentTertiaryHint': '三级高亮和标签。',
    'skinTokenAccentTertiaryContainer': '三级强调填充',
    'skinTokenAccentTertiaryContainerHint': '三级高亮背后的填充色。',
    'skinTokenAccentOnTertiaryContainer': '三级强调填充文本',
    'skinTokenAccentOnTertiaryContainerHint':
        '三级填充上的文本与图标。',
    'skinTokenStatusDanger': '错误与删除',
    'skinTokenStatusDangerHint': '错误文本、删除操作和错误边框。',
    'skinTokenStatusOnDanger': '错误颜色上的文本',
    'skinTokenStatusOnDangerHint': '在错误颜色上绘制的文本与图标。',
    'skinTokenStatusDangerContainer': '错误信息填充',
    'skinTokenStatusDangerContainerHint': '错误信息和横幅的填充色。',
    'skinTokenStatusOnDangerContainer': '错误信息文本',
    'skinTokenStatusOnDangerContainerHint': '错误信息中的文本与图标。',
    'skinTokenStatusInfo': '提示信息填充',
    'skinTokenStatusInfoHint': '提示横幅的填充色。',
    'skinTokenStatusOnInfo': '提示信息文本',
    'skinTokenStatusOnInfoHint': '提示横幅中的文本与图标。',
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
    stderr.writeln(
        'Error: Main language file app_en.arb not found in ${l10nDir.path}');
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