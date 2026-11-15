/// Edits an XMP packet as text, touching only the properties asked for.
///
/// XMP is XML, but every file's packet is written differently (attributes or
/// elements, any prefix layout, vendor namespaces). Parsing and re-writing it
/// would reorder or lose whatever this editor does not understand, such as a
/// motion photo's container directory. So the properties are found and
/// replaced in place and the rest of the packet is left byte for byte.
class XmpEditor {
  const XmpEditor._();

  static const String _dcNamespace = 'http://purl.org/dc/elements/1.1/';

  /// A new packet holding just [keywords].
  static String newPacket(List<String> keywords) {
    final b = StringBuffer()
      ..write('<?xpacket begin="\uFEFF" id="W5M0MpCehiHzreSzNTczkc9d"?>\n')
      ..write('<x:xmpmeta xmlns:x="adobe:ns:meta/">')
      ..write('<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">')
      ..write('<rdf:Description rdf:about="" xmlns:dc="$_dcNamespace">')
      ..write(_subjectElement(keywords))
      ..write('</rdf:Description></rdf:RDF></x:xmpmeta>\n')
      ..write('<?xpacket end="w"?>');
    return b.toString();
  }

  /// [xmp] with its keywords (`dc:subject`) replaced by [keywords]; an empty
  /// list removes them. Keywords of the digiKam tag list that are no longer
  /// wanted are dropped from it too, because the gallery reads both and a
  /// removed tag would otherwise come back.
  ///
  /// With no packet to edit ([xmp] null) a new one is made when there is
  /// something to store, and null (nothing to do) when there is not.
  static String? setKeywords(String? xmp, List<String> keywords) {
    if (xmp == null) return keywords.isEmpty ? null : newPacket(keywords);

    var out = xmp.replaceAll(
      RegExp(r'<dc:subject\b[^>]*?/>|<dc:subject\b[^>]*>.*?</dc:subject>', dotAll: true),
      '',
    );

    final wanted = {for (final k in keywords) k.toLowerCase()};
    out = out.replaceAllMapped(
      RegExp(r'<digiKam:TagsList\b[^>]*>(.*?)</digiKam:TagsList>', dotAll: true),
      (m) {
        final kept = <String>[];
        for (final li in RegExp(r'<rdf:li[^>]*>([^<]*)</rdf:li>').allMatches(m[1]!)) {
          final text = _unescape(li[1]!).trim();
          if (wanted.contains(text.toLowerCase())) kept.add(text);
        }
        if (kept.isEmpty) return '';
        final items = kept.map((t) => '<rdf:li>${_escape(t)}</rdf:li>').join();
        return '<digiKam:TagsList><rdf:Seq>$items</rdf:Seq></digiKam:TagsList>';
      },
    );

    if (keywords.isEmpty) return out;

    final description = RegExp(r'<rdf:Description\b([^>]*?)(/?)>').firstMatch(out);
    if (description == null) return newPacket(keywords);

    final attrs = description[1]!;
    final selfClosing = description[2] == '/';
    final inScope = attrs.contains('xmlns:dc=') ||
        out.substring(0, description.start).contains('xmlns:dc=');
    final opening = StringBuffer('<rdf:Description$attrs');
    if (!inScope) opening.write(' xmlns:dc="$_dcNamespace"');
    opening.write('>');
    final element = _subjectElement(keywords);
    final replacement = selfClosing
        ? '$opening$element</rdf:Description>'
        : '$opening$element';
    return out.replaceRange(description.start, description.end, replacement);
  }

  /// Date properties written when a photo's date is changed. Only those the
  /// packet already has are touched: Exif is the authority for a photo's date
  /// and the packet is kept consistent with it, not given new fields.
  static const List<String> _dateProperties = [
    'xmp:CreateDate',
    'photoshop:DateCreated',
    'exif:DateTimeOriginal',
    'exif:DateTimeDigitized',
  ];

  static final String _dateBody = r'\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2})?)?';

  /// [xmp] with the creation date properties it has set to [isoDate]
  /// (`YYYY-MM-DDTHH:MM:SS`). Any zone or fraction after the old value stays.
  static String setDates(String xmp, String isoDate) {
    var out = xmp;
    for (final name in _dateProperties) {
      final key = RegExp.escape(name);
      out = out.replaceAllMapped(
        RegExp('($key\\s*=\\s*["\'])$_dateBody'),
        (m) => '${m[1]}$isoDate',
      );
      out = out.replaceAllMapped(
        RegExp('(<$key\\b[^>]*>\\s*)$_dateBody'),
        (m) => '${m[1]}$isoDate',
      );
    }
    return out;
  }

  static String _subjectElement(List<String> keywords) {
    final items = keywords.map((k) => '<rdf:li>${_escape(k)}</rdf:li>').join();
    return '<dc:subject><rdf:Bag>$items</rdf:Bag></dc:subject>';
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
