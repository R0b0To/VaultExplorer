import 'dart:math' as math;

import 'package:vaultexplorer/features/settings/search/settings_search_models.dart';
import 'package:vaultexplorer/features/settings/search/settings_search_text.dart';

/// Ranks [index] against [query] and returns the matches, best first.
///
/// Every whitespace-separated word of the query has to match somewhere in the
/// entry (title, keywords, breadcrumb or details), so "auto lock timeout" and
/// "timeout lock" both find the timeout pickers. Title matches outrank
/// keyword/breadcrumb matches, which outrank detail (subtitle) matches. Words
/// of four or more letters also tolerate a typo. Matching is substring-based
/// as well as word-based, so it works for languages written without spaces.
///
/// Returns an empty list for a blank query. Ties keep registry order.
List<ResolvedSettingsEntry> searchSettingsIndex(
  String query,
  List<ResolvedSettingsEntry> index, {
  int limit = 40,
}) {
  final normalizedQuery = normalizeSearchText(query);
  if (normalizedQuery.isEmpty) return const [];
  final tokens = normalizedQuery.split(' ');

  final scored = <_Scored>[];
  for (var i = 0; i < index.length; i++) {
    final score = _scoreEntry(normalizedQuery, tokens, index[i]);
    if (score > 0) scored.add(_Scored(index[i], score, i));
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.order.compareTo(b.order);
  });
  return [for (final s in scored.take(limit)) s.entry];
}

class _Scored {
  const _Scored(this.entry, this.score, this.order);
  final ResolvedSettingsEntry entry;
  final int score;
  final int order;
}

int _scoreEntry(
  String query,
  List<String> tokens,
  ResolvedSettingsEntry entry,
) {
  var total = 0;
  for (final token in tokens) {
    final s = _tokenScore(token, entry);
    if (s == 0) return 0; // every word must match something
    total += s;
  }
  if (entry.normTitle == query) {
    total += 100;
  } else if (entry.normTitle.startsWith(query)) {
    total += 40;
  } else if (entry.normTitle.contains(query)) {
    total += 20;
  }
  return total;
}

int _tokenScore(String token, ResolvedSettingsEntry entry) {
  return math.max(
    math.max(
      _fieldScore(token, entry.normTitle, exact: 100, prefix: 80, within: 55, fuzzy: 40),
      _fieldScore(token, entry.normKeywords, exact: 45, prefix: 45, within: 30),
    ),
    math.max(
      _fieldScore(token, entry.normPath, exact: 35, prefix: 35, within: 25),
      _fieldScore(token, entry.normDetails, exact: 20, prefix: 20, within: 12),
    ),
  );
}

int _fieldScore(
  String token,
  String field, {
  required int exact,
  required int prefix,
  required int within,
  int fuzzy = 0,
}) {
  if (field.isEmpty) return 0;
  final words = field.split(' ');
  var best = 0;
  for (final word in words) {
    if (word == token) return exact;
    if (word.startsWith(token)) best = math.max(best, prefix);
  }
  if (best > 0) return best;
  if (field.contains(token)) return within;
  if (fuzzy > 0 && token.length >= 4) {
    for (final word in words) {
      if (_fuzzyPrefixMatch(token, word)) return fuzzy;
    }
  }
  return 0;
}

/// True when [token] is within a small edit distance of the start of [word]
/// (so "screnshot" still finds "screenshots").
bool _fuzzyPrefixMatch(String token, String word) {
  final maxDistance = token.length >= 8 ? 2 : 1;
  for (var length = token.length - 1; length <= token.length + 1; length++) {
    if (length < 3 || length > word.length) continue;
    if (_editDistance(token, word.substring(0, length)) <= maxDistance) {
      return true;
    }
  }
  return false;
}

int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = math.min(
        math.min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + cost,
      );
    }
    previous = current;
  }
  return previous[b.length];
}
