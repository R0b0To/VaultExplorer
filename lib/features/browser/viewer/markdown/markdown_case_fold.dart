// Unicode case folding for link reference labels (CommonMark spec 4.7:
// "matching is performed on normalized strings, not parsed inline content" using
// Unicode case fold).
//
// Dart's built-in case mapping lacks newer Unicode (e.g. U+1E9E, Georgian
// Mtavruli, extended Cyrillic/Latin), so on top of
// `toLowerCase().toUpperCase()` this applies an override table generated from
// the Unicode `casefold()` equivalence classes. Folding is done one code point
// at a time so context rules (final sigma) never apply.

String caseFoldForMatching(String s) {
  final out = StringBuffer();
  for (final rune in s.runes) {
    if (rune < 0x80) {
      out.writeCharCode(rune >= 0x61 && rune <= 0x7A ? rune - 32 : rune);
      continue;
    }
    final override = (_overrides ??= _parseOverrides())[rune];
    out.write(override ?? String.fromCharCode(rune).toLowerCase().toUpperCase());
  }
  return out.toString();
}

Map<int, String>? _overrides;

Map<int, String> _parseOverrides() {
  final table = <int, String>{};
  for (final entry in _overrideData.split(';')) {
    if (entry.isEmpty) continue;
    final eq = entry.indexOf('=');
    table[int.parse(entry.substring(0, eq), radix: 16)] = String.fromCharCodes(
      entry.substring(eq + 1).split(',').map((h) => int.parse(h, radix: 16)),
    );
  }
  return table;
}

