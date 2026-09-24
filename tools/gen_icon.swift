#!/usr/bin/env swift
// Generates the app icon (original artwork, no dependencies beyond macOS).
//
//     swift tools/gen_icon.swift
//
// Draws a 1024×1024 master on Apple's macOS icon grid (824 pt body, 100 pt
// margin) and writes every size into app/macos/Runner/Assets.xcassets/AppIcon.appiconset/.
// Motif: a tiny desktop — GNOME-blue backdrop, dark top bar with an Activities
// pill, a launcher grid of app tiles, and a dock.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("app/macos/Runner/Assets.xcassets/AppIcon.appiconset")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
          blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func draw(_ ctx: CGContext) {
  // Core Graphics is y-up; flip so the numbers below read top-down like a design file.
  ctx.translateBy(x: 0, y: 1024)
  ctx.scaleBy(x: 1, y: -1)
  let body = CGRect(x: 100, y: 100, width: 824, height: 824)
  let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

  // Drop shadow, as on Apple's template.
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: rgb(0x000000, 0.35))
  ctx.addPath(squircle)
  ctx.setFillColor(rgb(0x1c71d8))
  ctx.fillPath()
  ctx.restoreGState()

  ctx.saveGState()
  ctx.addPath(squircle)
  ctx.clip()

  // Backdrop: GNOME blue, lighter at the top.
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let bg = CGGradient(colorsSpace: space, colors: [rgb(0x62a0ea), rgb(0x1c71d8), rgb(0x1a5fb4)] as CFArray,
                      locations: [0, 0.55, 1])!
  ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

  // Top bar.
  ctx.setFillColor(rgb(0x1e1e1e, 0.92))
  ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 112))
  // Activities pill + status dots.
  ctx.setFillColor(rgb(0xffffff))
  ctx.addPath(CGPath(roundedRect: CGRect(x: 196, y: 140, width: 118, height: 34),
                     cornerWidth: 17, cornerHeight: 17, transform: nil))
  ctx.fillPath()
  for x in [760.0, 810.0] {
    ctx.fillEllipse(in: CGRect(x: x - 15, y: 142, width: 30, height: 30))
  }

  // Launcher grid: 3×2 app tiles.
  let tiles: [UInt32] = [0xf6d32d, 0xe66100, 0x2ec27e, 0xc061cb, 0xffffff, 0xed333b]
  let size = 150.0, gap = 44.0
  let gridW = size * 3 + gap * 2
  let x0 = 512 - gridW / 2, y0 = 302.0
  for (i, c) in tiles.enumerated() {
    let r = CGRect(x: x0 + Double(i % 3) * (size + gap), y: y0 + Double(i / 3) * (size + gap),
                   width: size, height: size)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 14, color: rgb(0x000000, 0.25))
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 38, cornerHeight: 38, transform: nil))
    ctx.setFillColor(rgb(c))
    ctx.fillPath()
    ctx.restoreGState()
  }

  // Dock: translucent dark pill with three app dots and a running indicator.
  let dock = CGRect(x: 262, y: 752, width: 500, height: 104)
  ctx.addPath(CGPath(roundedRect: dock, cornerWidth: 34, cornerHeight: 34, transform: nil))
  ctx.setFillColor(rgb(0x1e1e1e, 0.55))
  ctx.fillPath()
  let dockDots: [UInt32] = [0x62a0ea, 0x57e389, 0xf8e45c]
  for (i, c) in dockDots.enumerated() {
    let cx = 512 + Double(i - 1) * 132
    ctx.setFillColor(rgb(c))
    ctx.addPath(CGPath(roundedRect: CGRect(x: cx - 34, y: 770, width: 68, height: 68),
                       cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.fillPath()
  }
  ctx.setFillColor(rgb(0xffffff))
  ctx.fillEllipse(in: CGRect(x: 512 - 132 - 6, y: 842, width: 12, height: 12))

  ctx.restoreGState()

  // Hairline edge so the icon holds up on light backgrounds.
  ctx.addPath(squircle)
  ctx.setStrokeColor(rgb(0x000000, 0.12))
  ctx.setLineWidth(2)
  ctx.strokePath()
}

func render(_ px: Int) -> Data {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  let g = NSGraphicsContext(bitmapImageRep: rep)!
  let ctx = g.cgContext
  ctx.interpolationQuality = .high
  ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
  draw(ctx)
  g.flushGraphics()
  return rep.representation(using: .png, properties: [:])!
}

for px in [16, 32, 64, 128, 256, 512, 1024] {
  let url = out.appendingPathComponent("app_icon_\(px).png")
  try! render(px).write(to: url)
  print("wrote \(url.lastPathComponent)")
}
