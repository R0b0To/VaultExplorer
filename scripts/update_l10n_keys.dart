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
};

/// Add translations for each supported language here.
/// If a translation for a key is omitted, it falls back to the English value.
const Map<String, Map<String, String>> localizedValues = {
  'ar': {
    'apkOpenPackageInstaller': 'مُثبّت الحزم',
    'apkOpenPackageInstallerSubtitle': 'ثبّت هذا التطبيق على جهازك',
    'apkOpenAsZip': 'فتح كملف ZIP',
    'apkOpenAsZipSubtitle': 'تصفّح الملفات بداخله واستخراجها',
  },
  'de': {
    'apkOpenPackageInstaller': 'Paketinstaller',
    'apkOpenPackageInstallerSubtitle': 'Diese App auf dem Gerät installieren',
    'apkOpenAsZip': 'Als ZIP öffnen',
    'apkOpenAsZipSubtitle': 'Enthaltene Dateien durchsuchen und extrahieren',
  },
  'es': {
    'apkOpenPackageInstaller': 'Instalador de paquetes',
    'apkOpenPackageInstallerSubtitle': 'Instalar esta app en tu dispositivo',
    'apkOpenAsZip': 'Abrir como ZIP',
    'apkOpenAsZipSubtitle': 'Explorar los archivos que contiene y extraerlos',
  },
  'fr': {
    'apkOpenPackageInstaller': 'Installateur de paquets',
    'apkOpenPackageInstallerSubtitle': 'Installer cette application sur votre appareil',
    'apkOpenAsZip': 'Ouvrir comme ZIP',
    'apkOpenAsZipSubtitle': 'Parcourir les fichiers qu’il contient et les extraire',
  },
  'it': {
    'apkOpenPackageInstaller': 'Programma di installazione pacchetti',
    'apkOpenPackageInstallerSubtitle': 'Installa questa app sul dispositivo',
    'apkOpenAsZip': 'Apri come ZIP',
    'apkOpenAsZipSubtitle': 'Sfoglia i file contenuti ed estraili',
  },
  'ja': {
    'apkOpenPackageInstaller': 'パッケージインストーラー',
    'apkOpenPackageInstallerSubtitle': 'このアプリを端末にインストールします',
    'apkOpenAsZip': 'ZIPとして開く',
    'apkOpenAsZipSubtitle': '中のファイルを参照して展開します',
  },
  'ko': {
    'apkOpenPackageInstaller': '패키지 설치 프로그램',
    'apkOpenPackageInstallerSubtitle': '이 앱을 기기에 설치합니다',
    'apkOpenAsZip': 'ZIP으로 열기',
    'apkOpenAsZipSubtitle': '내부 파일을 둘러보고 압축을 풉니다',
  },
  'pt': {
    'apkOpenPackageInstaller': 'Instalador de pacotes',
    'apkOpenPackageInstallerSubtitle': 'Instalar este app no seu dispositivo',
    'apkOpenAsZip': 'Abrir como ZIP',
    'apkOpenAsZipSubtitle': 'Explorar os arquivos internos e extraí-los',
  },
  'uk': {
    'apkOpenPackageInstaller': 'Інсталятор пакетів',
    'apkOpenPackageInstallerSubtitle': 'Встановити цю програму на пристрій',
    'apkOpenAsZip': 'Відкрити як ZIP',
    'apkOpenAsZipSubtitle': 'Переглянути вміст і видобути файли',
  },
  'zh': {
    'apkOpenPackageInstaller': '软件包安装程序',
    'apkOpenPackageInstallerSubtitle': '将此应用安装到你的设备',
    'apkOpenAsZip': '作为 ZIP 打开',
    'apkOpenAsZipSubtitle': '浏览其中的文件并解压',
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