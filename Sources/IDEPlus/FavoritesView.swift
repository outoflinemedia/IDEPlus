import AppKit

extension NSPasteboard.PasteboardType {
	/// One FTP file dragged from the FTP tree: JSON {"siteID", "path", "siteName"}.
	static let ftpFile = NSPasteboard.PasteboardType("com.outoflinemedia.ideplus.ftp-file")
	/// A favorite being moved inside the Favorites panel: its id.
	static let favorite = NSPasteboard.PasteboardType("com.outoflinemedia.ideplus.favorite")
}

typealias FTPFileRef = (siteID: String, path: String, siteName: String)

/// The Favorites panel under the FTP tree: projects (folders) of FTP files from any site.
final class FavoritesView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSSearchFieldDelegate {
	private let store = FavoritesStore.shared
	private let outline = KeyOutlineView()
	private let scroll = NSScrollView()
	private let currentLabel = NSTextField(labelWithString: "")
	private let filter = NSSearchField()
	private let emptyView = NSStackView()
	private var shownProjects: [(FavoriteProject, [FavoriteItem])] = []
	private var shownLoose: [FavoriteItem] = []
	private var reloading = false

	/// Open these favorites (connecting to their sites as needed).
	var onOpen: (([FavoriteItem]) -> Void)?
	/// The ★+ button: add the file in the current tab.
	var onAddCurrent: (() -> Void)?

	override init(frame: NSRect) {
		super.init(frame: frame)
		build()
		reload()
		NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .favoritesChanged, object: nil)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	deinit { NotificationCenter.default.removeObserver(self) }

