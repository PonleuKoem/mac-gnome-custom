import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mac_gnome_custom/src/core/algorithms.dart';
import 'package:mac_gnome_custom/src/core/ui_state.dart';

void main() {
  group('fuzzy', () {
    test('prefix beats substring beats subsequence', () {
      final names = ['Terminal', 'System Settings', 'Activity Monitor', 'TextEdit'];
      expect(fuzzyFilter('te', names, (s) => s).take(2).toSet(), {'TextEdit', 'Terminal'}); // equal-length prefixes tie
      expect(fuzzyFilter('sett', names, (s) => s).first, 'System Settings');
      expect(fuzzyFilter('actmon', names, (s) => s), ['Activity Monitor']);
      expect(fuzzyFilter('zzz', names, (s) => s), isEmpty);
    });

    test('empty query matches everything', () {
      expect(fuzzyScore('', 'anything'), 0);
    });
  });

  group('formatClock', () {
    final t = DateTime(2026, 9, 24, 7, 5, 9);

    test('GNOME default', () {
      expect(formatClock(t, 'EEE MMM d  HH:mm'), 'Thu Sep 24  07:05');
    });

    test('12-hour and long names', () {
      expect(formatClock(t, 'EEEE, MMMM d · h:mm a'), 'Thursday, September 24 · 7:05 AM');
      expect(formatClock(DateTime(2026, 1, 1, 0, 0), 'hh:mm a'), '12:00 AM');
      expect(formatClock(t, 'HH:mm:ss'), '07:05:09');
    });

    test('unknown characters pass through', () {
      expect(formatClock(t, '[HH]'), '[07]');
    });
  });

  test('dockSize matches icon + padding math', () {
    final s = dockSize(items: 5, iconSize: 50, vertical: false);
    expect(s.width, 5 * (50 + 9) + 9);
    expect(s.height, 50 + 18 + 6);
    // Vertical: every icon also stacks its 6 pt running-indicator row.
    expect(dockSize(items: 5, iconSize: 50, vertical: true), Size(s.height, 5 * (50 + 9 + 6) + 9));
  });

  group('dock magnification', () {
    test('the icon under the pointer grows most, neighbours ease off symmetrically', () {
      // Pointer on icon 3's centre as drawn (the cursor is in magnified space).
      var cursor = 3 * 50 + 25.0;
      var s = <double>[];
      for (var k = 0; k < 6; k++) {
        s = dockMagnify(count: 7, slot: 50, cursor: cursor, maxScale: 1.5);
        cursor = s.take(3).fold<double>(0, (a, v) => a + 50 * v) + 50 * s[3] / 2;
      }
      expect(s[3], closeTo(1.5, 0.02));
      expect(s[2], closeTo(s[4], 0.02));
      expect(s[2], lessThan(s[3]));
      expect(s[1], lessThan(s[2]));
      expect(s[0], closeTo(1, 0.01));
      expect(s[6], closeTo(1, 0.01));
    });

    test('the icon under the pointer stays under it as the dock grows', () {
      // Pointer at the visual centre of icon 1 in the magnified layout.
      for (final i in [0, 1, 4]) {
        final rest = List.filled(6, 1.0);
        var s = rest;
        var cursor = i * 50 + 25.0;
        for (var k = 0; k < 3; k++) {
          s = dockMagnify(count: 6, slot: 50, cursor: cursor, maxScale: 1.8);
          cursor = s.take(i).fold<double>(0, (a, v) => a + 50 * v) + 50 * s[i] / 2;
        }
        final start = s.take(i).fold<double>(0, (a, v) => a + 50 * v);
        expect(cursor, inInclusiveRange(start, start + 50 * s[i]), reason: 'icon $i');
        expect(s[i], s.reduce(math.max));
      }
    });

    test('off, at rest, and across a panel gap', () {
      expect(dockMagnify(count: 4, slot: 50, cursor: 60, maxScale: 1), [1, 1, 1, 1]);
      expect(dockMagnify(count: 4, slot: 50, cursor: 60, maxScale: 1.5, strength: 0), [1, 1, 1, 1]);
      // Panel: 3 icons, a 600 pt gap, then 2 buttons. Pointer on the last icon.
      final s = dockMagnify(count: 5, slot: 50, cursor: 125, maxScale: 1.5, gapIndex: 3, gapBase: 600, length: 850);
      expect(s[2], greaterThan(1.4));
      expect([s[3], s[4]], [1, 1], reason: 'buttons across the gap are far away');
    });
  });

  group('ShellUi', () {
    test('toggling the same popover closes it; opening overview closes popovers', () {
      final ui = ShellUi();
      const p = PopoverState(kind: PopoverKind.calendar, screenId: 1, anchor: Rect.zero);
      ui.openPopover(p);
      expect(ui.popover, isNotNull);
      ui.openPopover(p);
      expect(ui.popover, isNull);
      ui.openPopover(p);
      ui.openOverview();
      expect(ui.popover, isNull);
      ui.setQuery('x');
      ui.closeOverview();
      expect(ui.query, isEmpty);
    });
  });
}
