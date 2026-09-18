import 'dart:typed_data';

import 'android_resource_chunk_reader.dart';

/// Well-known attribute resource id for `android:icon`
/// (`android.R.attr.icon` = `0x01010002`), from the framework's public
/// `attrs.xml`. Used as a fallback match via the XML resource map when an
/// attribute's name string can't be read directly -- see
/// [findApplicationIconResourceId]'s doc comment.
const _androidIconAttrResId = 0x01010002;

/// Parses a compiled `AndroidManifest.xml` (Android's "AXML" binary XML
/// format) and returns the resource id `android:icon` resolves to on the
/// `<application>` element, or `null` if there isn't one.
///
/// This only reads the parts of the format needed for that one lookup:
///
///  - The chunk's string pool (element/attribute names and any literal
///    string values) -- see [AndroidChunkReader.parseStringPool].
///  - The XML resource map (`RES_XML_RESOURCE_MAP_TYPE`), which maps each
///    string-pool index to a public attribute resource id where one
///    exists. This is normally redundant with matching the attribute's
///    name string against `"icon"` -- aapt/aapt2 always keeps the name
///    string too -- but is checked as a fallback in case a future/foreign
///    compiler ever omits it.
///  - `RES_XML_START_ELEMENT_TYPE`/`RES_XML_END_ELEMENT_TYPE` chunks, just
///    enough to find the `<application>` element and read its attributes.
///
/// Everything else in the file (namespaces, comments, line numbers,
/// CDATA, every other element/attribute) is skipped by advancing past
/// each chunk's own `size` unread.
///
/// Returns `null` -- never throws -- for anything this parser doesn't
/// understand: a missing/malformed top-level chunk, no `<application>`
/// element, no `icon` attribute, or an `icon` attribute whose value isn't
/// a resource reference (`Res_value.dataType` of `TYPE_REFERENCE` /
/// `TYPE_DYNAMIC_REFERENCE` -- the only way `android:icon="@mipmap/..."`
/// compiles). Callers should treat `null` as "no icon available" and fall
/// back to a generic file-type icon, exactly like a corrupt/unreadable
/// APK.
int? findApplicationIconResourceId(Uint8List manifestBytes) {
  try {
    final reader = AndroidChunkReader(manifestBytes);
    final top = reader.readChunkHeader(0);
    if (top.type != AndroidChunkType.resXml) return null;

    var pos = top.headerSize;
    final end = top.size < reader.length ? top.size : reader.length;

    List<String> strings = const [];
    List<int> resourceMap = const [];

    while (pos + 8 <= end) {
      final chunk = reader.readChunkHeader(pos);
      if (chunk.size <= 0) break;

      switch (chunk.type) {
        case AndroidChunkType.resStringPool:
          if (strings.isEmpty) {
            strings = reader.parseStringPool(pos);
          }
        case AndroidChunkType.resXmlResourceMap:
          final count = (chunk.size - chunk.headerSize) ~/ 4;
          resourceMap = List<int>.generate(
            count,
            (i) => reader.readU32(pos + chunk.headerSize + 4 * i),
          );
        case AndroidChunkType.resXmlStartElement:
          final iconResId = _readIconIfApplicationElement(
            reader,
            pos,
            chunk,
            strings,
            resourceMap,
          );
          if (iconResId != null) return iconResId;
      }

      pos += chunk.size;
    }
    return null;
  } catch (_) {
    // Truncated/malformed/adversarial input -- treat exactly like "no
    // icon found" rather than propagating a parse exception.
    return null;
  }
}

/// If the `RES_XML_START_ELEMENT_TYPE` chunk at [pos] is `<application>`,
/// scans its attributes for `icon` and returns the resource id it points
/// at. Returns `null` for any other element, or if `<application>` has no
/// usable `icon` attribute.
int? _readIconIfApplicationElement(
  AndroidChunkReader reader,
  int pos,
  AndroidChunkHeader chunk,
  List<String> strings,
  List<int> resourceMap,
) {
  // ResXMLTree_node body: {lineNumber u32; comment u32;} (8 bytes),
  // occupying the gap between the ResChunk_header and this element's own
  // fields -- i.e. exactly `chunk.headerSize` in from `pos`.
  final body = pos + chunk.headerSize;
  // ResXMLTree_attrExt: {ns u32; name u32; attributeStart u16;
  // attributeSize u16; attributeCount u16; idIndex u16; classIndex u16;
  // styleIndex u16;}
  final nameIdx = reader.readU32(body + 4);
  final elementName = _stringAt(strings, nameIdx);
  if (elementName != 'application') return null;

  final attributeStart = reader.readU16(body + 8);
  final attributeSize = reader.readU16(body + 10);
  final attributeCount = reader.readU16(body + 12);
  final attrsBase = body + attributeStart;

  for (var i = 0; i < attributeCount; i++) {
    final a = attrsBase + i * attributeSize;
    // ResXMLTree_attribute: {ns u32; name u32; rawValue u32;
    // typedValue: {size u16; res0 u8; dataType u8; data u32;}}
    final attrNameIdx = reader.readU32(a + 4);
    final valueDataType = reader.readU8(a + 15);
    final valueData = reader.readU32(a + 16);

    final attrName = _stringAt(strings, attrNameIdx);
    final mappedResId = attrNameIdx < resourceMap.length
        ? resourceMap[attrNameIdx]
        : null;
    final isIconAttr = attrName == 'icon' || mappedResId == _androidIconAttrResId;
    if (!isIconAttr) continue;

    final isReference = valueDataType == AndroidResValueType.typeReference ||
        valueDataType == AndroidResValueType.typeDynamicReference;
    if (isReference) return valueData;
  }
  return null;
}

String? _stringAt(List<String> strings, int index) =>
    (index >= 0 && index < strings.length) ? strings[index] : null;