	private func iconButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
		let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(), target: self, action: action)
		b.isBordered = false
		b.toolTip = tip
		b.setContentHuggingPriority(.required, for: .horizontal)
		return b
	}

	private func build() {
		let title = NSTextField(labelWithString: "FAVORITES")
		title.font = .systemFont(ofSize: 10, weight: .semibold)
		title.textColor = .secondaryLabelColor
		let header = NSStackView(views: [title, NSView(),
										 iconButton("folder.badge.plus", "New project", #selector(newProjectClicked)),
										 iconButton("star.circle", "Add the file in the current tab to the current project", #selector(addCurrentClicked))])
		header.spacing = 6

		currentLabel.font = .systemFont(ofSize: 11)
		currentLabel.textColor = .secondaryLabelColor
		currentLabel.lineBreakMode = .byTruncatingTail
		currentLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		filter.controlSize = .small
		filter.font = .systemFont(ofSize: 11)
		filter.placeholderString = "Filter favorites"
		filter.delegate = self

		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("fav"))
		outline.addTableColumn(column)
		outline.outlineTableColumn = column
		outline.headerView = nil
		outline.style = .plain
		outline.backgroundColor = .clear
		outline.rowSizeStyle = .small
		outline.allowsMultipleSelection = true
		outline.dataSource = self
		outline.delegate = self
		outline.target = self
		outline.doubleAction = #selector(doubleClicked)
		outline.registerForDraggedTypes([.ftpFile, .favorite])
		outline.setDraggingSourceOperationMask(.move, forLocal: true)
		outline.onDelete = { [weak self] in self?.removeSelected() }
		let menu = NSMenu()
		menu.delegate = self
		outline.menu = menu
		scroll.documentView = outline
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.drawsBackground = false

		// Shown instead of an empty list: the first step, not a blank.
		let hint = NSTextField(wrappingLabelWithString: "Keep the files you're working on together, from any of your sites.")
		hint.font = .systemFont(ofSize: 11)
		hint.textColor = .secondaryLabelColor
		hint.alignment = .center
		let create = NSButton(title: "Create a project", target: self, action: #selector(newProjectClicked))
		create.controlSize = .small
		create.bezelStyle = .rounded
		let tip = NSTextField(wrappingLabelWithString: "Then right-click files in the FTP list, or drag them here.")
		tip.font = .systemFont(ofSize: 10)
		tip.textColor = .tertiaryLabelColor
		tip.alignment = .center
		emptyView.setViews([hint, create, tip], in: .center)
		emptyView.orientation = .vertical
		emptyView.spacing = 8
		emptyView.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

		let stack = NSStackView(views: [header, currentLabel, filter, emptyView, scroll])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 4
		stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 4, right: 8)
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		for v in [header, currentLabel, filter, emptyView, scroll] as [NSView] {
			v.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: v === scroll ? 0 : 8).isActive = true
			v.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: v === scroll ? 0 : -8).isActive = true
		}
		stack.distribution = .fill
		scroll.setContentHuggingPriority(.init(1), for: .vertical)
		scroll.setContentCompressionResistancePriority(.init(1), for: .vertical)
		header.setHuggingPriority(.required, for: .vertical)
		for v in [currentLabel, filter] as [NSView] { v.setContentHuggingPriority(.required, for: .vertical) }
		emptyView.setContentHuggingPriority(.init(1), for: .vertical)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor),
			stack.topAnchor.constraint(equalTo: topAnchor),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor),
			heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
		])
	}

	override func draw(_ dirtyRect: NSRect) {
		Theme.rulerBackground.setFill()
		bounds.fill()
		NSColor.separatorColor.setFill()
		NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
	}

	// MARK: Refresh

	@objc private func storeChanged() { reload() }

	func reload() {
		reloading = true
		let filtered = store.filtered(filter.stringValue)
		shownProjects = filtered.projects
		shownLoose = filtered.loose
		outline.reloadData()
		let filtering = !filter.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
		for (p, _) in shownProjects {
			if filtering || p.expanded { outline.expandItem(p) } else { outline.collapseItem(p) }
		}
		reloading = false
		let empty = store.isEmpty
		emptyView.isHidden = !empty
		scroll.isHidden = empty
		filter.isHidden = empty
		if let p = store.currentProject {
			currentLabel.stringValue = "Adding to: \(p.name)"
			currentLabel.toolTip = "★ and Add to Project put files in “\(p.name)”. Click a project to change it."
		} else {
			currentLabel.stringValue = empty ? "" : "No project selected — click one to add files to it"
			currentLabel.toolTip = nil
		}
		currentLabel.isHidden = currentLabel.stringValue.isEmpty
	}

	func controlTextDidChange(_ obj: Notification) { reload() }

	// MARK: Adding

	/// Adds FTP files to the current project. With none selected, asks which project (or makes one)
	/// instead of failing. Returns the project they went into, or nil if cancelled.
	@discardableResult
	func add(_ files: [FTPFileRef]) -> FavoriteProject? {
		guard !files.isEmpty else { return nil }
		guard let project = store.currentProject ?? ProjectPicker.choose(for: files, store: store) else { return nil }
		store.add(files.map { (siteID: $0.siteID, path: $0.path, siteName: $0.siteName) }, to: project)
		if let i = outline.row(forItem: project) as Int?, i >= 0 { outline.expandItem(project) }
		return project
	}

	@objc private func newProjectClicked() {
		guard let name = Self.askName(title: "New project", message: "A project groups the files you're working on, from any of your sites.",
									  initial: "", ok: "Create") else { return }
		let p = store.newProject(named: name)
		reload()
		let row = outline.row(forItem: p)
		if row >= 0 { outline.selectRowIndexes([row], byExtendingSelection: false) }
	}

	@objc private func addCurrentClicked() { onAddCurrent?() }

	static func askName(title: String, message: String, initial: String, ok: String) -> String? {
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
		field.stringValue = initial
		field.placeholderString = "Project name"
		alert.accessoryView = field
		alert.addButton(withTitle: ok)
		alert.addButton(withTitle: "Cancel")
		alert.window.initialFirstResponder = field
		guard alert.runModal() == .alertFirstButtonReturn else { return nil }
		let v = field.stringValue.trimmingCharacters(in: .whitespaces)
		return v.isEmpty ? "New project" : v
	}

	// MARK: Actions

	private var selectedItems: [FavoriteItem] {
		let rows = outline.clickedRow >= 0 && !outline.selectedRowIndexes.contains(outline.clickedRow)
			? IndexSet(integer: outline.clickedRow) : outline.selectedRowIndexes
		return rows.compactMap { outline.item(atRow: $0) as? FavoriteItem }
	}

	@objc private func doubleClicked() {
		let row = outline.clickedRow
		guard row >= 0 else { return }
		if let item = outline.item(atRow: row) as? FavoriteItem {
			onOpen?([item])
		} else if let p = outline.item(atRow: row) as? FavoriteProject {
			if outline.isItemExpanded(p) { outline.collapseItem(p) } else { outline.expandItem(p) }
		}
	}

	private func removeSelected() {
		let items = selectedItems
		if !items.isEmpty {
			store.remove(items)
			return
		}
		if let p = outline.item(atRow: outline.selectedRow) as? FavoriteProject { confirmRemove(p) }
	}

	private func confirmRemove(_ p: FavoriteProject) {
		let alert = NSAlert()
		alert.messageText = "Remove the project “\(p.name)”?"
		alert.informativeText = "Its \(p.items.count) favorite\(p.items.count == 1 ? "" : "s") are removed from this list. The files on your server aren't touched."
		alert.addButton(withTitle: "Remove")
		alert.addButton(withTitle: "Cancel")
		if alert.runModal() == .alertFirstButtonReturn { store.removeProject(p) }
	}

	// MARK: Context menu

	func menuNeedsUpdate(_ menu: NSMenu) {
		menu.removeAllItems()
		let row = outline.clickedRow
		let target = row >= 0 ? outline.item(atRow: row) : nil
		func add(_ title: String, _ action: @escaping () -> Void) {
			let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
			let box = MenuAction(action)
			item.target = box
			item.representedObject = box
			menu.addItem(item)
		}
		if let p = target as? FavoriteProject {
			add("Open All") { [weak self] in self?.onOpen?(p.items) }
			add("Make Current Project") { [weak self] in self?.store.setCurrent(p) }
			add("Rename…") { [weak self] in
				if let n = Self.askName(title: "Rename project", message: "", initial: p.name, ok: "Rename") { self?.store.rename(p, to: n) }
			}
			menu.addItem(.separator())
			add("Remove Project…") { [weak self] in self?.confirmRemove(p) }
		} else if target is FavoriteItem {
			let items = selectedItems
			add(items.count > 1 ? "Open \(items.count) Files" : "Open") { [weak self] in self?.onOpen?(items) }
			add(items.count > 1 ? "Remove \(items.count) from Favorites" : "Remove from Favorites") { [weak self] in self?.store.remove(items) }
		} else {
			add("New Project…") { [weak self] in self?.newProjectClicked() }
		}
	}

	// MARK: Data source

	func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if let p = item as? FavoriteProject { return shownProjects.first { $0.0 === p }?.1.count ?? 0 }
		return item == nil ? shownProjects.count + shownLoose.count : 0
	}

	func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if let p = item as? FavoriteProject { return shownProjects.first { $0.0 === p }!.1[index] }
		return index < shownProjects.count ? shownProjects[index].0 : shownLoose[index - shownProjects.count]
	}

	func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { item is FavoriteProject }

	/// Files are two lines tall (name, then site); projects one.
	func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
		item is FavoriteItem ? 32 : outlineView.rowHeight
	}

	func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
		let cell = RemoteBrowserView.makeCell(NSUserInterfaceItemIdentifier("favCell"))
		if let p = item as? FavoriteProject {
			let current = p.id == store.currentProjectID
			cell.textField?.attributedStringValue = NSAttributedString(string: p.name, attributes: [
				.font: NSFont.systemFont(ofSize: 12, weight: current ? .semibold : .medium), .foregroundColor: NSColor.labelColor])
			cell.imageView?.image = Self.symbol(current ? "folder.fill" : "folder", current ? .controlAccentColor : .secondaryLabelColor)
			cell.toolTip = "\(p.items.count) file\(p.items.count == 1 ? "" : "s")"
		} else if let f = item as? FavoriteItem {
			let s = NSMutableAttributedString(string: f.name, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
			s.append(NSAttributedString(string: "\n" + f.siteLabel, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.tertiaryLabelColor]))
			// Two lines, the site under the file name; each is cut short with "…" when the panel is narrow.
			let lines = NSMutableParagraphStyle()
			lines.lineBreakMode = .byTruncatingTail
			s.addAttribute(.paragraphStyle, value: lines, range: NSRange(location: 0, length: s.length))
			cell.textField?.maximumNumberOfLines = 2
			cell.textField?.attributedStringValue = s
			cell.imageView?.image = Self.symbol("star.fill", .systemYellow)
			// The star sits beside the file name (the top line), not between the two lines.
			if let image = cell.imageView, let text = cell.textField {
				cell.constraints.filter { $0.firstItem === image && $0.firstAttribute == .centerY }.forEach { $0.isActive = false }
				image.centerYAnchor.constraint(equalTo: text.topAnchor, constant: 8).isActive = true
			}
			cell.toolTip = "\(f.siteLabel): /\(f.path)"
		}
		return cell
	}

	/// An SF Symbol drawn in a fixed colour (tinting alone can render grey in sidebars).
	static func symbol(_ name: String, _ color: NSColor) -> NSImage? {
		NSImage(systemSymbolName: name, accessibilityDescription: nil)?
			.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
	}

	func outlineViewSelectionDidChange(_ notification: Notification) {
		guard !reloading, outline.selectedRow >= 0 else { return }
		// Clicking a project (or a file inside one) makes it the current project.
		let item = outline.item(atRow: outline.selectedRow)
		if let p = item as? FavoriteProject { store.setCurrent(p) } else if let f = item as? FavoriteItem, let p = store.project(containing: f) { store.setCurrent(p) }
	}

	func outlineViewItemDidExpand(_ notification: Notification) {
		if !reloading, let p = notification.userInfo?["NSObject"] as? FavoriteProject { store.setExpanded(p, true) }
	}

	func outlineViewItemDidCollapse(_ notification: Notification) {
		if !reloading, let p = notification.userInfo?["NSObject"] as? FavoriteProject { store.setExpanded(p, false) }
	}

	// MARK: Drag and drop

	func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
		guard let f = item as? FavoriteItem else { return nil }
		let pb = NSPasteboardItem()
		pb.setString(f.id, forType: .favorite)
		return pb
	}

	func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
		let types = info.draggingPasteboard.types ?? []
		guard types.contains(.favorite) || types.contains(.ftpFile) else { return [] }
		if let f = item as? FavoriteItem {
			// Dropping onto a file means "next to it", in its project.
			let p = store.project(containing: f)
			let siblings = p.map { pr in shownProjects.first { $0.0 === pr }?.1 ?? [] } ?? shownLoose
			let i = siblings.firstIndex { $0 === f } ?? siblings.count
			outlineView.setDropItem(p, dropChildIndex: p == nil ? shownProjects.count + i : i)
		} else if item == nil && index >= 0 && index < shownProjects.count {
			// Between projects at the top level: outside any project, at the start of the loose files.
			outlineView.setDropItem(nil, dropChildIndex: shownProjects.count)
		}
		return types.contains(.favorite) ? .move : .copy
	}

	func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
		let project = item as? FavoriteProject
		let filtering = !filter.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
		var at: Int? = index < 0 || filtering ? nil : index
		if project == nil, let a = at { at = max(0, a - shownProjects.count) }
		let pbItems = info.draggingPasteboard.pasteboardItems ?? []
		let ids = pbItems.compactMap { $0.string(forType: .favorite) }
		if !ids.isEmpty {
			let all = store.projects.flatMap(\.items) + store.loose
			let moving = ids.compactMap { id in all.first { $0.id == id } }
			store.move(moving, to: project, at: at)
			if let project { store.setCurrent(project) }
			return true
		}
		let files: [FTPFileRef] = pbItems.compactMap { pb in
			guard let data = pb.data(forType: .ftpFile),
				  let d = try? JSONSerialization.jsonObject(with: data) as? [String: String],
				  let site = d["siteID"], let path = d["path"] else { return nil }
			return (site, path, d["siteName"] ?? "")
		}
		guard !files.isEmpty else { return false }
		store.add(files.map { (siteID: $0.siteID, path: $0.path, siteName: $0.siteName) }, to: project)
		if let project { store.setCurrent(project) }
		return true
	}
}

