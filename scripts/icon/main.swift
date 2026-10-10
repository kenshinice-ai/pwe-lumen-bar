#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// One drawing routine, two outputs: a true vector PDF (used for the menu bar,
// where it must stay crisp at any scale factor) and the rasterised .iconset the
// .icns format requires. Nothing is hand-traced, so the icon cannot drift
// between sizes.

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1
               ? CommandLine.arguments[1]
               : FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let build = root.appendingPathComponent("build")
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)

// MARK: - Brand colours
//
// PWE, brand standard §5. Amber is legal here because the ground
// is navy; nothing in this file ever puts it on paper.

let navy = CGColor(red: 14 / 255, green: 23 / 255, blue: 41 / 255, alpha: 1)
let amber = CGColor(red: 245 / 255, green: 179 / 255, blue: 53 / 255, alpha: 1)

// MARK: - Geometry

/// A screen: rounded rectangle plus a short stand.
func screenPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func standPath(under rect: CGRect, scale: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let neckW = rect.width * 0.15, neckH = rect.height * 0.14
    path.addRect(CGRect(x: rect.midX - neckW / 2, y: rect.minY - neckH,
                        width: neckW, height: neckH))
    let footW = rect.width * 0.44, footH = rect.height * 0.075
    path.addPath(CGPath(roundedRect: CGRect(x: rect.midX - footW / 2,
                                            y: rect.minY - neckH - footH,
                                            width: footW, height: footH),
                        cornerWidth: footH / 2, cornerHeight: footH / 2, transform: nil))
    return path
}

/// A four-pointed sparkle with concave sides — the same shape the resolution
/// menu uses to mark a HiDPI mode, so the icon and the UI say "sharp" the same way.
func sparklePath(center: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    // Control points sit close to the centre, which is what pulls the sides in.
    let waist = radius * 0.16
    path.move(to: CGPoint(x: center.x, y: center.y + radius))
    path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y),
                      control: CGPoint(x: center.x + waist, y: center.y + waist))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius),
                      control: CGPoint(x: center.x + waist, y: center.y - waist))
    path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y),
                      control: CGPoint(x: center.x - waist, y: center.y - waist))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius),
                      control: CGPoint(x: center.x - waist, y: center.y + waist))
    path.closeSubpath()
    return path
}

/// Two screens: one angled away behind, one square-on in front.
///
/// The back screen is what says "more than one display" at a glance; the front
/// one carries the half-lit interior that says "brightness". Both ideas have to
/// survive being drawn at 16 points, so the overlap is shallow and the back
/// screen is outline-only.
func drawPair(in ctx: CGContext, side: CGFloat,
              front: CGColor, back: CGColor, fill: CGColor,
              lineScale: CGFloat, sparkling: Bool) {
    let unit = side / 100

    // Front screen first, as geometry only — the back screen is drawn through
    // a clip that excludes it, which is what separates the two shapes.
    let frontRect = CGRect(x: 38 * unit, y: 28 * unit, width: 50 * unit, height: 34 * unit)
    let radius = 6.5 * unit
    let gap = 3.4 * unit * lineScale

    // Back screen: square-on, set up and to the left. Depth comes from the
    // offset and the lighter stroke, not from a tilt.
    let backRect = CGRect(x: 15 * unit, y: 47 * unit, width: 43 * unit, height: 29 * unit)
    ctx.saveGState()
    // Everything except the front screen's silhouette. An even-odd clip is the
    // only way to punch this hole that survives into a PDF — a `.clear` blend
    // is unsupported there and silently paints a solid rectangle instead.
    ctx.addRect(CGRect(x: -side, y: -side, width: side * 3, height: side * 3))
    ctx.addPath(screenPath(frontRect.insetBy(dx: -gap, dy: -gap), radius: radius + gap))
    ctx.clip(using: .evenOdd)
    ctx.setStrokeColor(back)
    ctx.setLineWidth(4.2 * unit * lineScale)
    ctx.setLineJoin(.round)
    ctx.addPath(screenPath(backRect, radius: 5.5 * unit))
    ctx.strokePath()
    ctx.restoreGState()

    ctx.setFillColor(front)
    ctx.addPath(standPath(under: frontRect, scale: unit))
    ctx.fillPath()

    // Interior. On the plate it is a lit screen with sparkles punched out of
    // it — the same mark the resolution menu uses for HiDPI. The 18pt menu bar
    // template gets the half-lit treatment instead: a 2pt hole is not a
    // sparkle, it is a smudge.
    let inner = frontRect.insetBy(dx: 5.8 * unit, dy: 5.8 * unit)
    ctx.setFillColor(fill)
    // At 18pt the front screen's interior is about 7×4pt. Anything filled in
    // there merges with the 1pt stroke around it, so the template is left as
    // pure outline and only the plate icon gets an interior.
    if fill.alpha == 0 {
        // outline only
    } else if sparkling {
        // Holes come from an even-odd fill rather than a clear blend: blend
        // modes do not survive into a PDF.
        let interior = CGMutablePath()
        interior.addPath(screenPath(inner, radius: radius * 0.5))
        interior.addPath(sparklePath(center: CGPoint(x: inner.midX + inner.width * 0.10,
                                                     y: inner.midY - inner.height * 0.06),
                                     radius: inner.height * 0.52))
        // The companion sparkle is detail, not structure: below 64pt it stops
        // being a shape and turns into a speck.
        if side >= 64 {
            interior.addPath(sparklePath(center: CGPoint(x: inner.minX + inner.width * 0.17,
                                                         y: inner.midY + inner.height * 0.27),
                                         radius: inner.height * 0.20))
        }
        ctx.addPath(interior)
        ctx.fillPath(using: .evenOdd)
    } else {
        ctx.saveGState()
        ctx.addPath(screenPath(inner, radius: radius * 0.5))
        ctx.clip()
        ctx.fill(CGRect(x: inner.midX, y: inner.minY,
                        width: inner.width / 2, height: inner.height))
        ctx.restoreGState()
    }

    ctx.setStrokeColor(front)
    ctx.setLineWidth(4.8 * unit * lineScale)
    ctx.addPath(screenPath(frontRect, radius: radius))
    ctx.strokePath()
}

