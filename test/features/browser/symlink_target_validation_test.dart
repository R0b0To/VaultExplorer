import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/symlink_target_validation.dart';

void main() {
  group('validateSymlinkTarget', () {
    test('accepts ordinary targets, stored as written', () {
      expect(validateSymlinkTarget('../target'), isNull);
      expect(validateSymlinkTarget('/absolute/path with spaces'), isNull);
      expect(validateSymlinkTarget('C:\\Users\\me'), isNull);
      expect(validateSymlinkTarget('https://example.com/x?y=1'), isNull);
      expect(validateSymlinkTarget('.'), isNull);
    });

    test('rejects an empty target', () {
      expect(validateSymlinkTarget(''), SymlinkTargetIssue.empty);
    });

    test('rejects a NUL anywhere, even with otherwise valid text', () {
      expect(validateSymlinkTarget('a\u0000b'), SymlinkTargetIssue.containsNul);
      expect(validateSymlinkTarget('\u0000'), SymlinkTargetIssue.containsNul);
      expect(validateSymlinkTarget('ok\u0000'), SymlinkTargetIssue.containsNul);
    });

    test('the limit is 32767 BYTES of UTF-8, not characters', () {
      expect(validateSymlinkTarget('a' * kMaxSymlinkTargetBytes), isNull);
      expect(validateSymlinkTarget('a' * (kMaxSymlinkTargetBytes + 1)), SymlinkTargetIssue.tooLong);

      // 2-byte characters: 16383 of them is 32766 bytes, 16384 is 32768
      expect(validateSymlinkTarget('é' * 16383), isNull);
      expect(validateSymlinkTarget('é' * 16384), SymlinkTargetIssue.tooLong);

      // 3-byte characters: 10922 * 3 = 32766 fits, 10923 * 3 = 32769 does not
      expect(validateSymlinkTarget('☃' * 10922), isNull);
      expect(validateSymlinkTarget('☃' * 10923), SymlinkTargetIssue.tooLong);

      // 4-byte characters (surrogate pairs): 8191 * 4 = 32764 fits, 8192 * 4 = 32768 does not
      expect(validateSymlinkTarget('😀' * 8191), isNull);
      expect(validateSymlinkTarget('😀' * 8192), SymlinkTargetIssue.tooLong);

      // exactly at the limit with a multi-byte tail: 32765 ASCII + one 2-byte char = 32767
      expect(validateSymlinkTarget('${'a' * 32765}é'), isNull);
      expect(validateSymlinkTarget('${'a' * 32766}é'), SymlinkTargetIssue.tooLong);
    });

    test('a NUL wins over length (the cheaper, clearer message first)', () {
      expect(
        validateSymlinkTarget('${'a' * 40000}\u0000'),
        SymlinkTargetIssue.containsNul,
      );
    });
  });
}
