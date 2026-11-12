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

const int kVeAbiVersion = 8;

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
  VeNative._(this._lib) {
    _openFile = _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Int32), int Function(Pointer<Utf8>, int)>('ve_open_file');
    _closeFd = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ve_close_fd');
    _createFile = _lib.lookupFunction<Int32 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ve_create_file');
    _createContainer = _lib.lookupFunction<Int32 Function(Pointer<VeCreateParams>), int Function(Pointer<VeCreateParams>)>('ve_create_container');
    _createHidden = _lib.lookupFunction<Int32 Function(Pointer<VeCreateHiddenParams>), int Function(Pointer<VeCreateHiddenParams>)>('ve_create_container_with_hidden');
    _abiVersion = _lib.lookupFunction<Int32 Function(), int Function()>('ve_abi_version');
    _maxVolumes = _lib.lookupFunction<Int32 Function(), int Function()>('ve_max_volumes');
    _probe = _lib.lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>('ve_probe_format');
    _unlock = _lib.lookupFunction<Int32 Function(Pointer<VeUnlockParams>), int Function(Pointer<VeUnlockParams>)>('ve_unlock');
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
  late final void Function(int) _cancelUnlock;
  late final void Function(int) _lock;
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
      return VeNative._(lib);
    }
    throw StateError('Could not load the VaultExplorer engine library:\n${problems.join('\n')}');
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
