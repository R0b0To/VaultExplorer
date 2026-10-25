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
  'skinEditDockTop': "Move panel to the top",
  '@skinEditDockTop': {'description': "Tooltip of the button that docks the floating skin editor panel to the top of the screen."},
  'skinEditDockBottom': "Move panel to the bottom",
  '@skinEditDockBottom': {'description': "Tooltip of the button that docks the floating skin editor panel to the bottom of the screen."},
  'skinEditEditorIndependent': "The text editor uses its own colors, so changes here will not show in it until it follows the app skin.",
  '@skinEditEditorIndependent': {'description': "Note shown when a text editor color is picked while the editor does not follow the app skin."},
};

/// Add translations for each supported language here.
/// If a translation for a key is omitted, it falls back to the English value.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    'skinEditDockTop': "نقل اللوحة إلى الأعلى",
    'skinEditDockBottom': "نقل اللوحة إلى الأسفل",
    'skinEditEditorIndependent': "يستخدم محرر النصوص ألوانه الخاصة، لذا لن تظهر التغييرات هنا فيه حتى يتبع المظهر التطبيق.",
  },
  'de': {
    'skinEditDockTop': "Bereich nach oben verschieben",
    'skinEditDockBottom': "Bereich nach unten verschieben",
    'skinEditEditorIndependent': "Der Texteditor verwendet eigene Farben, daher erscheinen Änderungen hier erst, wenn er dem App-Skin folgt.",
  },
  'es': {
    'skinEditDockTop': "Mover panel arriba",
    'skinEditDockBottom': "Mover panel abajo",
    'skinEditEditorIndependent': "El editor de texto usa sus propios colores, así que los cambios no se verán en él hasta que siga el aspecto de la app.",
  },
  'fr': {
    'skinEditDockTop': "Placer le panneau en haut",
    'skinEditDockBottom': "Placer le panneau en bas",
    'skinEditEditorIndependent': "L'éditeur de texte utilise ses propres couleurs ; les changements n'y apparaîtront qu'une fois qu'il suit le thème de l'app.",
  },
  'it': {
    'skinEditDockTop': "Sposta il pannello in alto",
    'skinEditDockBottom': "Sposta il pannello in basso",
    'skinEditEditorIndependent': "L'editor di testo usa colori propri, quindi le modifiche non vi compariranno finché non segue la skin dell'app.",
  },
  'ja': {
    'skinEditDockTop': "パネルを上に移動",
    'skinEditDockBottom': "パネルを下に移動",
    'skinEditEditorIndependent': "テキストエディターは独自の色を使っているため、アプリのスキンに従うよう設定するまで、ここでの変更は反映されません。",
  },
  'ko': {
    'skinEditDockTop': "패널을 위로 이동",
    'skinEditDockBottom': "패널을 아래로 이동",
    'skinEditEditorIndependent': "텍스트 편집기는 자체 색상을 사용하므로 앱 스킨을 따르도록 설정하기 전에는 여기서 바꾼 색이 적용되지 않습니다.",
  },
  'pt': {
    'skinEditDockTop': "Mover painel para cima",
    'skinEditDockBottom': "Mover painel para baixo",
    'skinEditEditorIndependent': "O editor de texto usa cores próprias, então as alterações não aparecerão nele até que siga a skin do app.",
  },
  'uk': {
    'skinEditDockTop': "Перемістити панель угору",
    'skinEditDockBottom': "Перемістити панель униз",
    'skinEditEditorIndependent': "Текстовий редактор використовує власні кольори, тож зміни тут не з’являться в ньому, доки він не почне наслідувати тему застосунку.",
  },
  'zh': {
    'skinEditDockTop': "将面板移到顶部",
    'skinEditDockBottom': "将面板移到底部",
    'skinEditEditorIndependent': "文本编辑器使用自己的颜色，因此在它跟随应用皮肤之前，这里的更改不会显示在其中。",
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