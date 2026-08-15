import 'dart:convert';
import 'dart:io';

void main() {
  final l10nDir = Directory('lib/l10n');
  final enFile = File('lib/l10n/app_en.arb');

  if (!enFile.existsSync()) {
    print('Error: lib/l10n/app_en.arb not found.');
    return;
  }

  // Read template source of truth
  final Map<String, dynamic> enJson = jsonDecode(enFile.readAsStringSync());

  // Find all target .arb files (e.g., app_uk.arb, app_es.arb)
  final targetFiles = l10nDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.arb') && !f.path.endsWith('app_en.arb'));

  if (targetFiles.isEmpty) {
    print('No target ARB files found to sync.');
    return;
  }

  for (final targetFile in targetFiles) {
    final fileName = targetFile.path.split(Platform.pathSeparator).last;
    final Map<String, dynamic> targetJson = targetFile.existsSync()
        ? jsonDecode(targetFile.readAsStringSync())
        : {};

    final Map<String, dynamic> updatedTargetJson = {};
    int addedCount = 0;
    int removedCount = 0;

    // 1. Preserve top-level file metadata starting with '@@' (e.g. @@locale)
    targetJson.forEach((key, value) {
      if (key.startsWith('@@')) {
        updatedTargetJson[key] = value;
      }
    });

    // If @@locale is missing, automatically infer it from the file name (app_uk.arb -> uk)
    if (!updatedTargetJson.containsKey('@@locale')) {
      final match = RegExp(r'app_([a-zA-Z_]+)\.arb$').firstMatch(fileName);
      if (match != null) {
        updatedTargetJson['@@locale'] = match.group(1);
      }
    }

    // 2. Sync translation keys from app_en.arb
    enJson.forEach((key, value) {
      if (key.startsWith('@')) return; // Skip @ metadata keys

      if (targetJson.containsKey(key)) {
        updatedTargetJson[key] = targetJson[key]; // Keep existing translation
      } else {
        updatedTargetJson[key] = value; // Add missing key
        addedCount++;
      }
    });

    // 3. Count obsolete keys removed
    targetJson.forEach((key, value) {
      if (!key.startsWith('@') && !enJson.containsKey(key)) {
        removedCount++;
      }
    });

    // Write formatted JSON back to file
    const encoder = JsonEncoder.withIndent('  ');
    targetFile.writeAsStringSync(encoder.convert(updatedTargetJson));

    print('Synced $fileName: +$addedCount added, -$removedCount removed.');
  }
}