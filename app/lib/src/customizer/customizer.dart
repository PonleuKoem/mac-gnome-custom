import 'package:flutter/material.dart';

import '../core/shell_controller.dart';
import '../widgets/common.dart';
import 'pages_system.dart';
import 'pages_theme.dart';
import 'theme_preview.dart';

/// The Customizer window (F7, F8, F9): the only regular window of the app.
///
/// Organised like System Settings: the theme gallery first, then everything
/// that belongs to the active theme (each theme keeps its own style, top bar,
/// dock, launcher, desktop and shortcuts), then app-wide settings.
class CustomizerApp extends StatefulWidget {
  const CustomizerApp({super.key});

  @override
  State<CustomizerApp> createState() => _CustomizerAppState();
}

class _CustomizerAppState extends State<CustomizerApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final ShellController _ctrl = Shell.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl.customizerVisible.removeListener(_visibility);
    _ctrl.customizerVisible.addListener(_visibility);
  }

  @override
  void dispose() {
    _ctrl.customizerVisible.removeListener(_visibility);
    super.dispose();
  }

  /// Closing the window only hides it; dismiss open dialogs (e.g. the
  /// shortcut recorder) so their cleanup runs.
  void _visibility() {
    if (!_ctrl.customizerVisible.value) _navigator.currentState?.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    final theme = ShellThemeScope.of(context);
    return ValueListenableBuilder(
      valueListenable: ctrl.system,
      builder: (context, status, _) {
        final dark = status?.darkMode ?? false;
        return MaterialApp(
          navigatorKey: _navigator,
          debugShowCheckedModeBanner: false,
          title: 'mac-gnome-custom',
          theme: ThemeData(
            colorSchemeSeed: theme.tokens.accent,
            brightness: dark ? Brightness.dark : Brightness.light,
            useMaterial3: true,
            visualDensity: VisualDensity.compact,
          ),
          home: const _CustomizerHome(),
        );
      },
    );
  }
}

/// A Customizer page: id (for [ShellController.openCustomizer]), sidebar
/// entry, and whether it edits the active theme.
typedef _PageEntry = ({String id, IconData icon, String label, bool themed, Widget page});

const _themePages = <_PageEntry>[
  (id: 'style', icon: Icons.format_paint_outlined, label: 'Style', themed: true, page: StylePage()),
  (id: 'topbar', icon: Icons.web_asset_rounded, label: 'Top bar', themed: true, page: TopBarPage()),
  (id: 'dock', icon: Icons.space_bar_rounded, label: 'Dock', themed: true, page: DockPage()),
  (id: 'launcher', icon: Icons.apps_rounded, label: 'Launcher', themed: true, page: LauncherPage()),
  (id: 'desktop', icon: Icons.wallpaper_rounded, label: 'Desktop', themed: true, page: DesktopPage()),
  (id: 'shortcuts', icon: Icons.keyboard_outlined, label: 'Shortcuts', themed: true, page: ShortcutsPage()),
];

const _appPages = <_PageEntry>[
  (id: 'windows', icon: Icons.verified_user_outlined, label: 'Windows & privacy', themed: false, page: PrivacyPage()),
  (id: 'general', icon: Icons.settings_outlined, label: 'General', themed: false, page: GeneralPage()),
  (id: 'safety', icon: Icons.restore_outlined, label: 'Safety', themed: false, page: SafetyPage()),
  (id: 'diagnostics', icon: Icons.monitor_heart_outlined, label: 'Diagnostics', themed: false, page: DiagnosticsPage()),
];

const _themesPage = (id: 'themes', icon: Icons.palette_outlined, label: 'Themes', themed: false, page: ThemesPage());

final _allPages = <_PageEntry>[_themesPage, ..._themePages, ..._appPages];

/// Lets pages switch the Customizer to another page.
class CustomizerNav extends InheritedWidget {
  const CustomizerNav({super.key, required this.go, required super.child});

  final void Function(String pageId) go;

  static void Function(String) of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CustomizerNav>()?.go ?? (_) {};

  @override
  bool updateShouldNotify(CustomizerNav old) => false;
}

class _CustomizerHome extends StatefulWidget {
  const _CustomizerHome();

  @override
  State<_CustomizerHome> createState() => _CustomizerHomeState();
}

