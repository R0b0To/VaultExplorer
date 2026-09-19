// tool/update_l10n_keys.dart
import 'dart:convert';
import 'dart:io';

const Map<String, dynamic> enMetadataAndValues = {
  'contentsLabel': 'Contents',
  '@contentsLabel': {
    'description': 'Label for item count row in folder info sheet',
  },
  'totalSizeLabel': 'Total Size',
  '@totalSizeLabel': {
    'description': 'Label for total size row in folder info sheet',
  },
  'folderItemCount': '{count, plural, =0{Empty} =1{1 item} other{{count} items}}',
  '@folderItemCount': {
    'description': 'Formatted item count for folder contents',
    'placeholders': {
      'count': {
        'type': 'num',
      }
    }
  },
  'calculatingFolderStats': 'Calculating…',
  '@calculatingFolderStats': {
    'description': 'Placeholder text while scanning folder contents',
  },
};

const Map<String, Map<String, String>> localizedValues = {
  'it': {
    'contentsLabel': 'Contenuto',
    'totalSizeLabel': 'Dimensione totale',
    'folderItemCount': '{count, plural, =0{Vuota} =1{1 elemento} other{{count} elementi}}',
    'calculatingFolderStats': 'Calcolo in corso…',
  },
  'de': {
    'contentsLabel': 'Inhalt',
    'totalSizeLabel': 'Gesamtgröße',
    'folderItemCount': '{count, plural, =0{Leer} =1{1 Element} other{{count} Elemente}}',
    'calculatingFolderStats': 'Wird berechnet…',
  },
  'es': {
    'contentsLabel': 'Contenido',
    'totalSizeLabel': 'Tamaño total',
    'folderItemCount': '{count, plural, =0{Vacía} =1{1 elemento} other{{count} elementos}}',
    'calculatingFolderStats': 'Calculando…',
  },
  'fr': {
    'contentsLabel': 'Contenu',
    'totalSizeLabel': 'Taille totale',
    'folderItemCount': '{count, plural, =0{Vide} =1{1 élément} other{{count} éléments}}',
    'calculatingFolderStats': 'Calcul en cours…',
  },
  'ar': {
    'contentsLabel': 'المحتويات',
    'totalSizeLabel': 'الحجم الإجمالي',
    'folderItemCount': '{count, plural, =0{فارغ} =1{عنصر واحد} =2{عنصران} few{{count} عناصر} many{{count} عنصر} other{{count} عنصر}}',
    'calculatingFolderStats': 'جارٍ الحساب…',
  },
  'ja': {
    'contentsLabel': 'コンテンツ',
    'totalSizeLabel': '合計サイズ',
    'folderItemCount': '{count, plural, =0{空} other{{count}個の項目}}',
    'calculatingFolderStats': '計算中…',
  },
  'ko': {
    'contentsLabel': '콘텐츠',
    'totalSizeLabel': '총 크기',
    'folderItemCount': '{count, plural, =0{비어 있음} other{{count}개 항목}}',
    'calculatingFolderStats': '계산 중…',
  },
  'pt': {
    'contentsLabel': 'Conteúdo',
    'totalSizeLabel': 'Tamanho total',
    'folderItemCount': '{count, plural, =0{Vazio} =1{1 item} other{{count} itens}}',
    'calculatingFolderStats': 'Calculando…',
  },
  'uk': {
    'contentsLabel': 'Вміст',
    'totalSizeLabel': 'Загальний розмір',
    'folderItemCount': '{count, plural, =0{Порожньо} =1{1 елемент} few{{count} елементи} many{{count} елементів} other{{count} елементів}}',
    'calculatingFolderStats': 'Обчислення…',
  },
  'zh': {
    'contentsLabel': '内容',
    'totalSizeLabel': '总大小',
    'folderItemCount': '{count, plural, =0{空} other{{count} 个项目}}',
    'calculatingFolderStats': '正在计算…',
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

  print('\nARB files updated successfully.');
  print('Please run "flutter gen-l10n" to regenerate localization Dart bindings.');
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