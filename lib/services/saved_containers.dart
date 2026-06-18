import 'dart:convert';
import 'dart:io';

class SavedContainerService {
  // Uses sandboxed private internal files directory
  static final File _saveFile = File('/data/data/com.example.cryptbridge/files/saved_containers.json');

  static Future<void> saveContainer(String uri, String name) async {
    try {
      if (!await _saveFile.parent.exists()) {
        await _saveFile.parent.create(recursive: true);
      }
      List<dynamic> list = [];
      if (await _saveFile.exists()) {
        final content = await _saveFile.readAsString();
        list = jsonDecode(content) as List<dynamic>;
      }
      list.removeWhere((item) => item['uri'] == uri);
      list.add({'uri': uri, 'name': name});
      await _saveFile.writeAsString(jsonEncode(list));
    } catch (e) {
      // safe fallback
    }
  }

  static Future<List<Map<String, String>>> loadContainers() async {
    try {
      if (await _saveFile.exists()) {
        final content = await _saveFile.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        return list.map((item) => {
          'uri': item['uri'] as String,
          'name': item['name'] as String,
        }).toList();
      }
    } catch (e) {
      // safe fallback
    }
    return [];
  }

  static Future<void> removeContainer(String uri) async {
    try {
      if (await _saveFile.exists()) {
        final content = await _saveFile.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        list.removeWhere((item) => item['uri'] == uri);
        await _saveFile.writeAsString(jsonEncode(list));
      }
    } catch (e) {
      // safe fallback
    }
  }
}