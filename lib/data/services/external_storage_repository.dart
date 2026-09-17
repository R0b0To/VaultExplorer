import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';

class ExternalStorageRepository {
  const ExternalStorageRepository();

  static const _kLogTag = 'ExternalStorageRepository';

  static Future<File> get _dataFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/external_storages.json');
  }

  Future<List<ExternalStorageLocation>> loadAll() async {
    try {
      final file = await _dataFile;
      if (!await file.exists()) return const [];
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return raw
          .map((e) => ExternalStorageLocation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      VeLog.w(_kLogTag, 'Failed to load external storages', e);
      return const [];
    }
  }

  Future<void> saveAll(List<ExternalStorageLocation> list) async {
    try {
      final file = await _dataFile;
      await file.writeAsString(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (e) {
      VeLog.w(_kLogTag, 'Failed to save external storages', e);
    }
  }
}