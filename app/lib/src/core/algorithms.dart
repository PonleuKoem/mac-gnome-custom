import 'dart:math' as math;
import 'dart:ui';

/// Fuzzy score of [query] against [text]: null when not every query character
/// appears in order. Higher is better: prefix and word-start matches and
/// contiguous runs score more; shorter candidates break ties.
double? fuzzyScore(String query, String text) {
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return 0;
  final t = text.toLowerCase();
  if (t.startsWith(q)) return 1000 - t.length.toDouble();
  final idx = t.indexOf(q);
  if (idx >= 0) {
    final wordStart = idx == 0 || !_isAlnum(t.codeUnitAt(idx - 1));
    return (wordStart ? 800 : 600) - idx - t.length / 100;
  }
  var score = 0.0;
  var ti = 0;
  var prev = -2;
  for (var qi = 0; qi < q.length; qi++) {
    final c = q.codeUnitAt(qi);
    while (ti < t.length && t.codeUnitAt(ti) != c) {
      ti++;
    }
    if (ti >= t.length) return null;
    if (ti == prev + 1) score += 5;
    if (ti == 0 || !_isAlnum(t.codeUnitAt(ti - 1))) score += 8;
    score += 1;
    prev = ti;
    ti++;
  }
  return score - t.length / 100;
}

bool _isAlnum(int c) => (c >= 48 && c <= 57) || (c >= 97 && c <= 122);

/// Items that match [query], best first.
List<T> fuzzyFilter<T>(String query, Iterable<T> items, String Function(T) text) {
  final scored = <(T, double)>[];
  for (final item in items) {
    final s = fuzzyScore(query, text(item));
    if (s != null) scored.add((item, s));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.map((e) => e.$1).toList();
}

/// Wall clock used by the UI. Tests replace it to make golden images stable.
DateTime Function() shellNow = DateTime.now;

/// Tiny strftime-like formatter for the top-bar clock (no intl dependency).
/// Tokens: EEEE EEE MMMM MMM MM M dd d HH H hh h mm ss a. Anything else is
/// copied verbatim.
String formatClock(DateTime t, String pattern) {
  const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  String two(int v) => v.toString().padLeft(2, '0');
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final tokens = <String, String Function()>{
    'EEEE': () => days[t.weekday - 1],
    'EEE': () => days[t.weekday - 1].substring(0, 3),
    'MMMM': () => months[t.month - 1],
    'MMM': () => months[t.month - 1].substring(0, 3),
    'MM': () => two(t.month),
    'M': () => '${t.month}',
    'dd': () => two(t.day),
    'd': () => '${t.day}',
    'HH': () => two(t.hour),
    'H': () => '${t.hour}',
    'hh': () => two(h12),
    'h': () => '$h12',
    'mm': () => two(t.minute),
    'ss': () => two(t.second),
    'a': () => t.hour < 12 ? 'AM' : 'PM',
  };
  final keys = tokens.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  final out = StringBuffer();
  var i = 0;
  outer:
  while (i < pattern.length) {
    for (final k in keys) {
      if (pattern.startsWith(k, i)) {
        out.write(tokens[k]!());
        i += k.length;
        continue outer;
      }
    }
    out.write(pattern[i]);
    i++;
  }
  return out.toString();
}

/// Size of the dock panel for [items] icons.
Size dockSize({required int items, required double iconSize, required bool vertical}) {
  final pad = iconSize * 0.18;
  const dot = 6.0; // running-indicator row under every icon
  final thickness = iconSize + pad * 2 + dot;
  // Stacked vertically, each icon also carries its indicator row.
  final extent = items * (iconSize + pad + (vertical ? dot : 0)) + pad;
  return vertical ? Size(thickness, extent) : Size(extent, thickness);
}

/// macOS-style dock magnification ("fisheye").
///
/// Items sit in slots of base extent [slot] along the dock; an optional
/// flexible gap (a panel dock's spacer) sits before item [gapIndex] with base
/// extent [gapBase] and absorbs growth, so the dock's total length [length]
/// stays fixed. [cursor] is the pointer along the main axis in the *magnified*
/// layout (what the user sees), relative to the first slot's start.
///
/// The cursor is mapped back to unmagnified coordinates (a few fixed-point
/// steps), so the icon under the pointer stays under it as its neighbours
/// grow — no jitter. Each item then scales by a cos² falloff over ~2 slots,
/// up to [maxScale] at [strength] 1.
List<double> dockMagnify({
  required int count,
  required double slot,
  required double cursor,
  required double maxScale,
  double strength = 1,
  int? gapIndex,
  double gapBase = 0,
  double? length,
}) {
  const reach = 2.2; // slots on each side that grow
  double baseCenter(int i) => i * slot + slot / 2 + (gapIndex != null && i >= gapIndex ? gapBase : 0);
  List<double> scalesAt(double u) => [
    for (var i = 0; i < count; i++)
      () {
        final x = (baseCenter(i) - u) / slot;
        if (x.abs() >= reach) return 1.0;
        final c = math.cos(math.pi * x / (2 * reach));
        return 1 + (maxScale - 1) * strength * c * c;
      }(),
  ];
  if (count == 0 || maxScale <= 1 || strength <= 0) return List.filled(count, 1.0);

  // Magnified position → base position, for given scales.
  double toBase(List<double> s) {
    final grown = s.fold<double>(0, (a, v) => a + slot * v);
    final gapNow = gapIndex == null ? 0.0 : math.max(0.0, (length ?? grown + gapBase) - grown);
    var acc = 0.0, base = 0.0;
    for (var i = 0; i < count; i++) {
      if (gapIndex != null && i == gapIndex) {
        if (cursor < acc + gapNow) return base + (gapNow == 0 ? 0 : (cursor - acc) * gapBase / gapNow);
        acc += gapNow;
        base += gapBase;
      }
      final w = slot * s[i];
      if (cursor < acc + w) return base + (cursor - acc) / s[i];
      acc += w;
      base += slot;
    }
    return base + (cursor - acc);
  }

  var u = cursor;
  var s = scalesAt(u);
  for (var k = 0; k < 4; k++) {
    u = toBase(s);
    s = scalesAt(u);
  }
  return s;
}
