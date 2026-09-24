import AppKit

/// Coordinate spaces:
/// - Cocoa (NSWindow/NSScreen): origin bottom-left of the primary screen, y up.
/// - Global top-left (CoreGraphics, AX, and everything we send to Dart): origin
///   top-left of the primary screen, y down.
public enum Geometry {
  /// Height of the primary screen (the one with the menu bar at launch), which
  /// anchors both coordinate systems.
  public static var primaryHeight: CGFloat {
    NSScreen.screens.first?.frame.height ?? 0
  }

  public static func topLeft(fromCocoa r: CGRect, primaryHeight h: CGFloat = primaryHeight) -> CGRect {
    CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
  }

  public static func cocoa(fromTopLeft r: CGRect, primaryHeight h: CGFloat = primaryHeight) -> CGRect {
    CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
  }

  /// Converts a screen-relative top-left rect into a Cocoa window frame.
  public static func cocoaFrame(screenRelative r: CGRect, screenCocoaFrame s: CGRect) -> CGRect {
    CGRect(x: s.minX + r.minX, y: s.maxY - r.minY - r.height, width: r.width, height: r.height)
  }

  /// Index of the screen whose (top-left) frame contains the centre of `rect`,
  /// falling back to the screen with the largest overlap, then the first one.
  public static func screenIndex(for rect: CGRect, screens: [CGRect]) -> Int? {
    guard !screens.isEmpty else { return nil }
    let center = CGPoint(x: rect.midX, y: rect.midY)
    if let i = screens.firstIndex(where: { $0.contains(center) }) { return i }
    var best: (Int, CGFloat) = (0, -1)
    for (i, s) in screens.enumerated() {
      let inter = s.intersection(rect)
      let area = inter.isNull ? 0 : inter.width * inter.height
      if area > best.1 { best = (i, area) }
    }
    return best.0
  }
}

public extension NSScreen {
  /// Stable-for-the-session display identifier.
  var displayID: CGDirectDisplayID {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
  }

  /// Height of the native menu bar strip on this screen. When the menu bar is
  /// visible, `frame.maxY - visibleFrame.maxY` is exact (including the notch).
  var menuBarHeight: CGFloat {
    let strip = frame.maxY - visibleFrame.maxY
    if strip > 0 { return strip }
    return max(24, safeAreaInsets.top)
  }

  var topLeftFrame: CGRect { Geometry.topLeft(fromCocoa: frame) }
  var topLeftVisibleFrame: CGRect { Geometry.topLeft(fromCocoa: visibleFrame) }
}
