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
  'dropImportOverlayLabel': 'Drop to import into this folder',
  '@dropImportOverlayLabel': {
    'description':
        'Desktop: text over the file browser while files are dragged in from the operating system\'s file manager and held over it',
  },
  'dropImportUnavailableHere': 'Files can only be dropped into a vault folder.',
  '@dropImportUnavailableHere': {
    'description':
        'Desktop: shown when files from the operating system are dropped on a place that cannot receive imports (a plain device folder or an archive being browsed)',
  },
  'dropImportSkippedItems':
      '{count, plural, =1{1 dropped item can’t be imported} other{{count} dropped items can’t be imported}}',
  '@dropImportSkippedItems': {
    'description':
        'Desktop: shown after files from the operating system were dropped on the file browser and some of them were left out (no longer there, not a file or folder, or the vault itself)',
    'placeholders': {
      'count': {'type': 'num'},
    },
  },
};

/// Add translations for each supported language here.
/// If a translation for a key is omitted, it falls back to the English value.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    'dropImportOverlayLabel': 'أفلت للاستيراد إلى هذا المجلد',
    'dropImportUnavailableHere': 'يمكن إفلات الملفات داخل مجلد في خزنة فقط.',
    'dropImportSkippedItems':
        '{count, plural, zero{لا يمكن استيراد أي عناصر تم إفلاتها} one{لا يمكن استيراد عنصر واحد تم إفلاته} two{لا يمكن استيراد عنصرين تم إفلاتهما} few{لا يمكن استيراد {count} عناصر تم إفلاتها} many{لا يمكن استيراد {count} عنصرًا تم إفلاته} other{لا يمكن استيراد {count} عنصر تم إفلاته}}',
  },
  'de': {
    'dropImportOverlayLabel': 'Zum Importieren in diesen Ordner ablegen',
    'dropImportUnavailableHere':
        'Dateien können nur in einen Tresorordner gezogen werden.',
    'dropImportSkippedItems':
        '{count, plural, =1{1 abgelegtes Element kann nicht importiert werden} other{{count} abgelegte Elemente können nicht importiert werden}}',
  },
  'es': {
    'dropImportOverlayLabel': 'Suelta para importar en esta carpeta',
    'dropImportUnavailableHere':
        'Los archivos solo se pueden soltar en una carpeta de una bóveda.',
    'dropImportSkippedItems':
        '{count, plural, =1{No se puede importar 1 elemento soltado} other{No se pueden importar {count} elementos soltados}}',
  },
  'fr': {
    'dropImportOverlayLabel': 'Déposez pour importer dans ce dossier',
    'dropImportUnavailableHere':
        'Les fichiers ne peuvent être déposés que dans un dossier d’un coffre.',
    'dropImportSkippedItems':
        '{count, plural, =1{1 élément déposé ne peut pas être importé} other{{count} éléments déposés ne peuvent pas être importés}}',
  },
  'it': {
    'dropImportOverlayLabel': 'Rilascia per importare in questa cartella',
    'dropImportUnavailableHere':
        'I file possono essere rilasciati solo in una cartella di un vault.',
    'dropImportSkippedItems':
        '{count, plural, =1{1 elemento rilasciato non può essere importato} other{{count} elementi rilasciati non possono essere importati}}',
  },
  'ja': {
    'dropImportOverlayLabel': 'ドロップしてこのフォルダにインポート',
    'dropImportUnavailableHere': 'ファイルは保管庫内のフォルダにのみドロップできます。',
    'dropImportSkippedItems':
        '{count, plural, other{ドロップされた{count}件の項目はインポートできません}}',
  },
  'ko': {
    'dropImportOverlayLabel': '여기에 놓아 이 폴더로 가져오기',
    'dropImportUnavailableHere': '파일은 볼트 폴더에만 놓을 수 있습니다.',
    'dropImportSkippedItems':
        '{count, plural, other{놓은 항목 {count}개를 가져올 수 없습니다}}',
  },
  'pt': {
    'dropImportOverlayLabel': 'Solte para importar para esta pasta',
    'dropImportUnavailableHere':
        'Os arquivos só podem ser soltos em uma pasta de um cofre.',
    'dropImportSkippedItems':
        '{count, plural, =1{1 item solto não pode ser importado} other{{count} itens soltos não podem ser importados}}',
  },
  'tr': {
    'dropImportOverlayLabel': 'Bu klasöre içe aktarmak için bırakın',
    'dropImportUnavailableHere':
        'Dosyalar yalnızca bir kasa klasörüne bırakılabilir.',
    'dropImportSkippedItems':
        '{count, plural, =1{Bırakılan 1 öğe içe aktarılamıyor} other{Bırakılan {count} öğe içe aktarılamıyor}}',
  },
  'uk': {
    'dropImportOverlayLabel': 'Відпустіть, щоб імпортувати в цю папку',
    'dropImportUnavailableHere':
        'Файли можна перетягувати лише до папки сховища.',
    'dropImportSkippedItems':
        '{count, plural, one{{count} перетягнутий елемент не можна імпортувати} few{{count} перетягнуті елементи не можна імпортувати} many{{count} перетягнутих елементів не можна імпортувати} other{{count} перетягнутих елементів не можна імпортувати}}',
  },
  'zh': {
    'dropImportOverlayLabel': '松开以导入到此文件夹',
    'dropImportUnavailableHere': '只能将文件拖放到保险库文件夹中。',
    'dropImportSkippedItems':
        '{count, plural, other{有 {count} 个拖入的项目无法导入}}',
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
