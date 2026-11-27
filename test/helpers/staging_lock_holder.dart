import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Expected one lock file path.');
    exitCode = 64;
    return;
  }

  final lockFile = await File(args.single).open(mode: FileMode.append);
  try {
    await lockFile.lock(FileLock.exclusive);
    stdout.writeln('locked');
    await stdout.flush();
    await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  } finally {
    await lockFile.unlock();
    await lockFile.close();
  }
}