/// `codepoint=target[,target]` entries separated by `;`, parsed on first use.
const String _overrideData =
    'df=53,53;130=49,307;131=131;149=2bc,4e;1f0=4a,30c;37f=3f3;390=399,308,301;3b0=3a5,308,301;'
    '524=525;526=527;528=529;52a=52b;52c=52d;52e=52f;587=535,552;10c7=2d27;10cd=2d2d;13f8=13f0;'
    '13f9=13f1;13fa=13f2;13fb=13f3;13fc=13f4;13fd=13f5;1c80=412;1c81=414;1c82=41e;1c83=421;'
    '1c84=422;1c85=422;1c86=42a;1c87=462;1c88=a64a;1c90=10d0;1c91=10d1;1c92=10d2;1c93=10d3;'
    '1c94=10d4;1c95=10d5;1c96=10d6;1c97=10d7;1c98=10d8;1c99=10d9;1c9a=10da;1c9b=10db;1c9c=10dc;'
    '1c9d=10dd;1c9e=10de;1c9f=10df;1ca0=10e0;1ca1=10e1;1ca2=10e2;1ca3=10e3;1ca4=10e4;1ca5=10e5;'
    '1ca6=10e6;1ca7=10e7;1ca8=10e8;1ca9=10e9;1caa=10ea;1cab=10eb;1cac=10ec;1cad=10ed;1cae=10ee;'
    '1caf=10ef;1cb0=10f0;1cb1=10f1;1cb2=10f2;1cb3=10f3;1cb4=10f4;1cb5=10f5;1cb6=10f6;1cb7=10f7;'
    '1cb8=10f8;1cb9=10f9;1cba=10fa;1cbd=10fd;1cbe=10fe;1cbf=10ff;1e96=48,331;1e97=54,308;'
    '1e98=57,30a;1e99=59,30a;1e9a=41,2be;1e9e=53,53;1f50=3a5,313;1f52=3a5,313,300;'
    '1f54=3a5,313,301;1f56=3a5,313,342;1f80=1f08,399;1f81=1f09,399;1f82=1f0a,399;1f83=1f0b,399;'
    '1f84=1f0c,399;1f85=1f0d,399;1f86=1f0e,399;1f87=1f0f,399;1f88=1f08,399;1f89=1f09,399;'
    '1f8a=1f0a,399;1f8b=1f0b,399;1f8c=1f0c,399;1f8d=1f0d,399;1f8e=1f0e,399;1f8f=1f0f,399;'
    '1f90=1f28,399;1f91=1f29,399;1f92=1f2a,399;1f93=1f2b,399;1f94=1f2c,399;1f95=1f2d,399;'
    '1f96=1f2e,399;1f97=1f2f,399;1f98=1f28,399;1f99=1f29,399;1f9a=1f2a,399;1f9b=1f2b,399;'
    '1f9c=1f2c,399;1f9d=1f2d,399;1f9e=1f2e,399;1f9f=1f2f,399;1fa0=1f68,399;1fa1=1f69,399;'
    '1fa2=1f6a,399;1fa3=1f6b,399;1fa4=1f6c,399;1fa5=1f6d,399;1fa6=1f6e,399;1fa7=1f6f,399;'
    '1fa8=1f68,399;1fa9=1f69,399;1faa=1f6a,399;1fab=1f6b,399;1fac=1f6c,399;1fad=1f6d,399;'
    '1fae=1f6e,399;1faf=1f6f,399;1fb2=1fba,399;1fb3=391,399;1fb4=386,399;1fb6=391,342;'
    '1fb7=391,342,399;1fbc=391,399;1fc2=1fca,399;1fc3=397,399;1fc4=389,399;1fc6=397,342;'
    '1fc7=397,342,399;1fcc=397,399;1fd2=399,308,300;1fd3=399,308,301;1fd6=399,342;'
    '1fd7=399,308,342;1fe2=3a5,308,300;1fe3=3a5,308,301;1fe4=3a1,313;1fe6=3a5,342;'
    '1fe7=3a5,308,342;1ff2=1ffa,399;1ff3=3a9,399;1ff4=38f,399;1ff6=3a9,342;1ff7=3a9,342,399;'
    '1ffc=3a9,399;2c2f=2c5f;2c70=252;2c7e=23f;2c7f=240;2ceb=2cec;2ced=2cee;2cf2=2cf3;a660=a661;'
    'a698=a699;a69a=a69b;a78d=265;a790=a791;a792=a793;a796=a797;a798=a799;a79a=a79b;a79c=a79d;'
    'a79e=a79f;a7a0=a7a1;a7a2=a7a3;a7a4=a7a5;a7a6=a7a7;a7a8=a7a9;a7aa=266;a7ab=25c;a7ac=261;'
    'a7ad=26c;a7ae=26a;a7b0=29e;a7b1=287;a7b2=29d;a7b3=ab53;a7b4=a7b5;a7b6=a7b7;a7b8=a7b9;'
    'a7ba=a7bb;a7bc=a7bd;a7be=a7bf;a7c0=a7c1;a7c2=a7c3;a7c4=a794;a7c5=282;a7c6=1d8e;a7c7=a7c8;'
    'a7c9=a7ca;a7d0=a7d1;a7d6=a7d7;a7d8=a7d9;a7f5=a7f6;ab70=13a0;ab71=13a1;ab72=13a2;ab73=13a3;'
    'ab74=13a4;ab75=13a5;ab76=13a6;ab77=13a7;ab78=13a8;ab79=13a9;ab7a=13aa;ab7b=13ab;ab7c=13ac;'
    'ab7d=13ad;ab7e=13ae;ab7f=13af;ab80=13b0;ab81=13b1;ab82=13b2;ab83=13b3;ab84=13b4;ab85=13b5;'
    'ab86=13b6;ab87=13b7;ab88=13b8;ab89=13b9;ab8a=13ba;ab8b=13bb;ab8c=13bc;ab8d=13bd;ab8e=13be;'
    'ab8f=13bf;ab90=13c0;ab91=13c1;ab92=13c2;ab93=13c3;ab94=13c4;ab95=13c5;ab96=13c6;ab97=13c7;'
    'ab98=13c8;ab99=13c9;ab9a=13ca;ab9b=13cb;ab9c=13cc;ab9d=13cd;ab9e=13ce;ab9f=13cf;aba0=13d0;'
    'aba1=13d1;aba2=13d2;aba3=13d3;aba4=13d4;aba5=13d5;aba6=13d6;aba7=13d7;aba8=13d8;aba9=13d9;'
    'abaa=13da;abab=13db;abac=13dc;abad=13dd;abae=13de;abaf=13df;abb0=13e0;abb1=13e1;abb2=13e2;'
    'abb3=13e3;abb4=13e4;abb5=13e5;abb6=13e6;abb7=13e7;abb8=13e8;abb9=13e9;abba=13ea;abbb=13eb;'
    'abbc=13ec;abbd=13ed;abbe=13ee;abbf=13ef;fb00=46,46;fb01=46,49;fb02=46,4c;fb03=46,46,49;'
    'fb04=46,46,4c;fb05=53,54;fb06=53,54;fb13=544,546;fb14=544,535;fb15=544,53b;fb16=54e,546;'
    'fb17=544,53d;104b0=104d8;104b1=104d9;104b2=104da;104b3=104db;104b4=104dc;104b5=104dd;'
    '104b6=104de;104b7=104df;104b8=104e0;104b9=104e1;104ba=104e2;104bb=104e3;104bc=104e4;'
    '104bd=104e5;104be=104e6;104bf=104e7;104c0=104e8;104c1=104e9;104c2=104ea;104c3=104eb;'
    '104c4=104ec;104c5=104ed;104c6=104ee;104c7=104ef;104c8=104f0;104c9=104f1;104ca=104f2;'
    '104cb=104f3;104cc=104f4;104cd=104f5;104ce=104f6;104cf=104f7;104d0=104f8;104d1=104f9;'
    '104d2=104fa;104d3=104fb;10570=10597;10571=10598;10572=10599;10573=1059a;10574=1059b;'
    '10575=1059c;10576=1059d;10577=1059e;10578=1059f;10579=105a0;1057a=105a1;1057c=105a3;'
    '1057d=105a4;1057e=105a5;1057f=105a6;10580=105a7;10581=105a8;10582=105a9;10583=105aa;'
    '10584=105ab;10585=105ac;10586=105ad;10587=105ae;10588=105af;10589=105b0;1058a=105b1;'
    '1058c=105b3;1058d=105b4;1058e=105b5;1058f=105b6;10590=105b7;10591=105b8;10592=105b9;'
    '10594=105bb;10595=105bc;10c80=10cc0;10c81=10cc1;10c82=10cc2;10c83=10cc3;10c84=10cc4;'
    '10c85=10cc5;10c86=10cc6;10c87=10cc7;10c88=10cc8;10c89=10cc9;10c8a=10cca;10c8b=10ccb;'
    '10c8c=10ccc;10c8d=10ccd;10c8e=10cce;10c8f=10ccf;10c90=10cd0;10c91=10cd1;10c92=10cd2;'
    '10c93=10cd3;10c94=10cd4;10c95=10cd5;10c96=10cd6;10c97=10cd7;10c98=10cd8;10c99=10cd9;'
    '10c9a=10cda;10c9b=10cdb;10c9c=10cdc;10c9d=10cdd;10c9e=10cde;10c9f=10cdf;10ca0=10ce0;'
    '10ca1=10ce1;10ca2=10ce2;10ca3=10ce3;10ca4=10ce4;10ca5=10ce5;10ca6=10ce6;10ca7=10ce7;'
    '10ca8=10ce8;10ca9=10ce9;10caa=10cea;10cab=10ceb;10cac=10cec;10cad=10ced;10cae=10cee;'
    '10caf=10cef;10cb0=10cf0;10cb1=10cf1;10cb2=10cf2;118a0=118c0;118a1=118c1;118a2=118c2;'
    '118a3=118c3;118a4=118c4;118a5=118c5;118a6=118c6;118a7=118c7;118a8=118c8;118a9=118c9;'
    '118aa=118ca;118ab=118cb;118ac=118cc;118ad=118cd;118ae=118ce;118af=118cf;118b0=118d0;'
    '118b1=118d1;118b2=118d2;118b3=118d3;118b4=118d4;118b5=118d5;118b6=118d6;118b7=118d7;'
    '118b8=118d8;118b9=118d9;118ba=118da;118bb=118db;118bc=118dc;118bd=118dd;118be=118de;'
    '118bf=118df;16e40=16e60;16e41=16e61;16e42=16e62;16e43=16e63;16e44=16e64;16e45=16e65;'
    '16e46=16e66;16e47=16e67;16e48=16e68;16e49=16e69;16e4a=16e6a;16e4b=16e6b;16e4c=16e6c;'
    '16e4d=16e6d;16e4e=16e6e;16e4f=16e6f;16e50=16e70;16e51=16e71;16e52=16e72;16e53=16e73;'
    '16e54=16e74;16e55=16e75;16e56=16e76;16e57=16e77;16e58=16e78;16e59=16e79;16e5a=16e7a;'
    '16e5b=16e7b;16e5c=16e7c;16e5d=16e7d;16e5e=16e7e;16e5f=16e7f;1e900=1e922;1e901=1e923;'
    '1e902=1e924;1e903=1e925;1e904=1e926;1e905=1e927;1e906=1e928;1e907=1e929;1e908=1e92a;'
    '1e909=1e92b;1e90a=1e92c;1e90b=1e92d;1e90c=1e92e;1e90d=1e92f;1e90e=1e930;1e90f=1e931;'
    '1e910=1e932;1e911=1e933;1e912=1e934;1e913=1e935;1e914=1e936;1e915=1e937;1e916=1e938;'
    '1e917=1e939;1e918=1e93a;1e919=1e93b;1e91a=1e93c;1e91b=1e93d;1e91c=1e93e;1e91d=1e93f;'
    '1e91e=1e940;1e91f=1e941;1e920=1e942;1e921=1e943;';
