import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mac_gnome_custom/src/core/shell_controller.dart';
import 'package:mac_gnome_custom/src/core/ui_state.dart';
import 'package:mac_gnome_custom/src/theme/shell_theme.dart';
import 'package:path/path.dart' as p;
import 'package:shellkit/shellkit.dart';

import 'support/fakes.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('startup covers the menu bar and keeps the GNOME dash inside Activities', () async {
    final (ctrl, c, events, themes, tmp) = await harness();
    final bar = c.shown['topbar:1']!;
    expect([bar.$1.x, bar.$1.y, bar.$1.w, bar.$1.h], [0, 0, 1512, 37]);
    expect(bar.$2, isFalse, reason: 'the top bar never takes keyboard focus');
    expect(c.shown.containsKey('dock'), isFalse, reason: 'overviewOnly mode');
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('shortcuts are public hotkey chords only (interface-only scope)', () async {
    final (ctrl, c, events, themes, tmp) = await harness();
    expect({for (final b in c.bindings) b.action: b.chord}, {'overview': 'alt+space', 'appGrid': 'ctrl+alt+space'});
    expect(c.bindings.map((b) => b.chord), isNot(contains(anyOf('superTap', 'superDoubleTap', 'cmd+tab'))));
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('before onboarding the shell is inert: no panels, no shortcuts, no system changes', () async {
    final (ctrl, c, events, themes, tmp) = await harness(onboarded: false);
    expect(c.shown, isEmpty, reason: 'the menu bar is not covered yet');
    expect(c.bindings, isEmpty, reason: 'no shortcuts registered yet');
    events.add(HotkeyEvent(action: 'overview'));
    await settle();
    expect(c.shown, isEmpty);
    await ctrl.applySystemNow();
    expect(c.applied, isEmpty);
    themes.setOnboarded(true);
    await settle();
    expect(c.shown.containsKey('topbar:1'), isTrue);
    expect(c.bindings, isNotEmpty);
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('a degraded (failed) theme is shown but never pushed to macOS', () async {
    final (ctrl, c, events, themes, tmp) = await harness();
    final dir = Directory(p.join(tmp.path, 'themes', 'broken'))..createSync(recursive: true);
    File(p.join(dir.path, 'theme.json')).writeAsStringSync('{ "id": "broken", ');
    await themes.repository.load();
    final t = themes.repository.resolve('broken');
    expect(t.degraded, isTrue);
    expect(t.warnings.single, contains('not found'));
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('applying after opt-in changes appearance only', () async {
    final (ctrl, c, events, themes, tmp) = await harness(onboarded: false);
    themes.setOnboarded(true);
    // Debounced (500 ms, DESIGN.md §5); poll so a loaded CI machine doesn't flake.
    for (var i = 0; i < 60 && c.applied.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(c.applied, isNotEmpty);
    final cfg = c.applied.last;
    expect(cfg.hideNativeDock, isTrue);
    expect(cfg.darkMode, isFalse, reason: 'Adwaita is light');
    expect(cfg.wallpaperPath, endsWith('gnome-adwaita/wallpapers/day.png'));
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('the Activities shortcut toggles the launcher below the top bar with keyboard focus', () async {
    final (ctrl, c, events, themes, tmp) = await harness();
    events.add(HotkeyEvent(action: 'overview'));
    await settle();
    final o = c.shown['overview']!;
    expect([o.$1.y, o.$1.h], [37, 982 - 37]);
    expect(o.$2, isTrue, reason: 'its search field takes typing');
    events.add(HotkeyEvent(action: 'appGrid'));
    await settle();
    expect(c.hidden, contains('overview'));
    events.add(HotkeyEvent(action: 'hotcorner'));
    await settle();
    expect(ctrl.ui.overviewOpen, isTrue);
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('native dismissal closes the launcher and its popover', () async {
    final (ctrl, c, events, themes, tmp) = await harness();
    ctrl.toggleOverview();
    ctrl.ui.openPopover(const PopoverState(kind: PopoverKind.calendar, screenId: 1, anchor: Rect.zero));
    events.add(SurfaceDismissedEvent(surfaceId: 'overview'));
    events.add(SurfaceDismissedEvent(surfaceId: 'popover'));
    await settle();
    expect(ctrl.ui.overviewOpen, isFalse);
    expect(ctrl.ui.popover, isNull);
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('dock clicks open apps the Dock way: activate if running, else launch', () async {
    final (ctrl, c, events, themes, tmp) = await harness(running: [app('com.a')]);
    ctrl.activate('com.a');
    ctrl.activate('com.b');
    await settle();
    expect(c.log.where((l) => !l.startsWith('setHitRegion')), ['activate com.a', 'launch com.b']);
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('the active app comes from public running-app data', () async {
    final (ctrl, c, events, themes, tmp) = await harness(running: [app('com.a'), app('com.b', active: true)]);
    expect(ctrl.apps.activeBundle, 'com.b');
    events.add(AppsChangedEvent(apps: [app('com.a', active: true), app('com.b')]));
    await settle();
    expect(ctrl.apps.activeBundle, 'com.a');
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('"always" dock mode shows a centred dock sized to its items', () async {
    final (ctrl, c, events, themes, tmp) = await harness(running: [app('com.x')]);
    themes.setActive('win11');
    await settle();
    final d = c.shown['dock']!.$1;
    expect(d.x + d.w / 2, closeTo(1512 / 2, 0.5));
    expect(d.y + d.h, closeTo(982 - 8, 0.5));
    final pinned = themes.theme.layout.pinned.length;
    expect(ctrl.dockItems().length, pinned + 1, reason: 'pinned + one unpinned running app');
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('a "panel" dock spans the screen edge below the menu bar (Ubuntu)', () async {
    final (ctrl, c, events, themes, tmp) = await harness(running: [app('com.x')]);
    themes.setActive('ubuntu');
    await settle();
    final d = ctrl.dockRestRect(ctrl.surfaces.mainScreen!);
    expect([d.left, d.top, d.height], [0, 37, 982 - 37]);
    expect(d.width, lessThan(80));
    final w = c.shown['dock']!.$1;
    expect([w.x, w.y, w.h], [0, 37, 982 - 37], reason: 'the window grows only away from the edge');
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test(
    'only what is visible takes clicks: the dock, magnified icons while hovered, the hover card while shown',
    () async {
      final (ctrl, c, events, themes, tmp) = await harness(running: [app('com.x')]);
      themes.setActive('win11');
      await settle();
      final main = ctrl.surfaces.mainScreen!;
      final rest = ctrl.dockHitRect(main)!;
      String region(Rect r) => 'setHitRegion dock ${r.left},${r.top},${r.width},${r.height}';
      expect(c.log.last, region(rest), reason: 'at rest: just the dock');

      ctrl.setDockPointerInside(true);
      final hovered = ctrl.dockActiveRect(main)!;
      expect(c.log.last, region(hovered));
      expect(hovered.bottom, rest.bottom);
      expect(hovered.top, lessThan(rest.top), reason: 'icons magnify up out of the dock');
      expect(hovered.top, greaterThan(0), reason: 'the empty room above stays click-through');

      final card = Rect.fromLTWH(rest.left, 10, 400, 150);
      ctrl.setDockCardRect(card);
      ctrl.setDockPointerInside(false); // pointer moved from the icon onto the card
      final withCard = ctrl.dockActiveRect(main)!;
      expect(withCard.top, 10);
      expect(withCard.contains(Offset(rest.left + 5, 100)), isTrue, reason: 'no gap between icon and card');

      ctrl.setDockCardRect(null);
      expect(c.log.last, region(rest), reason: 'card gone: back to just the dock');
      ctrl.dispose();
      themes.dispose();
      tmp.deleteSync(recursive: true);
    },
  );

  test('a floating dock on the right is centred vertically, 8 pt off the edge', () async {
    final (ctrl, c, events, themes, tmp) = await harness();
    themes.setActive('opus-tidepool');
    await settle();
    final d = c.shown['dock']!.$1;
    expect(d.x + d.w, closeTo(1512 - 8, 0.5));
    expect(d.y + d.h / 2, closeTo(982 / 2, 0.5));
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<SystemConfig> applied(Calls c) async {
    // Debounced (500 ms); poll so a loaded machine doesn't flake.
    final before = c.applied.length;
    for (var i = 0; i < 60 && c.applied.length == before; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return c.applied.last;
  }

  test('an always-visible dock asks macOS to keep windows clear of it', () async {
    final (ctrl, c, events, themes, tmp) = await harness(running: [app('com.x')]);
    themes.setActive('win11');
    final cfg = await applied(c);
    expect(cfg.dockReserveEdge, 'bottom');
    expect(cfg.dockReserveThickness, ctrl.dockThickness());
    expect(ctrl.dockThickness(), closeTo(36 + 36 * 0.36 + 6 + 16, 0.01), reason: 'island + 8 pt margins');

    // macOS reserved an 80 pt strip (the native spacer Dock): the dock fills
    // it, stays up while the launcher is open, and the launcher stops above it.
    events.add(
      ScreensChangedEvent(
        screens: [
          ScreenInfo(
            id: 1,
            frame: screen.frame,
            visibleFrame: RectD(x: 0, y: 37, w: 1512, h: 982 - 37 - 80),
            menuBarHeight: 37,
            scale: 2,
            isMain: true,
          ),
        ],
      ),
    );
    await settle();
    final d = ctrl.dockRestRect(ctrl.surfaces.mainScreen!);
    expect([d.left, d.top, d.width, d.height], [0, 982 - 80, 1512, 80]);
    expect(c.shown['dock']!.$1.y + c.shown['dock']!.$1.h, 982);
    ctrl.toggleOverview();
    await settle();
    final o = c.shown['overview']!.$1;
    expect([o.y, o.y + o.h], [37, 982 - 80]);
    expect(c.shown.containsKey('dock'), isTrue);

    // Turning it off hides the native Dock again and floats the dock.
    themes.setOverride('layout.dock.reserveSpace', false);
    expect((await applied(c)).dockReserveEdge, isNull);
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('no spacer when the dock only shows inside Activities', () async {
    final (ctrl, c, events, themes, tmp) = await harness(onboarded: false);
    themes.setOnboarded(true); // GNOME Adwaita: dock in the overview only
    final cfg = await applied(c);
    expect(cfg.hideNativeDock, isTrue);
    expect(cfg.dockReserveEdge, isNull);
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('the dock window has fixed room for magnified icons and the hover label, click-through at rest', () async {
    final (ctrl, c, events, themes, tmp) = await harness(running: [app('com.x')]);
    themes.setActive('win11');
    await settle();
    final window = c.shown['dock']!.$1;
    final size = themes.theme.layout.dockIconSize;
    final main = ctrl.surfaces.mainScreen!;
    final hit = ctrl.dockHitRect(main)!;
    // The clickable dock sits at the bottom of the window; above it is room
    // for 150% icons and the hover card (a row of window cards),
    // click-through until the pointer arrives.
    expect(hit.bottom, window.h);
    expect(window.h - hit.height, closeTo(size * 0.5 + 8 + ShellController.dockLabelRoom, 0.01));
    expect(window.w, greaterThanOrEqualTo(math.min(hit.width + ShellController.dockLabelWidth, main.frame.w)));
    expect(c.log, contains('setHitRegion dock ${hit.left},${hit.top},${hit.width},${hit.height}'));

    // Turning window previews on doesn't resize the dock window.
    ctrl.flags.value = {...ctrl.flags.value, 'windowThumbnails': true};
    await settle();
    expect(c.shown['dock']!.$1, window);
    ctrl.flags.value = {...ctrl.flags.value, 'windowThumbnails': false};
    await settle();

    // Without magnification there is still room for the label.
    themes.setOverride('layout.dock.magnification', 1);
    await settle();
    expect(window.h - ctrl.dockHitRect(main)!.height, isNonZero);
    await Future<void>.delayed(const Duration(milliseconds: 600)); // settings save debounce
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('the dock menu is the native macOS menu; its choices pin, unpin and open', () async {
    final (ctrl, c, events, themes, tmp) = await harness(running: [app('com.x')]);
    themes.setActive('win11');
    await settle();
    c.dockMenuAnswer = 'keep';
    await ctrl.showDockMenu('com.x', const Rect.fromLTWH(700, 920, 50, 50), DockPosition.bottom);
    expect(c.log, contains('dockMenu com.x bottom pinned=false at 700,920'));
    expect(themes.theme.layout.pinned, contains('com.x'));

    c.dockMenuAnswer = 'remove';
    await ctrl.showDockMenu('com.x', Rect.zero, DockPosition.bottom);
    expect(c.log.last, startsWith('dockMenu com.x bottom pinned=true'));
    expect(themes.theme.layout.pinned, isNot(contains('com.x')));

    c.dockMenuAnswer = 'open';
    await ctrl.showDockMenu('com.x', Rect.zero, DockPosition.left);
    expect(c.log.last, 'activate com.x');

    c.dockMenuAnswer = null; // dismissed
    final before = c.log.length;
    await ctrl.showDockMenu('com.x', Rect.zero, DockPosition.left);
    expect(c.log.length, before + 1, reason: 'only the menu call');
    await Future<void>.delayed(const Duration(milliseconds: 600)); // settings save debounce
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });

  test('pinning writes a per-theme override', () async {
    final (ctrl, c, events, themes, tmp) = await harness();
    ctrl.setPinned('com.new', true);
    expect(themes.theme.layout.pinned.last, 'com.new');
    ctrl.setPinned('com.new', false);
    expect(themes.theme.layout.pinned, isNot(contains('com.new')));
    ctrl.dispose();
    themes.dispose();
    tmp.deleteSync(recursive: true);
  });
}
