import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// The path the native player is given for [file] of [container].
///
/// Vault items are addressed relative to the mounted container. Local storage
/// has no vault session for the native player to stream decrypted bytes from
/// -- NativePlayerManager's local branch reads a real, absolute path (or a SAF
/// `content://` document) straight off disk, so it needs the full path rather
/// than one relative to the container root.
///
/// Shared by the media viewer and background audio playback so both resolve a playlist
/// entry identically.
String nativePlaybackPathFor(MountedContainer container, String file) {
  if (!container.isLocalStorage) return file;
  if (container.isSafStorage) {
    return file.startsWith(container.uri)
        ? file
        : '${container.uri}/${file.replaceFirst(RegExp(r"^/+"), "")}';
  }
  return p.isAbsolute(file) ? file : p.join(container.uri, file);
}

/// Secure-storage key under which the resume position of [fileName] inside
/// the container identified by [containerUri] is kept. Hashed, so file paths
/// from inside an encrypted vault never reach storage in the clear.
///
/// Throws a [StateError] when the hash cannot be derived.
Future<String> mediaResumePositionKey(
  VaultHashApi hashApi,
  String containerUri,
  String fileName,
) async {
  final identity = '$containerUri\u001f$fileName';
  final digest = await hashApi.hashBytesSha256(
    Uint8List.fromList(utf8.encode(identity)),
  );
  if (digest.isEmpty) throw StateError('Could not derive playback key');
  return 'media_resume_$digest';
}

/// Whether [position] is worth remembering: not the very start and not the
/// very end of the item. Anything else is cleared instead of saved.
bool isResumePositionWorthKeeping(Duration position, Duration? duration) {
  if (position <= const Duration(seconds: 3)) return false;
  if (duration != null &&
      duration > Duration.zero &&
      position >= duration - const Duration(seconds: 3)) {
    return false;
  }
  return true;
}
