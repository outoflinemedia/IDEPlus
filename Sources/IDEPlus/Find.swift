import AppKit

struct FindOptions {
	var query = ""
	var replacement = ""
	var regex = false
	var matchCase = false
	var wholeWord = false

	func makeRegex() throws -> NSRegularExpression? {
		guard !query.isEmpty else { return nil }
		var pattern = regex ? query : NSRegularExpression.escapedPattern(for: query)
		if wholeWord { pattern = #"\b(?:"# + pattern + #")\b"# }
		var opts: NSRegularExpression.Options = [.anchorsMatchLines]
		if !matchCase { opts.insert(.caseInsensitive) }
		return try NSRegularExpression(pattern: pattern, options: opts)
	}

	/// The replacement as a regex template. In regex mode \n and \t mean newline and tab.
	var template: String {
		guard regex else { return NSRegularExpression.escapedTemplate(for: replacement) }
		var out = ""
		var it = replacement.makeIterator()
		while let ch = it.next() {
			if ch == "\\", let next = it.next() {
				switch next {
				case "n": out.append("\n")
				case "t": out.append("\t")
				default: out.append(ch); out.append(next)
				}
			} else {
				out.append(ch)
			}
		}
		return out
	}
}

enum FindResult {
	case found(index: Int, total: Int, wrapped: Bool)
	case notFound
	case invalid(String)
	case empty
}

extension EditorView {
	private func allMatches(_ re: NSRegularExpression) -> [NSTextCheckingResult] {
		let s = textView.string
		return re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)).filter { $0.range.length > 0 }
	}

	func find(_ opt: FindOptions, backward: Bool) -> FindResult {
		let re: NSRegularExpression
		do {
			guard let r = try opt.makeRegex() else { return .empty }
			re = r
		} catch {
			return .invalid("Invalid regular expression")
		}
		let matches = allMatches(re)
		guard !matches.isEmpty else { return .notFound }
		let sel = textView.selectedRange()
		var wrapped = false
		let idx: Int
		if backward {
			if let i = matches.lastIndex(where: { $0.range.location < sel.location }) { idx = i } else { idx = matches.count - 1; wrapped = true }
		} else {
			if let i = matches.firstIndex(where: { $0.range.location >= NSMaxRange(sel) }) { idx = i } else { idx = 0; wrapped = true }
		}
		let r = matches[idx].range
		textView.setSelectedRange(r)
		centerOn(r)
		textView.showFindIndicator(for: r)
		return .found(index: idx + 1, total: matches.count, wrapped: wrapped)
	}

	func countMatches(_ opt: FindOptions) -> Int {
		guard let re = try? opt.makeRegex() else { return 0 }
		return allMatches(re).count
	}

	/// Replaces the selection if it is a match. Returns false when it is not.
	func replaceCurrent(_ opt: FindOptions) -> Bool {
		guard let re = try? opt.makeRegex() else { return false }
		let s = textView.string
		let sel = textView.selectedRange()
		guard sel.length > 0,
			  let m = re.firstMatch(in: s, options: [.anchored, .withTransparentBounds], range: sel),
			  m.range == sel else { return false }
		let rep = re.replacementString(for: m, in: s, offset: 0, template: opt.template)
		textView.replaceText(in: sel, with: rep, selecting: NSRange(location: sel.location + (rep as NSString).length, length: 0))
		return true
	}

	func replaceAll(_ opt: FindOptions) -> Int {
		guard let re = try? opt.makeRegex() else { return 0 }
		let s = textView.string
		let full = NSRange(location: 0, length: (s as NSString).length)
		let count = allMatches(re).count
		guard count > 0 else { return 0 }
		let result = re.stringByReplacingMatches(in: s, range: full, withTemplate: opt.template)
		let sel = textView.selectedRange()
		let origin = scrollView.contentView.bounds.origin
		textView.replaceText(in: full, with: result, selecting: nil)
		textView.setSelectedRange(NSRange(location: min(sel.location, (result as NSString).length), length: 0))
		scrollView.contentView.scroll(to: origin)
		scrollView.reflectScrolledClipView(scrollView.contentView)
		return count
	}
}

