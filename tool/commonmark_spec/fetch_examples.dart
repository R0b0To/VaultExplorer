// Downloads the official CommonMark spec (pinned version) and extracts its
// examples to build/commonmark/examples.json.
//
//   dart run tool/commonmark_spec/fetch_examples.dart
//
// The spec text is not stored in the repository (it is CC BY-SA 4.0).
import 'dart:convert';
import 'dart:io';

const specVersion = '0.31.2';

Future<void> main() async {
  final url = Uri.parse(
    'https://raw.githubusercontent.com/commonmark/commonmark-spec/$specVersion/spec.txt',
  );
  final client = HttpClient();
  final req = await client.getUrl(url);
  final res = await req.close();
  if (res.statusCode != 200) {
    stderr.writeln('HTTP ${res.statusCode} for $url');
    exit(1);
  }
  final text = (await res.transform(utf8.decoder).join()).replaceAll('\r\n', '\n');
  client.close();

  const fence = '````````````````````````````````';
  final lines = text.split('\n');
  final examples = <Map<String, Object>>[];
  var section = '';
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.startsWith('#')) section = l.replaceFirst(RegExp(r'^#+'), '').trim();
    if (l.startsWith('$fence example')) {
      final md = <String>[];
      final html = <String>[];
      var cur = md;
      i++;
      while (!lines[i].startsWith(fence)) {
        if (lines[i] == '.') {
          cur = html;
        } else {
          cur.add(lines[i]);
        }
        i++;
      }
      examples.add({
        'n': examples.length + 1,
        'section': section,
        'md': '${md.join('\n').replaceAll('→', '\t')}\n',
        'html': html.isEmpty ? '' : '${html.join('\n').replaceAll('→', '\t')}\n',
      });
    }
  }

  final out = File('build/commonmark/examples.json')..createSync(recursive: true);
  out.writeAsStringSync(jsonEncode(examples));
  stdout.writeln('spec $specVersion: ${examples.length} examples -> ${out.path}');
}
