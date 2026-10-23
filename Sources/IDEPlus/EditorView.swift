import AppKit

/// One document's editing surface: a scroll view with the text view and the line-number ruler.
final class EditorView: NSView, NSTextViewDelegate {
	let scrollView = NSScrollView()
	let textView: EditorTextView
	private(set) var ruler: LineNumberRuler!
	var onTextChange: (() -> Void)?
	var onSelectionChange: (() -> Void)?

	var language: Language = .plain {
		didSet {
			textView.language = language
			scheduleHighlight(immediate: true)
		}
	}

	/// Above this size only the visible part is highlighted.
	static let fullHighlightLimit = 400_000

	private var lineStarts: [Int]?
	private var highlightWork: DispatchWorkItem?

	override init(frame: NSRect) {
		let storage = NSTextStorage()
		let layout = NSLayoutManager()
		layout.allowsNonContiguousLayout = true
		storage.addLayoutManager(layout)
		let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
		container.widthTracksTextView = true
		layout.addTextContainer(container)
		// An explicit container keeps the text view on TextKit 1, which the ruler and highlighter use.
		textView = EditorTextView(frame: .zero, textContainer: container)
		super.init(frame: frame)
		setup()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func setup() {
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		if #available(macOS 14, *) {
			clipsToBounds = true
			scrollView.clipsToBounds = true
		}
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.borderType = .noBorder
		addSubview(scrollView)
		NSLayoutConstraint.activate([
			scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: topAnchor),
			scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		let tv = textView
		tv.minSize = .zero
		tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		tv.isVerticallyResizable = true
		tv.autoresizingMask = [.width]
		tv.isRichText = false
		tv.importsGraphics = false
		tv.allowsUndo = true
		tv.usesFontPanel = false
		tv.usesFindBar = false
		tv.isAutomaticQuoteSubstitutionEnabled = false
		tv.isAutomaticDashSubstitutionEnabled = false
		tv.isAutomaticTextReplacementEnabled = false
		tv.isAutomaticSpellingCorrectionEnabled = false
		tv.isContinuousSpellCheckingEnabled = false
		tv.isGrammarCheckingEnabled = false
		tv.isAutomaticLinkDetectionEnabled = false
		tv.isAutomaticDataDetectionEnabled = false
		tv.isAutomaticTextCompletionEnabled = false
		tv.smartInsertDeleteEnabled = false
		tv.textContainerInset = NSSize(width: 4, height: 4)
		tv.backgroundColor = .textBackgroundColor
		tv.insertionPointColor = .textColor
		tv.delegate = self
		tv.editor = self
		scrollView.documentView = tv

		ruler = LineNumberRuler(editor: self)
		scrollView.verticalRulerView = ruler
		scrollView.hasVerticalRuler = true

		scrollView.contentView.postsBoundsChangedNotifications = true
		NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
											   name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
		applyPreferences()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	// MARK: Settings

	func applyPreferences() {
		let font = Preferences.font
		let charWidth = (" " as NSString).size(withAttributes: [.font: font]).width
		let style = NSMutableParagraphStyle()
		style.tabStops = []
		style.defaultTabInterval = charWidth * CGFloat(Preferences.tabWidth)
		if Preferences.modernLook { style.lineHeightMultiple = 1.15 }
		textView.charWidth = charWidth
		let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.textColor]
		textView.baseAttributes = attrs
		textView.font = font
		textView.defaultParagraphStyle = style
		textView.typingAttributes = attrs
		if let storage = textView.textStorage, storage.length > 0 {
			storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
		}
		setWrap(Preferences.wordWrap)
		scrollView.rulersVisible = Preferences.showLineNumbers
		ruler.updateThickness()
		ruler.needsDisplay = true
		textView.needsDisplay = true
		scheduleHighlight(immediate: true)
	}

	private func setWrap(_ wrap: Bool) {
		guard let container = textView.textContainer else { return }
		if wrap {
			scrollView.hasHorizontalScroller = false
			textView.isHorizontallyResizable = false
			container.widthTracksTextView = true
			container.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
			textView.frame.size.width = scrollView.contentSize.width
		} else {
			scrollView.hasHorizontalScroller = true
			textView.isHorizontallyResizable = true
			container.widthTracksTextView = false
			container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		}
	}

	// MARK: Text

	var string: String { textView.string }

	/// Replaces the whole text without marking the document changed or keeping undo history.
	func setText(_ s: String) {
		textView.string = s
		if let storage = textView.textStorage, storage.length > 0 {
			storage.setAttributes(textView.baseAttributes, range: NSRange(location: 0, length: storage.length))
		}
		textView.undoManager?.removeAllActions()
		lineStarts = nil
		textView.setSelectedRange(NSRange(location: 0, length: 0))
		textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
		ruler.updateThickness()
		ruler.needsDisplay = true
		scheduleHighlight(immediate: true)
	}

	// MARK: Lines

	private func lineStartsArray() -> [Int] {
		if let ls = lineStarts { return ls }
		var arr = [0]
		var i = 0
		for u in textView.string.utf16 {
			i += 1
			if u == 10 { arr.append(i) }
		}
		lineStarts = arr
		return arr
	}

	var lineCount: Int { lineStartsArray().count }

	/// 1-based line number containing the UTF-16 offset.
	func lineNumber(at location: Int) -> Int {
		let starts = lineStartsArray()
		var lo = 0, hi = starts.count - 1
		while lo < hi {
			let mid = (lo + hi + 1) / 2
			if starts[mid] <= location { lo = mid } else { hi = mid - 1 }
		}
		return lo + 1
	}

	func caretPosition() -> (line: Int, column: Int) {
		let loc = textView.selectedRange().location
		let line = lineNumber(at: loc)
		let start = lineStartsArray()[line - 1]
		let ns = textView.string as NSString
		let tw = Preferences.tabWidth
		var col = 0
		var i = start
		while i < loc {
			if ns.character(at: i) == 9 { col += tw - col % tw } else { col += 1 }
			i += 1
		}
		return (line, col + 1)
	}

	func goToLine(_ n: Int) {
		let starts = lineStartsArray()
		let line = min(max(n, 1), starts.count)
		let loc = starts[line - 1]
		let range = NSRange(location: loc, length: 0)
		textView.setSelectedRange(range)
		centerOn(range)
		window?.makeFirstResponder(textView)
	}

	func centerOn(_ range: NSRange) {
		guard let lm = textView.layoutManager, let tc = textView.textContainer else {
			textView.scrollRangeToVisible(range)
			return
		}
		let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
		var rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
		rect.origin.y += textView.textContainerOrigin.y
		let visible = scrollView.contentView.bounds
		if !visible.insetBy(dx: 0, dy: visible.height * 0.15).contains(NSPoint(x: visible.minX + 1, y: rect.midY)) {
			let y = max(0, rect.midY - visible.height / 2)
			scrollView.contentView.scroll(to: NSPoint(x: visible.minX, y: y))
			scrollView.reflectScrolledClipView(scrollView.contentView)
		}
		textView.scrollRangeToVisible(range)
	}

	// MARK: Highlighting

	func scheduleHighlight(immediate: Bool = false) {
		highlightWork?.cancel()
		let work = DispatchWorkItem { [weak self] in self?.highlightNow() }
		highlightWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.12), execute: work)
	}

	private var isLarge: Bool { (textView.string as NSString).length > Self.fullHighlightLimit }

	private func highlightNow() {
		if isLarge {
			SyntaxHighlighter.apply(language, to: textView, range: visibleLineRange())
		} else {
			SyntaxHighlighter.apply(language, to: textView, range: nil)
		}
	}

	private func visibleLineRange() -> NSRange {
		guard let lm = textView.layoutManager, let tc = textView.textContainer else { return NSRange() }
		let glyphs = lm.glyphRange(forBoundingRect: textView.visibleRect, in: tc)
		let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
		return (textView.string as NSString).lineRange(for: chars)
	}

	@objc private func boundsChanged() {
		ruler.needsDisplay = true
		if isLarge { scheduleHighlight() }
	}

	// MARK: NSTextViewDelegate

	func textDidChange(_ notification: Notification) {
		lineStarts = nil
		ruler.updateThickness()
		ruler.needsDisplay = true
		scheduleHighlight()
		onTextChange?()
	}

	func textViewDidChangeSelection(_ notification: Notification) {
		textView.setNeedsDisplay(textView.visibleRect)
		ruler.needsDisplay = true
		updateBracketMatch()
		onSelectionChange?()
	}

	// MARK: Bracket matching

	private var bracketRanges: [NSRange] = []

	private func updateBracketMatch() {
		guard let lm = textView.layoutManager else { return }
		let ns = textView.string as NSString
		for r in bracketRanges where NSMaxRange(r) <= ns.length {
			lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
		}
		bracketRanges = []
		let sel = textView.selectedRange()
		guard sel.length == 0, let match = Self.matchingBracket(in: ns, caret: sel.location) else { return }
		bracketRanges = [NSRange(location: match.0, length: 1), NSRange(location: match.1, length: 1)]
		for r in bracketRanges {
			lm.addTemporaryAttribute(.backgroundColor, value: Theme.bracketMatch, forCharacterRange: r)
		}
	}

	/// The bracket next to the caret (after it first, then before it) and its partner.
	static func matchingBracket(in ns: NSString, caret: Int) -> (Int, Int)? {
		let open: [unichar: unichar] = [40: 41, 91: 93, 123: 125]
		let close: [unichar: unichar] = [41: 40, 93: 91, 125: 123]
		let limit = 50_000
		for at in [caret, caret - 1] where at >= 0 && at < ns.length {
			let c = ns.character(at: at)
			if let partner = open[c] {
				var depth = 0
				var i = at
				while i < ns.length && i - at < limit {
					let x = ns.character(at: i)
					if x == c { depth += 1 } else if x == partner { depth -= 1; if depth == 0 { return (at, i) } }
					i += 1
				}
				return nil
			}
			if let partner = close[c] {
				var depth = 0
				var i = at
				while i >= 0 && at - i < limit {
					let x = ns.character(at: i)
					if x == c { depth += 1 } else if x == partner { depth -= 1; if depth == 0 { return (i, at) } }
					i -= 1
				}
				return nil
			}
		}
		return nil
	}

	func undoManager(for view: NSTextView) -> UndoManager? {
		textView.ownUndoManager
	}
}