class _CustomizerHomeState extends State<_CustomizerHome> {
  String _page = 'themes';
  late final ShellController _ctrl = Shell.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ctrl.customizerPage.addListener(_requested);
      _requested();
    });
  }

  @override
  void dispose() {
    _ctrl.customizerPage.removeListener(_requested);
    super.dispose();
  }

  /// Another surface asked for a page (e.g. the dock's hover card → windows).
  void _requested() {
    final id = _ctrl.customizerPage.value;
    if (id == null) return;
    _ctrl.customizerPage.value = null;
    _go(id);
  }

  void _go(String id) {
    if (_allPages.any((p) => p.id == id) && id != _page) setState(() => _page = id);
  }

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    if (!store.onboarded) return const OnboardingPage();
    final entry = _allPages.firstWhere((p) => p.id == _page, orElse: () => _themesPage);
    return CustomizerNav(
      go: _go,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(selected: entry.id, compact: compact, onSelect: _go),
                VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
                Expanded(
                  child: KeyedSubtree(key: ValueKey(entry.id), child: entry.page),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.compact, required this.onSelect});

  final String selected;
  final bool compact;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final store = ShellThemeScope.storeOf(context);
    final changes = store.changeCount();
    Widget header(String label) => compact
        ? const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(indent: 16, endIndent: 16))
        : Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 6),
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.6),
            ),
          );
    Widget item(_PageEntry p) => _SidebarItem(
      icon: p.icon,
      label: p.label,
      selected: p.id == selected,
      compact: compact,
      onTap: () => onSelect(p.id),
    );
    return Container(
      width: compact ? 68 : 232,
      color: scheme.surfaceContainerLowest,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // The active theme at a glance; click to pick another.
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelect('themes'),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ThemePreview(theme: store.theme, showWindow: false),
                      const SizedBox(height: 8),
                      Text(store.theme.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        changes == 0 ? 'Active theme' : 'Active theme · $changes change${changes == 1 ? '' : 's'}',
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          item(_themesPage),
          header('${store.theme.name} settings'),
          for (final p in _themePages) item(p),
          header('App'),
          for (final p in _appPages) item(p),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    final tile = Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10, vertical: 7),
          child: Row(
            mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: fg),
              if (!compact) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: compact ? Tooltip(message: label, child: tile) : tile,
    );
  }
}

/// Page scaffold shared by every Customizer page: a fixed header (title,
/// help, actions) over scrolling content. [themed] pages edit the active
/// theme: their header says so and keeps a live preview in view.
class CustomizerPage extends StatelessWidget {
  const CustomizerPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.themed = false,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool themed;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final pad = wide ? 32.0 : 20.0;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: text.headlineSmall)),
                ...actions,
              ],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(subtitle!, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            if (themed) const Padding(padding: EdgeInsets.only(top: 12), child: ThemeBanner()),
          ],
        );
        // Live preview beside the heading while there's room; on short or
        // narrow windows the content gets the space instead.
        final showPreview = themed && wide && constraints.maxHeight >= 560;
        final previewWidth = (constraints.maxWidth * 0.3).clamp(200.0, 300.0);
        final store = ShellThemeScope.storeOf(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 24, pad, 16),
              child: showPreview
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: previewWidth,
                          child: ThemePreview(theme: store.theme),
                        ),
                      ],
                    )
                  : heading,
            ),
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            Expanded(
              child: SmoothScroll(
                builder: (context, scroll) => ListView(
                  controller: scroll,
                  padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "Only affects `theme`" + how many changes, reset and save.
class ThemeBanner extends StatelessWidget {
  const ThemeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ShellThemeScope.storeOf(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final n = store.changeCount();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Icon(Icons.palette_outlined, size: 16, color: scheme.onSecondaryContainer),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Only affects '),
                TextSpan(
                  text: store.theme.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: n == 0 ? ' — every theme keeps its own settings.' : ' · $n change${n == 1 ? '' : 's'}'),
              ],
            ),
            style: text.bodySmall?.copyWith(color: scheme.onSecondaryContainer),
          ),
          if (n > 0) ...[
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () async {
                if (await confirm(
                  context,
                  'Reset ${store.theme.name}?',
                  'Your $n change${n == 1 ? '' : 's'} to this theme will be undone.',
                  action: 'Reset',
                )) {
                  store.resetOverrides();
                }
              },
              child: const Text('Reset all'),
            ),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => saveThemeAsNew(context),
              child: const Text('Save as new theme'),
            ),
          ],
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

Future<bool> confirm(BuildContext context, String title, String message, {String action = 'Continue'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
