import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';

void main() {
  group('clampPim', () {
    test('passes through in-range values unchanged', () {
      expect(clampPim(0), 0);
      expect(clampPim(1), 1);
      expect(clampPim(500), 500);
      expect(clampPim(2000), 2000);
    });

    test('clamps negative values to 0', () {
      expect(clampPim(-1), 0);
      expect(clampPim(-1000000), 0);
    });

    test('clamps values above 2000 — this is the DoS guard, keep it strict', () {
      expect(clampPim(2001), 2000);
      // The exact case the doc comment on clampPim warns about: an
      // unclamped value here would translate to ~2 billion PBKDF2
      // iterations on-device.
      expect(clampPim(2000000), 2000);
    });
  });

  group('validateHiddenVolume', () {
    // Shared valid baseline; individual tests override only what they're
    // exercising so each test's intent stays visible at the call site.
    HiddenVolumeValidation run({
      String hiddenSizeText = '10',
      String hiddenSizeUnit = 'MB',
      int outerSizeBytes = 500 * 1024 * 1024, // 500 MB
      int outerPimClamped = 0,
      int hiddenPimClamped = 0,
      String outerPassword = 'outer-secret',
      String hiddenPassword = 'hidden-secret',
      bool hasHiddenKeyfiles = false,
      Set<String> outerKeyfileUris = const {},
      Set<String> hiddenKeyfileUris = const {},
    }) =>
        validateHiddenVolume(
          hiddenSizeText: hiddenSizeText,
          hiddenSizeUnit: hiddenSizeUnit,
          outerSizeBytes: outerSizeBytes,
          outerPimClamped: outerPimClamped,
          hiddenPimClamped: hiddenPimClamped,
          outerPassword: outerPassword,
          hiddenPassword: hiddenPassword,
          hasHiddenKeyfiles: hasHiddenKeyfiles,
          outerKeyfileUris: outerKeyfileUris,
          hiddenKeyfileUris: hiddenKeyfileUris,
        );

    test('accepts a well-formed request and returns the byte size', () {
      final result = run(hiddenSizeText: '10', hiddenSizeUnit: 'MB');
      expect(result.isValid, isTrue);
      expect(result.hiddenSizeBytes, 10 * 1024 * 1024);
      expect(result.error, isNull);
    });

    test('converts GB using the same multiplier as MB, scaled by 1024', () {
      final mb = run(hiddenSizeText: '10', hiddenSizeUnit: 'MB');
      final gb = run(
        hiddenSizeText: '10',
        hiddenSizeUnit: 'GB',
        outerSizeBytes: 20 * 1024 * 1024 * 1024,
      );
      expect(gb.hiddenSizeBytes, mb.hiddenSizeBytes! * 1024);
    });

    test('rejects non-numeric size text', () {
      final result = run(hiddenSizeText: 'not a number');
      expect(result.isValid, isFalse);
      expect(result.error, contains('valid hidden size'));
    });

    test('rejects zero and negative size', () {
      expect(run(hiddenSizeText: '0').isValid, isFalse);
      expect(run(hiddenSizeText: '-5').isValid, isFalse);
    });

    test('rejects hidden size >= outer size', () {
      final result = run(
        hiddenSizeText: '500',
        hiddenSizeUnit: 'MB',
        outerSizeBytes: 500 * 1024 * 1024,
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('less than the outer'));
    });

    test('rejects hidden size that leaves no room for the outer header '
        '(vcDataAreaOffset)', () {
      // Outer volume only just bigger than the hidden volume itself, with
      // no room left for the reserved header/data area.
      final hiddenBytes = 10 * 1024 * 1024;
      final result = run(
        hiddenSizeText: '10',
        hiddenSizeUnit: 'MB',
        outerSizeBytes: hiddenBytes + vcDataAreaOffset, // exactly the boundary
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('too large for this container size'));
    });

    test('accepts hidden size right at the boundary plus one byte', () {
      final hiddenBytes = 10 * 1024 * 1024;
      final result = run(
        hiddenSizeText: '10',
        hiddenSizeUnit: 'MB',
        outerSizeBytes: hiddenBytes + vcDataAreaOffset + 1,
      );
      expect(result.isValid, isTrue);
    });

    test('requires a hidden password or keyfile', () {
      final result = run(hiddenPassword: '', hasHiddenKeyfiles: false);
      expect(result.isValid, isFalse);
      expect(result.error, contains('password or keyfile is required'));
    });

    test('accepts empty hidden password when keyfiles are present instead', () {
      final result = run(hiddenPassword: '', hasHiddenKeyfiles: true);
      expect(result.isValid, isTrue);
    });

    test(
        'rejects hidden credentials identical to outer credentials '
        '(password + PIM + keyfiles all matching) — this is a plausible-'
        'deniability guard, not just a UX nicety', () {
      final result = run(
        outerPassword: 'same-secret',
        hiddenPassword: 'same-secret',
        outerPimClamped: 100,
        hiddenPimClamped: 100,
        outerKeyfileUris: {'content://a'},
        hiddenKeyfileUris: {'content://a'},
      );
      expect(result.isValid, isFalse);
      expect(result.error, contains('cannot be'));
    });

    test('accepts identical passwords if PIM differs', () {
      final result = run(
        outerPassword: 'same-secret',
        hiddenPassword: 'same-secret',
        outerPimClamped: 100,
        hiddenPimClamped: 200,
      );
      expect(result.isValid, isTrue);
    });

    test('accepts identical passwords and PIM if keyfiles differ', () {
      final result = run(
        outerPassword: 'same-secret',
        hiddenPassword: 'same-secret',
        outerKeyfileUris: {'content://a'},
        hiddenKeyfileUris: {'content://b'},
      );
      expect(result.isValid, isTrue);
    });

    test('treats keyfile sets as unordered — same members, different '
        'insertion order, still counts as identical', () {
      final result = run(
        outerPassword: 'same-secret',
        hiddenPassword: 'same-secret',
        outerKeyfileUris: {'content://a', 'content://b'},
        hiddenKeyfileUris: {'content://b', 'content://a'},
      );
      expect(result.isValid, isFalse);
    });
  });
}