/// The find/replace bar shown above the editor.
final class FindBarView: NSView, NSTextFieldDelegate {
	let findField = NSTextField()
	let replaceField = NSTextField()
	private let regexBox = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
	private let caseBox = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
	private let wordBox = NSButton(checkboxWithTitle: "Whole word", target: nil, action: nil)
	private let statusLabel = NSTextField(labelWithString: "")
	private var replaceRow: NSStackView!

	var onFind: ((_ backward: Bool) -> Void)?
	var onReplace: (() -> Void)?
	var onReplaceAll: (() -> Void)?
	var onClose: (() -> Void)?
	var onOptionsChanged: (() -> Void)?

	var showsReplace = true {
		didSet { replaceRow.isHidden = !showsReplace }
	}

	var options: FindOptions {
		FindOptions(query: findField.stringValue, replacement: replaceField.stringValue,
					regex: regexBox.state == .on, matchCase: caseBox.state == .on, wholeWord: wordBox.state == .on)
	}

	override init(frame: NSRect) {
		super.init(frame: frame)
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func button(_ title: String, _ action: Selector) -> NSButton {
		let b = NSButton(title: title, target: self, action: action)
		b.controlSize = .small
		b.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		b.bezelStyle = .rounded
		return b
	}

	private func label(_ s: String) -> NSTextField {
		let l = NSTextField(labelWithString: s)
		l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		l.alignment = .right
		l.widthAnchor.constraint(equalToConstant: 54).isActive = true
		return l
	}

	private func build() {
		for f in [findField, replaceField] {
			f.controlSize = .small
			f.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
			f.delegate = self
			f.lineBreakMode = .byClipping
			f.cell?.isScrollable = true
			f.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
			f.setContentHuggingPriority(.defaultLow, for: .horizontal)
		}
		findField.placeholderString = "Find"
		replaceField.placeholderString = "Replace with"
		for b in [regexBox, caseBox, wordBox] {
			b.controlSize = .small
			b.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
			b.target = self
			b.action = #selector(optionChanged)
		}
		statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
		statusLabel.textColor = .secondaryLabelColor
		statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		let close = NSButton(title: "✕", target: self, action: #selector(closeClicked))
		close.isBordered = false
		close.font = .systemFont(ofSize: 11)
		close.toolTip = "Close (Esc)"

		let findRow = NSStackView(views: [label("Find:"), findField, button("◀︎ Prev", #selector(prevClicked)),
										  button("Next ▶︎", #selector(nextClicked)), regexBox, caseBox, wordBox, statusLabel, close])
		replaceRow = NSStackView(views: [label("Replace:"), replaceField, button("Replace", #selector(replaceClicked)),
										 button("Replace All", #selector(replaceAllClicked))])
		for row in [findRow, replaceRow!] {
			row.orientation = .horizontal
			row.spacing = 6
			row.alignment = .centerY
		}
		let stack = NSStackView(views: [findRow, replaceRow])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 5
		stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 8)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
			findRow.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor, constant: -8),
			// Both fields must be in the same view tree before their widths can be linked.
			replaceField.widthAnchor.constraint(equalTo: findField.widthAnchor),
			findField.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
		])
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.barBackground.setFill()
		bounds.fill()
		NSColor.separatorColor.setFill()
		NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
	}

	func setStatus(_ s: String, error: Bool = false) {
		statusLabel.stringValue = s
		statusLabel.textColor = error ? .systemRed : .secondaryLabelColor
	}

	@objc private func prevClicked() { onFind?(true) }
	@objc private func nextClicked() { onFind?(false) }
	@objc private func replaceClicked() { onReplace?() }
	@objc private func replaceAllClicked() { onReplaceAll?() }
	@objc private func closeClicked() { onClose?() }
	@objc private func optionChanged() { onOptionsChanged?() }

	func controlTextDidChange(_ obj: Notification) {
		if (obj.object as? NSTextField) === findField { onOptionsChanged?() }
	}

	func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
		if sel == #selector(NSResponder.insertNewline(_:)) || sel == #selector(NSResponder.insertLineBreak(_:)) {
			if control === findField {
				onFind?(NSEvent.modifierFlags.contains(.shift))
			} else {
				onReplace?()
			}
			return true
		}
		if sel == #selector(NSResponder.cancelOperation(_:)) {
			onClose?()
			return true
		}
		return false
	}
}
