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
  'apkOpenPackageInstaller': 'Package installer',
  '@apkOpenPackageInstaller': {
    'description':
        'Choice label in the APK open dialog (and the file-associations list in settings): hand the .apk to the Android package installer',
  },
  'apkOpenPackageInstallerSubtitle': 'Install this app on your device',
  '@apkOpenPackageInstallerSubtitle': {
    'description':
        'Subtitle under the "Package installer" choice in the APK open dialog',
  },
  'apkOpenAsZip': 'Open as ZIP',
  '@apkOpenAsZip': {
    'description':
        'Choice label in the APK open dialog (and the file-associations list in settings): browse the .apk as a ZIP archive',
  },
  'apkOpenAsZipSubtitle': 'Browse the files inside and extract them',
  '@apkOpenAsZipSubtitle': {
    'description':
        'Subtitle under the "Open as ZIP" choice in the APK open dialog',
  },
  'skinEditorPanelBackground': 'Editor panel background',
  '@skinEditorPanelBackground': {
    'description':
        'Custom skin color used behind the text editor sidebar and More Actions menu',
  },
  'skinEditorPanelBackgroundDescription':
      'Shared background for the editor sidebar and More Actions menus.',
  'skinFollowAppSkin': 'Follow app skin',
  'fileSkinFollowAppSkinDescription':
      'File and folder styling follows the selected app skin.',
  'fileSkinUseIndependentStylesDescription':
      'Use the file manager icon and color choices below.',
  'skinChooseOrCreateSkin': 'Choose or create a skin',
  'skinSkinShortcutCustomDescription':
      'Edit app-wide colors and shared tokens. Component overrides stay on this page.',
  'skinSkinShortcutPresetDescription':
      'Browse built-in skins or create a custom skin from this look.',
  'textEditorUseIndependentAppearanceDescription':
      'Choose an independent editor background and syntax theme below.',
  'fileSkinComponentStyling': 'Component styling',
  'textEditorStyling': 'Editor styling',
};

