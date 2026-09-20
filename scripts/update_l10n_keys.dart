// tool/update_l10n_keys.dart
import 'dart:convert';
import 'dart:io';

const Map<String, dynamic> enMetadataAndValues = {
  'cardSwipeActionsTitle': 'Card Swipe Actions',
  '@cardSwipeActionsTitle': {
    'description': 'Settings toggle title to enable or disable card swipe gestures on the dashboard',
  },
  'cardSwipeActionsSubtitle': 'Swipe vault cards to quickly reveal edit and remove actions',
  '@cardSwipeActionsSubtitle': {
    'description': 'Settings toggle subtitle explaining card swipe actions on the dashboard',
  },
};

const Map<String, Map<String, String>> localizedValues = {
  'it': {
    'cardSwipeActionsTitle': 'Gesti di scorrimento delle schede',
    'cardSwipeActionsSubtitle': 'Scorri le schede dei vault per mostrare rapidamente le azioni di modifica e rimozione',
  },
  'de': {
    'cardSwipeActionsTitle': 'Karten-Wischgesten',
    'cardSwipeActionsSubtitle': 'Tresorkarten wischen, um Bearbeiten- und Entfernen-Aktionen schnell anzuzeigen',
  },
  'es': {
    'cardSwipeActionsTitle': 'Gestos de deslizamiento en tarjetas',
    'cardSwipeActionsSubtitle': 'Desliza las tarjetas de las bóvedas para mostrar rápidamente las acciones de editar y eliminar',
  },
  'fr': {
    'cardSwipeActionsTitle': 'Gestes de balayage des cartes',
    'cardSwipeActionsSubtitle': 'Faites glisser les cartes de coffre pour afficher rapidement les actions Modifier et Supprimer',
  },
  'ar': {
    'cardSwipeActionsTitle': 'إيماءات سحب البطاقات',
    'cardSwipeActionsSubtitle': 'اسحب بطاقات الخزائن لإظهار إجراءات التعديل والحذف بسرعة',
  },
  'ja': {
    'cardSwipeActionsTitle': 'カードのスワイプ操作',
    'cardSwipeActionsSubtitle': '保管庫カードをスワイプして編集および削除アクションをすばやく表示します',
  },
  'ko': {
    'cardSwipeActionsTitle': '카드 스와이프 제스처',
    'cardSwipeActionsSubtitle': '볼트 카드를 스와이프하여 편집 및 삭제 동작을 빠르게 표시합니다',
  },
  'pt': {
    'cardSwipeActionsTitle': 'Gestos de deslize nos cartões',
    'cardSwipeActionsSubtitle': 'Deslize os cartões de cofre para exibir rapidamente as ações de editar e remover',
  },
  'uk': {
    'cardSwipeActionsTitle': 'Жести змахування карток',
    'cardSwipeActionsSubtitle': 'Проведіть по картці сховища, щоб швидко відкрити дії редагування та видалення',
  },
  'zh': {
    'cardSwipeActionsTitle': '卡片滑动操作',
    'cardSwipeActionsSubtitle': '滑动保险库卡片以快速显示编辑和移除操作',
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