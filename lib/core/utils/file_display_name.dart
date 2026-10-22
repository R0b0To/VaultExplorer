/// How a file's name is shown in the file manager.
///
/// Only the *display* changes: renaming, opening, sorting and searching all
/// keep using the real name.

final RegExp _whitespace = RegExp(r'\s');

/// [name] without its extension: "report.pdf" -> "report".
///
/// Left alone, because there is nothing to strip or it is not an extension:
///  * names with no dot ("README"), or a name that only starts with one
///    (".bashrc" is a dotfile, not an empty name with an extension);
///  * names ending in a dot ("draft.");
///  * a "tail" containing whitespace ("Meeting 2024.05.12 notes"), which is a
///    sentence rather than an extension.
///
/// Compressed tarballs lose both parts: "backup.tar.gz" -> "backup".
String stripFileExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return name;
  if (_whitespace.hasMatch(name.substring(dot + 1))) return name;
  final stem = name.substring(0, dot);
  // "..hidden": a run of dots is no name to keep.
  if (stem.replaceAll('.', '').isEmpty) return name;
  if (stem.length > 4 && stem.toLowerCase().endsWith('.tar')) {
    return stem.substring(0, stem.length - 4);
  }
  return stem;
}
