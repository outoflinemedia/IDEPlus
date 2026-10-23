// Draws the IDEPlus app icon: a code page on the lower left, linked by a dashed line up to a
// server rack on the upper right, on a teal rounded square.
// Usage: swift tools/make_icon.swift Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
	NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

let teal = hex(0x0F6E56), tealMid = hex(0x5DCAA5), tealLight = hex(0x9FE1CB), page = NSColor.white

/// Draws at `size` pixels. The design uses a 100-unit square; the tile follows Apple's icon grid
/// (an 824/1024 body centred in the canvas), so it sits at the same size as other Mac icons.
func render(_ size: Int) -> NSBitmapImageRep {
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
							   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
							   bytesPerRow: 0, bitsPerPixel: 0)!
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	let s = CGFloat(size) / 1024
	let body = 824 * s, inset = 100 * s
	let u = body / 100
	// Design units -> pixels; y is flipped so the design reads top-down.
	func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: inset + x * u, y: CGFloat(size) - inset - y * u) }
	func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
		NSRect(x: inset + x * u, y: CGFloat(size) - inset - (y + h) * u, width: w * u, height: h * u)
	}

	// Runs `draw` with a drop shadow (sizes in design units).
	func shadowed(_ alpha: CGFloat, blur: CGFloat, dy: CGFloat, color: NSColor = .black, _ draw: () -> Void) {
		NSGraphicsContext.saveGraphicsState()
		let sh = NSShadow()
		sh.shadowColor = color.withAlphaComponent(alpha)
		sh.shadowBlurRadius = blur * u
		sh.shadowOffset = NSSize(width: 0, height: -dy * u)
		sh.set()
		draw()
		NSGraphicsContext.restoreGraphicsState()
	}
	// Fills a path top-to-bottom from `top` to `bottom`.
	func shade(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
		NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90)
	}

	// Tile: lit from above, with a soft shadow like other macOS app icons.
	let tile = NSBezierPath(roundedRect: r(0, 0, 100, 100), xRadius: 22.5 * u, yRadius: 22.5 * u)
	shadowed(0.30, blur: 2.4, dy: 1.0) { teal.setFill(); tile.fill() }
	shade(tile, hex(0x1E9A78), hex(0x0A5242))
	// Glossy sheen across the top half.
	NSGraphicsContext.saveGraphicsState()
	tile.addClip()
	let sheen = NSBezierPath(ovalIn: r(-30, -62, 160, 108))
	NSGradient(starting: NSColor.white.withAlphaComponent(0.16), ending: NSColor.white.withAlphaComponent(0.0))!.draw(in: sheen, angle: -90)
	NSGraphicsContext.restoreGraphicsState()
	// A faint light rim along the edge.
	let rim = NSBezierPath(roundedRect: r(0.4, 0.4, 99.2, 99.2), xRadius: 22.1 * u, yRadius: 22.1 * u)
	rim.lineWidth = 0.6 * u
	NSColor.white.withAlphaComponent(0.14).setStroke()
	rim.stroke()

	// Server rack, upper right: each unit casts a shadow and is lit from above.
	for (i, y) in [CGFloat(12), 25, 38].enumerated() {
		let unit = NSBezierPath(roundedRect: r(56, y, 32, 11), xRadius: 3 * u, yRadius: 3 * u)
		shadowed(0.30, blur: 1.6, dy: 0.9) { tealLight.setFill(); unit.fill() }
		shade(unit, hex(0xD2F5E8), hex(0x86D3B8))
		let top = NSBezierPath(roundedRect: r(57, y + 0.6, 30, 1.2), xRadius: 0.6 * u, yRadius: 0.6 * u)
		NSColor.white.withAlphaComponent(0.55).setFill()
		top.fill()
		teal.setFill()
		NSBezierPath(ovalIn: r(60, y + 3.6, 3.8, 3.8)).fill()
		if i == 0 {
			// The top unit's status light glows.
			shadowed(0.9, blur: 1.2, dy: 0, color: hex(0x3DF2B0)) { hex(0x3DF2B0).setFill(); NSBezierPath(ovalIn: r(65.5, y + 3.6, 3.8, 3.8)).fill() }
		} else {
			teal.setFill()
			NSBezierPath(ovalIn: r(65.5, y + 3.6, 3.8, 3.8)).fill()
		}
		hex(0x0A5242).setFill()
		NSBezierPath(roundedRect: r(72, y + 4.4, 12, 2.2), xRadius: 1.1 * u, yRadius: 1.1 * u).fill()
	}

	// Code page, lower left, with a folded corner; floats above the tile.
	let doc = NSBezierPath()
	doc.move(to: p(14, 40))
	doc.line(to: p(42, 40))
	doc.line(to: p(54, 52))
	doc.line(to: p(54, 86))
	doc.appendArc(withCenter: p(51, 86), radius: 3 * u, startAngle: 0, endAngle: -90, clockwise: true)
	doc.line(to: p(14, 89))
	doc.appendArc(withCenter: p(14, 86), radius: 3 * u, startAngle: -90, endAngle: -180, clockwise: true)
	doc.line(to: p(11, 43))
	doc.appendArc(withCenter: p(14, 43), radius: 3 * u, startAngle: 180, endAngle: 90, clockwise: true)
	doc.close()
	shadowed(0.35, blur: 2.6, dy: 1.4) { page.setFill(); doc.fill() }
	shade(doc, NSColor.white, hex(0xE3EFEA))
	// The fold casts a small shadow onto the page.
	let foldShadow = NSBezierPath()
	foldShadow.move(to: p(42, 52))
	foldShadow.line(to: p(54, 52))
	foldShadow.line(to: p(54, 54.5))
	foldShadow.line(to: p(42, 54.5))
	foldShadow.close()
	NSGradient(starting: NSColor.black.withAlphaComponent(0.10), ending: NSColor.black.withAlphaComponent(0.0))!.draw(in: foldShadow, angle: -90)
	let fold = NSBezierPath()
	fold.move(to: p(42, 40))
	fold.line(to: p(42, 52))
	fold.line(to: p(54, 52))
	fold.close()
	shade(fold, hex(0xC4EEDF), hex(0x7FCDB2))
	for (x, y, w, c) in [(CGFloat(17), CGFloat(56), CGFloat(18), teal), (21, 63.5, 24, tealMid), (21, 71, 15, tealMid), (17, 78.5, 22, teal)] {
		c.setFill()
		NSBezierPath(roundedRect: r(x, y, w, 3.2), xRadius: 1.6 * u, yRadius: 1.6 * u).fill()
	}

	// Dashed line from the page up to the server, ending in an arrow; slightly raised.
	let link = NSBezierPath()
	link.move(to: p(55, 68))
	link.curve(to: p(72, 55), controlPoint1: p(66, 68), controlPoint2: p(72, 64))
	link.lineWidth = 3.4 * u
	link.lineCapStyle = .round
	link.setLineDash([4.5 * u, 4 * u], count: 2, phase: 0)
	let arrow = NSBezierPath()
	arrow.move(to: p(66.5, 56.5))
	arrow.line(to: p(72, 50.5))
	arrow.line(to: p(77.5, 56.5))
	arrow.lineWidth = 3.4 * u
	arrow.lineCapStyle = .round
	arrow.lineJoinStyle = .round
	shadowed(0.30, blur: 1.2, dy: 0.7) {
		page.setStroke()
		link.stroke()
		arrow.stroke()
	}

	NSGraphicsContext.restoreGraphicsState()
	return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
	for scale in [1, 2] {
		let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
		try! render(base * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
	}
}
try! render(1024).representation(using: .png, properties: [:])!
	.write(to: URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote \(out)" : "iconutil failed")
