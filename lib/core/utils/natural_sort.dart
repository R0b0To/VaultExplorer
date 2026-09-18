const int _zeroCodeUnit = 0x30; // '0'
const int _nineCodeUnit = 0x39; // '9'

bool _isDigit(int codeUnit) =>
    codeUnit >= _zeroCodeUnit && codeUnit <= _nineCodeUnit;

/// Compares two strings the way a person reads them, instead of the way
/// [String.compareTo] does. Plain [String.compareTo] walks character by
/// character, so a run of digits is compared one digit at a time — "f10"
/// sorts before "f2" because '1' < '2' at that position, even though 10 is
/// the larger number. [naturalCompare] instead treats each maximal run of
/// digits as a single number, so file/folder names like "f1", "f2", "f10"
/// come out in the order a person expects: f1, f2, f10.
///
/// Non-digit runs still compare by code unit, same as [String.compareTo]
/// always has. Case is *not* normalized here — every current call site
/// already lowercases both names before comparing (for case-insensitive
/// sort order), and this function keeps that decision at the call site
/// rather than baking it in here.
///
/// Two digit runs of different length are compared by magnitude, not by
/// string length, after leading zeros are discounted — so "9" < "10" and
/// "07" is treated as the same number as "7". If the numeric value is
/// equal but the zero-padding differs (e.g. "7" vs "007"), the shorter
/// run sorts first, purely to keep the ordering deterministic; real
/// file/folder names essentially never hit this case.
int naturalCompare(String a, String b) {
  final aLen = a.length;
  final bLen = b.length;
  var i = 0;
  var j = 0;

  while (i < aLen && j < bLen) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);

    if (_isDigit(ca) && _isDigit(cb)) {
      // Consume the full digit run on each side so a multi-digit number
      // is compared as one value, not digit-by-digit.
      var aEnd = i;
      while (aEnd < aLen && _isDigit(a.codeUnitAt(aEnd))) {
        aEnd++;
      }
      var bEnd = j;
      while (bEnd < bLen && _isDigit(b.codeUnitAt(bEnd))) {
        bEnd++;
      }

      // Leading zeros don't add to a number's magnitude ("007" is "7"),
      // so skip them before comparing how many significant digits each
      // run has.
      var aStart = i;
      while (aStart < aEnd - 1 && a.codeUnitAt(aStart) == _zeroCodeUnit) {
        aStart++;
      }
      var bStart = j;
      while (bStart < bEnd - 1 && b.codeUnitAt(bStart) == _zeroCodeUnit) {
        bStart++;
      }

      final aMagnitude = aEnd - aStart;
      final bMagnitude = bEnd - bStart;
      if (aMagnitude != bMagnitude) {
        return aMagnitude < bMagnitude ? -1 : 1;
      }
      for (var k = 0; k < aMagnitude; k++) {
        final d = a.codeUnitAt(aStart + k) - b.codeUnitAt(bStart + k);
        if (d != 0) return d;
      }

      // Same numeric value — break the tie deterministically by whichever
      // run had fewer leading zeros, since neither string representation
      // is more "correct" than the other.
      final aRunLength = aEnd - i;
      final bRunLength = bEnd - j;
      if (aRunLength != bRunLength) {
        return aRunLength < bRunLength ? -1 : 1;
      }

      i = aEnd;
      j = bEnd;
    } else {
      if (ca != cb) return ca - cb;
      i++;
      j++;
    }
  }

  return (aLen - i) - (bLen - j);
}