/// The outline view, with Delete / Backspace removing the selection.
final class KeyOutlineView: NSOutlineView {
	var onDelete: (() -> Void)?

	override func keyDown(with event: NSEvent) {
		if event.keyCode == 51 || event.keyCode == 117 { onDelete?() } else { super.keyDown(with: event) }
	}
}

/// Lets a closure be a menu item's action.
final class MenuAction: NSObject {
	private let action: () -> Void
	init(_ action: @escaping () -> Void) { self.action = action }
	@objc func run() { action() }
}

/// The guided step when files are added with no project selected: pick a project or name a new one.
enum ProjectPicker {
	/// What the step offers: existing projects (most recent first) and a suggested new name.
	static func offer(for files: [FTPFileRef], store: FavoritesStore) -> (projects: [FavoriteProject], suggestedName: String) {
		let site = files.first?.siteName ?? ""
		return (Array(store.recentProjects.prefix(8)), site.isEmpty ? "New project" : site)
	}

	static func choose(for files: [FTPFileRef], store: FavoritesStore) -> FavoriteProject? {
		let offer = offer(for: files, store: store)
		let what = files.count == 1 ? "“\((files[0].path as NSString).lastPathComponent)”" : "\(files.count) files"
		let alert = NSAlert()
		alert.messageText = "Add \(what) to a project"
		alert.informativeText = offer.projects.isEmpty
			? "Projects keep the files you're working on together, from any of your sites. Name your first one:"
			: "Choose a project, or start a new one."

		let controller = PickerController(projects: offer.projects, suggested: offer.suggestedName)
		alert.accessoryView = controller.view
		alert.addButton(withTitle: "Add")
		alert.addButton(withTitle: "Cancel")
		alert.window.initialFirstResponder = offer.projects.isEmpty ? controller.nameField : nil
		guard alert.runModal() == .alertFirstButtonReturn else { return nil }

		let makeCurrent = controller.makeCurrent.state == .on
		if let p = controller.chosenProject {
			if makeCurrent { store.setCurrent(p) }
			return p
		}
		return store.newProject(named: controller.nameField.stringValue, makeCurrent: makeCurrent)
	}

