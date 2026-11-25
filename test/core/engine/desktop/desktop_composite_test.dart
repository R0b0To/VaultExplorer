import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:test/test.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_composite.dart';
import 'package:vaultexplorer/core/engine/desktop/ve_native.dart' show veErrCancelled, veErrException, veErrFailed, veErrInvalidArg, veErrMountFailed, veOk;

// DesktopComposite is the Dart half of composite containers (one volume spread over several ordinary files): it maps
// the method arguments onto the engine calls and every outcome onto the result maps and error codes that
// `VaultCompositeApi` already handles (the ones CompositeContainerHandlers.kt raises on Android). The native half is
// covered by the "composite" section of ve_smoke_test; here a fake engine call stands in for it.

/// The record `ve_composite_profile` writes (layout in ve_engine.h), built the way the engine builds it.
Uint8List _record(int total, List<({int fileIndex, int inputIndex, int tier, int size, int offset, int allocatable, String format, String path})> items) {
  final out = BytesBuilder();
  void u32(int v) => out.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u64(int v) => out.add(Uint8List(8)..buffer.asByteData().setUint64(0, v, Endian.little));
  void str(String s) {
    final b = utf8.encode(s);
    u32(b.length);
    out.add(b);
  }

  u64(total);
  u32(items.length);
  for (final i in items) {
    u32(i.fileIndex);
    u32(i.inputIndex);
    u32(i.tier);
    u64(i.size);
    u64(i.offset);
    u64(i.allocatable);
    str(i.format);
    str(i.path);
  }
  return out.toBytes();
}

const _twoCarriers = [
  (fileIndex: 0, inputIndex: 1, tier: 2, size: 6291456, offset: 6291456, allocatable: 3145728, format: 'generic', path: '/data/a.bin'),
  (fileIndex: 1, inputIndex: 0, tier: 0, size: 8388608, offset: 8388608, allocatable: 4194304, format: 'png', path: '/data/ü b.png'),
];

class _Registered {
  _Registered(this.vol, this.key, this.displayName, this.format, this.readOnly, this.args);
  final int vol;
  final String key;
  final String displayName;
  final String format;
  final bool readOnly;
  final Map<Object?, Object?> args;
}

class _Harness {
  final List<(String, List<Object?>)> calls = [];
  Future<Object?> Function(String op, List<Object?> args)? handler;
  final List<int> released = [];
  final List<String?> slotRequests = [];
  final List<_Registered> registered = [];
  final List<(String, Object?)> emitted = [];
  final List<String> logs = [];
  int nextSlot = 4;
  Object? slotError;

  late final DesktopComposite composite = DesktopComposite(
    call: (op, args) async {
      calls.add((op, args));
      return handler!(op, args);
    },
    slotFor: (key) async {
      slotRequests.add(key);
      final error = slotError;
      if (error != null) throw error;
      return nextSlot;
    },
    releaseSlot: released.add,
    register: (vol, key, name, format, readOnly, args) => registered.add(_Registered(vol, key, name, format, readOnly, args)),
    emit: (method, args) => emitted.add((method, args)),
    withActivity: (body) => body(),
    log: logs.add,
  );
}

Matcher _code(String code, [String? message]) => throwsA(
      isA<PlatformException>().having((e) => e.code, 'code', code).having(
            (e) => e.message,
            'message',
            message == null ? isNotNull : equals(message),
          ),
    );

