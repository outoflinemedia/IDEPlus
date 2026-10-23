import AppKit

/// Bottom bar: caret position, and pop-ups for syntax, line ending and encoding.
final class StatusBarView: NSView {
	private let positionLabel = NSTextField(labelWithString: "")
	private let messageLabel = NSTextField(labelWithString: "")
	private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
	private let endingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
	private let encodingPopup = NSPopUpButton(frame: .zero, pullsDown: false)

	var onLanguage: ((Language) -> Void)?
	var onLineEnding: ((LineEnding) -> Void)?
	var onEncoding: ((FileEncoding) -> Void)?

	override init(frame: NSRect) {
		super.init(frame: frame)
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func build() {
		let small = NSFont.systemFont(ofSize: 11)
		positionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
		positionLabel.textColor = .secondaryLabelColor
		positionLabel.lineBreakMode = .byTruncatingTail
		positionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		messageLabel.font = .systemFont(ofSize: 11)
		messageLabel.textColor = .secondaryLabelColor
		messageLabel.lineBreakMode = .byTruncatingTail
		messageLabel.setContentCompressionResistancePriority(.init(100), for: .horizontal)
		languagePopup.addItems(withTitles: Language.all.map(\.name))
		endingPopup.addItems(withTitles: LineEnding.allCases.map(\.rawValue))
		encodingPopup.addItems(withTitles: FileEncoding.all.map(\.name))
		languagePopup.toolTip = "Syntax"
		endingPopup.toolTip = "Line ending used when saving"
		encodingPopup.toolTip = "Encoding used when saving"
		for p in [languagePopup, endingPopup, encodingPopup] {
			p.isBordered = false
			p.font = small
			p.controlSize = .small
			p.target = self
			p.setContentHuggingPriority(.required, for: .horizontal)
		}
		languagePopup.action = #selector(languageChanged)
		endingPopup.action = #selector(endingChanged)
		encodingPopup.action = #selector(encodingChanged)

		let stack = NSStackView(views: [positionLabel, messageLabel, NSView(), languagePopup, endingPopup, encodingPopup])
		stack.orientation = .horizontal
		stack.spacing = 12
		stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 8)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.barBackground.setFill()
		bounds.fill()
		NSColor.separatorColor.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
	}

	func update(_ doc: EditorDocument?) {
		// No tabs open: nothing to describe.
		for popup in [languagePopup, endingPopup, encodingPopup] { popup.isHidden = doc == nil }
		guard let doc else {
			positionLabel.stringValue = ""
			return
		}
		let ed = doc.editor
		let pos = ed.caretPosition()
		let sel = ed.textView.selectedRange().length
		var s = "Ln \(pos.line), Col \(pos.column)   \(ed.lineCount) lines"
		if sel > 0 { s += "   Sel \(sel)" }
		positionLabel.stringValue = s
		languagePopup.selectItem(withTitle: doc.language.name)
		endingPopup.selectItem(withTitle: doc.lineEnding.rawValue)
		encodingPopup.selectItem(withTitle: doc.encoding.name)
	}

	/// Shows FTP progress and other short notices.
	func setMessage(_ s: String, error: Bool = false) {
		messageLabel.stringValue = s
		messageLabel.toolTip = s
		messageLabel.textColor = error ? .systemRed : .secondaryLabelColor
	}

	/// Call after the syntax files are reloaded.
	func reloadLanguages() {
		languagePopup.removeAllItems()
		languagePopup.addItems(withTitles: Language.all.map(\.name))
	}

	@objc private func languageChanged() {
		onLanguage?(Language.all[languagePopup.indexOfSelectedItem])
	}

	@objc private func endingChanged() {
		onLineEnding?(LineEnding.allCases[endingPopup.indexOfSelectedItem])
	}

	@objc private func encodingChanged() {
		onEncoding?(FileEncoding.all[encodingPopup.indexOfSelectedItem])
	}
}
