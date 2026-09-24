// Golden images of every surface per preset (DESIGN.md §11 Phase 6).
// Regenerate: flutter test --update-goldens test/golden_test.dart
// Goldens are macOS-rendered (real system font); run on macOS only.
@TestOn('mac-os')
library;

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mac_gnome_custom/src/core/algorithms.dart';
import 'package:mac_gnome_custom/src/core/shell_controller.dart';
import 'package:mac_gnome_custom/src/core/ui_state.dart';
import 'package:mac_gnome_custom/src/customizer/customizer.dart';
import 'package:mac_gnome_custom/src/customizer/pages_system.dart';
import 'package:mac_gnome_custom/src/surfaces/dock.dart';
import 'package:mac_gnome_custom/src/surfaces/overview.dart';
import 'package:mac_gnome_custom/src/surfaces/popover.dart';
import 'package:mac_gnome_custom/src/surfaces/top_bar.dart';
import 'package:mac_gnome_custom/src/theme/shell_theme.dart';
import 'package:mac_gnome_custom/src/theme/theme_store.dart';
import 'package:mac_gnome_custom/src/widgets/common.dart';
import 'package:shellkit/shellkit.dart';

import 'support/fakes.dart';

Future<void> loadFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final loader = FontLoader(family)..addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    await loader.load();
  }

  const sf = '/System/Library/Fonts/SFNS.ttf';
  for (final family in [
    'Cantarell',
    '.AppleSystemUIFont',
    'Roboto',
    'Segoe UI Variable',
    'Helvetica Neue',
    'Ubuntu',
    'Avenir Next',
    'Futura',
  ]) {
    await load(family, sf);
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/usr/local/flutter';
  await load('MaterialIcons', '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

Widget host(ShellController ctrl, ThemeStore themes, Widget child, {Color background = Colors.transparent}) {
  return Shell(
    controller: ctrl,
    child: ShellThemeScope(
      store: themes,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, fontFamily: '.AppleSystemUIFont'),
        home: ColoredBox(
          color: background,
          child: SurfaceBlur(
            surfaceId: 'test',
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    ),
  );
}

/// A fake desktop behind translucent surfaces.
const desktop = Color(0xFF5E96DE);

void main() {
  setUpAll(() async {
    shellNow = () => DateTime(2026, 9, 24, 9, 41);
    await loadFonts();
  });

  final running = [
    app('com.apple.Safari', active: true),
    app('com.apple.Terminal'),
    app('com.apple.mail'),
    app('com.apple.finder'),
  ];
  final installed = [
    for (final n in [
      'Calculator',
      'Calendar',
      'Contacts',
      'Finder',
      'Mail',
      'Maps',
      'Music',
      'Notes',
      'Photos',
      'Safari',
      'Terminal',
      'TextEdit',
    ])
      InstalledApp(bundleId: 'com.apple.$n', name: n, path: '/System/Applications/$n.app'),
  ];

  Future<(ShellController, ThemeStore)> setup(WidgetTester tester, String themeId) async {
    final result = await tester.runAsync(() async {
      final (ctrl, c, events, themes, tmp) = await harness(running: running);
      themes.setActive(themeId);
      ctrl.apps.setInstalled(installed);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      addTearDown(() {
        ctrl.dispose();
        themes.dispose();
        tmp.deleteSync(recursive: true);
      });
      return (ctrl, themes);
    });
    return result!;
  }

  Future<void> shoot(WidgetTester tester, Size size, Widget widget, String name) async {
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(widget);
    await tester.pump(const Duration(milliseconds: 600)); // > apply debounce
    // Goldens are rendered with this Mac's system font; CI runners have other
    // macOS versions (other font builds), so there the scene is only rendered.
    if (Platform.environment['CI'] == null) {
      await expectLater(find.byType(MaterialApp).first, matchesGoldenFile('goldens/$name.png'));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
  }

  for (final themeId in ['gnome-adwaita', 'win11']) {
    testWidgets('$themeId top bar', (tester) async {
      final (ctrl, themes) = await setup(tester, themeId);
      final spec = SurfaceSpec(viewId: 2, surfaceId: 'topbar:1', kind: 'topbar', screenId: 1);
      await shoot(tester, const Size(1512, 37), host(ctrl, themes, TopBar(spec: spec)), '$themeId-topbar');
    });

    testWidgets('$themeId activities', (tester) async {
      final (ctrl, themes) = await setup(tester, themeId);
      ctrl.ui.openOverview();
      await shoot(
        tester,
        const Size(1512, 945),
        host(ctrl, themes, const OverviewSurface(), background: desktop),
        '$themeId-activities',
      );
    });

    testWidgets('$themeId quick settings', (tester) async {
      final (ctrl, themes) = await setup(tester, themeId);
      ctrl.ui.openPopover(const PopoverState(kind: PopoverKind.quickSettings, screenId: 1, anchor: Rect.zero));
      await shoot(
        tester,
        const Size(360, 150),
        host(ctrl, themes, const PopoverSurface(), background: desktop),
        '$themeId-quicksettings',
      );
    });
  }

  // Presets added later: Ubuntu, iOS, Android, and the two "imagination"
  // themes (Tidepool, Overprint).
  for (final themeId in ['ubuntu', 'ios', 'android', 'opus-tidepool', 'fable-overprint']) {
    testWidgets('$themeId activities', (tester) async {
      final (ctrl, themes) = await setup(tester, themeId);
      ctrl.ui.openOverview();
      await shoot(
        tester,
        const Size(1512, 945),
        host(ctrl, themes, const OverviewSurface(), background: desktop),
        '$themeId-activities',
      );
    });

    testWidgets('$themeId dock', (tester) async {
      final (ctrl, themes) = await setup(tester, themeId);
      final rect = ctrl.dockRestRect(ctrl.surfaces.mainScreen!);
      // Edge-to-edge panel docks are cut to 520 pt so the image stays small.
      final panel = themes.theme.layout.dockStyle == DockStyle.panel;
      final size = panel ? Size(rect.width.clamp(0, 900), rect.height.clamp(0, 520)) : rect.size;
      await shoot(tester, size, host(ctrl, themes, const DockSurface(), background: desktop), '$themeId-dock');
    });

    testWidgets('$themeId top bar', (tester) async {
      final (ctrl, themes) = await setup(tester, themeId);
      final spec = SurfaceSpec(viewId: 2, surfaceId: 'topbar:1', kind: 'topbar', screenId: 1);
      await shoot(tester, const Size(1512, 37), host(ctrl, themes, TopBar(spec: spec)), '$themeId-topbar');
    });
  }

  testWidgets('dock (win11, always visible)', (tester) async {
    final (ctrl, themes) = await setup(tester, 'win11');
    final size = ctrl.dockRestRect(ctrl.surfaces.mainScreen!).size;
    await shoot(tester, size, host(ctrl, themes, const DockSurface(), background: desktop), 'win11-dock');
  });

  testWidgets('the dock\'s Customize button opens the Customizer', (tester) async {
    final (ctrl, themes) = await setup(tester, 'win11');
    await tester.pumpWidget(host(ctrl, themes, const Center(child: DockSurface())));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump();
    expect((ctrl.bridge.host as FakeHost).c.log, contains('openCustomizer'));
    themes.setOverride('layout.dock.showCustomizerButton', false);
    await tester.pump();
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1)); // let the debounced settings save run
  });

  // The dock over the strip macOS reserves (native Dock underneath as a
  // spacer): the wallpaper, cropped to where the strip sits on screen, covers
  // the native Dock; the island floats centred on it.
  testWidgets('win11 dock over a reserved strip paints the wallpaper crop', (tester) async {
    final (ctrl, themes) = await setup(tester, 'win11');
    ctrl.surfaces.setScreens([
      ScreenInfo(
        id: 1,
        frame: RectD(x: 0, y: 0, w: 1512, h: 982),
        visibleFrame: RectD(x: 0, y: 37, w: 1512, h: 982 - 37 - 80),
        menuBarHeight: 37,
        scale: 2,
        isMain: true,
      ),
    ]);
    final strip = ctrl.dockStrip(ctrl.surfaces.mainScreen!)!;
    expect(strip, const Rect.fromLTWH(0, 982 - 80, 1512, 80));
    await tester.binding.setSurfaceSize(strip.size);
    tester.view.physicalSize = strip.size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(host(ctrl, themes, const DockSurface()));
    await tester.pump();

    final crop = tester.widget<Positioned>(
      find.ancestor(of: find.byType(Image), matching: find.byType(Positioned)).first,
    );
    expect([crop.left, crop.top, crop.width, crop.height], [0, -(982 - 80), 1512, 982]);
    // Decoded at screen width, not the file's full resolution.
    final resized = tester.widget<Image>(find.byType(Image).first).image as ResizeImage;
    expect((resized.imageProvider as FileImage).file.path, themes.theme.system.wallpaperLight);
    expect(resized.width, 1512 * 2);
    // The island is centred in the strip.
    final island = tester.getRect(find.byType(DockBar));
    expect(island.center.dx, closeTo(1512 / 2, 0.5));
    expect(island.center.dy, closeTo(40, 0.5));
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
  });

  testWidgets('hovering the dock magnifies the icon under the pointer, and it settles back', (tester) async {
    final (ctrl, themes) = await setup(tester, 'win11');
    await tester.pumpWidget(host(ctrl, themes, const Center(child: DockSurface())));
    await tester.pump();
    final icons = find.byType(FittedBox);
    final rest = tester.getSize(icons.at(1)).width;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(icons.at(1)));
    await tester.pump(); // the ease-in starts on this frame
    await tester.pump(const Duration(milliseconds: 300));
    // Up to 150%; the pointer is on the icon's resting centre, which its
    // growing neighbour pushes slightly aside, as on macOS.
    expect(tester.getSize(icons.at(1)).width, inInclusiveRange(rest * 1.4, rest * 1.5));
    expect(tester.getSize(icons.at(0)).width, inExclusiveRange(rest, rest * 1.5));
    await mouse.moveTo(const Offset(-50, -50));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(icons.at(1)).width, closeTo(rest, 0.5));
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  Future<TestGesture> hoverRunningIcon(WidgetTester tester, ShellController ctrl) async {
    final running = ctrl.dockItems().firstWhere((i) => i.running);
    final icon = find.byType(FittedBox).at(ctrl.dockItems().indexWhere((i) => i.bundleId == running.bundleId));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(icon));
    return mouse;
  }

  testWidgets('hovering a dock icon shows its name and one placeholder per window, and offers previews', (
    tester,
  ) async {
    final (ctrl, themes) = await setup(tester, 'win11');
    await tester.binding.setSurfaceSize(const Size(1200, 420));
    await tester.pumpWidget(host(ctrl, themes, const DockSurface()));
    await tester.pump();
    final running = ctrl.dockItems().firstWhere((i) => i.running);
    final icon = find.byType(FittedBox).at(ctrl.dockItems().indexWhere((i) => i.bundleId == running.bundleId));
    final mouse = await hoverRunningIcon(tester, ctrl);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(ctrl.apps.nameFor(running.bundleId)), findsNothing, reason: 'waits a moment first');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text(ctrl.apps.nameFor(running.bundleId)), findsOneWidget);
    expect(find.text('3 windows'), findsOneWidget);
    // Previews are off: the shell only knows the count, so it shows that
    // many placeholders — no titles, no pictures.
    for (final n in [1, 2, 3]) {
      expect(find.text('Window $n'), findsOneWidget);
    }
    expect(find.text('Inbox'), findsNothing);
    // The card sits above the icon.
    expect(tester.getRect(find.text('3 windows')).bottom, lessThan(tester.getRect(icon).top));

    await mouse.moveTo(tester.getCenter(find.text('Turn on previews…')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Turn on previews…'), findsOneWidget, reason: 'stays while the pointer is on it');
    await tester.tap(find.text('Turn on previews…'));
    await tester.pump();
    await tester.pump();
    // The user's click turns previews on and shows where to allow access.
    expect(ctrl.windowThumbnails, isTrue);
    expect((ctrl.bridge.host as FakeHost).c.log, contains('openCustomizer'));
    expect(ctrl.customizerPage.value, 'windows');
    expect(find.text('3 windows'), findsNothing);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('opt-in previews: hovering shows each window; clicking one switches to exactly it', (tester) async {
    final (ctrl, themes) = await setup(tester, 'win11');
    final diagnostics = ctrl.bridge.diagnostics as FakeDiagnostics;
    expect(ctrl.windowThumbnails, isFalse, reason: 'off by default');
    ctrl.flags.value = {...ctrl.flags.value, 'windowThumbnails': true};
    await tester.binding.setSurfaceSize(const Size(1200, 420));
    await tester.pumpWidget(host(ctrl, themes, const DockSurface()));
    await tester.pump();
    final running = ctrl.dockItems().firstWhere((i) => i.running);
    final mouse = await hoverRunningIcon(tester, ctrl);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    for (final title in ['Inbox', 'Docs — 100 tabs', 'News']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('minimized'), findsOneWidget);
    expect(find.text('3 windows'), findsOneWidget);
    expect(find.text('Turn on previews…'), findsNothing);
    // Accessibility not allowed yet: the card says so instead of a click
    // silently doing nothing.
    expect(find.text('To switch to one window, allow Accessibility.'), findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.text('Docs — 100 tabs')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Docs — 100 tabs'));
    await tester.pump();
    expect((ctrl.bridge.host as FakeHost).c.log, contains('focusWindow ${running.bundleId} 101'));

    // Once allowed, the hint is gone.
    diagnostics.accessibility = true;
    await mouse.moveTo(
      tester.getCenter(find.byType(FittedBox).at(ctrl.dockItems().indexWhere((i) => i.bundleId == running.bundleId))),
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.pump();
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('To switch to one window, allow Accessibility.'), findsNothing);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('previews on but not allowed yet: placeholders and a way to set them up', (tester) async {
    final (ctrl, themes) = await setup(tester, 'win11');
    ctrl.flags.value = {...ctrl.flags.value, 'windowThumbnails': true};
    // macOS hasn't granted anything: the native side lists nothing.
    (ctrl.bridge.apps as FakeApps).windowList = const [];
    await tester.binding.setSurfaceSize(const Size(1200, 420));
    await tester.pumpWidget(host(ctrl, themes, const DockSurface()));
    await tester.pump();
    final mouse = await hoverRunningIcon(tester, ctrl);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.pump();
    expect(find.text('Window 3'), findsOneWidget);
    expect(find.text('Set up…'), findsOneWidget);
    await tester.tap(find.text('Set up…'));
    await tester.pump();
    expect(ctrl.customizerPage.value, 'windows');
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('right-click on a dock icon opens the native menu at the icon', (tester) async {
    final (ctrl, themes) = await setup(tester, 'win11');
    await tester.binding.setSurfaceSize(const Size(600, 200));
    await tester.pumpWidget(host(ctrl, themes, const Center(child: DockSurface())));
    await tester.pump();
    final icon = find.byType(FittedBox).first;
    await tester.tap(icon, buttons: kSecondaryButton);
    await tester.pump();
    final calls = (ctrl.bridge.host as FakeHost).c.log.where((l) => l.startsWith('dockMenu')).toList();
    expect(calls, hasLength(1));
    expect(calls.single, startsWith('dockMenu ${ctrl.dockItems().first.bundleId} bottom'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a mouse wheel glides the launcher instead of jumping', (tester) async {
    final (ctrl, themes) = await setup(tester, 'gnome-dark');
    ctrl.apps.setInstalled([
      for (var i = 0; i < 120; i++) InstalledApp(bundleId: 'b$i', name: 'App $i', path: '/x/$i.app'),
    ]);
    ctrl.ui.openOverview();
    await tester.binding.setSurfaceSize(const Size(1512, 945));
    tester.view.physicalSize = const Size(1512, 945);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(ctrl, themes, const OverviewSurface()));
    await tester.pump(const Duration(milliseconds: 400));
    final grid = find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)).first;
    double offset() => tester.state<ScrollableState>(grid).position.pixels;
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(grid),
        scrollDelta: const Offset(0, 300),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    expect(offset(), lessThan(300), reason: 'no jump');
    await tester.pump(const Duration(milliseconds: 60));
    final mid = offset();
    expect(mid, inExclusiveRange(0, 300), reason: 'gliding');
    await tester.pump(const Duration(milliseconds: 300));
    expect(offset(), 300);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('calendar', (tester) async {
    final (ctrl, themes) = await setup(tester, 'gnome-adwaita');
    ctrl.ui.openPopover(const PopoverState(kind: PopoverKind.calendar, screenId: 1, anchor: Rect.zero));
    await shoot(
      tester,
      const Size(320, 356),
      host(ctrl, themes, const PopoverSurface(), background: desktop),
      'gnome-adwaita-calendar',
    );
  });

  testWidgets('activities search', (tester) async {
    final (ctrl, themes) = await setup(tester, 'gnome-dark');
    ctrl.ui.openOverview();
    ctrl.ui.setQuery('ca');
    await shoot(
      tester,
      const Size(1512, 945),
      host(ctrl, themes, const OverviewSurface(), background: desktop),
      'gnome-dark-search',
    );
  });

  // Regression (first real use): the shell is an accessory app, so opening the
  // launcher changes the lifecycle state; FocusManager then parked focus on the
  // root scope and the search field never received typing.
  testWidgets(
    'launcher search keeps focus across lifecycle changes',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      // FocusManager only follows the lifecycle on desktop; tests default to Android.
      tester.binding.focusManager.listenToApplicationLifecycleChangesIfSupported();
      final (ctrl, themes) = await setup(tester, 'gnome-dark');
      ctrl.ui.openOverview();
      await tester.pumpWidget(host(ctrl, themes, const OverviewSurface()));
      await tester.pump();
      final field = find.byType(EditableText);
      bool focused() => tester.widget<EditableText>(field).focusNode.hasFocus;
      expect(focused(), isTrue);
      for (final state in [AppLifecycleState.inactive, AppLifecycleState.resumed, AppLifecycleState.inactive]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        expect(focused(), isTrue, reason: 'after $state');
      }
      tester.testTextInput.enterText('saf');
      await tester.pump();
      expect(ctrl.ui.query, 'saf');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('customizer privacy page', (tester) async {
    final (ctrl, themes) = await setup(tester, 'gnome-adwaita');
    await shoot(
      tester,
      const Size(1040, 700),
      host(ctrl, themes, const Material(child: PrivacyPage())),
      'customizer-privacy',
    );
  });

  testWidgets('customizer themes page', (tester) async {
    final (ctrl, themes) = await setup(tester, 'gnome-adwaita');
    await shoot(tester, const Size(1040, 700), host(ctrl, themes, const CustomizerApp()), 'customizer-themes');
  });

  testWidgets('customizer onboarding', (tester) async {
    final (ctrl, themes) = await setup(tester, 'gnome-adwaita');
    themes.setOnboarded(false);
    await shoot(tester, const Size(1040, 700), host(ctrl, themes, const CustomizerApp()), 'customizer-onboarding');
  });

  testWidgets('customizer style page', (tester) async {
    final (ctrl, themes) = await setup(tester, 'gnome-adwaita');
    ctrl.customizerPage.value = 'style';
    await shoot(tester, const Size(1040, 700), host(ctrl, themes, const CustomizerApp()), 'customizer-style');
  });

  testWidgets('customizer dock page at the smallest window size', (tester) async {
    final (ctrl, themes) = await setup(tester, 'ubuntu');
    ctrl.customizerPage.value = 'dock';
    await shoot(tester, const Size(820, 560), host(ctrl, themes, const CustomizerApp()), 'customizer-dock-narrow');
  });

  testWidgets('other surfaces can open the Customizer at a page', (tester) async {
    final (ctrl, themes) = await setup(tester, 'gnome-adwaita');
    await tester.binding.setSurfaceSize(const Size(1040, 700));
    await tester.pumpWidget(host(ctrl, themes, const CustomizerApp()));
    await tester.pump();
    expect(find.textContaining('Pick a look.'), findsOneWidget);
    await ctrl.openCustomizer(page: 'windows');
    await tester.pump();
    expect(find.text('Show window previews in the dock'), findsOneWidget);
    expect(ctrl.customizerPage.value, isNull, reason: 'consumed');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a changed setting shows a reset button that puts the theme value back', (tester) async {
    final (ctrl, themes) = await setup(tester, 'gnome-adwaita');
    ctrl.customizerPage.value = 'dock';
    await tester.binding.setSurfaceSize(const Size(1040, 1400));
    await tester.pumpWidget(host(ctrl, themes, const CustomizerApp()));
    await tester.pump();
    expect(find.byTooltip('Reset to the theme\'s value'), findsNothing);
    expect(find.textContaining('every theme keeps its own settings'), findsOneWidget);
    themes.setOverride('layout.dock.showRunningDots', false);
    await tester.pump();
    expect(find.textContaining('1 change'), findsWidgets);
    await tester.tap(find.byTooltip('Reset to the theme\'s value'));
    await tester.pump();
    expect(themes.theme.layout.showRunningDots, isTrue);
    expect(themes.changeCount(), 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1)); // let the debounced settings save run
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('the top bar text follows the interface size but always fits the bar', (tester) async {
    final (ctrl, themes) = await setup(tester, 'gnome-adwaita');
    final spec = SurfaceSpec(viewId: 2, surfaceId: 'topbar:1', kind: 'topbar', screenId: 1);
    Future<double> clockSize(double barHeight) async {
      await tester.binding.setSurfaceSize(Size(1280, barHeight));
      await tester.pumpWidget(host(ctrl, themes, TopBar(spec: spec)));
      await tester.pump();
      final style = DefaultTextStyle.of(
        tester.element(find.text(formatClock(shellNow(), themes.theme.layout.clockFormat))),
      );
      return style.style.fontSize!;
    }

    expect(await clockSize(37), 14);
    themes.setOverride('tokens.scale', 1.3);
    expect(await clockSize(37), closeTo(14 * 1.3, 0.01));
    // A 24 pt menu bar (Macs without a notch) caps it.
    expect(await clockSize(24), lessThan(14));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.binding.setSurfaceSize(null);
  });
}