void main() {
  late _Harness h;

  setUp(() => h = _Harness());

  group('parseCompositeProfile', () {
    test('decodes every field of every carrier, in the engine\'s canonical order', () {
      final profile = parseCompositeProfile(_record(7340032, _twoCarriers))!;
      expect(profile['totalAllocatableBytes'], 7340032);
      expect(profile['carriers'], [
        {
          'fileIndex': 0,
          'inputIndex': 1,
          'path': '/data/a.bin',
          'detectedFormat': 'generic',
          'fileSize': 6291456,
          'payloadOffset': 6291456,
          'allocatableBytes': 3145728,
          'tier': 2,
        },
        {
          'fileIndex': 1,
          'inputIndex': 0,
          'path': '/data/ü b.png',
          'detectedFormat': 'png',
          'fileSize': 8388608,
          'payloadOffset': 8388608,
          'allocatableBytes': 4194304,
          'tier': 0,
        },
      ]);
    });

    test('an empty profile is a profile', () {
      expect(parseCompositeProfile(_record(0, const [])), {'totalAllocatableBytes': 0, 'carriers': <Object?>[]});
    });

    test('a truncated or over-long record is rejected, not half-read', () {
      final good = _record(1, _twoCarriers);
      expect(parseCompositeProfile(Uint8List.sublistView(good, 0, good.length - 1)), isNull);
      expect(parseCompositeProfile(Uint8List.sublistView(good, 0, 5)), isNull);
      expect(parseCompositeProfile(Uint8List(0)), isNull);
      expect(parseCompositeProfile(Uint8List.fromList([...good, 0])), isNull);
    });
  });

  group('profileCarriers', () {
    test('sizes the carriers read-only and answers the map VaultCompositeApi decodes', () async {
      h.handler = (op, args) async => [veOk, _record(7340032, _twoCarriers)];
      final res = await h.composite.profileCarriers({
        'carrierUris': ['/data/ü b.png', Uri.file('/data/a.bin').toString()],
        'safetyMarginPct': 25,
      });
      expect(res['totalAllocatableBytes'], 7340032);
      expect((res['carriers'] as List).length, 2);
      final (op, args) = h.calls.single;
      expect(op, 'compositeProfile');
      expect(args[0], ['/data/ü b.png', Uri.file('/data/a.bin').toFilePath()]); // a file: URI is accepted
      expect(args[1], 25);
      expect(h.slotRequests, isEmpty); // profiling touches no slot
    });

    test('the margin defaults to 10 percent, as on Android', () async {
      h.handler = (op, args) async => [veOk, _record(0, const [])];
      await h.composite.profileCarriers({
        'carrierUris': ['/data/a.bin']
      });
      expect(h.calls.single.$2[1], 10);
    });

    test('a missing, empty or malformed carrier list is INVALID_ARGS and never reaches the engine', () async {
      for (final args in <Map<Object?, Object?>>[
        {},
        {'carrierUris': <Object?>[]},
        {'carrierUris': 'not a list'},
        {
          'carrierUris': ['/data/a.bin', '']
        },
        {
          'carrierUris': ['/data/a.bin', 7]
        },
      ]) {
        await expectLater(h.composite.profileCarriers(args), _code('INVALID_ARGS', 'carrierUris required'));
      }
      expect(h.calls, isEmpty);
    });

    test('an engine failure or an unreadable record is PROFILE_FAILED', () async {
      h.handler = (op, args) async => [veErrFailed, null];
      final args = {
        'carrierUris': ['/data/a.bin']
      };
      await expectLater(h.composite.profileCarriers(args), _code('PROFILE_FAILED', 'Failed profiling carrier files'));
      h.handler = (op, args) async => [veOk, Uint8List.fromList([1, 2, 3])];
      await expectLater(h.composite.profileCarriers(args), _code('PROFILE_FAILED'));
    });
  });

  group('createCompositeContainer', () {
    Map<Object?, Object?> createArgs({Object? password = 'pw', List<Object?> keyfiles = const [], Uint8List? entropy}) => {
          'carrierUris': ['/data/a.bin', '/data/ü b.png'],
          'payloadOffsets': [6291456, 8388608],
          'extentLengths': [3145728, 4194304],
          'safetyMarginPct': 50,
          'password': password,
          'pim': 3,
          'fileSystem': 'EXFAT',
          'cipherId': 1,
          'hashId': 2,
          'keyfilePaths': keyfiles,
          'quickFormat': true,
          'userEntropy': entropy,
        };

    test('asks the engine for the sum of the extents in a free slot and reports true', () async {
      String? sentPassword;
      h.handler = (op, args) async {
        sentPassword = utf8.decode(args[4] as Uint8List); // read while it is live: the caller wipes it afterwards
        return [veOk, null];
      };
      final entropy = Uint8List.fromList([9, 9, 9]);
      expect(await h.composite.create(createArgs(keyfiles: ['/k/one'], entropy: entropy)), isTrue);

      final (op, args) = h.calls.single;
      expect(op, 'compositeCreate');
      expect(args[0], ['/data/a.bin', '/data/ü b.png']);
      expect(args[1], 4); // the free slot the host chose
      expect(args[2], 3145728 + 4194304); // requested capacity
      expect(args[3], 50);
      expect(sentPassword, 'pw');
      expect(args.sublist(5, 11), [3, 'exfat', 1, 2, ['/k/one'], true]);
      expect(h.slotRequests, [null]); // never an existing session's slot
      expect(h.released, [4]); // and the slot is handed back
    });

    test('every secret this side holds is wiped once the call is over', () async {
      Uint8List? sentPassword;
      h.handler = (op, args) async {
        sentPassword = args[4] as Uint8List;
        expect(utf8.decode(sentPassword!), 'pw');
        return [veOk, null];
      };
      final entropy = Uint8List.fromList([1, 2, 3, 4]);
      await h.composite.create(createArgs(entropy: entropy));
      expect(sentPassword, everyElement(0));
      expect(entropy, everyElement(0));
    });

    test('a keyfile alone is a credential; neither a password nor a keyfile is refused up front', () async {
      h.handler = (op, args) async => [veOk, null];
      expect(await h.composite.create(createArgs(password: '', keyfiles: ['/k/one'])), isTrue);
      h.calls.clear();
      await expectLater(h.composite.create(createArgs(password: '')), _code('INVALID_ARGS'));
      expect(h.calls, isEmpty);
    });

    test('missing carrier, offset or extent lists are INVALID_ARGS', () async {
      for (final drop in ['carrierUris', 'payloadOffsets', 'extentLengths']) {
        final args = createArgs()..remove(drop);
        await expectLater(
          h.composite.create(args),
          _code('INVALID_ARGS', 'carrierUris, payloadOffsets, and extentLengths required'),
        );
      }
      expect(h.calls, isEmpty);
      expect(h.slotRequests, isEmpty);
    });

    test('an engine refusal is false with the reason logged; the slot is released either way', () async {
      h.handler = (op, args) async => [veErrFailed, 'SIZE_TOO_SMALL'];
      expect(await h.composite.create(createArgs()), isFalse);
      expect(h.logs.single, contains('SIZE_TOO_SMALL'));
      expect(h.released, [4]);
    });

    test('an engine fault or refused arguments are errors, not a quiet false', () async {
      h.handler = (op, args) async => [veErrInvalidArg, null];
      await expectLater(h.composite.create(createArgs()), _code('INVALID_ARGS'));
      h.handler = (op, args) async => [veErrException, null];
      await expectLater(h.composite.create(createArgs()), _code('C++_ERROR', 'Native composite create failed (code 6)'));
      expect(h.released, [4, 4]);
    });

    test('no free slot is the host\'s MAX_CONTAINERS error and nothing is written', () async {
      h.slotError = PlatformException(code: 'MAX_CONTAINERS', message: 'No free volume slots available');
      await expectLater(h.composite.create(createArgs()), _code('MAX_CONTAINERS'));
      expect(h.calls, isEmpty);
      expect(h.released, isEmpty);
    });
  });

  group('unlockCompositeContainer', () {
    Map<Object?, Object?> unlockArgs({Object? password = 'pw', bool readOnly = false, Map<Object?, Object?> extra = const {}}) => {
          'carrierUris': ['/data/ü b.png', '/data/a.bin', '/data/c.jpg'],
          'payloadOffsets': <Object?>[],
          'extentLengths': <Object?>[],
          'password': password,
          'pim': 0,
          'cipherId': 255,
          'hashId': 255,
          'keyfilePaths': ['/k/one'],
          'readOnly': readOnly,
          ...extra,
        };

    Map<String, Object?> unlocked() => {
          'rc': veOk,
          'format': 'veracrypt',
          'cipherId': 3,
          'hashId': 1,
          'files': ['docs', 'hello.txt'],
        };

    test('unlocks, registers the session under composite:<first carrier as given> and answers like unlock', () async {
      h.handler = (op, args) async => unlocked();
      final res = await h.composite.unlock(unlockArgs(extra: {'displayName': 'Holiday', 'documentProvider': true}));

      expect(res, {
        'volId': 4,
        'files': ['docs', 'hello.txt'],
        'matchedCipherId': 3,
        'matchedHashId': 1,
        'containerFormat': 'veracrypt',
      });
      final (op, args) = h.calls.single;
      expect(op, 'compositeUnlock');
      expect(args[0], ['/data/ü b.png', '/data/a.bin', '/data/c.jpg']);
      expect(args[1], 4);
      expect(args.sublist(3), [0, 255, 255, ['/k/one'], false]);

      expect(h.slotRequests, ['composite:/data/ü b.png']);
      expect(h.emitted, [
        ('onUnlockStarted', {'volId': 4})
      ]);
      final session = h.registered.single;
      expect((session.vol, session.key, session.displayName, session.format, session.readOnly),
          (4, 'composite:/data/ü b.png', 'Holiday', 'veracrypt', false));
      expect(session.args['documentProvider'], isTrue); // what the host needs to expose it afterwards
      expect(h.released, [4]);
    });

    test('the key uses the carrier exactly as the app wrote it, a file: URI included', () async {
      h.handler = (op, args) async => unlocked();
      final uri = Uri.file('/data/a.bin').toString();
      await h.composite.unlock(unlockArgs(extra: {
        'carrierUris': [uri, '/data/b.png']
      }));
      expect(h.slotRequests.single, 'composite:$uri');
      expect((h.calls.single.$2[0] as List).first, Uri.file('/data/a.bin').toFilePath()); // but opened as a path
      expect(h.registered.single.displayName, 'Composite Vault'); // Android's default name
    });

    test('a read-only unlock is registered read-only', () async {
      h.handler = (op, args) async => unlocked();
      await h.composite.unlock(unlockArgs(readOnly: true));
      expect(h.calls.single.$2[7], true);
      expect(h.registered.single.readOnly, isTrue);
    });

    test('the password this side holds is wiped, whatever the outcome', () async {
      final sent = <Uint8List>[];
      h.handler = (op, args) async {
        sent.add(args[2] as Uint8List);
        expect(utf8.decode(sent.last), 'pw');
        return sent.length == 1 ? unlocked() : {'rc': veErrFailed, 'error': 'INCORRECT_PASSWORD_OR_INVALID_CONTAINER'};
      };
      await h.composite.unlock(unlockArgs());
      await expectLater(h.composite.unlock(unlockArgs()), _code('AUTH_FAIL'));
      expect(sent, hasLength(2));
      for (final s in sent) {
        expect(s, everyElement(0));
      }
    });

    test('a refusal reaches the app as AUTH_FAIL carrying the engine\'s own reason, and registers nothing', () async {
      for (final reason in [
        'INCORRECT_PASSWORD_OR_INVALID_CONTAINER',
        'COMPOSITE_CARRIERS_INCOMPLETE',
        'NO_EXTENTS_DETECTED',
        'KEYFILE_FAILED',
      ]) {
        h.handler = (op, args) async => {'rc': veErrFailed, 'error': reason};
        await expectLater(
          h.composite.unlock(unlockArgs()),
          throwsA(isA<PlatformException>()
              .having((e) => e.code, 'code', 'AUTH_FAIL')
              .having((e) => e.message, 'message', reason)
              .having((e) => e.details, 'details', reason)),
        );
      }
      // no reason given by a failed call: the password / container message the unlock screen already shows
      h.handler = (op, args) async => {'rc': veErrFailed, 'error': null};
      await expectLater(h.composite.unlock(unlockArgs()), _code('AUTH_FAIL', 'INCORRECT_PASSWORD_OR_INVALID_CONTAINER'));
      expect(h.registered, isEmpty);
      expect(h.released, hasLength(5)); // every attempt gave its slot back
    });

    test('a mounted-but-unreadable file system is the engine\'s reason too', () async {
      h.handler = (op, args) async => {'rc': veErrMountFailed, 'error': 'FILESYSTEM_MOUNT_FAILED'};
      await expectLater(h.composite.unlock(unlockArgs()), _code('AUTH_FAIL', 'FILESYSTEM_MOUNT_FAILED'));
      expect(h.registered, isEmpty);
    });

    test('cancelling, refused arguments and engine faults each have their own code', () async {
      h.handler = (op, args) async => {'rc': veErrCancelled, 'error': 'HEADER_READ_FAILED'};
      await expectLater(h.composite.unlock(unlockArgs()), _code('CANCELLED', 'Unlock cancelled'));
      h.handler = (op, args) async => {'rc': veErrInvalidArg, 'error': null};
      await expectLater(h.composite.unlock(unlockArgs()), _code('INVALID_ARGS'));
      h.handler = (op, args) async => {'rc': veErrException, 'error': null};
      await expectLater(h.composite.unlock(unlockArgs()), _code('C++_ERROR', 'Native composite unlock failed (code 6)'));
    });

    test('no carriers is INVALID_ARGS; no free slot is MAX_CONTAINERS; neither reaches the engine', () async {
      await expectLater(h.composite.unlock({'carrierUris': <Object?>[]}), _code('INVALID_ARGS', 'carrierUris required'));
      await expectLater(h.composite.unlock({}), _code('INVALID_ARGS', 'carrierUris required'));
      h.slotError = PlatformException(code: 'MAX_CONTAINERS', message: 'No free volume slots available');
      await expectLater(h.composite.unlock(unlockArgs()), _code('MAX_CONTAINERS'));
      expect(h.calls, isEmpty);
      expect(h.emitted, isEmpty);
    });
  });
}