	/// The radio list inside the alert.
	final class PickerController: NSObject, NSTextFieldDelegate {
		let view: NSView
		let nameField = NSTextField()
		let makeCurrent = NSButton(checkboxWithTitle: "Make this the current project", target: nil, action: nil)
		private var radios: [NSButton] = []
		private let projects: [FavoriteProject]

		init(projects: [FavoriteProject], suggested: String) {
			self.projects = projects
			let stack = NSStackView()
			stack.orientation = .vertical
			stack.alignment = .leading
			stack.spacing = 6
			view = stack
			super.init()
			for p in projects {
				let r = NSButton(radioButtonWithTitle: p.name, target: self, action: #selector(radioClicked(_:)))
				radios.append(r)
				stack.addArrangedSubview(r)
			}
			let newRadio = NSButton(radioButtonWithTitle: "New project:", target: self, action: #selector(radioClicked(_:)))
			radios.append(newRadio)
			nameField.stringValue = suggested
			nameField.placeholderString = "Project name"
			nameField.delegate = self
			nameField.widthAnchor.constraint(equalToConstant: 200).isActive = true
			let row = NSStackView(views: [newRadio, nameField])
			row.spacing = 6
			stack.addArrangedSubview(row)
			makeCurrent.state = .on
			stack.addArrangedSubview(makeCurrent)
			stack.setCustomSpacing(12, after: row)
			select(projects.isEmpty ? newRadio : radios[0])
			stack.layoutSubtreeIfNeeded()
			stack.frame.size = stack.fittingSize
		}

		private func select(_ r: NSButton) {
			for b in radios { b.state = b === r ? .on : .off }
		}

		@objc private func radioClicked(_ sender: NSButton) { select(sender) }

		func controlTextDidChange(_ obj: Notification) { select(radios.last!) }

		var chosenProject: FavoriteProject? {
			guard let i = radios.firstIndex(where: { $0.state == .on }), i < projects.count else { return nil }
			return projects[i]
		}
	}
}
