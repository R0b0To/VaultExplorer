// dart:ffi bindings for the desktop engine C ABI (android/app/src/main/cpp/ffi/ve_engine.h).
//
// Everything here is SYNCHRONOUS and BLOCKING (key derivation, large copies) -- it is meant to
// run inside a worker isolate (see engine_worker_pool.dart), never on the UI isolate. The native
// engine keeps its state process-wide, so any isolate may call it; each isolate just needs its
// own [VeNative] (a DynamicLibrary handle + looked-up function pointers).
//
// Keep this file in lock-step with ve_engine.h (VE_ABI_VERSION): the struct layouts below mirror
// the C structs field for field.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int kVeAbiVersion = 16;

// Result codes (ve_engine.h)
const int veOk = 0;
const int veErrFailed = 1;
const int veErrCancelled = 2;
const int veErrNotUnlocked = 3;
const int veErrReadOnly = 4;
const int veErrInvalidArg = 5;
const int veErrException = 6;
const int veErrMountFailed = 7;
const int veErrAuthFailed = 8;
const int veErrUnsupported = 9;
const int veErrBusy = 10;
// Raw block devices (ve_unlock_device).
const int veErrDeviceNotFound = 11;
const int veErrDevicePermission = 12;
const int veErrDeviceBusy = 13;
const int veErrDeviceOpen = 14;
const int veErrTooLarge = 15; // refused by a size guard (image thumbnails)
const int veErrNoMemory = 16; // ran out of memory (image thumbnails)

// Folder-vault formats for ve_fv_* (VE_FV_*), and the container-format codes an unlocked folder-vault
// slot reports (VE_FORMAT_*, see veFormatWireName).
const int veFvGocryptfs = 0;
const int veFvCryptomator = 1;
const int veFvCryfs = 2;

// Operation flavors / event kinds
// Hash ids for ve_pbkdf2 / ve_hmac
const int veHashSha1 = 1;
const int veHashSha256 = 2;
const int veHashSha512 = 3;
const int veHashMd5 = 4; // digests only (not valid for pbkdf2 / hmac)

const int veOpCopy = 0;
const int veOpImport = 1;
const int veOpExport = 2;
const int veEventUnlockProgress = 1;
const int veEventSplitJoinProgress = 2;
const int veEventRepairLog = 3;
const int veEventCopyProgress = 4;
const int veEventImportProgress = 5;
const int veEventExportProgress = 6;

/// ContainerFormat (native enum) -> the wire name the Dart layer uses.
String veFormatWireName(int native) => switch (native) {
  0 => 'veracrypt',
  1 => 'luks1',
  2 => 'luks2',
  3 => 'bitlocker',
  4 => 'plain',
  10 => 'gocryptfs',
  11 => 'cryptomator',
  12 => 'cryfs',
  _ => 'unknown',
};

final class VeBuffer extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int len;
}

/// `ve_mount_options` (ve_engine.h).
final class VeMountOptions extends Struct {
  @Int32()
  external int structSize;
  @Int32()
  external int readOnly;
  @Int32()
  external int allowOther;
  @Int32()
  external int maxBufferMb;
  external Pointer<Utf8> volumeName;
  external Pointer<Utf8> subPath;
}

/// One row of `ve_list_mounts`.
class VeMountInfo {
  const VeMountInfo({required this.id, required this.volId, required this.ended, required this.mountPoint});
  final int id;
  final int volId;

  /// True when the mount went away without ve_unmount (ejected from outside) and still needs reaping.
  final bool ended;
  final String mountPoint;
}

/// One disk from `ve_list_block_devices` (a JSON row, see ve_engine.h).
class VeBlockDevice {
  const VeBlockDevice({
    required this.path,
    required this.name,
    required this.bus,
    required this.sizeBytes,
    required this.sectorSize,
    required this.removable,
    required this.readable,
    required this.writable,
    required this.inUse,
    required this.system,
    required this.formats,
  });

  factory VeBlockDevice.fromJson(Map<String, dynamic> j) => VeBlockDevice(
        path: j['path'] as String? ?? '',
        name: j['name'] as String? ?? '',
        bus: j['bus'] as String? ?? '',
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        sectorSize: (j['sectorSize'] as num?)?.toInt() ?? 512,
        removable: j['removable'] as bool? ?? false,
        readable: j['readable'] as bool? ?? false,
        writable: j['writable'] as bool? ?? false,
        inUse: j['inUse'] as bool? ?? false,
        system: j['system'] as bool? ?? false,
        formats: [for (final f in (j['formats'] as List<dynamic>? ?? const [])) f.toString()],
      );

  /// What `unlockDevice` takes: /dev/disk/by-id/... or /dev/sdX on Linux, \\.\PhysicalDriveN on Windows.
  final String path;
  final String name;

  /// "usb" | "nvme" | "sata" | "mmc" | "scsi" | "virtual" | "".
  final String bus;
  final int sizeBytes;
  final int sectorSize;
  final bool removable;

  /// This process may open it right now (root / disk group / elevated process).
  final bool readable;
  final bool writable;

  /// A file system on it, or on one of its partitions, is mounted by the OS.
  final bool inUse;

  /// It carries the running operating system.
  final bool system;

  /// "bitlocker" / "luks" signatures found at the start of a partition (readable disks only).
  final List<String> formats;
}

final class VeUnlockParams extends Struct {
  @Int32()
  external int structSize;
  @Int32()
  external int fd;
  external Pointer<Uint8> password;
  @Int32()
  external int passwordLen;
  @Int32()
  external int pim;
  @Int32()
  external int volId;
  @Int32()
  external int cipherId;
  @Int32()
  external int hashId;
  external Pointer<Uint8> preservedKey;
  @Int32()
  external int preservedKeyLen;
  external Pointer<Int32> keyfileFds;
  @Int32()
  external int keyfileCount;
  @Int32()
  external int readOnly;
  external Pointer<Uint8> hiddenPassword;
  @Int32()
  external int hiddenPasswordLen;
  @Int32()
  external int hiddenPim;
  @Int32()
  external int hiddenCipherId;
  @Int32()
  external int hiddenHashId;
  external Pointer<Int32> hiddenKeyfileFds;
  @Int32()
  external int hiddenKeyfileCount;
}

/// `ve_unlock_device_params` (ve_engine.h).
final class VeUnlockDeviceParams extends Struct {
  @Int32()
  external int structSize;
  external Pointer<Utf8> devicePath;
  @Int32()
  external int volId;
  external Pointer<Uint8> password;
  @Int32()
  external int passwordLen;
  @Int32()
  external int pim;
  @Int32()
  external int cipherId;
  @Int32()
  external int hashId;
  external Pointer<Uint8> preservedKey;
  @Int32()
  external int preservedKeyLen;
  external Pointer<Int32> keyfileFds;
  @Int32()
  external int keyfileCount;
  @Int32()
  external int readOnly;
  @Int64()
  external int partitionOffsetHint;
  external Pointer<Uint8> hiddenPassword;
  @Int32()
  external int hiddenPasswordLen;
  @Int32()
  external int hiddenPim;
  @Int32()
  external int hiddenCipherId;
  @Int32()
  external int hiddenHashId;
  external Pointer<Int32> hiddenKeyfileFds;
  @Int32()
  external int hiddenKeyfileCount;
  external Pointer<Int32> osErrorOut;
}

final class VeCreateParams extends Struct {
  @Int32()
  external int structSize;
  @Int32()
  external int fd;
  external Pointer<Uint8> password;
  @Int32()
  external int passwordLen;
  @Int32()
  external int pim;
  @Int64()
  external int sizeBytes;
  external Pointer<Utf8> fileSystem;
  @Int32()
  external int containerFormat;
  @Int32()
  external int cipherId;
  @Int32()
  external int hashId;
  external Pointer<Int32> keyfileFds;
  @Int32()
  external int keyfileCount;
  @Int32()
  external int quickFormat;
  external Pointer<Uint8> userEntropy;
  @Int32()
  external int userEntropyLen;
}

final class VeCreateHiddenParams extends Struct {
  @Int32()
  external int structSize;
  @Int32()
  external int fd;
  external Pointer<Uint8> outerPassword;
  @Int32()
  external int outerPasswordLen;
  external Pointer<Uint8> hiddenPassword;
  @Int32()
  external int hiddenPasswordLen;
  @Int32()
  external int outerPim;
  @Int32()
  external int hiddenPim;
  @Int64()
  external int sizeBytes;
  external Pointer<Utf8> outerFileSystem;
  external Pointer<Utf8> hiddenFileSystem;
  @Int64()
  external int hiddenSizeBytes;
  @Int32()
  external int outerCipherId;
  @Int32()
  external int outerHashId;
  @Int32()
  external int hiddenCipherId;
  @Int32()
  external int hiddenHashId;
  external Pointer<Int32> outerKeyfileFds;
  @Int32()
  external int outerKeyfileCount;
  external Pointer<Int32> hiddenKeyfileFds;
  @Int32()
  external int hiddenKeyfileCount;
  @Int32()
  external int quickFormat;
  external Pointer<Uint8> userEntropy;
  @Int32()
  external int userEntropyLen;
}

final class VeVaultInfo extends Struct {
  @Int32()
  external int structSize;
  @Int32()
  external int containerFormat;
  @Int32()
  external int readOnly;
  @Int32()
  external int hiddenVolume;
  @Int64()
  external int volumeSizeBytes;
  @Int32()
  external int hasCipherHash;
  @Int32()
  external int cipherId;
  @Int32()
  external int hashId;
  @Int32()
  external int luksVersion;
  @Int32()
  external int sectorSize;
  @Int32()
  external int hasFileSystem;
  @Array(64)
  external Array<Uint8> fileSystem;
}

final class VeChangePasswordParams extends Struct {
  @Int32()
  external int structSize;
  @Int32()
  external int fd;
  @Int32()
  external int containerFormat;
  external Pointer<Uint8> oldPassword;
  @Int32()
  external int oldPasswordLen;
  external Pointer<Uint8> newPassword;
  @Int32()
  external int newPasswordLen;
  @Int32()
  external int oldPim;
  @Int32()
  external int newPim;
  @Int32()
  external int cipherId;
  @Int32()
  external int hashId;
  external Pointer<Int32> oldKeyfileFds;
  @Int32()
  external int oldKeyfileCount;
  external Pointer<Int32> newKeyfileFds;
  @Int32()
  external int newKeyfileCount;
}

/// `ve_hidden_in_existing_params` (ABI 12): a hidden volume added to an existing standard volume.
final class VeHiddenInExistingParams extends Struct {
  @Int32()
  external int structSize;
  @Int32()
  external int fd;
  external Pointer<Uint8> outerPassword;
  @Int32()
  external int outerPasswordLen;
  @Int32()
  external int outerPim;
  @Int32()
  external int outerCipherId;
  @Int32()
  external int outerHashId;
  external Pointer<Int32> outerKeyfileFds;
  @Int32()
  external int outerKeyfileCount;
  external Pointer<Uint8> hiddenPassword;
  @Int32()
  external int hiddenPasswordLen;
  @Int32()
  external int hiddenPim;
  external Pointer<Utf8> hiddenFileSystem;
  @Int64()
  external int hiddenSizeBytes;
  @Int32()
  external int hiddenCipherId;
  @Int32()
  external int hiddenHashId;
  external Pointer<Int32> hiddenKeyfileFds;
  @Int32()
  external int hiddenKeyfileCount;
  @Int32()
  external int quickFormat;
  external Pointer<Uint8> userEntropy;
  @Int32()
  external int userEntropyLen;
}

/// `ve_composite_create_params` (ABI 13): one VeraCrypt volume spread over several ordinary files.
final class VeCompositeCreateParams extends Struct {
  @Int32()
  external int structSize;
  @Int32()
  external int volId;
  external Pointer<Pointer<Utf8>> carrierPaths;
  @Int32()
  external int carrierCount;
  @Int64()
  external int requestedBytes;
  @Int32()
  external int safetyMarginPct;
  external Pointer<Uint8> password;
  @Int32()
  external int passwordLen;
  @Int32()
  external int pim;
  external Pointer<Utf8> fileSystem;
  @Int32()
  external int cipherId;
  @Int32()
  external int hashId;
  external Pointer<Int32> keyfileFds;
  @Int32()
  external int keyfileCount;
  @Int32()
  external int quickFormat;
  external Pointer<Uint8> userEntropy;
  @Int32()
  external int userEntropyLen;
}

/// `ve_composite_unlock_params` (ABI 13).
final class VeCompositeUnlockParams extends Struct {
  @Int32()
  external int structSize;
  @Int32()
  external int volId;
  external Pointer<Pointer<Utf8>> carrierPaths;
  @Int32()
  external int carrierCount;
  external Pointer<Uint8> password;
  @Int32()
  external int passwordLen;
  @Int32()
  external int pim;
  @Int32()
  external int cipherId;
  @Int32()
  external int hashId;
  external Pointer<Int32> keyfileFds;
  @Int32()
  external int keyfileCount;
  @Int32()
  external int readOnly;
}

final class VeSingleFileParams extends Struct {
  @Int32()
  external int structSize;
  @Int32()
  external int srcFd;
  @Int32()
  external int destFd;
  @Int32()
  external int encrypt;
  @Int32()
  external int cipherIndex;
  external Pointer<Uint8> password;
  @Int32()
  external int passwordLen;
  external Pointer<Int32> keyfileFds;
  @Int32()
  external int keyfileCount;
  @Int32()
  external int opId;
}

final class VeEvent extends Struct {
  @Int32()
  external int kind;
  @Int32()
  external int volId;
  @Int32()
  external int opId;
  @Int32()
  external int i0;
  @Int32()
  external int i1;
  @Int32()
  external int i2;
  @Int32()
  external int i3;
  @Int32()
  external int i4;
  @Int64()
  external int n0;
  @Int64()
  external int n1;
  @Array(240)
  external Array<Uint8> text;
}

/// A decoded native event (only the fields the host forwards).
class VeNativeEvent {
  VeNativeEvent(this.kind, this.volId, this.opId, this.i, this.n0, this.n1, this.text);
  final int kind;
  final int volId;
  final int opId;
  final List<int> i; // i0..i4
  final int n0;
  final int n1;
  final String text;
}

