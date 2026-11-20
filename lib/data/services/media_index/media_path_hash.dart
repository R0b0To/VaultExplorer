/// 64-bit FNV-1a hash of a file's path inside its container.
///
/// The media index keys files by this instead of by path, which keeps an entry
/// at a fixed 28 bytes and lets a whole folder be looked up without building a
/// path string per file: FNV-1a is a running hash, so the hash of
/// `dir + '/' + name` is the hash of `dir/` continued over `name`
/// ([stateOfDir] once per folder, [ofName] per file).
///
/// A collision (about 1 in 2^64 per pair) cannot show a wrong shape for long:
/// every entry also carries the file's size and modified time, and the picture
/// itself replaces the shape the moment its thumbnail decodes.
abstract final class MediaPathHash {
  static const int _basis = 0xcbf29ce484222325;
  static const int _prime = 0x100000001b3;

  /// The hash state before any character: also the state of the root folder.
  static const int root = _basis;

  static int _feed(int h, String s, int from) {
    for (var i = from; i < s.length; i++) {
      h = (h ^ s.codeUnitAt(i)) * _prime;
    }
    return h;
  }

  /// Hash of a full path inside a container. A leading `/` is ignored, so
  /// `/a/b` and `a/b` are the same file.
  static int ofPath(String path) =>
      _feed(_basis, path, path.startsWith('/') ? 1 : 0);

  /// Running state after folder [dir] and its trailing separator; [root] for
  /// the container's root (`''` or `'/'`).
  static int stateOfDir(String dir) {
    final start = dir.startsWith('/') ? 1 : 0;
    if (start >= dir.length) return _basis;
    return (_feed(_basis, dir, start) ^ 0x2f) * _prime; // 0x2f == '/'
  }

  /// Hash of the file [name] directly inside the folder whose state is
  /// [dirState]. Equal to `ofPath('$dir/$name')`. Names that already are full
  /// paths (category views list files from many folders) go through the root
  /// state.
  static int ofName(int dirState, String name) =>
      _feed(dirState, name, dirState == _basis && name.startsWith('/') ? 1 : 0);
}
