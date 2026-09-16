// tool/update_l10n_keys.dart
import 'dart:convert';
import 'dart:io';

const Map<String, dynamic> enMetadataAndValues = {
 'useFabForToolbarLabel': 'Use floating button for toolbar',
  '@useFabForToolbarLabel': {
    'description': 'Label for option to collapse bottom toolbar actions into a floating action button',
  },
  'useFabForToolbarDesc': 'Replace the bottom bar with a single floating button for maximum viewing space',
  '@useFabForToolbarDesc': {
    'description': 'Description explaining that the bottom bar will be replaced by a floating button',
  },
};

const Map<String, Map<String, String>> localizedValues = {
  'it': {
    'useFabForToolbarLabel': 'Usa pulsante fluttuante per la barra',
    'useFabForToolbarDesc': 'Sostituisci la barra inferiore con un pulsante fluttuante per massimizzare lo spazio',
    // ...
  },
  'de': {
    'useFabForToolbarLabel': 'Schwebende Schaltfläche für Symbolleiste',
    'useFabForToolbarDesc': 'Untere Leiste durch eine schwebende Schaltfläche ersetzen, um Platz zu sparen',
    // ...
  },
  'es': {
    'useFabForToolbarLabel': 'Usar botón flotante para la barra',
    'useFabForToolbarDesc': 'Reemplazar la barra inferior con un botón flotante para maximizar el espacio',
    // ...
  },
  'fr': {
    'useFabForToolbarLabel': 'Bouton flottant pour la barre d’outils',
    'useFabForToolbarDesc': 'Remplacer la barre inférieure par un bouton flottant pour maximiser l’espace',
    // ...
  },
  'ar': {
    'useFabForToolbarLabel': 'استخدام زر عائم لشريط الأدوات',
    'useFabForToolbarDesc': 'استبدال الشريط السفلي بزر عائم لزيادة مساحة العرض إلى الحد الأقصى',
    // ...
  },
  'ja': {
    'useFabForToolbarLabel': 'ツールバーにフローティングボタンを使用',
    'useFabForToolbarDesc': '下部バーをフローティングボタンに置き換えて表示領域を最大化',
    // ...
  },
  'ko': {
    'useFabForToolbarLabel': '도구 모음에 플로팅 버튼 사용',
    'useFabForToolbarDesc': '하단 표시줄을 플로팅 버튼으로 대체하여 화면 공간 최대화',
    // ...
  },
  'pt': {
    'useFabForToolbarLabel': 'Usar botão flutuante para barra de ferramentas',
    'useFabForToolbarDesc': 'Substituir a barra inferior por um botão flutuante para maximizar o espaço',
    // ...
  },
  'uk': {
    'useFabForToolbarLabel': 'Плаваюча кнопка для панелі інструментів',
    'useFabForToolbarDesc': 'Замінити нижню панель плаваючою кнопкою для максимального простору',
    // ...
  },
  'zh': {
    'useFabForToolbarLabel': '使用浮动按钮作为工具栏',
    'useFabForToolbarDesc': '用单个浮动按钮替换底部工具栏以最大化查看空间',
    // ...
  },
};

void main() async {
  final l10nDir = _findL10nDirectory();
  if (l10nDir == null) {
    stderr.writeln('Could not find directory containing app_en.arb.');
    exit(1);
  }

  print('Targeting l10n directory: ${l10nDir.path}');

  // 1. Update main language: app_en.arb
  final enFile = File('${l10nDir.path}/app_en.arb');
  if (enFile.existsSync()) {
    _updateArb(enFile, enMetadataAndValues);
    print('Updated: app_en.arb');
  } else {
    stderr.writeln('Main language app_en.arb not found in ${l10nDir.path}');
    exit(1);
  }

  // 2. Update specific secondary languages: ar, de, es, fr, it, ja, ko, pt, uk, zh
  const targetLanguages = ['ar', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'pt', 'uk', 'zh'];
  for (final lang in targetLanguages) {
    final file = File('${l10nDir.path}/app_$lang.arb');
    if (!file.existsSync()) {
      print('Notice: app_$lang.arb does not exist at ${file.path}, skipping.');
      continue;
    }

    final translations = localizedValues[lang] ?? {};
    final Map<String, dynamic> toInsert = {};
    for (final entry in enMetadataAndValues.entries) {
      if (entry.key.startsWith('@')) continue; // Metadata only belongs in app_en.arb
      toInsert[entry.key] = translations[entry.key] ?? entry.value;
    }

    _updateArb(file, toInsert);
    print('Updated: app_$lang.arb');
  }

  // 3. Update generated Dart classes if present
  final genDir = Directory('${l10nDir.path}/generated');
  if (genDir.existsSync()) {
    _patchGeneratedClasses(genDir, targetLanguages);
  }

  print('\nARB update complete.');
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

void _patchGeneratedClasses(Directory genDir, List<String> targetLanguages) {
  final baseFile = File('${genDir.path}/app_localizations.dart');
  if (!baseFile.existsSync()) return;

  var baseContent = baseFile.readAsStringSync();
  final newKeys = enMetadataAndValues.keys.where((k) => !k.startsWith('@')).toList();

  for (final key in newKeys) {
    if (!baseContent.contains('String get $key;')) {
      final getter = '\n  String get $key;\n}';
      baseContent = baseContent.replaceFirst(RegExp(r'\}\s*$'), getter);
    }
  }
  baseFile.writeAsStringSync(baseContent);
  print('Patched base AppLocalizations in ${baseFile.path}');

  for (final lang in ['en', ...targetLanguages]) {
    final file = File('${genDir.path}/app_localizations_$lang.dart');
    if (!file.existsSync()) continue;

    var content = file.readAsStringSync();
    for (final key in newKeys) {
      if (!content.contains('String get $key =>')) {
        final val = (lang == 'en')
            ? enMetadataAndValues[key]
            : (localizedValues[lang]?[key] ?? enMetadataAndValues[key]);
        final escaped = (val as String).replaceAll("'", r"\'");
        final override = "\n  @override\n  String get $key => '$escaped';\n}";
        content = content.replaceFirst(RegExp(r'\}\s*$'), override);
      }
    }
    file.writeAsStringSync(content);
    print('Patched generated class: app_localizations_$lang.dart');
  }
}