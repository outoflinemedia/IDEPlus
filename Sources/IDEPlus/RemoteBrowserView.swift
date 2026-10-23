import AppKit

final class RemoteNode {
	let name: String
	let path: String
	let isDirectory: Bool
	weak var parent: RemoteNode?
	var children: [RemoteNode]?
	var loading = false

	init(name: String, path: String, isDirectory: Bool, parent: RemoteNode?) {
		self.name = name
		self.path = path
		self.isDirectory = isDirectory
		self.parent = parent
	}
}

/// The FTP tab of the directory window: pick a site, connect, browse, double-click to open.
final class RemoteBrowserView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
	private let sitePopup = NSPopUpButton(frame: .zero, pullsDown: false)
	private let connectButton = NSButton(title: "Connect", target: nil, action: nil)
	private let pathLabel = NSTextField(labelWithString: "")
	private let statusLabel = NSTextField(labelWithString: "")
	private let outline = NSOutlineView()
	private(set) var client: FTPClient?
	private var root: RemoteNode?
	/// Connections to other sites, used when opening favorites from them.
	private var clients: [String: FTPClient] = [:]
	let favorites = FavoritesView()
	private var favoritesSplit: NSSplitView?
	private var placedDivider = false

	var onOpen: ((FTPClient, String) -> Void)?
	var onManageSites: (() -> Void)?

	override init(frame: NSRect) {
		super.init(frame: frame)
		build()
		reloadSites()
		// Favorite files get a star in the tree.
		NotificationCenter.default.addObserver(self, selector: #selector(favoritesChanged), name: .favoritesChanged, object: nil)
	}

	deinit { NotificationCenter.default.removeObserver(self) }

	/// First time only (nothing saved yet): Favorites gets the lower part of the panel.
	override func layout() {
		super.layout()
		// The divider's saved layout also stores whether the panel is hidden; the setting wins.
		let hide = !Preferences.showFavoritesPanel
		if favorites.isHidden != hide { favorites.isHidden = hide }
		guard !placedDivider, let split = favoritesSplit, split.bounds.height > 200 else { return }
		placedDivider = true
		if UserDefaults.standard.object(forKey: "NSSplitView Subview Frames IDEPlusFavoritesSplit") == nil {
			split.setPosition(split.bounds.height * 0.55, ofDividerAt: 0)
		}
	}

	@objc private func favoritesChanged() {
		favorites.isHidden = !Preferences.showFavoritesPanel
		guard outline.numberOfRows > 0 else { return }
		outline.reloadData(forRowIndexes: IndexSet(integersIn: 0..<outline.numberOfRows), columnIndexes: [0])
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
		sitePopup.controlSize = .small
		sitePopup.font = .systemFont(ofSize: 11)
		sitePopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		connectButton.controlSize = .small
		connectButton.font = .systemFont(ofSize: 11)
		connectButton.bezelStyle = .rounded
		connectButton.target = self
		connectButton.action = #selector(connect)
		let siteRow = NSStackView(views: [sitePopup, connectButton, iconButton("gearshape", "FTP sites…", #selector(manageSites))])
		siteRow.spacing = 4

		pathLabel.font = .systemFont(ofSize: 11, weight: .semibold)
		pathLabel.lineBreakMode = .byTruncatingHead
		pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let pathRow = NSStackView(views: [iconButton("arrow.up", "Parent folder", #selector(goUp)), pathLabel, NSView(),
										  iconButton("arrow.clockwise", "Refresh", #selector(refreshAll))])
		pathRow.spacing = 6

		statusLabel.font = .systemFont(ofSize: 11)
		statusLabel.textColor = .secondaryLabelColor
		statusLabel.lineBreakMode = .byTruncatingTail
		statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

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
		outline.allowsMultipleSelection = true
		outline.setDraggingSourceOperationMask(.copy, forLocal: true)
		outline.menu = makeContextMenu()
		let scroll = NSScrollView()
		scroll.documentView = outline
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false

		// The FTP tree above, Favorites below, with a divider you can drag.
		let split = NSSplitView()
		split.isVertical = false
		split.dividerStyle = .thin
		split.addArrangedSubview(scroll)
		split.addArrangedSubview(favorites)
		split.setHoldingPriority(.init(250), forSubviewAt: 0)
		split.setHoldingPriority(.init(260), forSubviewAt: 1)
		scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
		let favHeight = favorites.heightAnchor.constraint(equalToConstant: 230)
		favHeight.priority = .init(200)
		favHeight.isActive = true
		split.autosaveName = "IDEPlusFavoritesSplit"

		let stack = NSStackView(views: [siteRow, pathRow, split, statusLabel])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 4
		stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		for v in [siteRow, pathRow, split, statusLabel] {
			v.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: v === split ? 0 : 8).isActive = true
			v.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: v === split ? 0 : -8).isActive = true
		}
		// The tree and Favorites take all the height; the rows above and the status line keep theirs.
		stack.distribution = .fill
		split.setContentHuggingPriority(.init(1), for: .vertical)
		split.setContentCompressionResistancePriority(.init(1), for: .vertical)
		statusLabel.setContentHuggingPriority(.required, for: .vertical)
		for row in [siteRow, pathRow] { row.setHuggingPriority(.required, for: .vertical) }
		favoritesSplit = split
		favorites.isHidden = !Preferences.showFavoritesPanel
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
		])
		setStatus("Choose a site and click Connect.")
	}

	func reloadSites() {
		let sites = FTPSites.all
		// A site's host or password may have changed: the next use connects with the new details.
		clients = [:]
		sitePopup.removeAllItems()
		if sites.isEmpty {
			sitePopup.addItem(withTitle: "No sites yet")
			sitePopup.isEnabled = false
			connectButton.title = "Add Site…"
		} else {
			sitePopup.addItems(withTitles: sites.map(\.name))
			sitePopup.isEnabled = true
			connectButton.title = "Connect"
			if let last = Preferences.lastSiteID, let i = sites.firstIndex(where: { $0.id == last }) { sitePopup.selectItem(at: i) }
		}
	}

	private func setStatus(_ s: String, error: Bool = false) {
		statusLabel.stringValue = s
		statusLabel.textColor = error ? .systemRed : .secondaryLabelColor
		statusLabel.toolTip = s
	}

	@objc private func manageSites() { onManageSites?() }

	/// Connects to the chosen site, asking for the password if the Keychain has none.
	@objc func connect() {
		let sites = FTPSites.all
		guard !sites.isEmpty else { onManageSites?(); return }
		let site = sites[max(0, sitePopup.indexOfSelectedItem)]
		Preferences.lastSiteID = site.id
		// Reuse the connection a favorite already made, so the Keychain is asked only once per site.
		guard let c = client(for: site.id) else { return }
		client = c
		setRoot(site.rootPath)
	}

	/// A connection to any saved site (for favorites), asking for the password if the Keychain has none.
	/// The tree keeps showing the site it's on.
	func client(for siteID: String) -> FTPClient? {
		if let c = clients[siteID] { return c }
		guard let site = FTPSites.site(id: siteID) else { return nil }
		guard let password = Keychain.password(for: site.id) ?? askPassword(for: site) else { return nil }
		let c = FTPClient(site: site, password: password)
		clients[siteID] = c
		return c
	}

	func askPassword(for site: FTPSite) -> String? {
		let alert = NSAlert()
		alert.messageText = "Password for \(site.username)@\(site.host)"
		alert.informativeText = "If you tick the box, macOS keeps it in your Keychain on this Mac, not IDEPlus. It's only ever sent to this server, to log in."
		let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
		let remember = NSButton(checkboxWithTitle: "Remember in Keychain", target: nil, action: nil)
		remember.state = .on
		let box = NSStackView(views: [field, remember])
		box.orientation = .vertical
		box.alignment = .leading
		box.frame = NSRect(x: 0, y: 0, width: 240, height: 52)
		alert.accessoryView = box
		alert.addButton(withTitle: "Connect")
		alert.addButton(withTitle: "Cancel")
		alert.window.initialFirstResponder = field
		guard alert.runModal() == .alertFirstButtonReturn else { return nil }
		if remember.state == .on { Keychain.setPassword(field.stringValue, for: site.id) }
		return field.stringValue
	}

	private func setRoot(_ path: String) {
		let node = RemoteNode(name: path, path: path, isDirectory: true, parent: nil)
		root = node
		pathLabel.stringValue = "/" + path
		pathLabel.toolTip = client?.displayURL(path)
		outline.reloadData()
		load(node)
	}

	private func load(_ node: RemoteNode) {
		guard let client, !node.loading else { return }
		node.loading = true
		setStatus("Loading /\(node.path)…")
		client.list(node.path) { [weak self] result in
			guard let self else { return }
			node.loading = false
			switch result {
			case let .success(entries):
				node.children = entries.map {
					RemoteNode(name: $0.name, path: FTPClient.join(node.path, $0.name), isDirectory: $0.isDirectory, parent: node)
				}
				self.setStatus("Connected to \(client.site.host)")
				self.outline.reloadItem(node === self.root ? nil : node, reloadChildren: true)
				if node !== self.root { self.outline.expandItem(node) }
			case let .failure(error):
				node.children = nil
				self.setStatus(error.message.components(separatedBy: "\n").first ?? error.message, error: true)
				if node === self.root { self.showError("Couldn't list /\(node.path)", error) }
			}
		}
	}

	@objc private func goUp() {
		guard let path = root?.path, !path.isEmpty else { return }
		setRoot((path as NSString).deletingLastPathComponent)
	}

	@objc private func refreshAll() {
		guard let root else { connect(); return }
		root.children = nil
		outline.reloadData()
		load(root)
	}

	/// Reloads one folder (after creating, renaming or deleting in it).
	private func refresh(_ dir: RemoteNode?) {
		let node = dir ?? root
		guard let node else { return }
		node.children = nil
		load(node)
	}

	@objc private func doubleClicked() {
		guard let n = outline.item(atRow: outline.clickedRow) as? RemoteNode, let client else { return }
		if n.isDirectory {
			if outline.isItemExpanded(n) { outline.collapseItem(n) } else { outline.expandItem(n) }
		} else {
			onOpen?(client, n.path)
		}
	}

	// MARK: Context menu

	private func makeContextMenu() -> NSMenu {
		let m = NSMenu()
		m.addItem(withTitle: "Add to Project", action: #selector(menuAddToProject), keyEquivalent: "").target = self
		m.addItem(.separator())
		for (title, action) in [("Open", #selector(menuOpen)), ("New File…", #selector(menuNewFile)),
								("New Folder…", #selector(menuNewFolder)), ("Rename…", #selector(menuRename)),
								("Delete…", #selector(menuDelete)), ("Make Root Folder", #selector(menuSetRoot)),
								("Refresh", #selector(menuRefresh))] {
			m.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
		}
		return m
	}

	private var clickedNode: RemoteNode? { outline.item(atRow: outline.clickedRow) as? RemoteNode }

	/// The files a right-click acts on: the whole selection if the clicked row is part of it.
	private var clickedFiles: [RemoteNode] {
		let row = outline.clickedRow
		let rows = row >= 0 && !outline.selectedRowIndexes.contains(row) ? IndexSet(integer: row) : outline.selectedRowIndexes
		return rows.compactMap { outline.item(atRow: $0) as? RemoteNode }.filter { !$0.isDirectory }
	}

	@objc private func menuAddToProject() {
		guard let client else { return }
		let files = clickedFiles
		guard !files.isEmpty else {
			setStatus("Add to Project works on files. Select one or more files, not folders.")
			return
		}
		if let p = favorites.add(files.map { (client.site.id, $0.path, client.site.name) }) {
			setStatus(files.count == 1 ? "Added \(files[0].name) to \(p.name)" : "Added \(files.count) files to \(p.name)")
		}
	}

	/// The folder a new item goes into: the clicked folder, the clicked file's folder, or the root.
	private var targetFolder: RemoteNode? {
		guard let n = clickedNode else { return root }
		return n.isDirectory ? n : (n.parent ?? root)
	}

	private func ask(_ title: String, _ initial: String = "") -> String? {
		let alert = NSAlert()
		alert.messageText = title
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
		field.stringValue = initial
		alert.accessoryView = field
		alert.addButton(withTitle: "OK")
		alert.addButton(withTitle: "Cancel")
		alert.window.initialFirstResponder = field
		guard alert.runModal() == .alertFirstButtonReturn else { return nil }
		let v = field.stringValue.trimmingCharacters(in: .whitespaces)
		return v.isEmpty || v.contains("/") ? nil : v
	}

	private func showError(_ message: String, _ error: FTPError) {
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = message
		alert.informativeText = error.message
		alert.runModal()
	}

	private func finish(_ result: Result<Void, FTPError>, _ what: String, refreshing dir: RemoteNode?) {
		switch result {
		case .success: setStatus(what)
		case let .failure(e): showError("Couldn't complete that.", e)
		}
		refresh(dir)
	}

	@objc private func menuOpen() {
		guard let n = clickedNode, let client else { return }
		if n.isDirectory { outline.expandItem(n) } else { onOpen?(client, n.path) }
	}

	@objc private func menuNewFile() {
		guard let client, let dir = targetFolder, let name = ask("New file name") else { return }
		let path = FTPClient.join(dir.path, name)
		let local = client.cacheURL(for: path)
		try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
		try? Data().write(to: local)
		client.upload(local, to: path) { [weak self] result in
			self?.finish(result, "Created \(name)", refreshing: dir)
			if case .success = result { self?.onOpen?(client, path) }
		}
	}

	@objc private func menuNewFolder() {
		guard let client, let dir = targetFolder, let name = ask("New folder name") else { return }
		client.command(["MKD " + FTPClient.join(dir.path, name)]) { [weak self] in
			self?.finish($0, "Created folder \(name)", refreshing: dir)
		}
	}

	@objc private func menuRename() {
		guard let client, let n = clickedNode, let name = ask("Rename “\(n.name)” to", n.name), name != n.name else { return }
		let dir = n.parent ?? root
		let target = FTPClient.join(dir?.path ?? "", name)
		client.command(["RNFR " + n.path, "RNTO " + target]) { [weak self] in
			self?.finish($0, "Renamed to \(name)", refreshing: dir)
		}
	}

	@objc private func menuDelete() {
		guard let client, let n = clickedNode else { return }
		let alert = NSAlert()
		alert.messageText = "Delete “\(n.name)” from the server?"
		alert.informativeText = n.isDirectory ? "Only empty folders can be deleted." : "This can't be undone."
		alert.alertStyle = .warning
		alert.addButton(withTitle: "Delete")
		alert.addButton(withTitle: "Cancel")
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let dir = n.parent ?? root
		client.command([(n.isDirectory ? "RMD " : "DELE ") + n.path]) { [weak self] in
			self?.finish($0, "Deleted \(n.name)", refreshing: dir)
		}
	}

	@objc private func menuSetRoot() {
		guard let n = clickedNode else { return }
		setRoot(n.isDirectory ? n.path : (n.path as NSString).deletingLastPathComponent)
	}

	@objc private func menuRefresh() {
		refresh(clickedNode?.isDirectory == true ? clickedNode : (clickedNode?.parent ?? root))
	}

	// MARK: Data source / delegate

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		guard let n = (item as? RemoteNode) ?? root else { return 0 }
		if n.children == nil && !n.loading && n !== root { load(n) }
		return n.children?.count ?? 0
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		((item as? RemoteNode) ?? root)!.children![index]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
		(item as? RemoteNode)?.isDirectory ?? false
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		guard let n = item as? RemoteNode else { return nil }
		let id = NSUserInterfaceItemIdentifier("remoteCell")
		let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? Self.makeCell(id)
		if !n.isDirectory, let client, FavoritesStore.shared.isFavorite(siteID: client.site.id, path: n.path) {
			let s = NSMutableAttributedString(string: n.name + "  ", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
			s.append(NSAttributedString(string: "★", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemYellow]))
			cell.textField?.attributedStringValue = s
			cell.toolTip = "In your favorites"
		} else {
			cell.textField?.stringValue = n.name
			cell.toolTip = nil
		}
		let icon = n.isDirectory ? NSWorkspace.shared.icon(for: .folder)
			: NSWorkspace.shared.icon(for: .init(filenameExtension: (n.name as NSString).pathExtension) ?? .data)
		icon.size = NSSize(width: 16, height: 16)
		cell.imageView?.image = icon
		return cell
	}

	/// Files can be dragged onto a project in Favorites.
	func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
		guard let n = item as? RemoteNode, !n.isDirectory, let client,
			  let data = try? JSONSerialization.data(withJSONObject: ["siteID": client.site.id, "path": n.path, "siteName": client.site.name]) else { return nil }
		let pb = NSPasteboardItem()
		pb.setData(data, forType: .ftpFile)
		return pb
	}

	static func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
		let cell = NSTableCellView()
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
		return cell
	}
}

/// The directory window: Local and FTP tabs.
final class SidebarView: NSView {
	let local = FileBrowserView()
	let remote = RemoteBrowserView()
	let clips = ClipsView()
	private let switcher = NSSegmentedControl(labels: ["Local", "FTP", "Clips"], trackingMode: .selectOne, target: nil, action: nil)

	override init(frame: NSRect) {
		super.init(frame: frame)
		switcher.target = self
		switcher.action = #selector(switched)
		switcher.controlSize = .small
		switcher.selectedSegment = 0
		switcher.translatesAutoresizingMaskIntoConstraints = false
		addSubview(switcher)
		for v in [local, remote, clips] as [NSView] {
			v.translatesAutoresizingMaskIntoConstraints = false
			addSubview(v)
			NSLayoutConstraint.activate([
				v.topAnchor.constraint(equalTo: switcher.bottomAnchor, constant: 4),
				v.leadingAnchor.constraint(equalTo: leadingAnchor),
				v.trailingAnchor.constraint(equalTo: trailingAnchor),
				v.bottomAnchor.constraint(equalTo: bottomAnchor),
			])
		}
		NSLayoutConstraint.activate([
			switcher.topAnchor.constraint(equalTo: topAnchor, constant: 6),
			switcher.centerXAnchor.constraint(equalTo: centerXAnchor),
		])
		switcher.selectedSegment = min(max(Preferences.sidebarTab, 0), 2)
		switched()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	override func draw(_ dirtyRect: NSRect) {
		Theme.rulerBackground.setFill()
		bounds.fill()
	}

	var showsRemote: Bool {
		get { switcher.selectedSegment == 1 }
		set {
			switcher.selectedSegment = newValue ? 1 : 0
			switched()
		}
	}

	var showsClips: Bool {
		get { switcher.selectedSegment == 2 }
		set {
			switcher.selectedSegment = newValue ? 2 : 0
			switched()
		}
	}

	@objc private func switched() {
		Preferences.sidebarTab = switcher.selectedSegment
		local.isHidden = switcher.selectedSegment != 0
		remote.isHidden = switcher.selectedSegment != 1
		clips.isHidden = switcher.selectedSegment != 2
	}
}
