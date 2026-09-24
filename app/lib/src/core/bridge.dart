import 'package:shellkit/shellkit.dart';

/// All native APIs in one place. Tests pass subclasses of the generated API
/// classes (they are plain Dart classes) to fake the native side.
///
/// Interface-only scope (ADR-0012): no API here reads other apps' windows,
/// screen contents or keystrokes, or changes the system beyond appearance.
class ShellBridge {
  ShellBridge({
    ShellHostApi? host,
    AppApi? apps,
    SystemApi? system,
    HotkeyApi? hotkeys,
    SafetyApi? safety,
    DiagnosticsApi? diagnostics,
    Stream<ShellEvent> Function()? eventStream,
  }) : host = host ?? ShellHostApi(),
       apps = apps ?? AppApi(),
       system = system ?? SystemApi(),
       hotkeys = hotkeys ?? HotkeyApi(),
       safety = safety ?? SafetyApi(),
       diagnostics = diagnostics ?? DiagnosticsApi(),
       _eventStream = eventStream ?? events;

  final ShellHostApi host;
  final AppApi apps;
  final SystemApi system;
  final HotkeyApi hotkeys;
  final SafetyApi safety;
  final DiagnosticsApi diagnostics;
  final Stream<ShellEvent> Function() _eventStream;

  Stream<ShellEvent> get eventStream => _eventStream();
}
