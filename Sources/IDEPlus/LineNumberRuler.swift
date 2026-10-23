import AppKit

final class LineNumberRuler: NSRulerView {
	weak var editor: EditorView?
	private var digits = 0

	init(editor: EditorView) {
		self.editor = editor
		super.init(scrollView: editor.scrollView, orientation: .verticalRuler)
		clientView = editor.textView
		reservedThicknessForMarkers = 0
		reservedThicknessForAccessoryView = 0
		// Since macOS 14 views may draw outside their bounds; the number of a half-visible top
		// line would otherwise spill over the tab bar above.
		if #available(macOS 14, *) { clipsToBounds = true }
		updateThickness()
	}

	required init(coder: NSCoder) { fatalError("not used") }

	override var isFlipped: Bool { true }
	override var isOpaque: Bool { true }

	private var numberFont: NSFont {
		.monospacedDigitSystemFont(ofSize: max(9, Preferences.fontSize - 2), weight: .regular)
	}

	/// Widens the ruler when the line count gains a digit.
	func updateThickness() {
		let count = editor?.lineCount ?? 1
		let d = max(3, String(count).count)
		let digitWidth = ("8" as NSString).size(withAttributes: [.font: numberFont]).width
		let thickness = ceil(CGFloat(d) * digitWidth + 16)
		if d != digits || abs(ruleThickness - thickness) > 0.5 {
			digits = d
			ruleThickness = thickness
		}
	}

	override func drawHashMarksAndLabels(in rect: NSRect) {
		NSBezierPath(rect: bounds).addClip()
		Theme.rulerBackground.setFill()
		bounds.fill()
		NSColor.separatorColor.setFill()
		NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

		guard let editor, let lm = editor.textView.layoutManager, let tc = editor.textView.textContainer else { return }
		let tv = editor.textView
		let font = numberFont
		let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
		let current: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
		let ns = tv.string as NSString
		let caretLine = editor.lineNumber(at: tv.selectedRange().location)
		let originY = tv.textContainerOrigin.y

		func draw(_ n: Int, _ frag: NSRect) {
			let p = convert(NSPoint(x: 0, y: frag.minY + originY), from: tv)
			let attrs = n == caretLine ? current : normal
			let s = "\(n)" as NSString
			let size = s.size(withAttributes: attrs)
			s.draw(at: NSPoint(x: bounds.width - size.width - 8, y: p.y + (frag.height - size.height) / 2), withAttributes: attrs)
		}

		let glyphs = lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc)
		let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
		var line = editor.lineNumber(at: chars.location)
		var idx = ns.lineRange(for: NSRange(location: min(chars.location, ns.length), length: 0)).location
		while idx < ns.length && idx <= NSMaxRange(chars) {
			let lineRange = ns.lineRange(for: NSRange(location: idx, length: 0))
			let frag = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: idx), effectiveRange: nil)
			draw(line, frag)
			line += 1
			idx = NSMaxRange(lineRange)
		}
		if idx >= ns.length && (ns.length == 0 || ns.character(at: ns.length - 1) == 10) {
			let frag = lm.extraLineFragmentRect
			if frag.height > 0 { draw(line, frag) }
		}
	}
}