/// The text view: own undo stack per document, auto-indent, soft tabs, current-line highlight.
final class EditorTextView: NSTextView {
	let ownUndoManager = UndoManager()
	weak var editor: EditorView?
	var language: Language = .plain
	var baseAttributes: [NSAttributedString.Key: Any] = [:]

	override var undoManager: UndoManager? { ownUndoManager }

	private func drawCurrentLine(in rect: NSRect) {
		super.drawBackground(in: rect)
		guard Preferences.highlightLine, selectedRange().length == 0, let lm = layoutManager else { return }
		let ns = string as NSString
		let loc = selectedRange().location
		var lineRect: NSRect
		if loc >= ns.length && (ns.length == 0 || ns.character(at: ns.length - 1) == 10) {
			lineRect = lm.extraLineFragmentRect
		} else {
			// Union of the first and last fragments of the line (more than one when wrapped).
			let lineRange = ns.lineRange(for: NSRange(location: min(loc, ns.length - 1), length: 0))
			var lastChar = NSMaxRange(lineRange) - 1
			if lastChar > lineRange.location && ns.character(at: lastChar) == 10 { lastChar -= 1 }
			let first = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: lineRange.location), effectiveRange: nil)
			let last = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: max(lastChar, lineRange.location)), effectiveRange: nil)
			lineRect = first.union(last)
		}
		guard lineRect.height > 0 else { return }
		lineRect.origin.x = 0
		lineRect.size.width = bounds.width
		lineRect.origin.y += textContainerOrigin.y
		(Preferences.modernLook ? Theme.modernCurrentLine : Theme.currentLine).setFill()
		lineRect.intersection(rect).fill()
	}

	var charWidth: CGFloat = 7

	/// Thin vertical lines at each indent level, as in modern IDEs.
	private func drawIndentGuides(in rect: NSRect) {
		guard Preferences.modernLook, let lm = layoutManager, let tc = textContainer else { return }
		let ns = string as NSString
		guard ns.length > 0 else { return }
		let tw = Preferences.tabWidth
		let glyphs = lm.glyphRange(forBoundingRect: rect, in: tc)
		let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
		let x0 = textContainerOrigin.x + tc.lineFragmentPadding
		Theme.indentGuide.setFill()
		var idx = ns.lineRange(for: NSRange(location: min(chars.location, ns.length - 1), length: 0)).location
		var lastIndent = 0
		while idx < ns.length && idx <= NSMaxRange(chars) {
			let lineRange = ns.lineRange(for: NSRange(location: idx, length: 0))
			var col = 0
			var i = lineRange.location
			var blank = true
			while i < NSMaxRange(lineRange) {
				let c = ns.character(at: i)
				if c == 32 { col += 1 } else if c == 9 { col += tw - col % tw } else { blank = c == 10 || c == 13; break }
				i += 1
			}
			// Blank lines continue the guides of the line above.
			let indent = blank ? lastIndent : col
			if !blank { lastIndent = col }
			if indent >= tw {
				let first = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: lineRange.location), effectiveRange: nil)
				let y = first.minY + textContainerOrigin.y
				var level = 0
				while level * tw < indent {
					NSRect(x: floor(x0 + CGFloat(level * tw) * charWidth) + 0.5, y: y, width: 1, height: first.height).fill()
					level += 1
				}
			}
			idx = NSMaxRange(lineRange)
		}
	}

	override func drawBackground(in rect: NSRect) {
		drawCurrentLine(in: rect)
		drawIndentGuides(in: rect)
	}

	override func insertNewline(_ sender: Any?) {
		let ns = string as NSString
		let sel = selectedRange()
		let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
		let before = ns.substring(with: NSRange(location: lineStart, length: sel.location - lineStart))
		let indent = String(before.prefix { $0 == " " || $0 == "\t" })
		guard Preferences.smartEditing else {
			insertPlain("\n" + indent, replacementRange: sel)
			return
		}
		// One level deeper after an opening bracket, a Python ":" or an opening HTML tag.
		let trimmed = before.trimmingCharacters(in: .whitespaces)
		let last = trimmed.last
		var deeper = last == "{" || last == "[" || last == "("
		if language === Language.python || language.name.lowercased().contains("python") { deeper = deeper || last == ":" }
		if language.isMarkup, last == ">", let tag = Self.openTagName(before: trimmed), !Self.voidTags.contains(tag) { deeper = true }
		let after = NSMaxRange(sel) < ns.length ? ns.substring(with: NSRange(location: NSMaxRange(sel), length: min(3, ns.length - NSMaxRange(sel)))) : ""
		let closesNext = deeper && (after.hasPrefix("}") || after.hasPrefix("]") || after.hasPrefix(")") || after.hasPrefix("</"))
		if closesNext {
			// {|} becomes {\n\t|\n}
			let inner = "\n" + indent + indentUnitString
			insertPlain(inner + "\n" + indent, replacementRange: sel)
			setSelectedRange(NSRange(location: sel.location + (inner as NSString).length, length: 0))
		} else {
			insertPlain("\n" + indent + (deeper ? indentUnitString : ""), replacementRange: sel)
		}
	}

	var indentUnitString: String {
		Preferences.useSpaces ? String(repeating: " ", count: Preferences.tabWidth) : "\t"
	}

	// MARK: Smart editing

	static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
										"param", "source", "track", "wbr", "!doctype"]
	private static let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
	private static let closers: Set<Character> = [")", "]", "}", "\"", "'", "`"]
	private var isInserting = false

	/// The tag name of an opening tag that ends `text` ("<div class=x>" gives "div").
	static func openTagName(before text: String) -> String? {
		guard let re = try? NSRegularExpression(pattern: #"<([A-Za-z][\w:.-]*)(?:\s[^<>]*)?>$"#),
			  let m = re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
			  !text.hasSuffix("/>") else { return nil }
		return (text as NSString).substring(with: m.range(at: 1)).lowercased()
	}

	/// Inserts text without the auto-close behaviour.
	func insertPlain(_ s: String, replacementRange: NSRange) {
		isInserting = true
		insertText(s, replacementRange: replacementRange)
		isInserting = false
	}

	// MARK: Auto-completion and clips

	/// A trigger word from the language's .ipsnip file, followed by Space, becomes its template.
	private func expandAutocompletion(at sel: NSRange) -> Bool {
		guard sel.length == 0, let ac = SyntaxLibrary.autocompletion(for: language) else { return false }
		let ns = string as NSString
		let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
		let before = ns.substring(with: NSRange(location: lineStart, length: sel.location - lineStart))
		let word = String(before.reversed().prefix { !$0.isWhitespace }.reversed())
		guard !word.isEmpty else { return false }
		let atLineStart = before.dropLast(word.count).allSatisfy { $0 == " " || $0 == "\t" }
		guard let entry = ac.entry(for: word, atLineStart: atLineStart) else { return false }
		let indent = String(before.prefix { $0 == " " || $0 == "\t" })
		let (text, caret) = SnippetSet.expand(entry.body, indent: indent, unit: indentUnitString)
		let wordLength = (word as NSString).length
		let range = NSRange(location: sel.location - wordLength, length: wordLength)
		replaceText(in: range, with: text,
					selecting: NSRange(location: range.location + (caret ?? (text as NSString).length), length: 0))
		return true
	}

	/// Inserts a clip (or template) at the cursor, replacing any selection.
	func insertSnippet(_ body: String) {
		let ns = string as NSString
		let sel = selectedRange()
		let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
		let before = ns.substring(with: NSRange(location: lineStart, length: sel.location - lineStart))
		let indent = String(before.prefix { $0 == " " || $0 == "\t" })
		let (text, caret) = SnippetSet.expand(body, indent: indent, unit: indentUnitString)
		replaceText(in: sel, with: text,
					selecting: NSRange(location: sel.location + (caret ?? (text as NSString).length), length: 0))
	}

	override func insertText(_ string: Any, replacementRange: NSRange) {
		let typed = (string as? String) ?? (string as? NSAttributedString)?.string
		if Preferences.autoComplete, !isInserting, !hasMarkedText(), typed == " ",
		   expandAutocompletion(at: replacementRange.location == NSNotFound ? selectedRange() : replacementRange) {
			return
		}
		guard Preferences.smartEditing, !isInserting, !hasMarkedText(), let s = typed, s.count == 1, let ch = s.first else {
			super.insertText(string, replacementRange: replacementRange)
			return
		}
		let ns = self.string as NSString
		let sel = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
		let next: Character? = NSMaxRange(sel) < ns.length ? Character(UnicodeScalar(ns.character(at: NSMaxRange(sel))) ?? " ") : nil
		let prev: Character? = sel.location > 0 ? Character(UnicodeScalar(ns.character(at: sel.location - 1)) ?? " ") : nil
		let isQuote = ch == "\"" || ch == "'" || ch == "`"

		// Typing a closer that is already next to the caret just steps over it.
		if sel.length == 0, Self.closers.contains(ch), next == ch {
			setSelectedRange(NSRange(location: sel.location + 1, length: 0))
			return
		}
		// Brackets and quotes wrap a selection.
		if sel.length > 0, let close = Self.pairs[ch] {
			let inner = ns.substring(with: sel)
			replaceText(in: sel, with: String(ch) + inner + String(close),
						selecting: NSRange(location: sel.location + 1, length: (inner as NSString).length))
			return
		}
		if sel.length == 0, let close = Self.pairs[ch] {
			let nextOK = next == nil || next!.isWhitespace || Self.closers.contains(next!) || next == ";" || next == "," || next == ">"
			let quoteOK = !isQuote || (prev.map { !$0.isLetter && !$0.isNumber } ?? true) && !(language === Language.plain || language === Language.markdown)
			if nextOK && quoteOK {
				insertPlain(String(ch) + String(close), replacementRange: sel)
				setSelectedRange(NSRange(location: sel.location + 1, length: 0))
				return
			}
		}
		// A closing bracket typed on a blank line moves back one indent level.
		if sel.length == 0, ch == "}" || ch == "]" || ch == ")" {
			let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
			let before = ns.substring(with: NSRange(location: lineStart, length: sel.location - lineStart))
			if !before.isEmpty && before.allSatisfy({ $0 == " " || $0 == "\t" }) {
				var outdented = before
				if outdented.hasSuffix("\t") { outdented.removeLast() } else {
					let n = min(Preferences.tabWidth, outdented.reversed().prefix { $0 == " " }.count)
					outdented.removeLast(n)
				}
				insertPlain(outdented + String(ch), replacementRange: NSRange(location: lineStart, length: sel.location - lineStart))
				return
			}
		}
		// Typing ">" after an opening tag adds the closing tag.
		if sel.length == 0, ch == ">", language.isMarkup {
			let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
			let before = ns.substring(with: NSRange(location: lineStart, length: sel.location - lineStart)) + ">"
			if let tag = Self.openTagName(before: before), !Self.voidTags.contains(tag) {
				insertPlain("></" + tag + ">", replacementRange: sel)
				setSelectedRange(NSRange(location: sel.location + 1, length: 0))
				return
			}
		}
		super.insertText(string, replacementRange: replacementRange)
	}

	/// Backspace between an empty pair such as () or "" deletes both.
	override func deleteBackward(_ sender: Any?) {
		let sel = selectedRange()
		let ns = string as NSString
		if Preferences.smartEditing, sel.length == 0, sel.location > 0, sel.location < ns.length,
		   let open = UnicodeScalar(ns.character(at: sel.location - 1)).map(Character.init),
		   let close = Self.pairs[open], UnicodeScalar(ns.character(at: sel.location)).map(Character.init) == close {
			replaceText(in: NSRange(location: sel.location - 1, length: 2), with: "", selecting: NSRange(location: sel.location - 1, length: 0))
			return
		}
		super.deleteBackward(sender)
	}

	override func insertTab(_ sender: Any?) {
		let sel = selectedRange()
		let ns = string as NSString
		// Tab out: jump past closing brackets and quotes right after the cursor, e.g. echo("hi|") → echo("hi")|
		if Preferences.smartEditing, sel.length == 0 {
			var end = sel.location
			while end < ns.length, let ch = UnicodeScalar(ns.character(at: end)).map(Character.init), Self.closers.contains(ch) {
				end += 1
			}
			if end > sel.location {
				setSelectedRange(NSRange(location: end, length: 0))
				return
			}
		}
		if sel.length > 0 && ns.substring(with: sel).contains("\n") {
			indentLines(sender)
			return
		}
		if Preferences.useSpaces {
			let col = editor?.caretPosition().column ?? 1
			let tw = Preferences.tabWidth
			let n = tw - (col - 1) % tw
			insertPlain(String(repeating: " ", count: n), replacementRange: sel)
		} else {
			super.insertTab(sender)
		}
	}

	override func insertBacktab(_ sender: Any?) {
		unindentLines(sender)
	}

	// Pasted text may carry CR or CRLF breaks; keep "\n" inside the editor.
	override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
		if let s = pboard.string(forType: .string), s.utf16.contains(13) {
			insertPlain(LineEnding.normalize(s), replacementRange: selectedRange())
			return true
		}
		return super.readSelection(from: pboard, type: type)
	}
}
