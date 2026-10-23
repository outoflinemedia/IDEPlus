import AppKit

final class FileNode {
	let url: URL
	let isDirectory: Bool

	init(url: URL, isDirectory: Bool) {
		self.url = url
		self.isDirectory = isDirectory
	}

	private var cached: [FileNode]?

	var children: [FileNode] {
		if let cached { return cached }
		let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
		let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
		let nodes = urls.map { u -> FileNode in
			let v = try? u.resourceValues(forKeys: Set(keys))
			return FileNode(url: u, isDirectory: (v?.isDirectory ?? false) && !(v?.isPackage ?? false))
		}.sorted {
			if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
			return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
		}
		cached = nodes
		return nodes
	}

	func reset() { cached = nil }
}

/// The "directory window": a folder tree on the left. Double-click a file to open it.
final class FileBrowserView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
	private let outline = NSOutlineView()
	private let scroll = NSScrollView()
	private let titleLabel = NSTextField(labelWithString: "")
	private var root: FileNode?
	var onOpen: ((URL) -> Void)?

	override init(frame: NSRect) {
		super.init(frame: frame)
		build()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func iconButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
		let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(), target: self, action: action)
		b.isBordered = false
		b.toolTip = tip
		b.setContentHuggingPriority(.required, for: .horizontal)
		return b
	}

	private func build() {
		titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
		titleLabel.lineBreakMode = .byTruncatingMiddle
		titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let header = NSStackView(views: [
			iconButton("arrow.up", "Parent folder", #selector(goUp)),
			titleLabel,
			NSView(),
			iconButton("arrow.clockwise", "Refresh", #selector(refresh)),
			iconButton("folder", "Choose folder…", #selector(chooseFolder)),
		])
		header.orientation = .horizontal
		header.spacing = 6
		header.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
		header.translatesAutoresizingMaskIntoConstraints = false

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
		outline.addTableColumn(column)
		outline.outlineTableColumn = column
		outline.headerView = nil
		outline.style = .sourceList
		outline.rowSizeStyle = .small
		outline.dataSource = self
		outline.delegate = self
		outline.target = self
		outline.doubleAction = #selector(doubleClicked)
		outline.autoresizesOutlineColumn = true
		outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
		outline.menu = makeContextMenu()

		scroll.documentView = outline
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false
		scroll.translatesAutoresizingMaskIntoConstraints = false

		addSubview(header)
		addSubview(scroll)
		NSLayoutConstraint.activate([
			header.topAnchor.constraint(equalTo: topAnchor),
			header.leadingAnchor.constraint(equalTo: leadingAnchor),
			header.trailingAnchor.constraint(equalTo: trailingAnchor),
			header.heightAnchor.constraint(equalToConstant: 28),
			scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
			scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
			scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
			scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		let start = Preferences.lastFolder.map { URL(fileURLWithPath: $0) }
			.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
			?? FileManager.default.homeDirectoryForCurrentUser
		setRoot(start)
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.rulerBackground.setFill()
		bounds.fill()
	}

	func setRoot(_ url: URL) {
		root = FileNode(url: url, isDirectory: true)
		titleLabel.stringValue = url.path == NSHomeDirectory() ? "~" : url.lastPathComponent
		titleLabel.toolTip = url.path
		Preferences.lastFolder = url.path
		outline.reloadData()
	}

	@objc func chooseFolder() {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.directoryURL = root?.url
		panel.prompt = "Choose"
		if panel.runModal() == .OK, let url = panel.url { setRoot(url) }
	}

	@objc private func goUp() {
		guard let url = root?.url, url.path != "/" else { return }
		setRoot(url.deletingLastPathComponent())
	}

	@objc private func refresh() {
		guard let url = root?.url else { return }
		setRoot(url)
	}

	private func node(_ item: Any?) -> FileNode? { (item as? FileNode) ?? root }

	@objc private func doubleClicked() {
		guard let n = outline.item(atRow: outline.clickedRow) as? FileNode else { return }
		if n.isDirectory {
			if outline.isItemExpanded(n) { outline.collapseItem(n) } else { outline.expandItem(n) }
		} else {
			onOpen?(n.url)
		}
	}

	// MARK: Context menu

	private func makeContextMenu() -> NSMenu {
		let m = NSMenu()
		m.addItem(withTitle: "Open", action: #selector(menuOpen), keyEquivalent: "").target = self
		m.addItem(withTitle: "Make Root Folder", action: #selector(menuSetRoot), keyEquivalent: "").target = self
		m.addItem(withTitle: "Reveal in Finder", action: #selector(menuReveal), keyEquivalent: "").target = self
		return m
	}

	private var clickedNode: FileNode? { outline.item(atRow: outline.clickedRow) as? FileNode }

	@objc private func menuOpen() {
		guard let n = clickedNode else { return }
		if n.isDirectory { outline.expandItem(n) } else { onOpen?(n.url) }
	}

	@objc private func menuSetRoot() {
		guard let n = clickedNode else { return }
		setRoot(n.isDirectory ? n.url : n.url.deletingLastPathComponent())
	}

	@objc private func menuReveal() {
		guard let n = clickedNode else { return }
		NSWorkspace.shared.activateFileViewerSelecting([n.url])
	}

	// MARK: Data source / delegate

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		node(item)?.children.count ?? 0
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		node(item)!.children[index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		(item as? FileNode)?.isDirectory ?? false
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let n = item as? FileNode else { return nil }
		let id = NSUserInterfaceItemIdentifier("cell")
		let cell: NSTableCellView
		if let reused = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
			cell = reused
		} else {
			cell = NSTableCellView()
			cell.identifier = id
			let image = NSImageView()
			let text = NSTextField(labelWithString: "")
			text.lineBreakMode = .byTruncatingTail
			text.font = .systemFont(ofSize: 12)
			image.translatesAutoresizingMaskIntoConstraints = false
			text.translatesAutoresizingMaskIntoConstraints = false
			cell.addSubview(image)
			cell.addSubview(text)
			cell.imageView = image
			cell.textField = text
			NSLayoutConstraint.activate([
				image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
				image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
				image.widthAnchor.constraint(equalToConstant: 16),
				image.heightAnchor.constraint(equalToConstant: 16),
				text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
				text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
				text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
			])
		}
		cell.textField?.stringValue = n.url.lastPathComponent
		let icon = NSWorkspace.shared.icon(forFile: n.url.path)
		icon.size = NSSize(width: 16, height: 16)
		cell.imageView?.image = icon
		return cell
	}
}
