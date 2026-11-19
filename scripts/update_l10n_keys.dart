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
  'motionPhotoCopyNote':
      'The edited copy will be a still image. The original file, its EXIF metadata, and any embedded video remain unchanged.',
  '@motionPhotoCopyNote': {
    'description':
        'Notice shown when an image with protected metadata is edited: only a still-image copy can be saved; the original file and embedded content are protected.',
  },
};

/// Add translations for each supported language here.
/// If a translation for a key is omitted, it falls back to the English value.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    'motionPhotoCopyNote':
        'ستكون النسخة المعدلة صورة ثابتة. سيبقى الملف الأصلي وبيانات EXIF وأي فيديو مضمّن دون تغيير.',
  },
  'de': {
    'motionPhotoCopyNote':
        'Die bearbeitete Kopie ist ein Standbild. Die Originaldatei, ihre EXIF-Daten und eingebettete Videos bleiben unverändert.',
  },
  'es': {
    'motionPhotoCopyNote':
        'La copia editada será una imagen fija. El archivo original, sus datos EXIF y cualquier vídeo integrado permanecerán intactos.',
  },
  'fr': {
    'motionPhotoCopyNote':
        'La copie modifiée sera une image fixe. Le fichier d’origine, ses données EXIF et toute vidéo intégrée resteront intacts.',
  },
  'it': {
    'motionPhotoCopyNote':
        'La copia modificata sarà un’immagine statica. Il file originale, i dati EXIF e qualsiasi video incorporato resteranno invariati.',
  },
  'ja': {
    'motionPhotoCopyNote': '編集したコピーは静止画になります。元のファイル、EXIF情報、埋め込み動画は変更されません。',
  },
  'ko': {
    'motionPhotoCopyNote':
        '편집된 사본은 정지 이미지로 저장됩니다. 원본 파일, EXIF 정보 및 내장 동영상은 변경되지 않습니다.',
  },
  'pt': {
    'motionPhotoCopyNote':
        'A cópia editada será uma imagem estática. O arquivo original, os dados EXIF e qualquer vídeo incorporado permanecerão intactos.',
  },
  'uk': {
    'motionPhotoCopyNote':
        'Відредагована копія буде нерухомим зображенням. Оригінальний файл, дані EXIF і будь-яке вбудоване відео залишаться незмінними.',
  },
  'zh': {'motionPhotoCopyNote': '编辑后的副本将是静态图片。原始文件、EXIF 信息和任何嵌入的视频都将保持不变。'},
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
