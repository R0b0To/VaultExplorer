// Runs the CommonMark spec examples through the viewer's Markdown parser.
//
//   dart run tool/commonmark_spec/fetch_examples.dart      (once)
//   dart run tool/commonmark_spec/run.dart                 summary + regression gate
//   dart run tool/commonmark_spec/run.dart --show 42 77    expected vs actual for examples
//   dart run tool/commonmark_spec/run.dart --all           list every failure
//
// Exit code 1 means an example that is not listed in known_failures.txt failed.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_parser.dart';

import 'render.dart';

void _worker(List<Object> msg) {
  final port = msg[0] as SendPort;
  try {
    port.send(blk(parseMarkdownDocument(msg[1] as String)));
  } catch (e) {
    port.send('EXCEPTION: $e');
  }
}

Future<String> _render(String md) async {
  final rp = ReceivePort();
  final iso = await Isolate.spawn(_worker, [rp.sendPort, md]);
  try {
    return await rp.first.timeout(const Duration(seconds: 3)) as String;
  } catch (_) {
    iso.kill(priority: Isolate.immediate);
    return 'TIMEOUT';
  } finally {
    rp.close();
  }
}

Map<int, String> _knownFailures() {
  final known = <int, String>{};
  final file = File('tool/commonmark_spec/known_failures.txt');
  if (!file.existsSync()) return known;
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'\s+'));
    known[int.parse(parts.first)] = parts.skip(1).join(' ');
  }
  return known;
}

Future<void> main(List<String> args) async {
  final src = File('build/commonmark/examples.json');
  if (!src.existsSync()) {
    stderr.writeln('Run: dart run tool/commonmark_spec/fetch_examples.dart');
    exit(2);
  }
  final examples = (jsonDecode(src.readAsStringSync()) as List).cast<Map<String, dynamic>>();

  final showIdx = args.indexOf('--show');
  if (showIdx >= 0) {
    for (final a in args.skip(showIdx + 1)) {
      final e = examples.firstWhere((x) => x['n'] == int.parse(a));
      final got = await _render(e['md'] as String);
      stdout.writeln('#${e['n']} [${e['section']}]\n--- markdown\n${e['md']}--- expected\n${e['html']}--- actual\n$got');
    }
    return;
  }

  final known = _knownFailures();
  final perSection = <String, List<int>>{};
  final failed = <int>[];
  for (final e in examples) {
    final got = await _render(e['md'] as String);
    final ok = norm(got) == norm(e['html'] as String);
    final s = perSection.putIfAbsent(e['section'] as String, () => [0, 0]);
    s[1]++;
    if (ok) {
      s[0]++;
    } else {
      failed.add(e['n'] as int);
    }
  }

  stdout.writeln('CommonMark spec examples (${examples.length}) vs the viewer parser\n');
  perSection.forEach((k, v) => stdout.writeln('${v[0].toString().padLeft(4)} / ${v[1].toString().padRight(4)} $k'));
  final passed = examples.length - failed.length;
  stdout.writeln('\nTOTAL ${passed} / ${examples.length}');

  final unexpected = failed.where((n) => !known.containsKey(n)).toList();
  final nowPassing = known.keys.where((n) => !failed.contains(n)).toList();
  if (args.contains('--all')) {
    for (final n in failed) {
      stdout.writeln('  #$n  ${known[n] ?? "UNEXPECTED"}');
    }
  }
  if (nowPassing.isNotEmpty) {
    stdout.writeln('\nNow passing, remove from known_failures.txt: ${nowPassing.join(', ')}');
  }
  if (unexpected.isNotEmpty) {
    stdout.writeln('\nNEW FAILURES (not in known_failures.txt): ${unexpected.join(', ')}');
    exit(1);
  }
  stdout.writeln('\nNo regressions: every failure is a documented difference.');
}
