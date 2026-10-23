import AppKit

/// The Clips tab: pick a library, double-click an entry to insert it.
final class ClipsView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
	private let libraryPopup = NSPopUpButton(frame: .zero, pullsDown: false)
	private let search = NSSearchField()
	private let table = NSTableView()
	private let emptyLabel = NSTextField(wrappingLabelWithString: "")
	private var shown: [SnippetSet.Entry] = []

	var onInsert: ((String) -> Void)?

	override init(frame: NSRect) {
		super.init(frame: frame)
		build()
		reload()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func build() {
		libraryPopup.controlSize = .small
		libraryPopup.font = .systemFont(ofSize: 11)
		libraryPopup.target = self
		libraryPopup.action = #selector(libraryChanged)
		search.controlSize = .small
		search.font = .systemFont(ofSize: 11)
		search.placeholderString = "Filter"
		search.delegate = self

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
		table.addTableColumn(column)
		table.headerView = nil
		table.style = .sourceList
		table.rowSizeStyle = .small
		table.dataSource = self
		table.delegate = self
		table.target = self
		table.doubleAction = #selector(insertClicked)
		let menu = NSMenu()
		menu.addItem(withTitle: "Insert", action: #selector(insertClicked), keyEquivalent: "").target = self
		table.menu = menu
		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false

		emptyLabel.font = .systemFont(ofSize: 11)
		emptyLabel.textColor = .secondaryLabelColor

		let stack = NSStackView(views: [libraryPopup, search, emptyLabel, scroll])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 6
		stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		for v in [libraryPopup, search, emptyLabel, scroll] as [NSView] {
			v.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: v === scroll ? 0 : 8).isActive = true
			v.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: v === scroll ? 0 : -8).isActive = true
		}
		scroll.setContentHuggingPriority(.init(1), for: .vertical)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
	}

	/// Call after the syntax folder is reloaded.
	func reload() {
		let libs = SyntaxLibrary.clipLibraries
		libraryPopup.removeAllItems()
		libraryPopup.addItems(withTitles: libs.map(\.title))
		libraryPopup.isEnabled = !libs.isEmpty
		if let last = Preferences.lastClipLibrary, let i = libs.firstIndex(where: { $0.title == last }) {
			libraryPopup.selectItem(at: i)
		}
		emptyLabel.stringValue = "No clip libraries. Add .ipclip files to your syntax folder."
		emptyLabel.isHidden = !libs.isEmpty
		filter()
	}

	private var library: SnippetSet? {
		let libs = SyntaxLibrary.clipLibraries
		let i = libraryPopup.indexOfSelectedItem
		return libs.indices.contains(i) ? libs[i] : nil
	}

	private func filter() {
		let q = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
		let all = library?.entries ?? []
		shown = q.isEmpty ? all : all.filter { $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q) }
		libraryPopup.toolTip = library?.info
		table.reloadData()
	}

	@objc private func libraryChanged() {
		Preferences.lastClipLibrary = library?.title
		filter()
	}

	func controlTextDidChange(_ obj: Notification) { filter() }

	@objc private func insertClicked() {
		let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
		guard shown.indices.contains(row) else { return }
		onInsert?(shown[row].body)
	}

	func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let entry = shown[row]
		let label = NSTextField(labelWithString: entry.title)
		label.font = .systemFont(ofSize: 12)
		label.lineBreakMode = .byTruncatingTail
		// The tooltip previews what will be inserted.
		label.toolTip = SnippetSet.expand(entry.body, indent: "").text
		return label
	}
}
