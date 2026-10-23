import AppKit

/// The document tabs. Click selects, the × or a middle click closes.
final class TabBarView: NSView {
	struct Item {
		let title: String
		let dirty: Bool
		let tooltip: String
		/// FTP files only: whether the file is a favorite (nil for other files: no star shown).
		var star: Bool? = nil
	}

	var items: [Item] = [] {
		didSet { layoutTabs(); needsDisplay = true }
	}
	var selectedIndex = -1 {
		didSet { needsDisplay = true }
	}
	var onSelect: ((Int) -> Void)?
	var onClose: ((Int) -> Void)?
	var onStar: ((Int) -> Void)?

	private var tabRects: [NSRect] = []
	private var hoverIndex = -1
	private var hoverClose = false

	override var isFlipped: Bool { true }

	override func setFrameSize(_ newSize: NSSize) {
		super.setFrameSize(newSize)
		layoutTabs()
	}

	private func layoutTabs() {
		let count = items.count
		guard count > 0 else { tabRects = []; return }
		let width = min(200, max(90, (bounds.width - 4) / CGFloat(count)))
		tabRects = (0..<count).map { NSRect(x: 2 + CGFloat($0) * width, y: 0, width: width, height: bounds.height - 1) }
		removeAllToolTips()
		for (i, r) in tabRects.enumerated() { addToolTip(r, owner: self, userData: UnsafeMutableRawPointer(bitPattern: i + 1)) }
	}

	private func starRect(_ r: NSRect) -> NSRect {
		NSRect(x: r.minX + 6, y: r.midY - 8, width: 16, height: 16)
	}

	private func closeRect(_ r: NSRect) -> NSRect {
		NSRect(x: r.maxX - 22, y: r.midY - 8, width: 16, height: 16)
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.barBackground.setFill()
		bounds.fill()

		let para = NSMutableParagraphStyle()
		para.lineBreakMode = .byTruncatingMiddle
		for (i, r) in tabRects.enumerated() where i < items.count {
			let selected = i == selectedIndex
			if selected {
				NSColor.textBackgroundColor.setFill()
				r.fill()
				NSColor.controlAccentColor.setFill()
				NSRect(x: r.minX, y: r.minY, width: r.width, height: 2).fill()
			} else if i == hoverIndex {
				NSColor.labelColor.withAlphaComponent(0.06).setFill()
				r.fill()
			}
			NSColor.separatorColor.setFill()
			NSRect(x: r.maxX - 1, y: r.minY + 5, width: 1, height: r.height - 10).fill()

			let item = items[i]
			let font = NSFont.systemFont(ofSize: 12, weight: selected ? .medium : .regular)
			let attrs: [NSAttributedString.Key: Any] = [
				.font: font,
				.foregroundColor: selected ? NSColor.labelColor : NSColor.secondaryLabelColor,
				.paragraphStyle: para,
			]
			let title = item.title + (item.dirty ? " *" : "")
			let cr = closeRect(r)
			let h = ceil(font.ascender - font.descender)
			var textX = r.minX + 10
			if let star = item.star {
				// A star on FTP tabs: filled if the file is a favorite; click to add or remove.
				let sr = starRect(r)
				let glyph = (star ? "★" : "☆") as NSString
				let sa: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12),
														 .foregroundColor: star ? NSColor.systemYellow : NSColor.tertiaryLabelColor]
				let gs = glyph.size(withAttributes: sa)
				glyph.draw(at: NSPoint(x: sr.midX - gs.width / 2, y: sr.midY - gs.height / 2), withAttributes: sa)
				textX = sr.maxX + 2
			}
			(title as NSString).draw(with: NSRect(x: textX, y: r.midY - h / 2, width: cr.minX - textX - 2, height: h),
									 options: [.usesLineFragmentOrigin], attributes: attrs)
			if selected || i == hoverIndex {
				if i == hoverIndex && hoverClose {
					NSColor.labelColor.withAlphaComponent(0.12).setFill()
					NSBezierPath(roundedRect: cr, xRadius: 3, yRadius: 3).fill()
				}
				let x = "×" as NSString
				let xa: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor]
				let s = x.size(withAttributes: xa)
				x.draw(at: NSPoint(x: cr.midX - s.width / 2, y: cr.midY - s.height / 2), withAttributes: xa)
			}
		}
		// The line along the top of the text area, drawn last so it runs under every tab,
		// matching the line along the top of the status bar.
		NSColor.separatorColor.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
	}

	private func index(at p: NSPoint) -> Int? {
		tabRects.firstIndex { $0.contains(p) }
	}

	override func mouseDown(with event: NSEvent) {
		let p = convert(event.locationInWindow, from: nil)
		guard let i = index(at: p) else { return }
		if closeRect(tabRects[i]).contains(p) {
			onClose?(i)
		} else if items[i].star != nil, starRect(tabRects[i]).contains(p) {
			onStar?(i)
		} else {
			onSelect?(i)
		}
	}

	override func otherMouseDown(with event: NSEvent) {
		let p = convert(event.locationInWindow, from: nil)
		if event.buttonNumber == 2, let i = index(at: p) { onClose?(i) }
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		trackingAreas.forEach(removeTrackingArea)
		addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
									   owner: self, userInfo: nil))
	}

	override func mouseMoved(with event: NSEvent) {
		let p = convert(event.locationInWindow, from: nil)
		let i = index(at: p) ?? -1
		let onClose = i >= 0 && closeRect(tabRects[i]).contains(p)
		if i != hoverIndex || onClose != hoverClose {
			hoverIndex = i
			hoverClose = onClose
			needsDisplay = true
		}
	}

	override func mouseExited(with event: NSEvent) {
		hoverIndex = -1
		hoverClose = false
		needsDisplay = true
	}
}

extension TabBarView: NSViewToolTipOwner {
	func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
		let i = Int(bitPattern: data) - 1
		return items.indices.contains(i) ? items[i].tooltip : ""
	}
}