class VeNative {
  VeNative._(this._lib, this.libraryPath) {
    _openFile = _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Int32), int Function(Pointer<Utf8>, int)>('ve_open_file');
    _closeFd = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ve_close_fd');
    _createFile = _lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ve_create_file');
    _createContainer = _lib.lookupFunction<Int32 Function(Pointer<VeCreateParams>), int Function(Pointer<VeCreateParams>)>('ve_create_container');
    _createHidden = _lib.lookupFunction<Int32 Function(Pointer<VeCreateHiddenParams>), int Function(Pointer<VeCreateHiddenParams>)>('ve_create_container_with_hidden');
    _abiVersion = _lib.lookupFunction<Int32 Function(), int Function()>('ve_abi_version');
    _maxVolumes = _lib.lookupFunction<Int32 Function(), int Function()>('ve_max_volumes');
    _probe = _lib.lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>('ve_probe_format');
    _unlock = _lib.lookupFunction<Int32 Function(Pointer<VeUnlockParams>), int Function(Pointer<VeUnlockParams>)>('ve_unlock');
    _unlockDevice = _lib.lookupFunction<Int32 Function(Pointer<VeUnlockDeviceParams>), int Function(Pointer<VeUnlockDeviceParams>)>('ve_unlock_device');
    _listBlockDevices = _lib.lookupFunction<Int32 Function(Pointer<VeBuffer>), int Function(Pointer<VeBuffer>)>('ve_list_block_devices');
    _cancelUnlock = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ve_request_cancel_unlock');
    _lock = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ve_lock');
    _format = _lib.lookupFunction<Int32 Function(Int32), int Function(int)>('ve_get_container_format');
    _matchedCipher = _lib.lookupFunction<Int32 Function(Int32), int Function(int)>('ve_get_matched_cipher_id');
    _matchedHash = _lib.lookupFunction<Int32 Function(Int32), int Function(int)>('ve_get_matched_hash_id');
    _vaultInfo = _lib.lookupFunction<Int32 Function(Int32, Pointer<VeVaultInfo>), int Function(int, Pointer<VeVaultInfo>)>('ve_get_vault_info');
    _pbkdf2 = _lib.lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Uint32, Pointer<Uint8>, Size), int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int, int, Pointer<Uint8>, int)>('ve_pbkdf2');
    _hmac = _lib.lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Size>), int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Size>)>('ve_hmac');
    _scrypt = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size, Uint32, Uint32, Uint32, Pointer<Uint8>, Size), int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, int, int, int, Pointer<Uint8>, int)>('ve_scrypt');
    _argon2id = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size, Uint32, Uint32, Uint32, Pointer<Uint8>, Size), int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, int, int, int, Pointer<Uint8>, int)>('ve_argon2id');
    _gcmSeal = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<VeBuffer>), int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<VeBuffer>)>('ve_aes_gcm_seal');
    _gcmOpen = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<VeBuffer>), int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<VeBuffer>)>('ve_aes_gcm_open');
    _cbcDecrypt = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<VeBuffer>), int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<VeBuffer>)>('ve_aes_cbc_decrypt');
    _xchachaOpen = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<VeBuffer>), int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<VeBuffer>)>('ve_xchacha20poly1305_open');
    _changePassword = _lib.lookupFunction<Int32 Function(Pointer<VeChangePasswordParams>), int Function(Pointer<VeChangePasswordParams>)>('ve_change_password');
    _singleFile = _lib.lookupFunction<Int32 Function(Pointer<VeSingleFileParams>), int Function(Pointer<VeSingleFileParams>)>('ve_single_file_crypt');
    _hashBegin = _lib.lookupFunction<Int64 Function(Uint32), int Function(int)>('ve_hash_begin');
    _hashUpdate = _lib.lookupFunction<Int32 Function(Int64, Pointer<Uint8>, Size), int Function(int, Pointer<Uint8>, int)>('ve_hash_update');
    _hashFinish = _lib.lookupFunction<Int32 Function(Int64, Int32, Pointer<Uint8>, Size, Pointer<Size>), int Function(int, int, Pointer<Uint8>, int, Pointer<Size>)>('ve_hash_finish');
    _hashFree = _lib.lookupFunction<Void Function(Int64), void Function(int)>('ve_hash_free');
    _hashBytes = _lib.lookupFunction<Int32 Function(Int32, Pointer<Uint8>, Size, Pointer<Uint8>, Size, Pointer<Size>), int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Size>)>('ve_hash_bytes');
    _bufferFree = _lib.lookupFunction<Void Function(Pointer<VeBuffer>), void Function(Pointer<VeBuffer>)>('ve_buffer_free');
    _list = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<VeBuffer>), int Function(int, Pointer<Utf8>, Pointer<VeBuffer>)>('ve_list_directory');
    _fileSize = _lib.lookupFunction<Int64 Function(Int32, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('ve_get_file_size');
    _folderSize = _lib.lookupFunction<Int64 Function(Int32, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('ve_get_folder_size');
    _readChunk = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Int64, Int32, Pointer<VeBuffer>), int Function(int, Pointer<Utf8>, int, int, Pointer<VeBuffer>)>('ve_read_file_chunk');
    _writeChunk = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Int64, Pointer<Uint8>, Size), int Function(int, Pointer<Utf8>, int, Pointer<Uint8>, int)>('ve_write_file_chunk');
    _delete = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('ve_delete_file');
    _mkdir = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('ve_create_directory');
    _rename = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>), int Function(int, Pointer<Utf8>, Pointer<Utf8>)>('ve_rename_file');
    _setMtime = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Int64), int Function(int, Pointer<Utf8>, int)>('ve_set_last_modified');
    _copy = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Int32, Pointer<Utf8>, Int32), int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int)>('ve_copy_file');
    _import = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>, Int32), int Function(int, Pointer<Utf8>, Pointer<Utf8>, int)>('ve_import_file');
    _export = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>, Int32), int Function(int, Pointer<Utf8>, Pointer<Utf8>, int)>('ve_export_file');
    _space = _lib.lookupFunction<Int32 Function(Int32, Pointer<Uint64>, Pointer<Uint64>), int Function(int, Pointer<Uint64>, Pointer<Uint64>)>('ve_get_space_info');
    _opRegister = _lib.lookupFunction<Void Function(Int32, Int32), void Function(int, int)>('ve_op_register');
    _opCancel = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ve_op_cancel');
    _opUnregister = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ve_op_unregister');
    _poll = _lib.lookupFunction<Int32 Function(Pointer<VeEvent>), int Function(Pointer<VeEvent>)>('ve_poll_event');
    _fvSupported = _lib.lookupFunction<Int32 Function(), int Function()>('ve_fv_supported');
    _fvProbe = _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Int32>), int Function(Pointer<Utf8>, Pointer<Int32>)>('ve_fv_probe');
    _fvUnlock = _lib.lookupFunction<
        Int32 Function(Int32, Int32, Pointer<Utf8>, Pointer<Uint8>, Int32, Pointer<Uint8>, Int32, Int32, Int32, Pointer<Utf8>, Pointer<Utf8>, Pointer<VeBuffer>, Pointer<VeBuffer>),
        int Function(int, int, Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Uint8>, int, int, int, Pointer<Utf8>, Pointer<Utf8>, Pointer<VeBuffer>, Pointer<VeBuffer>)>('ve_fv_unlock');
    _fvProbeCryptomator = _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Int32>), int Function(Pointer<Utf8>, Pointer<Int32>)>('ve_fv_probe_cryptomator');
    _fvCreate = _lib.lookupFunction<
        Int32 Function(Int32, Pointer<Utf8>, Pointer<Uint8>, Int32, Int32, Int32, Int32, Int32, Int32, Pointer<Utf8>, Pointer<Uint8>, Int32, Pointer<Utf8>, Pointer<Utf8>, Pointer<VeBuffer>),
        int Function(int, Pointer<Utf8>, Pointer<Uint8>, int, int, int, int, int, int, Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Utf8>, Pointer<Utf8>, Pointer<VeBuffer>)>('ve_fv_create');
    _fvChangePassword = _lib.lookupFunction<
        Int32 Function(Int32, Pointer<Utf8>, Pointer<Uint8>, Int32, Pointer<Uint8>, Int32, Pointer<VeBuffer>),
        int Function(int, Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<VeBuffer>)>('ve_fv_change_password');
    _fvMigrate = _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Uint8>, Int32, Pointer<VeBuffer>), int Function(Pointer<Utf8>, Pointer<Uint8>, int, Pointer<VeBuffer>)>('ve_fv_migrate_cryptomator');
    _fvInfo = _lib.lookupFunction<Int32 Function(Int32, Pointer<VeBuffer>), int Function(int, Pointer<VeBuffer>)>('ve_fv_info');
    _listSymlinks = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<VeBuffer>), int Function(int, Pointer<Utf8>, Pointer<VeBuffer>)>('ve_list_symlinks');
    _readSymlink = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<VeBuffer>), int Function(int, Pointer<Utf8>, Pointer<VeBuffer>)>('ve_read_symlink');
    _createSymlink = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>), int Function(int, Pointer<Utf8>, Pointer<Utf8>)>('ve_create_symlink');
    _fvHidden = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('ve_fv_hidden_entry_count');
    _fvFinishWrite = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('ve_fv_finish_write');
    _fvBatch = _lib.lookupFunction<Int32 Function(Int32, Int32, Int32), int Function(int, int, int)>('ve_fv_batch');
  }

  final DynamicLibrary _lib;
  final String libraryPath;
  late final int Function(Pointer<Utf8>, int) _openFile;
  late final void Function(int) _closeFd;
  late final int Function(Pointer<Utf8>) _createFile;
  late final int Function(Pointer<VeCreateParams>) _createContainer;
  late final int Function(Pointer<VeCreateHiddenParams>) _createHidden;
  late final int Function() _abiVersion;
  late final int Function() _maxVolumes;
  late final Pointer<Utf8> Function(int) _probe;
  late final int Function() _fvSupported;
  late final int Function(Pointer<Utf8>, Pointer<Int32>) _fvProbe;
  late final int Function(int, int, Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Uint8>, int, int, int, Pointer<Utf8>, Pointer<Utf8>, Pointer<VeBuffer>, Pointer<VeBuffer>) _fvUnlock;
  late final int Function(Pointer<Utf8>, Pointer<Int32>) _fvProbeCryptomator;
  late final int Function(int, Pointer<Utf8>, Pointer<Uint8>, int, int, int, int, int, int, Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Utf8>, Pointer<Utf8>, Pointer<VeBuffer>) _fvCreate;
  late final int Function(int, Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<VeBuffer>) _fvChangePassword;
  late final int Function(Pointer<Utf8>, Pointer<Uint8>, int, Pointer<VeBuffer>) _fvMigrate;
  late final int Function(int, Pointer<VeBuffer>) _fvInfo;
  late final int Function(int, Pointer<Utf8>, Pointer<VeBuffer>) _listSymlinks;
  late final int Function(int, Pointer<Utf8>, Pointer<VeBuffer>) _readSymlink;
  late final int Function(int, Pointer<Utf8>, Pointer<Utf8>) _createSymlink;
  late final int Function(int, Pointer<Utf8>) _fvHidden;
  late final int Function(int, Pointer<Utf8>) _fvFinishWrite;
  late final int Function(int, int, int) _fvBatch;
  late final int Function(Pointer<VeUnlockParams>) _unlock;
  late final int Function(Pointer<VeUnlockDeviceParams>) _unlockDevice;
  late final int Function(Pointer<VeBuffer>) _listBlockDevices;
  late final void Function(int) _cancelUnlock;
  late final void Function(int) _lock;

  // OS mounts (ABI 9). Bound lazily so a library built without them still loads; callers check
  // [hasMounts] first.
  bool get hasMounts => _lib.providesSymbol('ve_mount');
  late final int Function(Pointer<Utf8>, int) _mountSupported =
      _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Size), int Function(Pointer<Utf8>, int)>('ve_mount_supported');
  late final int Function(int, Pointer<Utf8>, Pointer<VeMountOptions>, Pointer<Int64>) _mount = _lib.lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Pointer<VeMountOptions>, Pointer<Int64>),
      int Function(int, Pointer<Utf8>, Pointer<VeMountOptions>, Pointer<Int64>)>('ve_mount');
  late final int Function(int, int) _unmount =
      _lib.lookupFunction<Int32 Function(Int64, Int32), int Function(int, int)>('ve_unmount');
  late final int Function(Pointer<VeBuffer>) _listMounts =
      _lib.lookupFunction<Int32 Function(Pointer<VeBuffer>), int Function(Pointer<VeBuffer>)>('ve_list_mounts');
  late final int Function(Pointer<Utf8>, int) _mountLastError =
      _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Size), int Function(Pointer<Utf8>, int)>('ve_mount_last_error');

  // Video thumbnails (ABI 16): ve_video_thumbnail / ve_video_thumbnail_file (ve_engine.h).
  late final int Function(int, Pointer<Utf8>, int, int, int, double, int, int, Pointer<VeBuffer>, Pointer<Int32>)
      _videoThumbnail = _lib.lookupFunction<
          Int32 Function(
              Int32, Pointer<Utf8>, Int32, Int32, Int32, Double, Int64, Int32, Pointer<VeBuffer>, Pointer<Int32>),
          int Function(int, Pointer<Utf8>, int, int, int, double, int, int, Pointer<VeBuffer>,
              Pointer<Int32>)>('ve_video_thumbnail');
  late final int Function(Pointer<Utf8>, int, int, int, double, int, int, Pointer<VeBuffer>, Pointer<Int32>)
      _videoThumbnailFile = _lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32, Int32, Int32, Double, Int64, Int32, Pointer<VeBuffer>, Pointer<Int32>),
          int Function(Pointer<Utf8>, int, int, int, double, int, int, Pointer<VeBuffer>,
              Pointer<Int32>)>('ve_video_thumbnail_file');

  // Image thumbnails (ABI 15): ve_image_thumbnail / ve_image_thumbnail_file / ve_image_thumbnail_mem (ve_engine.h).
  late final int Function(int, Pointer<Utf8>, int, int, int, int, Pointer<VeBuffer>, Pointer<Int32>) _imageThumbnail =
      _lib.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Int32, Int32, Int32, Int64, Pointer<VeBuffer>, Pointer<Int32>),
          int Function(int, Pointer<Utf8>, int, int, int, int, Pointer<VeBuffer>, Pointer<Int32>)>('ve_image_thumbnail');
  late final int Function(Pointer<Utf8>, int, int, int, int, Pointer<VeBuffer>, Pointer<Int32>) _imageThumbnailFile =
      _lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Int32, Int32, Int32, Int64, Pointer<VeBuffer>, Pointer<Int32>),
          int Function(Pointer<Utf8>, int, int, int, int, Pointer<VeBuffer>, Pointer<Int32>)>('ve_image_thumbnail_file');
  late final int Function(Pointer<Uint8>, int, int, int, int, Pointer<VeBuffer>, Pointer<Int32>) _imageThumbnailMem =
      _lib.lookupFunction<
          Int32 Function(Pointer<Uint8>, Size, Int32, Int32, Int32, Pointer<VeBuffer>, Pointer<Int32>),
          int Function(Pointer<Uint8>, int, int, int, int, Pointer<VeBuffer>, Pointer<Int32>)>('ve_image_thumbnail_mem');

  // Archives (ABI 10): ve_archive_scan / ve_archive_extract_entry / ve_archive_extract_all (ve_engine.h).
  late final int Function(int, Pointer<Utf8>, Pointer<Utf8>, Pointer<VeBuffer>) _archiveScan = _lib.lookupFunction<
      Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>, Pointer<VeBuffer>),
      int Function(int, Pointer<Utf8>, Pointer<Utf8>, Pointer<VeBuffer>)>('ve_archive_scan');
  late final int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int, Pointer<Utf8>, Pointer<VeBuffer>, Pointer<VeBuffer>)
      _archiveExtractEntry = _lib.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Int32, Pointer<Utf8>, Int32, Pointer<Utf8>, Pointer<VeBuffer>, Pointer<VeBuffer>),
          int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int, Pointer<Utf8>, Pointer<VeBuffer>, Pointer<VeBuffer>)>(
        've_archive_extract_entry',
      );
  late final int Function(int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Utf8>, int, Pointer<VeBuffer>)
      _archiveExtractAll = _lib.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32, Pointer<Utf8>, Int32, Pointer<VeBuffer>),
          int Function(int, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Utf8>, int, Pointer<VeBuffer>)>(
        've_archive_extract_all',
      );
  late final int Function(
    int,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>,
    Pointer<Int64>,
    int,
    int,
    Pointer<Utf8>,
    int,
    Pointer<Utf8>,
    int,
    int,
    int,
    int,
    Pointer<Utf8>,
    int,
    Pointer<VeBuffer>,
  ) _archiveCreate = _lib.lookupFunction<
      Int32 Function(
        Int32,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
        Pointer<Int64>,
        Int32,
        Int32,
        Pointer<Utf8>,
        Int32,
        Pointer<Utf8>,
        Int32,
        Int32,
        Int32,
        Uint64,
        Pointer<Utf8>,
        Int32,
        Pointer<VeBuffer>,
      ),
      int Function(
        int,
        Pointer<Pointer<Utf8>>,
        Pointer<Pointer<Utf8>>,
        Pointer<Int64>,
        int,
        int,
        Pointer<Utf8>,
        int,
        Pointer<Utf8>,
        int,
        int,
        int,
        int,
        Pointer<Utf8>,
        int,
        Pointer<VeBuffer>,
      )>('ve_archive_create');

  // Check & Repair, header backup, folder-vault check/repair (ABI 11; ve_engine.h).
  late final int Function(int, Pointer<Utf8>, Pointer<Uint8>, int, int, Pointer<Utf8>, Pointer<Utf8>, int, Pointer<VeBuffer>)
      _fvCheck = _lib.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Pointer<Uint8>, Int32, Int32, Pointer<Utf8>, Pointer<Utf8>, Int32, Pointer<VeBuffer>),
          int Function(int, Pointer<Utf8>, Pointer<Uint8>, int, int, Pointer<Utf8>, Pointer<Utf8>, int, Pointer<VeBuffer>)>(
        've_fv_check',
      );
  late final int Function(int, Pointer<Utf8>, Pointer<Uint8>, int, int, Pointer<Utf8>, Pointer<Utf8>, int, Pointer<VeBuffer>)
      _fvRepair = _lib.lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Pointer<Uint8>, Int32, Int32, Pointer<Utf8>, Pointer<Utf8>, Int32, Pointer<VeBuffer>),
          int Function(int, Pointer<Utf8>, Pointer<Uint8>, int, int, Pointer<Utf8>, Pointer<Utf8>, int, Pointer<VeBuffer>)>(
        've_fv_repair',
      );
  late final int Function(int, Pointer<VeBuffer>) _fvConfigFileName =
      _lib.lookupFunction<Int32 Function(Int32, Pointer<VeBuffer>), int Function(int, Pointer<VeBuffer>)>('ve_fv_config_file_name');
  late final int Function(int, Pointer<Uint8>, int, Pointer<VeBuffer>) _fvValidateConfig = _lib.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Int32, Pointer<VeBuffer>),
      int Function(int, Pointer<Uint8>, int, Pointer<VeBuffer>)>('ve_fv_validate_config');
  late final int Function(int, int, Pointer<Int32>, Pointer<Int32>) _repairDiagnoseFile = _lib.lookupFunction<
      Int32 Function(Int32, Int32, Pointer<Int32>, Pointer<Int32>),
      int Function(int, int, Pointer<Int32>, Pointer<Int32>)>('ve_repair_diagnose_file');
  late final int Function(int, int) _repairRestoreLuks2 =
      _lib.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('ve_repair_restore_luks2');
  late final int Function(int, Pointer<Uint8>, int, int, int, int, int, Pointer<Int32>) _repairRestoreVeracrypt =
      _lib.lookupFunction<
          Int32 Function(Int32, Pointer<Uint8>, Int32, Int32, Int32, Int32, Int32, Pointer<Int32>),
          int Function(int, Pointer<Uint8>, int, int, int, int, int, Pointer<Int32>)>('ve_repair_restore_veracrypt');
  late final int Function(int, int, Pointer<Int32>) _repairDiagnoseMounted = _lib.lookupFunction<
      Int32 Function(Int32, Int32, Pointer<Int32>),
      int Function(int, int, Pointer<Int32>)>('ve_repair_diagnose_mounted');
  late final int Function(int, int, Pointer<Int32>) _repairCheckMounted = _lib.lookupFunction<
      Int32 Function(Int32, Int32, Pointer<Int32>),
      int Function(int, int, Pointer<Int32>)>('ve_repair_check_mounted');
  late final int Function(int, int, Pointer<VeBuffer>) _headerExport = _lib.lookupFunction<
      Int32 Function(Int32, Int32, Pointer<VeBuffer>),
      int Function(int, int, Pointer<VeBuffer>)>('ve_header_export');
  late final int Function(int, int, Pointer<Uint8>, int, Pointer<Uint8>, int, int, int, int, int, Pointer<Int32>, int, Pointer<Int32>)
      _headerRestore = _lib.lookupFunction<
          Int32 Function(Int32, Int32, Pointer<Uint8>, Int32, Pointer<Uint8>, Int32, Int32, Int32, Int32, Int32, Pointer<Int32>, Int32, Pointer<Int32>),
          int Function(int, int, Pointer<Uint8>, int, Pointer<Uint8>, int, int, int, int, int, Pointer<Int32>, int, Pointer<Int32>)>(
        've_header_restore',
      );
  // Container tools: expand / grow / hidden volume in an existing container (ABI 12; ve_engine.h).
  late final int Function(int, Pointer<Uint8>, int, int, int, int, Pointer<Int32>, int, int, int, int, Pointer<Int32>) _expandVeracrypt =
      _lib.lookupFunction<
          Int32 Function(Int32, Pointer<Uint8>, Int32, Int32, Int32, Int32, Pointer<Int32>, Int32, Int64, Int32, Int32, Pointer<Int32>),
          int Function(int, Pointer<Uint8>, int, int, int, int, Pointer<Int32>, int, int, int, int, Pointer<Int32>)>('ve_expand_veracrypt');
  late final int Function(int, Pointer<Uint8>, int, Pointer<Int32>, int, int, int, int, Pointer<Int32>) _expandLuks = _lib.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Int32, Pointer<Int32>, Int32, Int64, Int32, Int32, Pointer<Int32>),
      int Function(int, Pointer<Uint8>, int, Pointer<Int32>, int, int, int, int, Pointer<Int32>)>('ve_expand_luks');
  late final int Function(int, Pointer<Uint8>, int, int, int, int, Pointer<Int32>) _expandBitlocker = _lib.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Int32, Int64, Int32, Int32, Pointer<Int32>),
      int Function(int, Pointer<Uint8>, int, int, int, int, Pointer<Int32>)>('ve_expand_bitlocker');
  late final int Function(int, Pointer<Uint8>, int, int, int, int, Pointer<Int32>, int, Pointer<Int32>) _growVeracryptFs = _lib.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Int32, Int32, Int32, Int32, Pointer<Int32>, Int32, Pointer<Int32>),
      int Function(int, Pointer<Uint8>, int, int, int, int, Pointer<Int32>, int, Pointer<Int32>)>('ve_grow_veracrypt_fs');
  late final int Function(int, Pointer<Uint8>, int, Pointer<Int32>, int, Pointer<Int32>) _growLuksFs = _lib.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Int32, Pointer<Int32>, Int32, Pointer<Int32>),
      int Function(int, Pointer<Uint8>, int, Pointer<Int32>, int, Pointer<Int32>)>('ve_grow_luks_fs');
  late final int Function(int, Pointer<Uint8>, int, Pointer<Int32>) _growBitlockerFs = _lib.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Int32, Pointer<Int32>),
      int Function(int, Pointer<Uint8>, int, Pointer<Int32>)>('ve_grow_bitlocker_fs');
  late final int Function(int, Pointer<Uint8>, int, int, int, int, Pointer<Int32>, int, Pointer<Int64>) _hiddenAnalyze = _lib.lookupFunction<
      Int32 Function(Int32, Pointer<Uint8>, Int32, Int32, Int32, Int32, Pointer<Int32>, Int32, Pointer<Int64>),
      int Function(int, Pointer<Uint8>, int, int, int, int, Pointer<Int32>, int, Pointer<Int64>)>('ve_hidden_analyze');
  late final int Function(Pointer<VeHiddenInExistingParams>, Pointer<Int32>) _hiddenCreateInExisting = _lib.lookupFunction<
      Int32 Function(Pointer<VeHiddenInExistingParams>, Pointer<Int32>),
      int Function(Pointer<VeHiddenInExistingParams>, Pointer<Int32>)>('ve_hidden_create_in_existing');
  // Composite containers (ABI 13; ve_engine.h).
  late final int Function(Pointer<Pointer<Utf8>>, int, int, Pointer<VeBuffer>) _compositeProfile = _lib.lookupFunction<
      Int32 Function(Pointer<Pointer<Utf8>>, Int32, Int32, Pointer<VeBuffer>),
      int Function(Pointer<Pointer<Utf8>>, int, int, Pointer<VeBuffer>)>('ve_composite_profile');
  late final int Function(Pointer<VeCompositeCreateParams>, Pointer<VeBuffer>) _compositeCreate = _lib.lookupFunction<
      Int32 Function(Pointer<VeCompositeCreateParams>, Pointer<VeBuffer>),
      int Function(Pointer<VeCompositeCreateParams>, Pointer<VeBuffer>)>('ve_composite_create');
  late final int Function(Pointer<VeCompositeUnlockParams>, Pointer<VeBuffer>) _compositeUnlock = _lib.lookupFunction<
      Int32 Function(Pointer<VeCompositeUnlockParams>, Pointer<VeBuffer>),
      int Function(Pointer<VeCompositeUnlockParams>, Pointer<VeBuffer>)>('ve_composite_unlock');
  late final int Function(int) _format;
  late final int Function(int) _matchedCipher;
  late final int Function(int) _matchedHash;
  late final int Function(int, Pointer<VeVaultInfo>) _vaultInfo;
  late final int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int, int, Pointer<Uint8>, int) _pbkdf2;
  late final int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Size>) _hmac;
  late final int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, int, int, int, Pointer<Uint8>, int) _scrypt;
  late final int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, int, int, int, Pointer<Uint8>, int) _argon2id;
  late final int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<VeBuffer>) _gcmSeal;
  late final int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<VeBuffer>) _gcmOpen;
  late final int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<VeBuffer>) _cbcDecrypt;
  late final int Function(Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<VeBuffer>) _xchachaOpen;
  late final int Function(Pointer<VeChangePasswordParams>) _changePassword;
  late final int Function(Pointer<VeSingleFileParams>) _singleFile;
  late final int Function(int) _hashBegin;
  late final int Function(int, Pointer<Uint8>, int) _hashUpdate;
  late final int Function(int, int, Pointer<Uint8>, int, Pointer<Size>) _hashFinish;
  late final void Function(int) _hashFree;
  late final int Function(int, Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Size>) _hashBytes;
  late final void Function(Pointer<VeBuffer>) _bufferFree;
  late final int Function(int, Pointer<Utf8>, Pointer<VeBuffer>) _list;
  late final int Function(int, Pointer<Utf8>) _fileSize;
  late final int Function(int, Pointer<Utf8>) _folderSize;
  late final int Function(int, Pointer<Utf8>, int, int, Pointer<VeBuffer>) _readChunk;
  late final int Function(int, Pointer<Utf8>, int, Pointer<Uint8>, int) _writeChunk;
  late final int Function(int, Pointer<Utf8>) _delete;
  late final int Function(int, Pointer<Utf8>) _mkdir;
  late final int Function(int, Pointer<Utf8>, Pointer<Utf8>) _rename;
  late final int Function(int, Pointer<Utf8>, int) _setMtime;
  late final int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int) _copy;
  late final int Function(int, Pointer<Utf8>, Pointer<Utf8>, int) _import;
  late final int Function(int, Pointer<Utf8>, Pointer<Utf8>, int) _export;
  late final int Function(int, Pointer<Uint64>, Pointer<Uint64>) _space;
  late final void Function(int, int) _opRegister;
  late final void Function(int) _opCancel;
  late final void Function(int) _opUnregister;
  late final int Function(Pointer<VeEvent>) _poll;

  /// Where the engine library is looked for, in order: $VE_ENGINE_LIBRARY, next to the executable
  /// (the bundle layout the Flutter Linux/Windows build produces), then the system loader path.
  static List<String> candidatePaths() {
    final name = Platform.isWindows ? 'vaultexplorer_engine.dll' : 'libvaultexplorer_engine.so';
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    return [
      if (Platform.environment['VE_ENGINE_LIBRARY'] case final String env when env.isNotEmpty) env,
      '$exeDir$sep$name',
      '$exeDir${sep}lib$sep$name',
      name,
    ];
  }

  static VeNative open([String? explicitPath]) {
    final problems = <String>[];
    for (final path in [if (explicitPath != null) explicitPath, ...candidatePaths()]) {
      final DynamicLibrary lib;
      try {
        lib = DynamicLibrary.open(path);
      } on Object {
        problems.add('$path: not found / not loadable');
        continue;
      }
      // Check the ABI version BEFORE binding anything. A stale library (built from older sources)
      // lacks the newer functions, and the raw "undefined symbol" error says nothing useful.
      final int version;
      try {
        version = lib.lookupFunction<Int32 Function(), int Function()>('ve_abi_version')();
      } on Object {
        problems.add('$path: loaded, but it has no ve_abi_version (not a VaultExplorer engine?)');
        continue;
      }
      if (version != kVeAbiVersion) {
        problems.add('$path: is engine ABI $version but this app needs $kVeAbiVersion. It is out of date: '
            'rebuild it with scripts/build_desktop_engine.sh, then rebuild the app so the bundle gets the new copy '
            '(or run with VE_ENGINE_LIBRARY=<path to the fresh .so>).');
        continue;
      }
      return VeNative._(lib, path);
    }
    throw StateError('Could not load the VaultExplorer engine library:\n${problems.join('\n')}');
  }

  /// Returns the first candidate engine library path that exists on disk, or null.
  static String? resolveExistingLibraryPath() {
    for (final path in candidatePaths()) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  int get maxVolumes => _maxVolumes();

  // ── helpers ────────────────────────────────────────────────────────────

  T _withUtf8<T>(String s, T Function(Pointer<Utf8>) body) {
    final p = s.toNativeUtf8();
    try {
      return body(p);
    } finally {
      calloc.free(p);
    }
  }

  /// Runs [body] with a zeroed, freshly allocated VeBuffer and returns its contents (copied out and
  /// wiped natively) when the call reports success.
  (int, Uint8List?) _withBuffer(int Function(Pointer<VeBuffer>) body) {
    final buf = calloc<VeBuffer>();
    try {
      final rc = body(buf);
      Uint8List? bytes;
      if (rc == veOk && buf.ref.data != nullptr && buf.ref.len > 0) {
        bytes = Uint8List.fromList(buf.ref.data.asTypedList(buf.ref.len));
      } else if (rc == veOk) {
        bytes = Uint8List(0);
      }
      _bufferFree(buf);
      return (rc, bytes);
    } finally {
      calloc.free(buf);
    }
  }

  // ── host files / probing ───────────────────────────────────────────────

  int openFile(String path, {bool writable = false}) => _withUtf8(path, (p) => _openFile(p, writable ? 1 : 0));
  /// Creates (or truncates) [path] for read/write and returns a descriptor, or -1.
  int createFile(String path) => _withUtf8(path, (p) => _createFile(p));
  void closeFd(int fd) => _closeFd(fd);
  String probeFormat(int fd) => _probe(fd).toDartString();

  // ── lifecycle ──────────────────────────────────────────────────────────

  /// Unlocks [containerPath] into slot [volId]. The engine takes ownership of every descriptor
  /// opened here (container + keyfiles), exactly once, on success or failure.
  /// Returns a ve* result code (veOk on success), or -1 when the container file cannot be opened.
  int unlock({
    required String containerPath,
    required Uint8List password,
    required int pim,
    required int volId,
    int cipherId = 255,
    int hashId = 255,
    Uint8List? preservedKey,
    List<String> keyfilePaths = const [],
    bool readOnly = false,
    Uint8List? hiddenPassword,
    int hiddenPim = 0,
    int hiddenCipherId = 255,
    int hiddenHashId = 255,
    List<String> hiddenKeyfilePaths = const [],
  }) {
    final fd = openFile(containerPath, writable: !readOnly);
    if (fd < 0) return -1;

    List<int> openAll(List<String> paths) {
      final fds = <int>[];
      for (final p in paths) {
        final k = openFile(p);
        if (k < 0) {
          for (final f in fds) {
            closeFd(f);
          }
          return const [];
        }
        fds.add(k);
      }
      return fds;
    }

    final kf = openAll(keyfilePaths);
    if (keyfilePaths.isNotEmpty && kf.isEmpty) {
      closeFd(fd);
      return -1;
    }
    final hkf = hiddenPassword != null ? openAll(hiddenKeyfilePaths) : const <int>[];
    if (hiddenPassword != null && hiddenKeyfilePaths.isNotEmpty && hkf.isEmpty) {
      closeFd(fd);
      for (final f in kf) {
        closeFd(f);
      }
      return -1;
    }

    final params = calloc<VeUnlockParams>();
    Pointer<Uint8> copyBytes(Uint8List? src) {
      if (src == null) return nullptr;
      final p = calloc<Uint8>(src.isEmpty ? 1 : src.length);
      p.asTypedList(src.length).setAll(0, src);
      return p;
    }

    Pointer<Int32> copyFds(List<int> fds) {
      if (fds.isEmpty) return nullptr;
      final p = calloc<Int32>(fds.length);
      for (var i = 0; i < fds.length; i++) {
        p[i] = fds[i];
      }
      return p;
    }

    final pw = copyBytes(password);
    final pk = copyBytes(preservedKey);
    final hpw = copyBytes(hiddenPassword);
    final kfp = copyFds(kf);
    final hkfp = copyFds(hkf);
    try {
      final r = params.ref;
      r.structSize = sizeOf<VeUnlockParams>();
      r.fd = fd;
      r.password = pw;
      r.passwordLen = password.length;
      r.pim = pim;
      r.volId = volId;
      r.cipherId = cipherId;
      r.hashId = hashId;
      r.preservedKey = pk;
      r.preservedKeyLen = preservedKey?.length ?? 0;
      r.keyfileFds = kfp;
      r.keyfileCount = kf.length;
      r.readOnly = readOnly ? 1 : 0;
      r.hiddenPassword = hpw;
      r.hiddenPasswordLen = hiddenPassword?.length ?? 0;
      r.hiddenPim = hiddenPim;
      r.hiddenCipherId = hiddenCipherId;
      r.hiddenHashId = hiddenHashId;
      r.hiddenKeyfileFds = hkfp;
      r.hiddenKeyfileCount = hkf.length;
      return _unlock(params);
    } finally {
      // Wipe secrets before freeing.
      if (pw != nullptr) {
        pw.asTypedList(password.length).fillRange(0, password.length, 0);
        calloc.free(pw);
      }
      if (pk != nullptr) {
        pk.asTypedList(preservedKey!.length).fillRange(0, preservedKey.length, 0);
        calloc.free(pk);
      }
      if (hpw != nullptr) {
        hpw.asTypedList(hiddenPassword!.length).fillRange(0, hiddenPassword.length, 0);
        calloc.free(hpw);
      }
      if (kfp != nullptr) calloc.free(kfp);
      if (hkfp != nullptr) calloc.free(hkfp);
      calloc.free(params);
    }
  }

  // ── raw block devices ──────────────────────────────────────────────────

  /// The disks the OS lists (empty where the platform cannot enumerate, or on a read error).
  List<VeBlockDevice> listBlockDevices() {
    final (rc, bytes) = _withBuffer((b) => _listBlockDevices(b));
    if (rc != veOk || bytes == null || bytes.isEmpty) return const [];
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      if (decoded is! List) return const [];
      return [
        for (final row in decoded)
          if (row is Map<String, dynamic>) VeBlockDevice.fromJson(row),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Unlocks the disk, partition or disk image at [devicePath] into slot [volId]: the engine scans its partitions
  /// for LUKS / BitLocker and tries VeraCrypt at the start of the device and of every partition. The engine
  /// takes ownership of the keyfile descriptors opened here, exactly once, on success or failure.
  ///
  /// Returns (ve* result code, OS error number of a failed open). The code is veOk, veErrFailed (no volume on it
  /// opened with these credentials), veErrDevice* (the device itself could not be opened), veErrMountFailed,
  /// veErrCancelled, or -1 when a keyfile cannot be opened.
  (int, int) unlockDevice({
    required String devicePath,
    required Uint8List password,
    required int pim,
    required int volId,
    int cipherId = 255,
    int hashId = 255,
    Uint8List? preservedKey,
    List<String> keyfilePaths = const [],
    bool readOnly = false,
    int partitionOffsetHint = -1,
    Uint8List? hiddenPassword,
    int hiddenPim = 0,
    int hiddenCipherId = 255,
    int hiddenHashId = 255,
    List<String> hiddenKeyfilePaths = const [],
  }) {
    List<int> openAll(List<String> paths) {
      final fds = <int>[];
      for (final p in paths) {
        final k = openFile(p);
        if (k < 0) {
          for (final f in fds) {
            closeFd(f);
          }
          return const [];
        }
        fds.add(k);
      }
      return fds;
    }

    final kf = openAll(keyfilePaths);
    if (keyfilePaths.isNotEmpty && kf.isEmpty) return (-1, 0);
    final hkf = hiddenPassword != null ? openAll(hiddenKeyfilePaths) : const <int>[];
    if (hiddenPassword != null && hiddenKeyfilePaths.isNotEmpty && hkf.isEmpty) {
      for (final f in kf) {
        closeFd(f);
      }
      return (-1, 0);
    }

    Pointer<Uint8> copyBytes(Uint8List? src) {
      if (src == null) return nullptr;
      final p = calloc<Uint8>(src.isEmpty ? 1 : src.length);
      p.asTypedList(src.length).setAll(0, src);
      return p;
    }

    Pointer<Int32> copyFds(List<int> fds) {
      if (fds.isEmpty) return nullptr;
      final p = calloc<Int32>(fds.length);
      for (var i = 0; i < fds.length; i++) {
        p[i] = fds[i];
      }
      return p;
    }

    final params = calloc<VeUnlockDeviceParams>();
    final path = devicePath.toNativeUtf8();
    final osError = calloc<Int32>();
    final pw = copyBytes(password);
    final pk = copyBytes(preservedKey);
    final hpw = copyBytes(hiddenPassword);
    final kfp = copyFds(kf);
    final hkfp = copyFds(hkf);
    try {
      final r = params.ref;
      r.structSize = sizeOf<VeUnlockDeviceParams>();
      r.devicePath = path;
      r.volId = volId;
      r.password = pw;
      r.passwordLen = password.length;
      r.pim = pim;
      r.cipherId = cipherId;
      r.hashId = hashId;
      r.preservedKey = pk;
      r.preservedKeyLen = preservedKey?.length ?? 0;
      r.keyfileFds = kfp;
      r.keyfileCount = kf.length;
      r.readOnly = readOnly ? 1 : 0;
      r.partitionOffsetHint = partitionOffsetHint;
      r.hiddenPassword = hpw;
      r.hiddenPasswordLen = hiddenPassword?.length ?? 0;
      r.hiddenPim = hiddenPim;
      r.hiddenCipherId = hiddenCipherId;
      r.hiddenHashId = hiddenHashId;
      r.hiddenKeyfileFds = hkfp;
      r.hiddenKeyfileCount = hkf.length;
      r.osErrorOut = osError;
      final rc = _unlockDevice(params);
      return (rc, osError.value);
    } finally {
      // Wipe secrets before freeing.
      if (pw != nullptr) {
        pw.asTypedList(password.length).fillRange(0, password.length, 0);
        calloc.free(pw);
      }
      if (pk != nullptr) {
        pk.asTypedList(preservedKey!.length).fillRange(0, preservedKey.length, 0);
        calloc.free(pk);
      }
      if (hpw != nullptr) {
        hpw.asTypedList(hiddenPassword!.length).fillRange(0, hiddenPassword.length, 0);
        calloc.free(hpw);
      }
      if (kfp != nullptr) calloc.free(kfp);
      if (hkfp != nullptr) calloc.free(hkfp);
      calloc.free(path);
      calloc.free(osError);
      calloc.free(params);
    }
  }

  // ── crypto primitives ──────────────────────────────────────────────────
  // Inputs (often passwords or keys) are copied into native memory for the call and wiped before it
  // is freed. Every function returns (resultCode, bytes?): bytes is null unless the code is veOk.

  (int, Uint8List?) _fixedOut(int outLen, List<Uint8List?> inputs, int Function(List<_Pin> pins, Pointer<Uint8> out) body) {
    if (outLen <= 0) return (veErrInvalidArg, null);
    final pins = [for (final i in inputs) _Pin(i)];
    final out = calloc<Uint8>(outLen);
    try {
      final rc = body(pins, out);
      return (rc, rc == veOk ? Uint8List.fromList(out.asTypedList(outLen)) : null);
    } finally {
      out.asTypedList(outLen).fillRange(0, outLen, 0);
      calloc.free(out);
      for (final p in pins) {
        p.release();
      }
    }
  }

  (int, Uint8List?) _bufferOut(List<Uint8List?> inputs, int Function(List<_Pin> pins, Pointer<VeBuffer> out) body) {
    final pins = [for (final i in inputs) _Pin(i)];
    try {
      return _withBuffer((b) => body(pins, b));
    } finally {
      for (final p in pins) {
        p.release();
      }
    }
  }

  (int, Uint8List?) pbkdf2(int hash, Uint8List password, Uint8List salt, int iterations, int outLen) =>
      _fixedOut(outLen, [password, salt], (p, out) =>
          _pbkdf2(hash, p[0].ptr, p[0].len, p[1].ptr, p[1].len, iterations, out, outLen));

  (int, Uint8List?) hmac(int hash, Uint8List key, Uint8List data) {
    final out = calloc<Uint8>(64);
    final written = calloc<Size>();
    final kp = _Pin(key);
    final dp = _Pin(data);
    try {
      final rc = _hmac(hash, kp.ptr, kp.len, dp.ptr, dp.len, out, 64, written);
      return (rc, rc == veOk ? Uint8List.fromList(out.asTypedList(written.value)) : null);
    } finally {
      kp.release();
      dp.release();
      calloc.free(out);
      calloc.free(written);
    }
  }

  (int, Uint8List?) scrypt(Uint8List password, Uint8List salt, int n, int r, int p, int dkLen) =>
      _fixedOut(dkLen, [password, salt], (pins, out) =>
          _scrypt(pins[0].ptr, pins[0].len, pins[1].ptr, pins[1].len, n, r, p, out, dkLen));

  (int, Uint8List?) argon2id(Uint8List password, Uint8List salt, int memoryKiB, int iterations, int parallelism, int outLen) =>
      _fixedOut(outLen, [password, salt], (pins, out) =>
          _argon2id(pins[0].ptr, pins[0].len, pins[1].ptr, pins[1].len, memoryKiB, iterations, parallelism, out, outLen));

  (int, Uint8List?) aesGcmSeal(Uint8List key, Uint8List iv, Uint8List? aad, Uint8List plaintext) =>
      _bufferOut([key, iv, aad, plaintext], (p, b) =>
          _gcmSeal(p[0].ptr, p[0].len, p[1].ptr, p[1].len, p[2].ptr, p[2].len, p[3].ptr, p[3].len, b));

  (int, Uint8List?) aesGcmOpen(Uint8List key, Uint8List iv, Uint8List? aad, Uint8List ciphertextAndTag) =>
      _bufferOut([key, iv, aad, ciphertextAndTag], (p, b) =>
          _gcmOpen(p[0].ptr, p[0].len, p[1].ptr, p[1].len, p[2].ptr, p[2].len, p[3].ptr, p[3].len, b));

  (int, Uint8List?) aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List ciphertext) =>
      _bufferOut([key, iv, ciphertext], (p, b) =>
          _cbcDecrypt(p[0].ptr, p[0].len, p[1].ptr, p[1].len, p[2].ptr, p[2].len, b));

  (int, Uint8List?) xchacha20Poly1305Open(Uint8List key, Uint8List nonce, Uint8List? aad, Uint8List ciphertextAndTag) =>
      _bufferOut([key, nonce, aad, ciphertextAndTag], (p, b) =>
          _xchachaOpen(p[0].ptr, p[0].len, p[1].ptr, p[1].len, p[2].ptr, p[2].len, p[3].ptr, p[3].len, b));

  // ── single-file encryption ─────────────────────────────────────────────

  /// Encrypts / decrypts the host file [srcPath] into a NEW file at [destPath]. Returns a ve* code
  /// (veOk, veErrCancelled, veErrFailed -- a wrong password or a corrupt file on decrypt), or -1
  /// when a file cannot be opened/created. On any non-ok result the caller deletes [destPath].
  /// Register [opId] with opRegister() first to make the run cancellable.
  int singleFileCrypt({
    required String srcPath,
    required String destPath,
    required bool encrypt,
    required Uint8List password,
    int cipherIndex = 0,
    List<String> keyfilePaths = const [],
    int opId = 0,
  }) {
    final kf = <int>[];
    void closeAll(int a, int b) {
      if (a >= 0) closeFd(a);
      if (b >= 0) closeFd(b);
      for (final x in kf) {
        closeFd(x);
      }
    }

    final src = openFile(srcPath);
    final dest = src < 0 ? -1 : createFile(destPath);
    if (src < 0 || dest < 0) {
      closeAll(src, dest);
      return -1;
    }
    for (final k in keyfilePaths) {
      final f = openFile(k);
      if (f < 0) {
        closeAll(src, dest);
        return -1;
      }
      kf.add(f);
    }

    final pin = _Pin(password);
    final params = calloc<VeSingleFileParams>();
    Pointer<Int32> kfPtr = nullptr;
    if (kf.isNotEmpty) {
      kfPtr = calloc<Int32>(kf.length);
      for (var i = 0; i < kf.length; i++) {
        kfPtr[i] = kf[i];
      }
    }
    try {
      final r = params.ref;
      r.structSize = sizeOf<VeSingleFileParams>();
      r.srcFd = src;
      r.destFd = dest;
      r.encrypt = encrypt ? 1 : 0;
      r.cipherIndex = cipherIndex;
      r.password = pin.ptr;
      r.passwordLen = pin.len;
      r.keyfileFds = kfPtr;
      r.keyfileCount = kf.length;
      r.opId = opId;
      return _singleFile(params);
    } finally {
      pin.release();
      if (kfPtr != nullptr) calloc.free(kfPtr);
      calloc.free(params);
    }
  }

  // ── streaming digests ──────────────────────────────────────────────────

  /// Opens a digest session for the algorithms in [mask] (bit 1 << veHash*). 0 on failure.
  int hashBegin(int mask) => _hashBegin(mask);
  void hashFree(int handle) => _hashFree(handle);

  int hashUpdate(int handle, Uint8List data) {
    final pin = _Pin(data);
    try {
      return _hashUpdate(handle, pin.ptr, pin.len);
    } finally {
      pin.release();
    }
  }

  (int, Uint8List?) hashFinish(int handle, int algorithm) {
    final out = calloc<Uint8>(64);
    final n = calloc<Size>();
    try {
      final rc = _hashFinish(handle, algorithm, out, 64, n);
      return (rc, rc == veOk ? Uint8List.fromList(out.asTypedList(n.value)) : null);
    } finally {
      calloc.free(out);
      calloc.free(n);
    }
  }

  (int, Uint8List?) hashBytes(int algorithm, Uint8List data) {
    final pin = _Pin(data);
    final out = calloc<Uint8>(64);
    final n = calloc<Size>();
    try {
      final rc = _hashBytes(algorithm, pin.ptr, pin.len, out, 64, n);
      return (rc, rc == veOk ? Uint8List.fromList(out.asTypedList(n.value)) : null);
    } finally {
      pin.release();
      calloc.free(out);
      calloc.free(n);
    }
  }

  // ── password change ────────────────────────────────────────────────────

  /// Changes the password / PIM / keyfiles of the container FILE at [path] ([containerFormat]: 0 =
  /// VeraCrypt, 1/2 = LUKS). Returns a ve* code: veOk, veErrAuthFailed (LUKS: the old password did
  /// not verify), veErrFailed, or -1 when the container / a keyfile cannot be opened.
  int changePassword({
    required String path,
    required int containerFormat,
    required Uint8List oldPassword,
    required Uint8List newPassword,
    int oldPim = 0,
    int newPim = 0,
    int cipherId = 255,
    int hashId = 255,
    List<String> oldKeyfilePaths = const [],
    List<String> newKeyfilePaths = const [],
  }) {
    final opened = <int>[];
    List<int>? openKeyfiles(List<String> paths) {
      final fds = <int>[];
      for (final k in paths) {
        final f = openFile(k);
        if (f < 0) {
          for (final x in fds) {
            closeFd(x);
          }
          return null;
        }
        fds.add(f);
      }
      opened.addAll(fds);
      return fds;
    }

    final oldKf = openKeyfiles(oldKeyfilePaths);
    final newKf = oldKf == null ? null : openKeyfiles(newKeyfilePaths);
    if (oldKf == null || newKf == null) {
      for (final x in opened) {
        closeFd(x);
      }
      return -1;
    }
    final fd = openFile(path, writable: true);
    if (fd < 0) {
      for (final x in opened) {
        closeFd(x);
      }
      return -1;
    }

    final oldPin = _Pin(oldPassword);
    final newPin = _Pin(newPassword);
    final params = calloc<VeChangePasswordParams>();
    Pointer<Int32> fdArray(List<int> fds) {
      if (fds.isEmpty) return nullptr;
      final p = calloc<Int32>(fds.length);
      for (var i = 0; i < fds.length; i++) {
        p[i] = fds[i];
      }
      return p;
    }

    final oldKfPtr = fdArray(oldKf);
    final newKfPtr = fdArray(newKf);
    try {
      final r = params.ref;
      r.structSize = sizeOf<VeChangePasswordParams>();
      r.fd = fd;
      r.containerFormat = containerFormat;
      r.oldPassword = oldPin.ptr;
      r.oldPasswordLen = oldPin.len;
      r.newPassword = newPin.ptr;
      r.newPasswordLen = newPin.len;
      r.oldPim = oldPim;
      r.newPim = newPim;
      r.cipherId = cipherId;
      r.hashId = hashId;
      r.oldKeyfileFds = oldKfPtr;
      r.oldKeyfileCount = oldKf.length;
      r.newKeyfileFds = newKfPtr;
      r.newKeyfileCount = newKf.length;
      return _changePassword(params);
    } finally {
      oldPin.release();
      newPin.release();
      if (oldKfPtr != nullptr) calloc.free(oldKfPtr);
      if (newKfPtr != nullptr) calloc.free(newKfPtr);
      calloc.free(params);
    }
  }

  // ── container creation ─────────────────────────────────────────────────

  /// Creates a new container in a NEW file at [path] (VeraCrypt, or LUKS1/2 via [containerFormat]
  /// 1/2; with [hiddenPassword] a VeraCrypt container with an embedded hidden volume).
  /// Returns a ve* result code, or -1 when the file / a keyfile cannot be opened. On any failure
  /// the caller should delete [path]. Secrets are wiped from native memory before returning.
  int createContainer({
    required String path,
    required Uint8List password,
    required int pim,
    required int sizeBytes,
    required String fileSystem,
    int containerFormat = 0,
    int cipherId = 255,
    int hashId = 255,
    List<String> keyfilePaths = const [],
    bool quickFormat = false,
    Uint8List? userEntropy,
    Uint8List? hiddenPassword,
    String? hiddenFileSystem,
    int hiddenSizeBytes = 0,
    int hiddenPim = 0,
    int hiddenCipherId = 255,
    int hiddenHashId = 255,
    List<String> hiddenKeyfilePaths = const [],
  }) {
    List<int>? openKeyfiles(List<String> paths) {
      final fds = <int>[];
      for (final k in paths) {
        final f = openFile(k);
        if (f < 0) {
          for (final x in fds) {
            closeFd(x);
          }
          return null;
        }
        fds.add(f);
      }
      return fds;
    }

    final kf = openKeyfiles(keyfilePaths);
    if (kf == null) return -1;
    final hidden = hiddenPassword != null;
    final hkf = hidden ? openKeyfiles(hiddenKeyfilePaths) : <int>[];
    if (hkf == null) {
      for (final x in kf) {
        closeFd(x);
      }
      return -1;
    }
    final fd = createFile(path);
    if (fd < 0) {
      for (final x in [...kf, ...hkf]) {
        closeFd(x);
      }
      return -1;
    }

    final allocated = <Pointer<NativeType>>[]; // freed in finally
    final secrets = <(Pointer<Uint8>, int)>[]; // wiped, then freed
    Pointer<Uint8> secretBytes(Uint8List? src) {
      if (src == null) return nullptr;
      final p = calloc<Uint8>(src.isEmpty ? 1 : src.length);
      p.asTypedList(src.length).setAll(0, src);
      secrets.add((p, src.length));
      return p;
    }

    Pointer<Int32> fdArray(List<int> fds) {
      if (fds.isEmpty) return nullptr;
      final p = calloc<Int32>(fds.length);
      for (var i = 0; i < fds.length; i++) {
        p[i] = fds[i];
      }
      allocated.add(p);
      return p;
    }

    Pointer<Utf8> cString(String s) {
      final p = s.toNativeUtf8();
      allocated.add(p);
      return p;
    }

    try {
      if (!hidden) {
        final params = calloc<VeCreateParams>();
        allocated.add(params);
        final r = params.ref;
        r.structSize = sizeOf<VeCreateParams>();
        r.fd = fd;
        r.password = secretBytes(password);
        r.passwordLen = password.length;
        r.pim = pim;
        r.sizeBytes = sizeBytes;
        r.fileSystem = cString(fileSystem);
        r.containerFormat = containerFormat;
        r.cipherId = cipherId;
        r.hashId = hashId;
        r.keyfileFds = fdArray(kf);
        r.keyfileCount = kf.length;
        r.quickFormat = quickFormat ? 1 : 0;
        r.userEntropy = secretBytes(userEntropy);
        r.userEntropyLen = userEntropy?.length ?? 0;
        return _createContainer(params);
      }
      final params = calloc<VeCreateHiddenParams>();
      allocated.add(params);
      final r = params.ref;
      r.structSize = sizeOf<VeCreateHiddenParams>();
      r.fd = fd;
      r.outerPassword = secretBytes(password);
      r.outerPasswordLen = password.length;
      r.hiddenPassword = secretBytes(hiddenPassword);
      r.hiddenPasswordLen = hiddenPassword.length;
      r.outerPim = pim;
      r.hiddenPim = hiddenPim;
      r.sizeBytes = sizeBytes;
      r.outerFileSystem = cString(fileSystem);
      r.hiddenFileSystem = cString(hiddenFileSystem ?? 'fat');
      r.hiddenSizeBytes = hiddenSizeBytes;
      r.outerCipherId = cipherId;
      r.outerHashId = hashId;
      r.hiddenCipherId = hiddenCipherId;
      r.hiddenHashId = hiddenHashId;
      r.outerKeyfileFds = fdArray(kf);
      r.outerKeyfileCount = kf.length;
      r.hiddenKeyfileFds = fdArray(hkf);
      r.hiddenKeyfileCount = hkf.length;
      r.quickFormat = quickFormat ? 1 : 0;
      r.userEntropy = secretBytes(userEntropy);
      r.userEntropyLen = userEntropy?.length ?? 0;
      return _createHidden(params);
    } finally {
      for (final (p, len) in secrets) {
        p.asTypedList(len).fillRange(0, len, 0);
        calloc.free(p);
      }
      for (final p in allocated) {
        calloc.free(p);
      }
    }
  }

  void requestCancelUnlock(int volId) => _cancelUnlock(volId);
  void lock(int volId) => _lock(volId);

  // ── OS mounts: expose an unlocked slot as a real folder (Linux: FUSE 3) ──

  /// (available, reason when not). Cheap; safe to call repeatedly.
  (bool, String) mountSupported() {
    if (!hasMounts) return (false, 'this engine build has no OS-mount support');
    final buf = calloc<Uint8>(256);
    try {
      final ok = _mountSupported(buf.cast<Utf8>(), 256) == 1;
      return (ok, buf.cast<Utf8>().toDartString());
    } finally {
      calloc.free(buf);
    }
  }

  /// Why the most recent mount/unmount failed, in words a user can act on.
  String mountLastError() {
    if (!hasMounts) return '';
    final buf = calloc<Uint8>(512);
    try {
      _mountLastError(buf.cast<Utf8>(), 512);
      return buf.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buf);
    }
  }

  /// Mounts [volId] (or its folder [subPath], vault-relative, e.g. `/Documents`) at [mountPoint].
  /// Returns (veOk | ve* error, mount id). Blocks until the mount is serving requests: call it from a
  /// worker isolate, not the UI isolate.
  (int, int) mount(
    int volId,
    String mountPoint, {
    bool readOnly = false,
    bool allowOther = false,
    int maxBufferMb = 0,
    String? volumeName,
    String? subPath,
  }) {
    if (!hasMounts) return (veErrUnsupported, 0);
    final opts = calloc<VeMountOptions>();
    final outId = calloc<Int64>();
    Pointer<Utf8>? name;
    Pointer<Utf8>? sub;
    try {
      name = volumeName?.toNativeUtf8();
      sub = subPath?.toNativeUtf8();
      opts.ref
        ..structSize = sizeOf<VeMountOptions>()
        ..readOnly = readOnly ? 1 : 0
        ..allowOther = allowOther ? 1 : 0
        ..maxBufferMb = maxBufferMb
        ..volumeName = name ?? nullptr
        ..subPath = sub ?? nullptr;
      final rc = _withUtf8(mountPoint, (mp) => _mount(volId, mp, opts, outId));
      return (rc, rc == veOk ? outId.value : 0);
    } finally {
      if (name != null) calloc.free(name);
      if (sub != null) calloc.free(sub);
      calloc.free(opts);
      calloc.free(outId);
    }
  }

  /// [force] false returns [veErrBusy] while files are open; true detaches regardless. Also reaps a
  /// mount that already ended on its own.
  int unmount(int mountId, {bool force = false}) => hasMounts ? _unmount(mountId, force ? 1 : 0) : veOk;

  List<VeMountInfo> listMounts() {
    if (!hasMounts) return const [];
    final (rc, bytes) = _withBuffer((b) => _listMounts(b));
    if (rc != veOk || bytes == null || bytes.length < 4) return const [];
    final bd = ByteData.sublistView(bytes);
    final count = bd.getUint32(0, Endian.little);
    final out = <VeMountInfo>[];
    var off = 4;
    for (var i = 0; i < count && off + 4 <= bytes.length; i++) {
      final len = bd.getUint32(off, Endian.little);
      off += 4;
      if (off + len > bytes.length) break;
      final row = utf8.decode(Uint8List.sublistView(bytes, off, off + len), allowMalformed: true);
      off += len;
      final parts = row.split('|');
      if (parts.length < 4) continue;
      out.add(VeMountInfo(
        id: int.tryParse(parts[0]) ?? 0,
        volId: int.tryParse(parts[1]) ?? -1,
        ended: parts[2] == 'ended',
        mountPoint: parts.sublist(3).join('|'),
      ));
    }
    return out;
  }
  int containerFormat(int volId) => _format(volId);
  int matchedCipherId(int volId) => _matchedCipher(volId);
  int matchedHashId(int volId) => _matchedHash(volId);

  // ── filesystem ─────────────────────────────────────────────────────────

  /// The "Vault information" map, with the same keys the Android bridge produces:
  /// readOnly, volumeSizeBytes, fileSystem?, and per format cipherId/hashId/hiddenVolume (VeraCrypt)
  /// or luksVersion/cipherId/sectorSize (LUKS). BitLocker only has the first three.
  (int, Map<String, Object?>?) vaultInfo(int volId) {
    if (_format(volId) >= 10) return fvInfo(volId); // gocryptfs / Cryptomator / CryFS slot
    final p = calloc<VeVaultInfo>();
    try {
      p.ref.structSize = sizeOf<VeVaultInfo>();
      final rc = _vaultInfo(volId, p);
      if (rc != veOk) return (rc, null);
      final r = p.ref;
      final map = <String, Object?>{
        'readOnly': r.readOnly != 0,
        'volumeSizeBytes': r.volumeSizeBytes,
      };
      if (r.hasFileSystem != 0) {
        final chars = <int>[];
        for (var i = 0; i < 64; i++) {
          final c = r.fileSystem[i];
          if (c == 0) break;
          chars.add(c);
        }
        map['fileSystem'] = utf8.decode(chars, allowMalformed: true);
      }
      switch (r.containerFormat) {
        case 0:
          map['cipherId'] = r.cipherId;
          map['hashId'] = r.hashId;
          map['hiddenVolume'] = r.hiddenVolume != 0;
        case 1 || 2:
          map['luksVersion'] = r.luksVersion;
          map['cipherId'] = r.cipherId;
          map['sectorSize'] = r.sectorSize;
      }
      return (rc, map);
    } finally {
      calloc.free(p);
    }
  }

  /// (resultCode, entries). Entries are the engine's directory-entry wire strings.
  (int, List<String>) listDirectory(int volId, String path) {
    final (rc, bytes) = _withUtf8(path, (p) => _withBuffer((b) => _list(volId, p, b)));
    if (rc != veOk || bytes == null || bytes.length < 4) return (rc, const []);
    final bd = ByteData.sublistView(bytes);
    final count = bd.getUint32(0, Endian.little);
    final out = <String>[];
    var off = 4;
    for (var i = 0; i < count && off + 4 <= bytes.length; i++) {
      final len = bd.getUint32(off, Endian.little);
      off += 4;
      if (off + len > bytes.length) break;
      out.add(utf8.decode(Uint8List.sublistView(bytes, off, off + len), allowMalformed: true));
      off += len;
    }
    return (rc, out);
  }

  /// >= 0 size, -1 when the path does not exist, or another negative -veErr* code.
  int fileSize(int volId, String path) => _withUtf8(path, (p) => _fileSize(volId, p));
  int folderSize(int volId, String path) => _withUtf8(path, (p) => _folderSize(volId, p));

  (int, Uint8List?) readFileChunk(int volId, String path, int offset, int length) =>
      _withUtf8(path, (p) => _withBuffer((b) => _readChunk(volId, p, offset, length, b)));

  int writeFileChunk(int volId, String path, int offset, Uint8List data) {
    final buf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      buf.asTypedList(data.length).setAll(0, data);
      return _withUtf8(path, (p) => _writeChunk(volId, p, offset, buf, data.length));
    } finally {
      buf.asTypedList(data.length).fillRange(0, data.length, 0);
      calloc.free(buf);
    }
  }

  int deleteFile(int volId, String path) => _withUtf8(path, (p) => _delete(volId, p));
  int createDirectory(int volId, String path) => _withUtf8(path, (p) => _mkdir(volId, p));
  int renameFile(int volId, String from, String to) =>
      _withUtf8(from, (a) => _withUtf8(to, (b) => _rename(volId, a, b)));
  int setLastModified(int volId, String path, int epochSeconds) =>
      _withUtf8(path, (p) => _setMtime(volId, p, epochSeconds));

  int copyFile(int srcVol, String src, int dstVol, String dst, int opId) =>
      _withUtf8(src, (a) => _withUtf8(dst, (b) => _copy(srcVol, a, dstVol, b, opId)));
  int importFile(int volId, String vaultPath, String hostSource, int opId) =>
      _withUtf8(vaultPath, (a) => _withUtf8(hostSource, (b) => _import(volId, a, b, opId)));
  int exportFile(int volId, String vaultPath, String hostDest, int opId) =>
      _withUtf8(vaultPath, (a) => _withUtf8(hostDest, (b) => _export(volId, a, b, opId)));

  /// (resultCode, [total, free])
  (int, List<int>) spaceInfo(int volId) {
    final t = calloc<Uint64>();
    final f = calloc<Uint64>();
    try {
      final rc = _space(volId, t, f);
      return (rc, rc == veOk ? [t.value, f.value] : const <int>[]);
    } finally {
      calloc.free(t);
      calloc.free(f);
    }
  }

  // ── folder vaults (gocryptfs / Cryptomator / CryFS) ────────────────────
  //
  // Once unlocked, a folder vault is addressed through its slot with every ordinary call above
  // (listDirectory, readFileChunk, copyFile, ...). Only what is specific to the format lives here.

  /// False on builds without the folder-vault core (Windows, for now).
  bool get fvSupported => _fvSupported() != 0;

  /// The folder-vault format [root] looks like (veFv*), or -1.
  int fvProbe(String root) {
    final out = calloc<Int32>();
    try {
      final rc = _withUtf8(root, (p) => _fvProbe(p, out));
      return rc == veOk ? out.value : -1;
    } finally {
      calloc.free(out);
    }
  }

  /// Copies [data] to native memory for the duration of [body] and wipes it afterwards.
  T _withBytes<T>(Uint8List? data, T Function(Pointer<Uint8> ptr, int len) body) {
    if (data == null) return body(nullptr, 0);
    final buf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      buf.asTypedList(data.length).setAll(0, data);
      return body(buf, data.length);
    } finally {
      buf.asTypedList(data.isEmpty ? 1 : data.length).fillRange(0, data.isEmpty ? 1 : data.length, 0);
      calloc.free(buf);
    }
  }

  /// Takes the contents of [b] (wiping and freeing the native copy) or null when it is empty.
  Uint8List? _takeBuffer(Pointer<VeBuffer> b) {
    Uint8List? bytes;
    if (b.ref.data != nullptr && b.ref.len > 0) bytes = Uint8List.fromList(b.ref.data.asTypedList(b.ref.len));
    _bufferFree(b);
    return bytes;
  }

  String? _takeMessage(Pointer<VeBuffer> b) {
    final bytes = _takeBuffer(b);
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// Opens the vault at [root] into slot [volId]. `rc` is veOk / veErrAuthFailed (wrong password) /
  /// veErrFailed (not a vault, I/O error); [derivedKey] is the CryFS key the caller may remember.
  ({int rc, String? message, Uint8List? derivedKey}) fvUnlock({
    required int volId,
    required int format,
    required String root,
    required Uint8List password,
    Uint8List? combinedKey,
    bool readOnly = false,
    bool backupKeyFiles = true,
    String localStateDir = '',
    String tempDir = '',
  }) {
    final msg = calloc<VeBuffer>();
    final key = calloc<VeBuffer>();
    final localP = localStateDir.toNativeUtf8();
    final tempP = tempDir.toNativeUtf8();
    try {
      final rc = _withUtf8(
        root,
        (r) => _withBytes(
          password,
          (pw, pwLen) => _withBytes(
            combinedKey,
            (ck, ckLen) => _fvUnlock(volId, format, r, pw, pwLen, ck, ckLen, readOnly ? 1 : 0, backupKeyFiles ? 1 : 0, localP, tempP, msg, key),
          ),
        ),
      );
      return (rc: rc, message: _takeMessage(msg), derivedKey: _takeBuffer(key));
    } finally {
      calloc.free(msg);
      calloc.free(key);
      calloc.free(localP);
      calloc.free(tempP);
    }
  }

  /// Creates a vault in the (empty) directory [root]. See ve_fv_create for the option meanings.
  ({int rc, String? message}) fvCreate({
    required int format,
    required String root,
    required Uint8List password,
    int cipher = 0,
    bool plaintextNames = false,
    bool deterministicNames = false,
    int longNameMax = 0,
    int blockSize = 0,
    String cipherName = '',
    Uint8List? userEntropy,
    String localStateDir = '',
    String tempDir = '',
  }) {
    final msg = calloc<VeBuffer>();
    final cipherP = cipherName.toNativeUtf8();
    final localP = localStateDir.toNativeUtf8();
    final tempP = tempDir.toNativeUtf8();
    try {
      final rc = _withUtf8(
        root,
        (r) => _withBytes(
          password,
          (pw, pwLen) => _withBytes(
            userEntropy,
            (ue, ueLen) => _fvCreate(format, r, pw, pwLen, cipher, plaintextNames ? 1 : 0, deterministicNames ? 1 : 0,
                longNameMax, blockSize, cipherP, ue, ueLen, localP, tempP, msg),
          ),
        ),
      );
      return (rc: rc, message: _takeMessage(msg));
    } finally {
      calloc.free(msg);
      calloc.free(cipherP);
      calloc.free(localP);
      calloc.free(tempP);
    }
  }

  ({int rc, String? message}) fvChangePassword({
    required int format,
    required String root,
    required Uint8List oldPassword,
    required Uint8List newPassword,
  }) {
    final msg = calloc<VeBuffer>();
    try {
      final rc = _withUtf8(
        root,
        (r) => _withBytes(
          oldPassword,
          (o, oLen) => _withBytes(newPassword, (n, nLen) => _fvChangePassword(format, r, o, oLen, n, nLen, msg)),
        ),
      );
      return (rc: rc, message: _takeMessage(msg));
    } finally {
      calloc.free(msg);
    }
  }

  ({int rc, String? message}) fvMigrateCryptomator({required String root, required Uint8List password}) {
    final msg = calloc<VeBuffer>();
    try {
      final rc = _withUtf8(root, (r) => _withBytes(password, (pw, pwLen) => _fvMigrate(r, pw, pwLen, msg)));
      return (rc: rc, message: _takeMessage(msg));
    } finally {
      calloc.free(msg);
    }
  }

  /// The vault's own properties plus `readOnly`, with the keys/types the info screen reads.
  (int, Map<String, Object?>?) fvInfo(int volId) {
    final (rc, bytes) = _withBuffer((b) => _fvInfo(volId, b));
    if (rc != veOk || bytes == null || bytes.length < 4) return (rc, null);
    final bd = ByteData.sublistView(bytes);
    var off = 0;
    String? readStr() {
      if (off + 4 > bytes.length) return null;
      final len = bd.getUint32(off, Endian.little);
      off += 4;
      if (off + len > bytes.length) return null;
      final s = utf8.decode(Uint8List.sublistView(bytes, off, off + len), allowMalformed: true);
      off += len;
      return s;
    }

    final count = bd.getUint32(off, Endian.little);
    off += 4;
    final map = <String, Object?>{};
    for (var i = 0; i < count; i++) {
      final key = readStr();
      final kind = readStr();
      final value = readStr();
      if (key == null || kind == null || value == null) break;
      map[key] = switch (kind) {
        'i' => int.tryParse(value) ?? 0,
        'b' => value == 'true',
        _ => value,
      };
    }
    return (rc, map);
  }

  /// Password-free format check of a Cryptomator vault folder: 0 not a readable vault, 7 migratable,
  /// 8 current, -8 key file is v8+ but vault.cryptomator has not synced yet (never migrate), 6 too old.
  int fvProbeCryptomator(String root) {
    final out = calloc<Int32>();
    try {
      final rc = _withUtf8(root, (p) => _fvProbeCryptomator(p, out));
      return rc == veOk ? out.value : 0;
    } finally {
      calloc.free(out);
    }
  }

  // ── symbolic links (any slot: ext/NTFS containers and Cryptomator vaults) ──

  /// Only the symlinks directly inside [path], as directory-entry wire strings:
  /// "L|targetBytes|mtime|name", or "LD|0|mtime|name" when the target is a directory.
  (int, List<String>) listSymlinks(int volId, String path) {
    final (rc, bytes) = _withUtf8(path, (p) => _withBuffer((b) => _listSymlinks(volId, p, b)));
    if (rc != veOk || bytes == null || bytes.length < 4) return (rc, const []);
    final bd = ByteData.sublistView(bytes);
    final count = bd.getUint32(0, Endian.little);
    final out = <String>[];
    var off = 4;
    for (var i = 0; i < count && off + 4 <= bytes.length; i++) {
      final len = bd.getUint32(off, Endian.little);
      off += 4;
      if (off + len > bytes.length) break;
      out.add(utf8.decode(Uint8List.sublistView(bytes, off, off + len), allowMalformed: true));
      off += len;
    }
    return (rc, out);
  }

  /// The raw target of the link at [path] (never followed), or null if it is not a readable link.
  (int, String?) readSymlink(int volId, String path) {
    final (rc, bytes) = _withUtf8(path, (p) => _withBuffer((b) => _readSymlink(volId, p, b)));
    return (rc, rc == veOk && bytes != null ? utf8.decode(bytes, allowMalformed: true) : null);
  }

  int createSymlink(int volId, String path, String target) =>
      _withUtf8(path, (p) => _withUtf8(target, (t) => _createSymlink(volId, p, t)));

  /// Entries hidden from listings in [path] (>= 0), or a negative -veErr* code.
  int fvHiddenEntryCount(int volId, String path) => _withUtf8(path, (p) => _fvHidden(volId, p));
  int fvFinishWrite(int volId, String path) => _withUtf8(path, (p) => _fvFinishWrite(volId, p));

  // ── video thumbnails (ABI 16) ───────────────────────────────────────────
  // Same reply as the image calls (rc, bytes, info), with info[7] = the duration in milliseconds (0 = unknown) and
  // info[1]/[2] the picture as shown. [strategy]: 0 the start, 1 the picture at [framePosition], 2 the start and, when
  // it looks blank, the first not-blank one at [framePosition] / 25% / 45%. [explicitTimeUs] >= 0 wins over all of it.
  // rc veErrUnsupported: this engine cannot open or decode it (or was built without FFmpeg): use another route.

  /// A thumbnail of the video at [path] inside unlocked slot [volId].
  (int, Uint8List?, List<int>) videoThumbnail(
    int volId,
    String path, {
    required int targetSize,
    required int quality,
    required int strategy,
    required double framePosition,
    required int explicitTimeUs,
    required int timeoutMs,
  }) =>
      _withUtf8(
        path,
        (p) => _imageCall((b, info) => _videoThumbnail(
            volId, p, targetSize, quality, strategy, framePosition, explicitTimeUs, timeoutMs, b, info)),
      );

  /// A thumbnail of a video file on this machine.
  (int, Uint8List?, List<int>) videoThumbnailFile(
    String hostPath, {
    required int targetSize,
    required int quality,
    required int strategy,
    required double framePosition,
    required int explicitTimeUs,
    required int timeoutMs,
  }) =>
      _withUtf8(
        hostPath,
        (p) => _imageCall((b, info) => _videoThumbnailFile(
            p, targetSize, quality, strategy, framePosition, explicitTimeUs, timeoutMs, b, info)),
      );

  // ── image thumbnails (ABI 15) ───────────────────────────────────────────
  // Each call answers (rc, thumbnail bytes, info). `info` is VE_IMAGE_INFO_COUNT ints, in this order:
  // isPng (0 JPEG / 1 PNG), source width, source height, thumbnail width, thumbnail height, hasAlpha, isBlank.
  // rc: veOk; veErrUnsupported when this decoder does not handle the format (use another one); veErrTooLarge;
  // veErrNoMemory; veErrNotUnlocked / veErrInvalidArg; otherwise veErrFailed.

  static const int _imageInfoCount = 8;

  (int, Uint8List?, List<int>) _imageCall(int Function(Pointer<VeBuffer>, Pointer<Int32>) body) {
    final info = calloc<Int32>(_imageInfoCount);
    try {
      final (rc, bytes) = _withBuffer((b) => body(b, info));
      return (rc, bytes, rc == veOk ? List<int>.generate(_imageInfoCount, (i) => info[i]) : const <int>[]);
    } finally {
      calloc.free(info);
    }
  }

  /// A thumbnail of the picture at [path] inside unlocked slot [volId].
  (int, Uint8List?, List<int>) imageThumbnail(
    int volId,
    String path, {
    required int targetSize,
    required int quality,
    required bool preserveAlpha,
    required int maxSourceBytes,
  }) =>
      _withUtf8(
        path,
        (p) => _imageCall((b, info) =>
            _imageThumbnail(volId, p, targetSize, quality, preserveAlpha ? 1 : 0, maxSourceBytes, b, info)),
      );

  /// A thumbnail of a picture file on this machine.
  (int, Uint8List?, List<int>) imageThumbnailFile(
    String hostPath, {
    required int targetSize,
    required int quality,
    required bool preserveAlpha,
    required int maxSourceBytes,
  }) =>
      _withUtf8(
        hostPath,
        (p) => _imageCall((b, info) =>
            _imageThumbnailFile(p, targetSize, quality, preserveAlpha ? 1 : 0, maxSourceBytes, b, info)),
      );

  /// A thumbnail of a picture that is already in memory (a video frame).
  (int, Uint8List?, List<int>) imageThumbnailMem(
    Uint8List data, {
    required int targetSize,
    required int quality,
    required bool preserveAlpha,
  }) =>
      _withBytes(
        data,
        (ptr, len) => _imageCall((b, info) =>
            _imageThumbnailMem(ptr, len, targetSize, quality, preserveAlpha ? 1 : 0, b, info)),
      );

  // ── archives (ABI 10) ───────────────────────────────────────────────────
  // Each call answers VE_OK with a result record (layout in ve_engine.h, decoded by ArchiveRecord in
  // desktop_archive.dart); what happened to the archive is inside the record. srcVol < 0 means a host file.

  T _withOptUtf8<T>(String? s, T Function(Pointer<Utf8>) body) => s == null ? body(nullptr) : _withUtf8(s, body);

  (int, Uint8List?) archiveScan(int srcVol, String srcPath, String? passphrase) => _withUtf8(
        srcPath,
        (src) => _withOptUtf8(passphrase, (pw) => _withBuffer((out) => _archiveScan(srcVol, src, pw, out))),
      );

  /// One entry. With [destPath] null the entry comes back in `data` (an empty list for a zero-byte entry);
  /// otherwise it is streamed into that host file ([destVol] < 0) or vault file.
  ({int rc, Uint8List? record, Uint8List? data}) archiveExtractEntry({
    required int srcVol,
    required String srcPath,
    required int index,
    String? passphrase,
    int destVol = -1,
    String? destPath,
  }) {
    final toMemory = destPath == null;
    final data = calloc<VeBuffer>();
    final record = calloc<VeBuffer>();
    final src = srcPath.toNativeUtf8();
    final Pointer<Utf8> pw = passphrase == null ? nullptr : passphrase.toNativeUtf8();
    final Pointer<Utf8> dst = destPath == null ? nullptr : destPath.toNativeUtf8();
    Uint8List? take(Pointer<VeBuffer> b) {
      Uint8List? bytes;
      if (b.ref.data != nullptr && b.ref.len > 0) bytes = Uint8List.fromList(b.ref.data.asTypedList(b.ref.len));
      _bufferFree(b); // wipes: the data can be plaintext
      return bytes;
    }

    try {
      final rc = _archiveExtractEntry(srcVol, src, index, pw, destVol, dst, toMemory ? data : nullptr, record);
      final recordBytes = take(record);
      final dataBytes = toMemory && rc == veOk ? (take(data) ?? Uint8List(0)) : null;
      return (rc: rc, record: recordBytes, data: dataBytes);
    } finally {
      calloc.free(src);
      if (pw != nullptr) calloc.free(pw);
      if (dst != nullptr) calloc.free(dst);
      calloc.free(data);
      calloc.free(record);
    }
  }

  /// Everything, or the entries under [subPath], into the folder [destDir] (host folder when [destVol] < 0).
  /// [opId] > 0 must be registered (opRegister) to be cancellable; progress arrives as split/join events.
  (int, Uint8List?) archiveExtractAll({
    required int srcVol,
    required String srcPath,
    String? passphrase,
    String? subPath,
    int destVol = -1,
    required String destDir,
    int opId = 0,
  }) =>
      _withUtf8(
        srcPath,
        (src) => _withOptUtf8(
          passphrase,
          (pw) => _withOptUtf8(
            subPath,
            (sub) => _withUtf8(
              destDir,
              (dst) => _withBuffer((out) => _archiveExtractAll(srcVol, src, pw, sub, destVol, dst, opId, out)),
            ),
          ),
        ),
      );

  /// Creates an archive (`ve_archive_create`, ve_engine.h). [srcVol] < 0: [srcPaths] are host paths, otherwise
  /// paths in that slot; [destVol] likewise for [destPath]. A name in [entryNames] ending in `/` is a folder
  /// entry. [splitSize] > 0 writes parts (zip / 7z). [tempDir] is where 7z and ISO assemble their output.
  (int, Uint8List?) archiveCreate({
    required int srcVol,
    required List<String> srcPaths,
    required List<String> entryNames,
    required List<int> modifiedSecs,
    required int destVol,
    required String destPath,
    required int format,
    String? passphrase,
    bool encryptFilenames = false,
    int compressionLevel = -1,
    int compressionMethod = 0,
    int splitSize = 0,
    String? tempDir,
    int opId = 0,
  }) {
    final count = srcPaths.length;
    final paths = calloc<Pointer<Utf8>>(count);
    final names = calloc<Pointer<Utf8>>(count);
    final mtimes = calloc<Int64>(count);
    final allocated = <Pointer<Utf8>>[];
    try {
      for (var i = 0; i < count; i++) {
        final sp = srcPaths[i].toNativeUtf8();
        final en = entryNames[i].toNativeUtf8();
        allocated
          ..add(sp)
          ..add(en);
        paths[i] = sp;
        names[i] = en;
        mtimes[i] = modifiedSecs[i];
      }
      return _withUtf8(
        destPath,
        (dst) => _withOptUtf8(
          passphrase,
          (pw) => _withOptUtf8(
            tempDir,
            (tmp) => _withBuffer(
              (out) => _archiveCreate(
                srcVol,
                paths,
                names,
                mtimes,
                count,
                destVol,
                dst,
                format,
                pw,
                encryptFilenames ? 1 : 0,
                compressionLevel,
                compressionMethod,
                splitSize,
                tmp,
                opId,
                out,
              ),
            ),
          ),
        ),
      );
    } finally {
      for (final p in allocated) {
        calloc.free(p);
      }
      calloc.free(paths);
      calloc.free(names);
      calloc.free(mtimes);
    }
  }

  // ── Check & Repair, header backup (ABI 11) ───────────────────────────────
  // The fd-taking calls CLOSE the descriptor on every path (ve_engine.h); callers must not close it again.

  /// Copies [bytes] into native memory for the duration of [body], then wipes and frees it (null/empty: no pointer).
  T _withSecretBytes<T>(Uint8List? bytes, T Function(Pointer<Uint8> p, int len) body) {
    if (bytes == null || bytes.isEmpty) return body(nullptr, 0);
    final p = calloc<Uint8>(bytes.length);
    try {
      p.asTypedList(bytes.length).setAll(0, bytes);
      return body(p, bytes.length);
    } finally {
      p.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      calloc.free(p);
    }
  }

  /// `ve_fv_check` / `ve_fv_repair`: the result record (ve_engine.h), decoded by `parseFolderVaultReport`.
  /// [sessionVol] >= 0 uses that slot's unlocked vault as the credential instead of [password].
  (int, Uint8List?) fvCheckOrRepair({
    required bool repair,
    required int format,
    required String root,
    Uint8List? password,
    int sessionVol = -1,
    String localStateDir = '',
    String tempDir = '',
    int opId = 0,
  }) =>
      _withUtf8(
        root,
        (r) => _withSecretBytes(
          password,
          (pw, n) => _withUtf8(
            localStateDir,
            (ls) => _withUtf8(
              tempDir,
              (td) => _withBuffer(
                (out) => (repair ? _fvRepair : _fvCheck)(format, r, pw, n, sessionVol, ls, td, opId, out),
              ),
            ),
          ),
        ),
      );

  /// The file that holds a folder vault's key material (gocryptfs.conf, ...), or null for an unknown format.
  String? fvConfigFileName(int format) {
    final (rc, bytes) = _withBuffer((out) => _fvConfigFileName(format, out));
    return rc == veOk && bytes != null ? utf8.decode(bytes, allowMalformed: true) : null;
  }

  /// Null when [bytes] parses as a genuine config for [format], else the reason it does not.
  String? fvValidateConfig(int format, Uint8List bytes) {
    final out = calloc<VeBuffer>();
    try {
      final rc = _withSecretBytes(bytes, (p, n) => _fvValidateConfig(format, p, n, out));
      final reason = _takeMessage(out);
      if (rc == veOk) return null;
      return reason ?? 'This is not a valid config file for this vault format.';
    } finally {
      calloc.free(out);
    }
  }

  /// `ve_repair_diagnose_file`: (rc, RepairDiagnosisCode, ContainerFormat ordinal or -1). Closes [fd].
  (int, int, int) repairDiagnoseFile(int fd, int opId) {
    final code = calloc<Int32>();
    final format = calloc<Int32>();
    try {
      final rc = _repairDiagnoseFile(fd, opId, code, format);
      return (rc, code.value, format.value);
    } finally {
      calloc.free(code);
      calloc.free(format);
    }
  }

  /// `ve_repair_restore_luks2`: VE_OK when the primary header was restored. Closes [fd].
  int repairRestoreLuks2(int fd, int opId) => _repairRestoreLuks2(fd, opId);

  /// `ve_repair_restore_veracrypt`: (rc, VeraCryptRestoreResult: 0 ok, 1 wrong password, 2 healthy, 3 I/O). Closes [fd].
  (int, int) repairRestoreVeracrypt(int fd, Uint8List password, int pim, int cipherId, int hashId, int opId) {
    final result = calloc<Int32>();
    try {
      final rc = _withSecretBytes(
        password,
        (p, n) => _repairRestoreVeracrypt(fd, p, n, pim, cipherId, hashId, opId, result),
      );
      return (rc, result.value);
    } finally {
      calloc.free(result);
    }
  }

  (int, int) repairDiagnoseMounted(int volId, int opId) {
    final code = calloc<Int32>();
    try {
      final rc = _repairDiagnoseMounted(volId, opId, code);
      return (rc, code.value);
    } finally {
      calloc.free(code);
    }
  }

  (int, bool) repairCheckMounted(int volId, int opId) {
    final ok = calloc<Int32>();
    try {
      final rc = _repairCheckMounted(volId, opId, ok);
      return (rc, ok.value != 0);
    } finally {
      calloc.free(ok);
    }
  }

  /// `ve_header_export`: the result record (u32 result, u32 format, u32 length, payload). Closes [fd].
  (int, Uint8List?) headerExport(int fd, int opId) => _withBuffer((out) => _headerExport(fd, opId, out));

  /// `ve_header_restore`: (rc, HeaderRestoreResult: 0 ok, 1 wrong password, 2 invalid, 3 too small, 4 I/O).
  /// Closes [fd] and every fd in [keyfileFds].
  (int, int) headerRestore({
    required int fd,
    required int format,
    required Uint8List payload,
    Uint8List? password,
    int pim = 0,
    int cipherId = 255,
    int hashId = 255,
    int opId = 0,
    List<int> keyfileFds = const [],
  }) {
    final result = calloc<Int32>();
    final Pointer<Int32> kf = keyfileFds.isEmpty ? nullptr : calloc<Int32>(keyfileFds.length);
    try {
      for (var i = 0; i < keyfileFds.length; i++) {
        kf[i] = keyfileFds[i];
      }
      final rc = _withSecretBytes(
        payload,
        (pl, plLen) => _withSecretBytes(
          password,
          (pw, pwLen) => _headerRestore(fd, format, pl, plLen, pw, pwLen, pim, cipherId, hashId, opId, kf, keyfileFds.length, result),
        ),
      );
      return (rc, result.value);
    } finally {
      if (kf != nullptr) calloc.free(kf);
      calloc.free(result);
    }
  }

  // ── Container tools: expand, grow the file system, hidden volume in an existing volume (ABI 12) ──
  // Every call CLOSES [fd] and every fd in its keyfile list on every path (ve_engine.h); callers must not close
  // them again. Passwords are raw UTF-8 bytes, copied to native memory for the call and wiped afterwards.

  /// Runs [body] with [fds] as a native int32 array (a null pointer when empty), freed afterwards.
  T _withFdArray<T>(List<int> fds, T Function(Pointer<Int32> p, int n) body) {
    if (fds.isEmpty) return body(nullptr, 0);
    final p = calloc<Int32>(fds.length);
    try {
      for (var i = 0; i < fds.length; i++) {
        p[i] = fds[i];
      }
      return body(p, fds.length);
    } finally {
      calloc.free(p);
    }
  }

  /// The shared shape of the expand / grow calls: (rc, [outcome, fileSystemStep, fileSystemKind]). The defaults are
  /// what the engine itself starts from (I/O error, file-system step not run, unknown kind).
  (int, List<int>) _expandResult(int Function(Pointer<Int32> out) body) {
    final out = calloc<Int32>(3);
    out[0] = 4;
    out[1] = -1;
    out[2] = 0;
    try {
      final rc = body(out);
      return (rc, [out[0], out[1], out[2]]);
    } finally {
      calloc.free(out);
    }
  }

  /// `ve_expand_veracrypt`: (rc, [outcome, fsStep, fsKind]). [newSizeBytes] is rounded down to the format's unit.
  (int, List<int>) expandVeracrypt({
    required int fd,
    required Uint8List password,
    int pim = 0,
    int cipherId = 255,
    int hashId = 255,
    List<int> keyfileFds = const [],
    required int newSizeBytes,
    bool initFreeSpace = false,
    bool growFileSystem = true,
  }) =>
      _expandResult(
        (out) => _withSecretBytes(
          password,
          (pw, n) => _withFdArray(
            keyfileFds,
            (kf, kfCount) => _expandVeracrypt(
              fd, pw, n, pim, cipherId, hashId, kf, kfCount, newSizeBytes, initFreeSpace ? 1 : 0, growFileSystem ? 1 : 0, out),
          ),
        ),
      );

  /// `ve_expand_luks`: like [expandVeracrypt]. A keyfile REPLACES the password for LUKS.
  (int, List<int>) expandLuks({
    required int fd,
    required Uint8List password,
    List<int> keyfileFds = const [],
    required int newSizeBytes,
    bool initFreeSpace = false,
    bool growFileSystem = true,
  }) =>
      _expandResult(
        (out) => _withSecretBytes(
          password,
          (pw, n) => _withFdArray(
            keyfileFds,
            (kf, kfCount) =>
                _expandLuks(fd, pw, n, kf, kfCount, newSizeBytes, initFreeSpace ? 1 : 0, growFileSystem ? 1 : 0, out),
          ),
        ),
      );

  /// `ve_expand_bitlocker`: like [expandVeracrypt]; the credential is a password or the 48-digit recovery key.
  (int, List<int>) expandBitlocker({
    required int fd,
    required Uint8List password,
    required int newSizeBytes,
    bool initFreeSpace = false,
    bool growFileSystem = true,
  }) =>
      _expandResult(
        (out) => _withSecretBytes(
          password,
          (pw, n) => _expandBitlocker(fd, pw, n, newSizeBytes, initFreeSpace ? 1 : 0, growFileSystem ? 1 : 0, out),
        ),
      );

  /// `ve_grow_veracrypt_fs`: only the file-system step, for a volume whose container was expanded earlier.
  (int, List<int>) growVeracryptFs({
    required int fd,
    required Uint8List password,
    int pim = 0,
    int cipherId = 255,
    int hashId = 255,
    List<int> keyfileFds = const [],
  }) =>
      _expandResult(
        (out) => _withSecretBytes(
          password,
          (pw, n) => _withFdArray(
            keyfileFds,
            (kf, kfCount) => _growVeracryptFs(fd, pw, n, pim, cipherId, hashId, kf, kfCount, out),
          ),
        ),
      );

  /// `ve_grow_luks_fs`.
  (int, List<int>) growLuksFs({
    required int fd,
    required Uint8List password,
    List<int> keyfileFds = const [],
  }) =>
      _expandResult(
        (out) => _withSecretBytes(
          password,
          (pw, n) => _withFdArray(keyfileFds, (kf, kfCount) => _growLuksFs(fd, pw, n, kf, kfCount, out)),
        ),
      );

  /// `ve_grow_bitlocker_fs`.
  (int, List<int>) growBitlockerFs({required int fd, required Uint8List password}) => _expandResult(
        (out) => _withSecretBytes(password, (pw, n) => _growBitlockerFs(fd, pw, n, out)),
      );

  /// `ve_hidden_analyze` (read-only): (rc, [outcome, fsKind, clusterSize, maxHiddenBytes]).
  (int, List<int>) hiddenAnalyze({
    required int fd,
    required Uint8List password,
    int pim = 0,
    int cipherId = 255,
    int hashId = 255,
    List<int> keyfileFds = const [],
  }) {
    final out = calloc<Int64>(4);
    out[0] = 4; // I/O error until the engine says otherwise
    out[1] = 0;
    out[2] = 0;
    out[3] = 0;
    try {
      final rc = _withSecretBytes(
        password,
        (pw, n) => _withFdArray(keyfileFds, (kf, kfCount) => _hiddenAnalyze(fd, pw, n, pim, cipherId, hashId, kf, kfCount, out)),
      );
      return (rc, [out[0], out[1], out[2], out[3]]);
    } finally {
      calloc.free(out);
    }
  }

  /// `ve_hidden_create_in_existing`: (rc, outcome: 0 created, 1 wrong outer password, 2 unsupported outer file system,
  /// 3 no room, 4 I/O error, 5 unreadable keyfile, 6 invalid). [hiddenFileSystem] is "FAT", "exFAT" or "NTFS".
  (int, int) hiddenCreateInExisting({
    required int fd,
    required Uint8List outerPassword,
    int outerPim = 0,
    int outerCipherId = 255,
    int outerHashId = 255,
    List<int> outerKeyfileFds = const [],
    required Uint8List hiddenPassword,
    int hiddenPim = 0,
    required String hiddenFileSystem,
    required int hiddenSizeBytes,
    int hiddenCipherId = 0,
    int hiddenHashId = 0,
    List<int> hiddenKeyfileFds = const [],
    bool quickFormat = true,
    Uint8List? userEntropy,
  }) {
    final allocated = <Pointer<NativeType>>[]; // freed in finally
    final secrets = <(Pointer<Uint8>, int)>[]; // wiped, then freed
    Pointer<Uint8> secretBytes(Uint8List? src) {
      if (src == null) return nullptr;
      final p = calloc<Uint8>(src.isEmpty ? 1 : src.length);
      p.asTypedList(src.length).setAll(0, src);
      secrets.add((p, src.length));
      return p;
    }

    Pointer<Int32> fdArray(List<int> fds) {
      if (fds.isEmpty) return nullptr;
      final p = calloc<Int32>(fds.length);
      for (var i = 0; i < fds.length; i++) {
        p[i] = fds[i];
      }
      allocated.add(p);
      return p;
    }

    final outcome = calloc<Int32>();
    outcome.value = 4; // I/O error, which is what the engine starts from too
    allocated.add(outcome);
    try {
      final params = calloc<VeHiddenInExistingParams>();
      allocated.add(params);
      final fsName = hiddenFileSystem.toNativeUtf8();
      allocated.add(fsName);
      final r = params.ref;
      r.structSize = sizeOf<VeHiddenInExistingParams>();
      r.fd = fd;
      r.outerPassword = secretBytes(outerPassword);
      r.outerPasswordLen = outerPassword.length;
      r.outerPim = outerPim;
      r.outerCipherId = outerCipherId;
      r.outerHashId = outerHashId;
      r.outerKeyfileFds = fdArray(outerKeyfileFds);
      r.outerKeyfileCount = outerKeyfileFds.length;
      r.hiddenPassword = secretBytes(hiddenPassword);
      r.hiddenPasswordLen = hiddenPassword.length;
      r.hiddenPim = hiddenPim;
      r.hiddenFileSystem = fsName;
      r.hiddenSizeBytes = hiddenSizeBytes;
      r.hiddenCipherId = hiddenCipherId;
      r.hiddenHashId = hiddenHashId;
      r.hiddenKeyfileFds = fdArray(hiddenKeyfileFds);
      r.hiddenKeyfileCount = hiddenKeyfileFds.length;
      r.quickFormat = quickFormat ? 1 : 0;
      r.userEntropy = secretBytes(userEntropy);
      r.userEntropyLen = userEntropy?.length ?? 0;
      final rc = _hiddenCreateInExisting(params, outcome);
      return (rc, outcome.value);
    } finally {
      for (final (p, len) in secrets) {
        p.asTypedList(len).fillRange(0, len, 0);
        calloc.free(p);
      }
      for (final p in allocated) {
        calloc.free(p);
      }
    }
  }

  // ── Composite containers (ABI 13) ────────────────────────────────────────
  // Carriers are host paths the engine opens itself. Only the keyfile descriptors belong to the call (it closes them on
  // every path, including a refused argument), so callers must not close them again.

  /// Runs [body] with [paths] as a native `char*` array (UTF-8), freed afterwards.
  T _withPathArray<T>(List<String> paths, T Function(Pointer<Pointer<Utf8>> p, int n) body) {
    final array = calloc<Pointer<Utf8>>(paths.isEmpty ? 1 : paths.length);
    final strings = <Pointer<Utf8>>[];
    try {
      for (var i = 0; i < paths.length; i++) {
        final s = paths[i].toNativeUtf8();
        strings.add(s);
        array[i] = s;
      }
      return body(array, paths.length);
    } finally {
      for (final s in strings) {
        calloc.free(s);
      }
      calloc.free(array);
    }
  }

  /// `ve_composite_profile` (read-only): (rc, record). The record is `parseCompositeProfile`'s input
  /// (desktop_composite.dart); it is null unless [rc] is [veOk].
  (int, Uint8List?) compositeProfile({required List<String> carrierPaths, required int safetyMarginPct}) {
    final out = calloc<VeBuffer>();
    try {
      final rc = _withPathArray(carrierPaths, (paths, n) => _compositeProfile(paths, n, safetyMarginPct, out));
      final record = _takeBuffer(out);
      return (rc, rc == veOk ? record : null);
    } finally {
      calloc.free(out);
    }
  }

  /// `ve_composite_create`: (rc, error). WRITES TO THE CARRIER FILES. [error] is the engine's failure code
  /// (CARRIER_CAPACITY_CHANGED, SIZE_TOO_SMALL, ...) when there is one. The slot [volId] is left empty on success.
  (int, String?) compositeCreate({
    required List<String> carrierPaths,
    required int volId,
    required int requestedBytes,
    required int safetyMarginPct,
    required Uint8List password,
    int pim = 0,
    required String fileSystem,
    int cipherId = 255,
    int hashId = 255,
    List<int> keyfileFds = const [],
    bool quickFormat = true,
    Uint8List? userEntropy,
  }) {
    final params = calloc<VeCompositeCreateParams>();
    final err = calloc<VeBuffer>();
    final fsName = fileSystem.toNativeUtf8();
    final entropy = _Pin(userEntropy);
    try {
      final rc = _withPathArray(
        carrierPaths,
        (paths, n) => _withSecretBytes(
          password,
          (pw, pwLen) => _withFdArray(keyfileFds, (kf, kfCount) {
            final r = params.ref;
            r.structSize = sizeOf<VeCompositeCreateParams>();
            r.volId = volId;
            r.carrierPaths = paths;
            r.carrierCount = n;
            r.requestedBytes = requestedBytes;
            r.safetyMarginPct = safetyMarginPct;
            r.password = pw;
            r.passwordLen = pwLen;
            r.pim = pim;
            r.fileSystem = fsName;
            r.cipherId = cipherId;
            r.hashId = hashId;
            r.keyfileFds = kf;
            r.keyfileCount = kfCount;
            r.quickFormat = quickFormat ? 1 : 0;
            r.userEntropy = entropy.ptr;
            r.userEntropyLen = entropy.len;
            return _compositeCreate(params, err);
          }),
        ),
      );
      return (rc, _takeMessage(err));
    } finally {
      entropy.release();
      calloc.free(fsName);
      calloc.free(err);
      calloc.free(params);
    }
  }

  /// `ve_composite_unlock`: (rc, error). On [veOk] the volume is unlocked into [volId] and its file system mounted,
  /// like `unlock`. [error] is the engine's failure code (INCORRECT_PASSWORD_OR_INVALID_CONTAINER,
  /// COMPOSITE_CARRIERS_INCOMPLETE, NO_EXTENTS_DETECTED, ...).
  (int, String?) compositeUnlock({
    required List<String> carrierPaths,
    required int volId,
    required Uint8List password,
    int pim = 0,
    int cipherId = 255,
    int hashId = 255,
    List<int> keyfileFds = const [],
    bool readOnly = false,
  }) {
    final params = calloc<VeCompositeUnlockParams>();
    final err = calloc<VeBuffer>();
    try {
      final rc = _withPathArray(
        carrierPaths,
        (paths, n) => _withSecretBytes(
          password,
          (pw, pwLen) => _withFdArray(keyfileFds, (kf, kfCount) {
            final r = params.ref;
            r.structSize = sizeOf<VeCompositeUnlockParams>();
            r.volId = volId;
            r.carrierPaths = paths;
            r.carrierCount = n;
            r.password = pw;
            r.passwordLen = pwLen;
            r.pim = pim;
            r.cipherId = cipherId;
            r.hashId = hashId;
            r.keyfileFds = kf;
            r.keyfileCount = kfCount;
            r.readOnly = readOnly ? 1 : 0;
            return _compositeUnlock(params, err);
          }),
        ),
      );
      return (rc, _takeMessage(err));
    } finally {
      calloc.free(err);
      calloc.free(params);
    }
  }

  /// kind 0 = writes, 1 = deletes.
  int fvBatch(int volId, int kind, {required bool begin}) => _fvBatch(volId, kind, begin ? 1 : 0);

  // ── operations / events ────────────────────────────────────────────────

  void opRegister(int opId, int flavor) => _opRegister(opId, flavor);
  void opCancel(int opId) => _opCancel(opId);
  void opUnregister(int opId) => _opUnregister(opId);

  /// Drains the native event queue (cheap; safe on the UI isolate).
  List<VeNativeEvent> pollEvents({int max = 64}) {
    final ev = calloc<VeEvent>();
    final out = <VeNativeEvent>[];
    try {
      while (out.length < max && _poll(ev) == 1) {
        final r = ev.ref;
        final chars = <int>[];
        for (var i = 0; i < 240; i++) {
          final c = r.text[i];
          if (c == 0) break;
          chars.add(c);
        }
        out.add(VeNativeEvent(r.kind, r.volId, r.opId, [r.i0, r.i1, r.i2, r.i3, r.i4], r.n0, r.n1,
            utf8.decode(chars, allowMalformed: true)));
      }
    } finally {
      calloc.free(ev);
    }
    return out;
  }
}

/// An input copied into native memory for one call; [release] wipes it, then frees it.
/// A null source pins as a null pointer with length 0.
class _Pin {
  _Pin(Uint8List? src)
      : len = src?.length ?? 0,
        ptr = src == null ? nullptr : calloc<Uint8>(src.isEmpty ? 1 : src.length) {
    if (src != null && src.isNotEmpty) ptr.asTypedList(src.length).setAll(0, src);
  }

  final Pointer<Uint8> ptr;
  final int len;

  void release() {
    if (ptr == nullptr) return;
    ptr.asTypedList(len).fillRange(0, len, 0);
    calloc.free(ptr);
  }
}
