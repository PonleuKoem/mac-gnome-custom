import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

enum PopoverKind { calendar, quickSettings }

@immutable
class PopoverState {
  const PopoverState({required this.kind, required this.screenId, required this.anchor, this.payload, this.size});

  final PopoverKind kind;
  final int screenId;

  /// Screen-relative rect of the control that opened it.
  final Rect anchor;

  /// e.g. the bundle id for a dock menu.
  final String? payload;

  /// Preferred size reported by the content (null until measured).
  final Size? size;

  PopoverState withSize(Size s) =>
      PopoverState(kind: kind, screenId: screenId, anchor: anchor, payload: payload, size: s);
}

/// Transient UI state shared by all surfaces.
class ShellUi extends ChangeNotifier {
  bool _overviewOpen = false;
  String _query = '';
  PopoverState? _popover;

  /// The Activities launcher (search + app grid + dash).
  bool get overviewOpen => _overviewOpen;
  String get query => _query;
  PopoverState? get popover => _popover;

  void openOverview() {
    if (_overviewOpen) return;
    _overviewOpen = true;
    _popover = null;
    notifyListeners();
  }

  void closeOverview() {
    if (!_overviewOpen) return;
    _overviewOpen = false;
    _query = '';
    notifyListeners();
  }

  void setQuery(String q) {
    if (q == _query) return;
    _query = q;
    notifyListeners();
  }

  void openPopover(PopoverState p) {
    if (_popover?.kind == p.kind && _popover?.payload == p.payload && _popover?.screenId == p.screenId) {
      _popover = null; // toggling the same control closes it
    } else {
      _popover = p;
    }
    notifyListeners();
  }

  void closePopover() {
    if (_popover == null) return;
    _popover = null;
    notifyListeners();
  }

  void setPopoverSize(Size size) {
    final p = _popover;
    if (p == null || p.size == size) return;
    _popover = p.withSize(size);
    notifyListeners();
  }
}