/// Add translations for each supported language here.
/// If a translation for a key is omitted, it falls back to the English value.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    'apkOpenPackageInstaller': 'مُثبّت الحزم',
    'apkOpenPackageInstallerSubtitle': 'ثبّت هذا التطبيق على جهازك',
    'apkOpenAsZip': 'فتح كملف ZIP',
    'apkOpenAsZipSubtitle': 'تصفّح الملفات بداخله واستخراجها',
    'skinEditorPanelBackground': 'خلفية لوحات المحرر',
    'skinEditorPanelBackgroundDescription':
        'خلفية مشتركة للشريط الجانبي وقوائم المزيد من الإجراءات في المحرر.',
    'skinFollowAppSkin': 'اتباع مظهر التطبيق',
    'fileSkinFollowAppSkinDescription':
        'يتبع تنسيق الملفات والمجلدات مظهر التطبيق المحدد.',
    'fileSkinUseIndependentStylesDescription':
        'استخدم خيارات الأيقونات والألوان لمدير الملفات أدناه.',
    'skinChooseOrCreateSkin': 'اختر مظهرًا أو أنشئه',
    'skinSkinShortcutCustomDescription':
        'عدّل ألوان التطبيق ورموزه المشتركة. تبقى تخصيصات المكوّنات في هذه الصفحة.',
    'skinSkinShortcutPresetDescription':
        'تصفّح المظاهر المضمنة أو أنشئ مظهرًا مخصصًا من هذا التصميم.',
    'textEditorUseIndependentAppearanceDescription':
        'اختر خلفية مستقلة للمحرر وقالب تمييز الصياغة أدناه.',
    'fileSkinComponentStyling': 'تنسيق المكوّنات',
    'textEditorStyling': 'تنسيق المحرر',
  },
  'de': {
    'apkOpenPackageInstaller': 'Paketinstaller',
    'apkOpenPackageInstallerSubtitle': 'Diese App auf dem Gerät installieren',
    'apkOpenAsZip': 'Als ZIP öffnen',
    'apkOpenAsZipSubtitle': 'Enthaltene Dateien durchsuchen und extrahieren',
    'skinEditorPanelBackground': 'Hintergrund der Editorbereiche',
    'skinEditorPanelBackgroundDescription':
        'Gemeinsamer Hintergrund für die Editor-Seitenleiste und das Menü „Weitere Aktionen“.',
    'skinFollowAppSkin': 'App-Design übernehmen',
    'fileSkinFollowAppSkinDescription':
        'Datei- und Ordnerdarstellung folgt dem ausgewählten App-Design.',
    'fileSkinUseIndependentStylesDescription':
        'Verwende die folgenden Symbol- und Farboptionen des Dateimanagers.',
    'skinChooseOrCreateSkin': 'Design auswählen oder erstellen',
    'skinSkinShortcutCustomDescription':
        'App-weite Farben und gemeinsame Tokens bearbeiten. Komponentenüberschreibungen bleiben auf dieser Seite.',
    'skinSkinShortcutPresetDescription':
        'Integrierte Designs ansehen oder ein eigenes Design aus diesem Look erstellen.',
    'textEditorUseIndependentAppearanceDescription':
        'Wähle unten einen unabhängigen Editorhintergrund und ein Syntaxdesign.',
    'fileSkinComponentStyling': 'Komponentenstil',
    'textEditorStyling': 'Editorstil',
  },
  'es': {
    'apkOpenPackageInstaller': 'Instalador de paquetes',
    'apkOpenPackageInstallerSubtitle': 'Instalar esta app en tu dispositivo',
    'apkOpenAsZip': 'Abrir como ZIP',
    'apkOpenAsZipSubtitle': 'Explorar los archivos que contiene y extraerlos',
    'skinEditorPanelBackground': 'Fondo de los paneles del editor',
    'skinEditorPanelBackgroundDescription':
        'Fondo compartido de la barra lateral y los menús de más acciones del editor.',
    'skinFollowAppSkin': 'Seguir el tema de la app',
    'fileSkinFollowAppSkinDescription':
        'El estilo de archivos y carpetas sigue el tema seleccionado de la app.',
    'fileSkinUseIndependentStylesDescription':
        'Usa las opciones de iconos y colores del gestor de archivos que aparecen abajo.',
    'skinChooseOrCreateSkin': 'Elegir o crear un tema',
    'skinSkinShortcutCustomDescription':
        'Edita los colores y tokens compartidos de la app. Los ajustes del componente permanecen en esta página.',
    'skinSkinShortcutPresetDescription':
        'Explora los temas incluidos o crea uno personalizado a partir de este aspecto.',
    'textEditorUseIndependentAppearanceDescription':
        'Elige abajo un fondo y un tema de sintaxis independientes para el editor.',
    'fileSkinComponentStyling': 'Estilo de los componentes',
    'textEditorStyling': 'Estilo del editor',
  },
  'fr': {
    'apkOpenPackageInstaller': 'Installateur de paquets',
    'apkOpenPackageInstallerSubtitle':
        'Installer cette application sur votre appareil',
    'apkOpenAsZip': 'Ouvrir comme ZIP',
    'apkOpenAsZipSubtitle':
        'Parcourir les fichiers qu’il contient et les extraire',
    'skinEditorPanelBackground': 'Arrière-plan des panneaux de l’éditeur',
    'skinEditorPanelBackgroundDescription':
        'Arrière-plan commun de la barre latérale et du menu d’actions de l’éditeur.',
    'skinFollowAppSkin': 'Suivre le thème de l’application',
    'fileSkinFollowAppSkinDescription':
        'L’apparence des fichiers et dossiers suit le thème sélectionné.',
    'fileSkinUseIndependentStylesDescription':
        'Utilisez les options d’icônes et de couleurs du gestionnaire de fichiers ci-dessous.',
    'skinChooseOrCreateSkin': 'Choisir ou créer un thème',
    'skinSkinShortcutCustomDescription':
        'Modifiez les couleurs et tokens partagés de l’application. Les réglages du composant restent sur cette page.',
    'skinSkinShortcutPresetDescription':
        'Parcourez les thèmes intégrés ou créez un thème personnalisé à partir de cette apparence.',
    'textEditorUseIndependentAppearanceDescription':
        'Choisissez ci-dessous un arrière-plan et un thème de syntaxe indépendants pour l’éditeur.',
    'fileSkinComponentStyling': 'Style des composants',
    'textEditorStyling': 'Style de l’éditeur',
  },
  'it': {
    'apkOpenPackageInstaller': 'Programma di installazione pacchetti',
    'apkOpenPackageInstallerSubtitle': 'Installa questa app sul dispositivo',
    'apkOpenAsZip': 'Apri come ZIP',
    'apkOpenAsZipSubtitle': 'Sfoglia i file contenuti ed estraili',
    'skinEditorPanelBackground': 'Sfondo dei pannelli dell’editor',
    'skinEditorPanelBackgroundDescription':
        'Sfondo condiviso per la barra laterale e il menu Altre azioni dell’editor.',
    'skinFollowAppSkin': 'Segui il tema dell’app',
    'fileSkinFollowAppSkinDescription':
        'Lo stile di file e cartelle segue il tema selezionato dell’app.',
    'fileSkinUseIndependentStylesDescription':
        'Usa le opzioni di icone e colori del file manager qui sotto.',
    'skinChooseOrCreateSkin': 'Scegli o crea un tema',
    'skinSkinShortcutCustomDescription':
        'Modifica colori e token condivisi dell’app. Le personalizzazioni del componente restano in questa pagina.',
    'skinSkinShortcutPresetDescription':
        'Esplora i temi integrati o creane uno personalizzato partendo da questo aspetto.',
    'textEditorUseIndependentAppearanceDescription':
        'Scegli qui sotto uno sfondo e un tema di sintassi indipendenti per l’editor.',
    'fileSkinComponentStyling': 'Stile dei componenti',
    'textEditorStyling': 'Stile dell’editor',
  },
  'ja': {
    'apkOpenPackageInstaller': 'パッケージインストーラー',
    'apkOpenPackageInstallerSubtitle': 'このアプリを端末にインストールします',
    'apkOpenAsZip': 'ZIPとして開く',
    'apkOpenAsZipSubtitle': '中のファイルを参照して展開します',
    'skinEditorPanelBackground': 'エディターパネルの背景',
    'skinEditorPanelBackgroundDescription':
        'エディターのサイドバーとその他のアクションメニューで共有する背景です。',
    'skinFollowAppSkin': 'アプリのスキンに合わせる',
    'fileSkinFollowAppSkinDescription': 'ファイルとフォルダーのスタイルを選択中のアプリスキンに合わせます。',
    'fileSkinUseIndependentStylesDescription': '以下のファイルマネージャーのアイコンと色の設定を使います。',
    'skinChooseOrCreateSkin': 'スキンを選択または作成',
    'skinSkinShortcutCustomDescription':
        'アプリ全体の色と共通トークンを編集します。コンポーネント固有の設定はこのページに残ります。',
    'skinSkinShortcutPresetDescription': '内蔵スキンを確認するか、現在の外観からカスタムスキンを作成します。',
    'textEditorUseIndependentAppearanceDescription':
        '以下でエディター専用の背景色と構文テーマを選択します。',
    'fileSkinComponentStyling': 'コンポーネントのスタイル',
    'textEditorStyling': 'エディターのスタイル',
  },
  'ko': {
    'apkOpenPackageInstaller': '패키지 설치 프로그램',
    'apkOpenPackageInstallerSubtitle': '이 앱을 기기에 설치합니다',
    'apkOpenAsZip': 'ZIP으로 열기',
    'apkOpenAsZipSubtitle': '내부 파일을 둘러보고 압축을 풉니다',
    'skinEditorPanelBackground': '편집기 패널 배경',
    'skinEditorPanelBackgroundDescription':
        '편집기 사이드바와 더보기 작업 메뉴에서 함께 사용하는 배경입니다.',
    'skinFollowAppSkin': '앱 스킨 따르기',
    'fileSkinFollowAppSkinDescription': '파일과 폴더 스타일이 선택한 앱 스킨을 따릅니다.',
    'fileSkinUseIndependentStylesDescription': '아래의 파일 관리자 아이콘 및 색상 옵션을 사용합니다.',
    'skinChooseOrCreateSkin': '스킨 선택 또는 만들기',
    'skinSkinShortcutCustomDescription':
        '앱 전체 색상과 공통 토큰을 편집합니다. 구성 요소별 설정은 이 페이지에 유지됩니다.',
    'skinSkinShortcutPresetDescription':
        '기본 제공 스킨을 둘러보거나 현재 모습으로 사용자 지정 스킨을 만듭니다.',
    'textEditorUseIndependentAppearanceDescription':
        '아래에서 편집기 전용 배경과 구문 테마를 선택합니다.',
    'fileSkinComponentStyling': '구성 요소 스타일',
    'textEditorStyling': '편집기 스타일',
  },
  'pt': {
    'apkOpenPackageInstaller': 'Instalador de pacotes',
    'apkOpenPackageInstallerSubtitle': 'Instalar este app no seu dispositivo',
    'apkOpenAsZip': 'Abrir como ZIP',
    'apkOpenAsZipSubtitle': 'Explorar os arquivos internos e extraí-los',
    'skinEditorPanelBackground': 'Fundo dos painéis do editor',
    'skinEditorPanelBackgroundDescription':
        'Fundo compartilhado da barra lateral e do menu Mais ações do editor.',
    'skinFollowAppSkin': 'Seguir o tema do app',
    'fileSkinFollowAppSkinDescription':
        'O estilo de arquivos e pastas segue o tema selecionado do app.',
    'fileSkinUseIndependentStylesDescription':
        'Use as opções de ícones e cores do gerenciador de arquivos abaixo.',
    'skinChooseOrCreateSkin': 'Escolher ou criar um tema',
    'skinSkinShortcutCustomDescription':
        'Edite cores e tokens compartilhados do app. As substituições do componente ficam nesta página.',
    'skinSkinShortcutPresetDescription':
        'Explore os temas integrados ou crie um tema personalizado a partir deste visual.',
    'textEditorUseIndependentAppearanceDescription':
        'Escolha abaixo um fundo e um tema de sintaxe independentes para o editor.',
    'fileSkinComponentStyling': 'Estilo dos componentes',
    'textEditorStyling': 'Estilo do editor',
  },
  'uk': {
    'apkOpenPackageInstaller': 'Інсталятор пакетів',
    'apkOpenPackageInstallerSubtitle': 'Встановити цю програму на пристрій',
    'apkOpenAsZip': 'Відкрити як ZIP',
    'apkOpenAsZipSubtitle': 'Переглянути вміст і видобути файли',
    'skinEditorPanelBackground': 'Тло панелей редактора',
    'skinEditorPanelBackgroundDescription':
        'Спільне тло бічної панелі та меню додаткових дій редактора.',
    'skinFollowAppSkin': 'Використовувати тему програми',
    'fileSkinFollowAppSkinDescription':
        'Стиль файлів і папок відповідає вибраній темі програми.',
    'fileSkinUseIndependentStylesDescription':
        'Використовуйте наведені нижче параметри значків і кольорів файлового менеджера.',
    'skinChooseOrCreateSkin': 'Вибрати або створити тему',
    'skinSkinShortcutCustomDescription':
        'Змініть спільні кольори й токени програми. Перевизначення компонентів залишаються на цій сторінці.',
    'skinSkinShortcutPresetDescription':
        'Перегляньте вбудовані теми або створіть власну на основі цього вигляду.',
    'textEditorUseIndependentAppearanceDescription':
        'Нижче виберіть окреме тло редактора та тему підсвічування синтаксису.',
    'fileSkinComponentStyling': 'Стиль компонентів',
    'textEditorStyling': 'Стиль редактора',
  },
  'zh': {
    'apkOpenPackageInstaller': '软件包安装程序',
    'apkOpenPackageInstallerSubtitle': '将此应用安装到你的设备',
    'apkOpenAsZip': '作为 ZIP 打开',
    'apkOpenAsZipSubtitle': '浏览其中的文件并解压',
    'skinEditorPanelBackground': '编辑器面板背景',
    'skinEditorPanelBackgroundDescription': '编辑器侧边栏和更多操作菜单共用的背景。',
    'skinFollowAppSkin': '跟随应用皮肤',
    'fileSkinFollowAppSkinDescription': '文件和文件夹样式跟随当前应用皮肤。',
    'fileSkinUseIndependentStylesDescription': '使用下方的文件管理器图标和颜色选项。',
    'skinChooseOrCreateSkin': '选择或创建皮肤',
    'skinSkinShortcutCustomDescription': '编辑应用全局颜色和共享标记。此页面上的组件覆盖设置会保留。',
    'skinSkinShortcutPresetDescription': '浏览内置皮肤，或根据当前外观创建自定义皮肤。',
    'textEditorUseIndependentAppearanceDescription': '在下方选择独立的编辑器背景和语法主题。',
    'fileSkinComponentStyling': '组件样式',
    'textEditorStyling': '编辑器样式',
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
      'Error: Main language file app_en.arb not found in ${l10nDir.path}',
    );
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
      if (entry.key.startsWith('@'))
        continue; // Metadata belongs only in app_en.arb
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
