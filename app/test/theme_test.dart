import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mac_gnome_custom/src/theme/json_util.dart';
import 'package:mac_gnome_custom/src/theme/shell_theme.dart';
import 'package:mac_gnome_custom/src/theme/theme_parser.dart';
import 'package:mac_gnome_custom/src/theme/theme_repository.dart';
import 'package:mac_gnome_custom/src/theme/theme_store.dart';
import 'package:path/path.dart' as p;

import 'support/disk_bundle.dart';

void main() {
  group('json utils', () {
    test('parseColor handles #rgb, #rrggbb, #rrggbbaa', () {
      expect(parseColor('#fff'), const Color(0xFFFFFFFF));
      expect(parseColor('#3584e4'), const Color(0xFF3584E4));
      expect(parseColor('#000000cc'), const Color(0xCC000000));
      expect(parseColor('red'), isNull);
      expect(parseColor('#12345'), isNull);
      expect(parseColor(42), isNull);
    });

    test('colorToHex round-trips', () {
      for (final hex in ['#3584e4', '#000000cc', '#ffffff']) {
        expect(colorToHex(parseColor(hex)!), hex);
      }
    });

    test('deepMerge merges maps, replaces lists, null deletes', () {
      final out = deepMerge(
        {
          'a': {'b': 1, 'c': 2},
          'l': [1, 2],
          'x': 1,
        },
        {
          'a': {'c': 3},
          'l': [9],
          'x': null,
        },
      );
      expect(out, {
        'a': {'b': 1, 'c': 3},
        'l': [9],
      });
    });

    test('paths keep dotted token keys intact', () {
      expect(splitPath('tokens.color.bar.bg'), ['tokens', 'color', 'bar.bg']);
      expect(splitPath('tokens.font.size.bar'), ['tokens', 'font', 'size.bar']);
      expect(splitPath('keybindings.workspace.1'), ['keybindings', 'workspace.1']);
      expect(splitPath('layout.dock.iconSize'), ['layout', 'dock', 'iconSize']);
      final j = writePath({}, 'tokens.color.bar.bg', '#123456');
      expect(j, {
        'tokens': {
          'color': {'bar.bg': '#123456'},
        },
      });
    });

    test('writePath / readPath', () {
      final j = writePath({}, 'tokens.color.accent', '#ff0000');
      expect(readPath(j, 'tokens.color.accent'), '#ff0000');
      expect(readPath(j, 'tokens.nope'), isNull);
    });
  });

  group('ThemeParser', () {
    test('an empty theme resolves to the defaults with no warnings', () {
      final t = ThemeParser.parse({'id': 'x', 'name': 'X'});
      expect(t.warnings, isEmpty);
      expect(t.tokens.accent, const Color(0xFF3584E4));
      expect(t.layout.dockMode, DockMode.overviewOnly);
      expect(t.keybindings, {
        'overview': 'alt+space',
        'appGrid': 'ctrl+alt+space',
      }, reason: 'public hotkey chords only (ADR-0012); never ⌃Space (input sources)');
    });

    test('bad values fall back per token and are reported', () {
      final t = ThemeParser.parse({
        'tokens': {
          'color': {'accent': 'blue', 'bar.bg': '#ff0000'},
          'font': {'size.bar': 400},
          'motion': {'curve': 'bouncy'},
        },
        'layout': {
          'dock': {'mode': 'floating'},
          'topBar': {
            'left': ['activities', 'workspaces'],
          },
        },
        'system': {'accent': 'teal'},
        'keybindings': {'launchRockets': 'cmd+r'},
      });
      expect(t.tokens.accent, const Color(0xFF3584E4));
      expect(t.tokens.barBg, const Color(0xFFFF0000), reason: 'valid siblings still apply');
      expect(t.tokens.barFontSize, 14);
      expect(t.layout.dockMode, DockMode.overviewOnly);
      expect(t.layout.left, ['activities']);
      expect(t.system.accent, isNull);
      expect(t.keybindings.containsKey('launchRockets'), isFalse);
      expect(t.warnings.length, 7, reason: t.warnings.join('\n'));
    });

    test('wallpapers resolve against the theme folder', () {
      final t = ThemeParser.parse({
        'system': {
          'wallpaper': {'light': 'w/day.png', 'dark': '/abs/night.png'},
        },
      }, dir: '/themes/mine');
      expect(t.system.wallpaperFor(dark: false), '/themes/mine/w/day.png');
      expect(t.system.wallpaperFor(dark: true), '/abs/night.png');
    });

    test('lone-⌘ taps need keyboard monitoring and fall back to the default', () {
      final t = ThemeParser.parse({
        'keybindings': {'overview': 'superTap'},
      });
      expect(t.keybindings['overview'], 'alt+space');
      expect(t.warnings.single, contains('keyboard monitoring'));
    });

    test('an empty keybinding unbinds the action', () {
      final t = ThemeParser.parse({
        'keybindings': {'overview': ''},
      });
      expect(t.keybindings.containsKey('overview'), isFalse);
    });

    test('icon shape, dock style and launcher options parse, and bad values fall back', () {
      final ok = ThemeParser.parse({
        'tokens': {
          'icon': {'shape': 'circle'},
          'color': {'icon.plate': '#dfe8cf'},
        },
        'layout': {
          'dock': {'style': 'panel'},
          'launcher': {'iconSize': 96, 'labels': false},
        },
      });
      expect(ok.warnings, isEmpty);
      expect(ok.tokens.iconShape, IconShape.circle);
      expect(ok.tokens.iconPlate, const Color(0xFFDFE8CF));
      expect(ok.layout.dockStyle, DockStyle.panel);
      expect([ok.layout.launcherIconSize, ok.layout.launcherLabels], [96, false]);

      final bad = ThemeParser.parse({
        'tokens': {
          'icon': {'shape': 'hexagon'},
        },
        'layout': {
          'dock': {'style': 'sideways'},
          'launcher': {'iconSize': 500},
        },
      });
      expect(bad.tokens.iconShape, IconShape.native);
      expect(bad.layout.dockStyle, DockStyle.floating);
      expect(bad.layout.launcherIconSize, 72);
      expect(bad.warnings, hasLength(3));
    });

    test('bar hairline, dock colour, per-widget weight and launcher texture parse', () {
      final plain = ThemeParser.parse({
        'tokens': {
          'color': {'surface.fg': '#123456'},
        },
      });
      expect(plain.tokens.barBorder.a, 0, reason: 'no hairline unless asked for');
      expect(plain.tokens.dockFg, const Color(0xFF123456), reason: 'dock.fg follows surface.fg by default');
      expect(plain.tokens.weightFor('clock'), plain.tokens.barFontWeight);
      expect(plain.tokens.scrimTexture, ScrimTexture.none);

      final t = ThemeParser.parse({
        'tokens': {
          'color': {'bar.border': '#1f2f6b', 'dock.fg': '#e8347c'},
          'font': {'weight.bar': 500, 'weight.clock': 700},
          'texture': {'scrim': 'halftone', 'strength': 0.2},
        },
      });
      expect(t.warnings, isEmpty);
      expect(t.tokens.barBorder, const Color(0xFF1F2F6B));
      expect(t.tokens.dockFg, const Color(0xFFE8347C));
      expect(t.tokens.weightFor('clock'), FontWeight.w700);
      expect(t.tokens.weightFor('activities'), FontWeight.w500);
      expect([t.tokens.scrimTexture, t.tokens.textureStrength], [ScrimTexture.halftone, 0.2]);

      final bad = ThemeParser.parse({
        'tokens': {
          'font': {'weight.menu': 700},
          'texture': {'scrim': 'plaid', 'strength': 3},
        },
      });
      expect(bad.warnings, hasLength(3));
      expect(bad.tokens.scrimTexture, ScrimTexture.none);
    });

    test('darkMode accepts strings and booleans', () {
      expect(
        ThemeParser.parse({
          'system': {'darkMode': 'dark'},
        }).system.appearance,
        Appearance.dark,
      );
      expect(
        ThemeParser.parse({
          'system': {'darkMode': false},
        }).system.appearance,
        Appearance.light,
      );
      expect(ThemeParser.parse({}).system.appearance, Appearance.untouched);
    });
  });

  group('extends', () {
    test('child overrides parent, cycles are reported', () {
      final themes = {
        'a': {
          'id': 'a',
          'tokens': {
            'color': {'accent': '#111111', 'bar.bg': '#222222'},
          },
        },
        'b': {
          'id': 'b',
          'extends': 'a',
          'tokens': {
            'color': {'accent': '#333333'},
          },
        },
        'c1': {'id': 'c1', 'extends': 'c2'},
        'c2': {'id': 'c2', 'extends': 'c1'},
      };
      final merged = resolveExtends(themes['b']!, (id) => themes[id]);
      expect(readPath(merged, 'tokens.color.accent'), '#333333');
      expect(readPath(merged, 'tokens.color.bar.bg'), '#222222');
      final warnings = <String>[];
      resolveExtends(themes['c1']!, (id) => themes[id], warnings: warnings);
      expect(warnings.single, contains('cycle'));
      final w2 = <String>[];
      resolveExtends({'id': 'z', 'extends': 'missing'}, (_) => null, warnings: w2);
      expect(w2.single, contains('unknown'));
    });
  });

  group('built-in presets', () {
    late ThemeRepository repo;
    late Directory tmp;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('mgc-themes');
      repo = ThemeRepository(userDir: tmp.path, bundle: DiskBundle(), assetRoot: Directory.current.path);
      await repo.load();
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    for (final id in builtInThemeIds) {
      test('$id parses without warnings and its wallpapers exist', () {
        final t = repo.resolve(id);
        expect(t.warnings, isEmpty, reason: t.warnings.join('\n'));
        for (final path in [t.system.wallpaperLight, t.system.wallpaperDark].whereType<String>()) {
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      });
    }

    test('duplicate pinned apps are removed', () {
      final t = ThemeParser.parse({
        'layout': {
          'dock': {
            'pinned': ['a', 'b', 'a'],
          },
        },
      });
      expect(t.layout.pinned, ['a', 'b']);
    });

    test('GNOME Dark inherits the Adwaita layout', () {
      final t = repo.resolve('gnome-dark');
      expect(t.layout.left, ['activities']);
      expect(t.layout.right, ['appName', 'indicators']);
      expect(t.system.appearance, Appearance.dark);
      expect(t.tokens.accent, const Color(0xFF78AEED));
    });

    test('Classic Mac keeps the native Dock and menu bar', () {
      final t = repo.resolve('classic-mac');
      expect(t.system.hideNativeDock, isFalse);
      expect(t.layout.topBarEnabled, isFalse);
      expect(t.layout.dockMode, DockMode.off);
    });

    test('user theme extending a preset keeps the preset wallpapers', () async {
      final id = await repo.saveUserTheme({
        'name': 'Mine',
        'extends': 'gnome-adwaita',
        'tokens': {
          'color': {'accent': '#ff7800'},
        },
      });
      final t = repo.resolve(id);
      expect(t.tokens.accent, const Color(0xFFFF7800));
      expect(File(t.system.wallpaperLight!).existsSync(), isTrue);
      expect(t.sourceDir, p.join(tmp.path, id));
    });

    test('an extends cycle without wallpapers never crashes', () async {
      await repo.saveUserTheme({'id': 'loop-a', 'name': 'A', 'extends': 'loop-b'});
      await repo.saveUserTheme({'id': 'loop-b', 'name': 'B', 'extends': 'loop-a'});
      await repo.saveUserTheme({'id': 'self', 'name': 'Self', 'extends': 'self'});
      for (final id in ['loop-a', 'loop-b', 'self']) {
        final t = repo.resolve(id);
        expect(t.warnings.any((w) => w.contains('cycle')), isTrue, reason: id);
      }
    });

    test('saving a variant with its own light wallpaper keeps the inherited dark one', () async {
      final light = File(p.join(tmp.path, 'mine.png'))..writeAsBytesSync([0]);
      final id = await repo.saveUserTheme({
        'name': 'Variant',
        'extends': 'gnome-adwaita',
        'system': {
          'wallpaper': {'light': light.path},
        },
      });
      final t = repo.resolve(id);
      expect(t.system.wallpaperLight, light.path);
      expect(File(t.system.wallpaperDark!).existsSync(), isTrue, reason: t.system.wallpaperDark);
    });

    test('a typo while editing keeps the last good version', () async {
      final id = await repo.saveUserTheme({
        'name': 'Editing',
        'tokens': {
          'color': {'accent': '#123456'},
        },
      });
      File(p.join(tmp.path, id, 'theme.json')).writeAsStringSync('{ "name": "Editing", oops');
      await repo.load();
      final t = repo.resolve(id);
      expect(t.degraded, isFalse);
      expect(t.tokens.accent, const Color(0xFF123456));
      expect(t.warnings.first, contains('last good version'));
    });

    test('export → import round-trips a theme with its wallpaper', () async {
      final out = p.join(tmp.path, 'x.mgctheme');
      await repo.exportTheme('gnome-adwaita', {
        'tokens': {
          'color': {'accent': '#00ff00'},
        },
      }, out);
      final id = await repo.importTheme(out);
      final t = repo.resolve(id);
      expect(t.tokens.accent, const Color(0xFF00FF00));
      expect(t.system.wallpaperLight, isNotNull);
      expect(File(t.system.wallpaperLight!).existsSync(), isTrue);
      expect(p.isWithin(tmp.path, t.system.wallpaperLight!), isTrue, reason: 'copied into the user theme');
    });
  });

  group('theme pack safety', () {
    test('zip-slip entries are refused', () {
      final archive = Archive()..addFile(ArchiveFile.string('../../evil.txt', 'x'));
      final dir = Directory.systemTemp.createTempSync('mgc-zip');
      expect(() => extractThemeArchive(ZipEncoder().encode(archive), dir.path), throwsFormatException);
      expect(File(p.join(dir.parent.path, 'evil.txt')).existsSync(), isFalse);
      dir.deleteSync(recursive: true);
    });

    test('absolute entries are refused', () {
      final archive = Archive()..addFile(ArchiveFile.string('/tmp/evil.txt', 'x'));
      final dir = Directory.systemTemp.createTempSync('mgc-zip');
      expect(() => extractThemeArchive(ZipEncoder().encode(archive), dir.path), throwsFormatException);
      dir.deleteSync(recursive: true);
    });

    test('declared sizes are checked before decompressing (zip bomb)', () {
      final big = ArchiveFile('bomb.txt', 5000, List<int>.filled(5000, 0));
      final archive = Archive()..addFile(big);
      final dir = Directory.systemTemp.createTempSync('mgc-zip');
      expect(() => extractThemeArchive(ZipEncoder().encode(archive), dir.path, maxBytes: 1024), throwsFormatException);
      expect(dir.listSync(), isEmpty, reason: 'nothing written');
      dir.deleteSync(recursive: true);
    });

    test('oversized packs are refused', () {
      final archive = Archive()..addFile(ArchiveFile.string('big.txt', 'x' * 2048));
      final dir = Directory.systemTemp.createTempSync('mgc-zip');
      expect(() => extractThemeArchive(ZipEncoder().encode(archive), dir.path, maxBytes: 1024), throwsFormatException);
      dir.deleteSync(recursive: true);
    });
  });

  group('ThemeStore', () {
    test('overrides persist per theme and survive a reload', () async {
      final tmp = Directory.systemTemp.createTempSync('mgc-store');
      ThemeStore make() => ThemeStore(
        repository: ThemeRepository(
          userDir: p.join(tmp.path, 'themes'),
          bundle: DiskBundle(),
          assetRoot: Directory.current.path,
        ),
        settingsPath: p.join(tmp.path, 'settings.json'),
      );
      final a = make();
      await a.load();
      expect(a.onboarded, isFalse, reason: 'first run must not change the system');
      a.setOverride('tokens.color.accent', '#ff0000');
      a.setOnboarded(true);
      a.setActive('win11');
      a.setOverride('layout.dock.iconSize', 48);
      a.saveNow();
      a.dispose();

      final b = make();
      await b.load();
      expect(b.activeId, 'win11');
      expect(b.onboarded, isTrue);
      expect(b.theme.layout.dockIconSize, 48);
      b.setActive('gnome-adwaita');
      expect(b.theme.tokens.accent, const Color(0xFFFF0000), reason: 'overrides are kept per theme');
      final json = jsonDecode(File(p.join(tmp.path, 'settings.json')).readAsStringSync()) as Map;
      expect((json['overrides'] as Map).keys, containsAll(['gnome-adwaita', 'win11']));
      b.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('one setting can be reset on its own; changes are counted per theme', () async {
      final tmp = Directory.systemTemp.createTempSync('mgc-store');
      final store = ThemeStore(
        repository: ThemeRepository(
          userDir: p.join(tmp.path, 'themes'),
          bundle: DiskBundle(),
          assetRoot: Directory.current.path,
        ),
        settingsPath: p.join(tmp.path, 'settings.json'),
      );
      await store.load();
      store.setActive('ubuntu');
      final shipped = store.theme.layout.dockIconSize;
      store.setOverride('layout.dock.iconSize', 80);
      store.setOverride('tokens.color.bar.bg', '#123456');
      expect(store.changeCount(), 2);
      expect(store.isOverridden('layout.dock.iconSize'), isTrue);
      expect(store.isOverridden('layout.dock.position'), isFalse);

      store.clearOverride('layout.dock.iconSize');
      expect(store.theme.layout.dockIconSize, shipped);
      expect(store.changeCount(), 1);
      expect(store.overrides, {
        'tokens': {
          'color': {'bar.bg': '#123456'},
        },
      }, reason: 'empty maps are pruned');

      // Another theme's changes are separate and can be reset from outside it.
      store.setActive('ios');
      expect(store.changeCount(), 0);
      expect(store.changeCount('ubuntu'), 1);
      store.resetOverrides('ubuntu');
      expect(store.changeCount('ubuntu'), 0);
      store.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('interface size scales text, icons and corners together', () async {
      final tmp = Directory.systemTemp.createTempSync('mgc-store');
      final store = ThemeStore(
        repository: ThemeRepository(
          userDir: p.join(tmp.path, 'themes'),
          bundle: DiskBundle(),
          assetRoot: Directory.current.path,
        ),
        settingsPath: p.join(tmp.path, 'settings.json'),
      );
      await store.load();
      store.setActive('gnome-adwaita');
      final before = store.theme;
      store.setOverride('tokens.scale', 1.3);
      final after = store.theme;
      expect(after.tokens.scale, 1.3);
      expect(after.tokens.barFontSize, closeTo(before.tokens.barFontSize * 1.3, 1e-9));
      expect(after.tokens.bodyFontSize, closeTo(before.tokens.bodyFontSize * 1.3, 1e-9));
      expect(after.layout.dockIconSize, closeTo(before.layout.dockIconSize * 1.3, 1e-9));
      expect(after.layout.launcherIconSize, closeTo(before.layout.launcherIconSize * 1.3, 1e-9));
      expect(after.tokens.radius('dock'), closeTo(before.tokens.radius('dock') * 1.3, 1e-9));
      expect(after.tokens.radius('button'), before.tokens.radius('button'), reason: 'pills stay pills');
      // The Customizer edits the theme's own numbers, not the scaled ones.
      expect(store.valueAt('layout.dock.iconSize'), 56);
      // Out-of-range values fall back (and are reported), like other tokens.
      store.setOverride('tokens.scale', 9);
      expect(store.theme.tokens.scale, 1.0);
      expect(store.theme.warnings, contains(contains('tokens.scale')));
      store.dispose();
      tmp.deleteSync(recursive: true);
    });
  });
}
