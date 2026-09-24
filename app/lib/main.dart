import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shellkit/shellkit.dart';

import 'src/core/bridge.dart';
import 'src/core/shell_controller.dart';
import 'src/customizer/customizer.dart';
import 'src/surfaces/dock.dart';
import 'src/surfaces/overview.dart';
import 'src/surfaces/popover.dart';
import 'src/surfaces/top_bar.dart';
import 'src/theme/theme_repository.dart';
import 'src/theme/theme_store.dart';
import 'src/widgets/common.dart';

/// One Dart isolate renders every shell surface: each native panel hosts a
/// FlutterView, and [ShellRoot] maps view ids to surfaces (ADR-0003).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bridge = ShellBridge();
  final support = await bridge.host.supportDirectory();
  final themes = ThemeStore(
    repository: ThemeRepository(userDir: p.join(support, 'themes')),
    settingsPath: ThemeStore.defaultSettingsPath(support),
  );
  await themes.load();
  final controller = ShellController(bridge: bridge, themes: themes);
  runWidget(ShellRoot(controller: controller, themes: themes));
  await controller.start();

  // Multi-view self-check (MGC_SPIKE_S1=1, see CONTRIBUTING.md): report the
  // view ↔ surface mapping, then quit.
  if (Platform.environment['MGC_SPIKE_S1'] != null) {
    await Future<void>.delayed(const Duration(seconds: 3));
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final specs = controller.surfaces.all.toList();
    final mapped = specs.where((s) => views.any((v) => v.viewId == s.viewId)).length;
    stdout.writeln('S1 RESULT: ${views.length} views, ${specs.length} surfaces, $mapped mapped');
    await bridge.host.quit();
  }
}

class ShellRoot extends StatefulWidget {
  const ShellRoot({super.key, required this.controller, required this.themes});

  final ShellController controller;
  final ThemeStore themes;

  @override
  State<ShellRoot> createState() => _ShellRootState();
}

class _ShellRootState extends State<ShellRoot> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.surfaces.addListener(_rebuild);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.surfaces.removeListener(_rebuild);
    super.dispose();
  }

  Map<int, SurfaceSpec> _views = const {};

  /// Rebuild the view tree only when panels come or go, not on every screen
  /// or placement update (each rebuild relayouts every panel).
  void _rebuild() {
    final next = widget.controller.surfaces.byView;
    if (identical(next, _views)) return;
    _views = next;
    setState(() {});
  }

  /// Views are added/removed as panels come and go (e.g. display changes).
  @override
  void didChangeMetrics() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final specs = widget.controller.surfaces.byView;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return Shell(
      controller: widget.controller,
      child: ShellThemeScope(
        store: widget.themes,
        child: ViewCollection(
          views: [
            for (final view in views)
              if (specs[view.viewId] case final spec?)
                View(
                  key: ValueKey(view.viewId),
                  view: view,
                  child: SurfaceHost(spec: spec),
                ),
          ],
        ),
      ),
    );
  }
}

/// Picks the widget tree for a surface kind.
class SurfaceHost extends StatelessWidget {
  const SurfaceHost({super.key, required this.spec});

  final SurfaceSpec spec;

  @override
  Widget build(BuildContext context) {
    if (spec.kind == 'customizer') return const CustomizerApp();
    final t = ShellThemeScope.of(context).tokens;
    final Widget child = switch (spec.kind) {
      'topbar' => TopBar(spec: spec),
      'dock' => const DockSurface(),
      'overview' => const OverviewSurface(),
      'popover' => const PopoverSurface(),
      _ => const SizedBox.shrink(),
    };
    // A minimal MaterialApp per panel supplies Overlay, text editing and
    // localizations; the background stays transparent.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: const Color(0x00000000),
      theme: ThemeData(
        brightness: isDark(t.surface) ? Brightness.dark : Brightness.light,
        colorSchemeSeed: t.accent,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0x00000000),
        canvasColor: const Color(0x00000000),
        splashFactory: NoSplash.splashFactory,
      ),
      home: SurfaceBlur(
        surfaceId: spec.surfaceId,
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}