/// App icon: the brand tile.
///
/// Navy squircle, amber wing at 60 % width — the same construction as
/// `01 BRAND ASSETS/logo/app-icon-512.svg`, and the same as PWE Loan Bar and
/// PWE MAC MONITOR, because that tile *is* the house identity.
///
/// The sparkles are this product's one addition to it: three identical tiles in
/// /Applications is a real defect, and the sparkle is the only differentiator
/// available that does not touch the mark. Standard §7 forbids modifying the
/// wing — recolouring, stretching, adding effects to it. A separate element on
/// the ground, in a brand colour, clear of the mark, is not a modification of
/// the mark. It is also the motif the resolution menu already uses for HiDPI,
/// so the icon and the interface say "sharp" with the same shape.
func drawAppIcon(in ctx: CGContext, side: CGFloat) {
    let pad = side * 0.085
    let plate = CGRect(x: pad, y: pad, width: side - pad * 2, height: side - pad * 2)
    let plateRadius = plate.width * 0.2237

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: plate, cornerWidth: plateRadius,
                       cornerHeight: plateRadius, transform: nil))
    ctx.clip()
    ctx.setFillColor(navy)
    ctx.fill(plate)

    // The mark's own golden box, centred, at 60 % of the plate's width.
    let markWidth = plate.width * 0.60
    let mark = CGRect(x: plate.midX - markWidth / 2,
                      y: plate.midY - markWidth / BrandMark.aspect / 2,
                      width: markWidth, height: markWidth / BrandMark.aspect)
    ctx.setFillColor(amber)
    ctx.addPath(BrandMark.path(in: mark).cgPath)
    ctx.fillPath()

    // Sparkles off the leading feather's tip, which the generator puts at the
    // top-right corner of the mark's box. Both sit outside the wing entirely.
    let sparkles = CGMutablePath()
    sparkles.addPath(sparklePath(center: CGPoint(x: mark.maxX + plate.width * 0.035,
                                                 y: mark.maxY + plate.width * 0.028),
                                 radius: plate.width * 0.055))
    // Detail, not structure: below 64 pt the second one is a speck, not a shape.
    if side >= 64 {
        sparkles.addPath(sparklePath(center: CGPoint(x: mark.maxX + plate.width * 0.115,
                                                     y: mark.maxY + plate.width * 0.098),
                                     radius: plate.width * 0.026))
    }
    ctx.addPath(sparkles)
    ctx.fillPath()
    ctx.restoreGState()
}

/// Menu bar version: monochrome template art, no plate.
func drawMenuBarIcon(in ctx: CGContext, side: CGFloat) {
    ctx.saveGState()
    // The glyph is drawn in a 100-unit space that assumes a plate around it;
    // without one it can grow to fill the bar's full height.
    ctx.translateBy(x: side * 0.5, y: side * 0.5)
    ctx.scaleBy(x: 1.24, y: 1.24)
    ctx.translateBy(x: -side * 0.5, y: -side * 0.5)
    ctx.translateBy(x: -side * 0.03, y: side * 0.02)
    drawPair(in: ctx, side: side,
             front: CGColor(gray: 0, alpha: 1),
             back: CGColor(gray: 0, alpha: 0.5),
             fill: CGColor(gray: 0, alpha: 0),
             lineScale: 1.15,
             sparkling: false)
    ctx.restoreGState()
}

// MARK: - Emit vector PDFs

func writePDF(to url: URL, side: CGFloat, draw: (CGContext, CGFloat) -> Void) {
    var box = CGRect(x: 0, y: 0, width: side, height: side)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        FileHandle.standardError.write("cannot create PDF at \(url.path)\n".data(using: .utf8)!)
        exit(1)
    }
    ctx.beginPDFPage(nil)
    draw(ctx, side)
    ctx.endPDFPage()
    ctx.closePDF()
}

writePDF(to: resources.appendingPathComponent("AppIcon.pdf"), side: 1024, draw: drawAppIcon)
writePDF(to: resources.appendingPathComponent("MenuBarIcon.pdf"), side: 18, draw: drawMenuBarIcon)

// MARK: - Emit .iconset for .icns

let iconset = build.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let ctx = CGContext(data: nil, width: variant.px, height: variant.px,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    ctx.setAllowsAntialiasing(true)
    drawAppIcon(in: ctx, side: CGFloat(variant.px))
    guard let image = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: variant.px, height: variant.px)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}

print("wrote Resources/AppIcon.pdf, Resources/MenuBarIcon.pdf, build/AppIcon.iconset")
