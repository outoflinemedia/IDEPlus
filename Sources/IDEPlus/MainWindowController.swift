import AppKit

/// The single main window: directory tree, tabs, find bar, editor, status bar.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
	private(set) var documents: [EditorDocument] = []
	private var currentIndex = -1
	var current: EditorDocument? { documents.indices.contains(currentIndex) ? documents[currentIndex] : nil }

	private let tabBar = TabBarView()
	private let findBar = FindBarView()
	private let statusBar = StatusBarView()
	private let editorHost = NSView()
	/// Shown in place of an editor when every tab is closed.
	private let emptyView = EmptyStateView()
	private let sidebar = SidebarView()
	private var siteManager: SiteManagerWindow?
	private let splitView = NSSplitView()
	private var checkingDisk = false

	init() {
		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
							  styleMask: [.titled, .closable, .miniaturizable, .resizable],
							  backing: .buffered, defer: false)
		window.minSize = NSSize(width: 520, height: 320)
		window.tabbingMode = .disallowed
		window.title = "IDEPlus"
		super.init(window: window)
		window.delegate = self
		buildLayout()
		window.center()
		window.setFrameAutosaveName("IDEPlusMain")
		NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
											   name: NSApplication.didBecomeActiveNotification, object: nil)
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func buildLayout() {
		guard let content = window?.contentView else { return }
		splitView.isVertical = true
		splitView.dividerStyle = .thin
		splitView.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(splitView)
		NSLayoutConstraint.activate([
			splitView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			splitView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			splitView.topAnchor.constraint(equalTo: content.topAnchor),
			splitView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
		])

		let right = NSStackView()
		right.orientation = .vertical
		right.spacing = 0
		right.distribution = .fill
		for v in [tabBar, findBar, editorHost, statusBar] as [NSView] {
			v.translatesAutoresizingMaskIntoConstraints = false
			right.addArrangedSubview(v)
			v.leadingAnchor.constraint(equalTo: right.leadingAnchor).isActive = true
			v.trailingAnchor.constraint(equalTo: right.trailingAnchor).isActive = true
		}
		tabBar.heightAnchor.constraint(equalToConstant: 30).isActive = true
		statusBar.heightAnchor.constraint(equalToConstant: 24).isActive = true
		editorHost.setContentHuggingPriority(.init(1), for: .vertical)
		editorHost.setContentCompressionResistancePriority(.init(1), for: .vertical)
		findBar.isHidden = true
		if #available(macOS 14, *) { editorHost.clipsToBounds = true }
		emptyView.translatesAutoresizingMaskIntoConstraints = false
		emptyView.isHidden = true
		editorHost.addSubview(emptyView)
		NSLayoutConstraint.activate([
			emptyView.leadingAnchor.constraint(equalTo: editorHost.leadingAnchor),
			emptyView.trailingAnchor.constraint(equalTo: editorHost.trailingAnchor),
			emptyView.topAnchor.constraint(equalTo: editorHost.topAnchor),
			emptyView.bottomAnchor.constraint(equalTo: editorHost.bottomAnchor),
		])
		emptyView.onNewFile = { [weak self] in self?.newUntitled() }

		splitView.addArrangedSubview(sidebar)
		splitView.addArrangedSubview(right)
		sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
		right.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
		splitView.setHoldingPriority(.init(260), forSubviewAt: 0)
		splitView.setHoldingPriority(.init(250), forSubviewAt: 1)
		sidebar.isHidden = !Preferences.showDirectory
		DispatchQueue.main.async { [weak self] in self?.splitView.setPosition(230, ofDividerAt: 0) }

		tabBar.onSelect = { [weak self] in self?.select($0) }
		tabBar.onClose = { [weak self] in self?.closeDocument(at: $0) }
		sidebar.local.onOpen = { [weak self] in self?.open($0) }
		sidebar.remote.onOpen = { [weak self] client, path in self?.openRemote(client, path) }
		sidebar.remote.onManageSites = { [weak self] in self?.showSiteManager(nil) }
		sidebar.remote.favorites.onOpen = { [weak self] items in self?.openFavorites(items) }
		sidebar.remote.favorites.onAddCurrent = { [weak self] in self?.addCurrentToProject(nil) }
		tabBar.onStar = { [weak self] i in self?.toggleFavorite(at: i) }
		NotificationCenter.default.addObserver(self, selector: #selector(favoritesChanged), name: .favoritesChanged, object: nil)
		sidebar.clips.onInsert = { [weak self] body in
			guard let tv = self?.current?.editor.textView else { return }
			tv.insertSnippet(body)
			self?.window?.makeFirstResponder(tv)
		}

		findBar.onFind = { [weak self] backward in self?.runFind(backward: backward) }
		findBar.onReplace = { [weak self] in self?.runReplace() }
		findBar.onReplaceAll = { [weak self] in self?.runReplaceAll() }
		findBar.onClose = { [weak self] in self?.hideFindBar() }
		findBar.onOptionsChanged = { [weak self] in self?.updateMatchCount() }

		statusBar.onLanguage = { [weak self] lang in
			self?.current?.language = lang
			self?.updateStatus()
		}
		statusBar.onLineEnding = { [weak self] ending in self?.changeLineEnding(ending) }
		statusBar.onEncoding = { [weak self] enc in self?.changeEncoding(enc) }
	}

	// MARK: Documents

	func addDocument(_ doc: EditorDocument) {
		doc.editor.onTextChange = { [weak self, weak doc] in
			guard let self, let doc else { return }
			if !doc.isDirty {
				doc.isDirty = true
				self.refreshTabs()
				self.updateTitle()
			}
			self.updateStatus()
		}
		doc.editor.onSelectionChange = { [weak self] in self?.updateStatus() }
		documents.append(doc)
		select(documents.count - 1)
	}

	func select(_ index: Int) {
		guard documents.indices.contains(index) else { return }
		if index != currentIndex { current?.editor.removeFromSuperview() }
		currentIndex = index
		emptyView.isHidden = true
		let ed = documents[index].editor
		if ed.superview !== editorHost {
			ed.translatesAutoresizingMaskIntoConstraints = false
			editorHost.addSubview(ed)
			NSLayoutConstraint.activate([
				ed.leadingAnchor.constraint(equalTo: editorHost.leadingAnchor),
				ed.trailingAnchor.constraint(equalTo: editorHost.trailingAnchor),
				ed.topAnchor.constraint(equalTo: editorHost.topAnchor),
				ed.bottomAnchor.constraint(equalTo: editorHost.bottomAnchor),
			])
		}
		window?.makeFirstResponder(ed.textView)
		refreshTabs()
		updateTitle()
		updateStatus()
		updateMatchCount()
	}

	func newUntitled() {
		addDocument(EditorDocument())
	}

	/// Opens a file, or switches to it when it is already open.
	func open(_ url: URL) {
		let url = url.standardizedFileURL
		if let i = documents.firstIndex(where: { $0.url?.standardizedFileURL == url }) {
			select(i)
			return
		}
		var isDir: ObjCBool = false
		if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
			sidebar.local.setRoot(url)
			return
		}
		do {
			if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 50_000_000 {
				guard confirm("“\(url.lastPathComponent)” is \(size / 1_000_000) MB.", "Large files can be slow to edit. Open it anyway?", "Open") else { return }
			}
			let doc = EditorDocument()
			try doc.load(from: url)
			if let cur = current, cur.isEmptyUntitled {
				replaceCurrent(with: doc)
			} else {
				addDocument(doc)
			}
			Preferences.noteRecent(url)
		} catch {
			showError("Couldn't open “\(url.lastPathComponent)”.", error)
		}
	}

	private func replaceCurrent(with doc: EditorDocument) {
		let i = currentIndex
		current?.editor.removeFromSuperview()
		documents.remove(at: i)
		currentIndex = -1
		addDocument(doc)
		let d = documents.removeLast()
		documents.insert(d, at: i)
		select(i)
	}

	func closeDocument(at index: Int) {
		guard documents.indices.contains(index) else { return }
		let doc = documents[index]
		guard confirmClose(doc) else { return }
		doc.editor.removeFromSuperview()
		documents.remove(at: index)
		if documents.isEmpty {
			showEmptyState()
			return
		}
		if index < currentIndex || currentIndex >= documents.count {
			currentIndex -= 1
		}
		let next = min(currentIndex, documents.count - 1)
		currentIndex = -1
		select(max(0, next))
	}

	/// Asks to save a changed document. False means the user cancelled.
	func confirmClose(_ doc: EditorDocument) -> Bool {
		guard doc.isDirty else { return true }
		if let i = documents.firstIndex(where: { $0 === doc }) { select(i) }
		let alert = NSAlert()
		alert.messageText = "Save changes to “\(doc.displayName)”?"
		alert.informativeText = "Your changes will be lost if you don't save them."
		alert.addButton(withTitle: "Save")
		alert.addButton(withTitle: "Cancel")
		alert.addButton(withTitle: "Don't Save")
		switch alert.runModal() {
		case .alertFirstButtonReturn: return save(doc)
		case .alertThirdButtonReturn: return true
		default: return false
		}
	}

	func confirmCloseAll() -> Bool {
		for doc in documents where doc.isDirty {
			if !confirmClose(doc) { return false }
		}
		return true
	}

	@discardableResult
	func save(_ doc: EditorDocument) -> Bool {
		guard let url = doc.url else { return saveAs(doc) }
		do {
			try doc.save(to: url)
		} catch {
			showError("Couldn't save “\(doc.displayName)”.", error)
			return false
		}
		if doc.remote != nil { upload(doc) }
		refreshTabs()
		updateTitle()
		updateStatus()
		return true
	}

	// MARK: FTP

	/// Opens a file from the server: downloads it to a local copy, which is uploaded again on every save.
	/// `quiet` reports a failed download in the status bar instead of an alert (used when reopening tabs at launch).
	func openRemote(_ client: FTPClient, _ path: String, quiet: Bool = false, done: ((Bool) -> Void)? = nil) {
		if let i = documents.firstIndex(where: { $0.remote?.client.site.id == client.site.id && $0.remote?.path == path }) {
			select(i)
			done?(true)
			return
		}
		let local = client.cacheURL(for: path)
		statusBar.setMessage("Downloading \(path)…")
		client.download(path, to: local) { [weak self] result in
			guard let self else { return }
			switch result {
			case .success:
				let doc = EditorDocument()
				do {
					try doc.load(from: local)
				} catch {
					if quiet { self.statusBar.setMessage("Couldn't open \(path)", error: true) } else { self.showError("Couldn't open “\(path)”.", error) }
					done?(false)
					return
				}
				doc.remote = EditorDocument.RemoteFile(client: client, path: path)
				if let cur = self.current, cur.isEmptyUntitled { self.replaceCurrent(with: doc) } else { self.addDocument(doc) }
				self.statusBar.setMessage("Opened \(client.site.host)/\(path)")
				done?(true)
			case let .failure(error):
				if quiet { self.statusBar.setMessage("Couldn't reopen \(client.site.host)/\(path)", error: true) } else {
					self.statusBar.setMessage("")
					self.showError("Couldn't download “\(path)”.", error)
				}
				done?(false)
			}
		}
	}

	private func upload(_ doc: EditorDocument) {
		guard let remote = doc.remote, let local = doc.url else { return }
		doc.uploadState = .uploading
		statusBar.setMessage("Uploading \(remote.path)…")
		remote.client.upload(local, to: remote.path) { [weak self, weak doc] result in
			guard let self, let doc else { return }
			switch result {
			case .success:
				doc.uploadState = .idle
				let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
				self.statusBar.setMessage("✓ Uploaded \(remote.path) to \(remote.client.site.host) at \(time)")
			case let .failure(error):
				doc.uploadState = .failed
				doc.isDirty = true
				self.statusBar.setMessage("⚠︎ Upload failed: \(remote.path)", error: true)
				let alert = NSAlert()
				alert.alertStyle = .warning
				alert.messageText = "“\(doc.displayName)” was saved locally but NOT uploaded."
				alert.informativeText = error.message
				alert.addButton(withTitle: "Try Again")
				alert.addButton(withTitle: "Later")
				if alert.runModal() == .alertFirstButtonReturn { self.upload(doc) }
			}
			self.refreshTabs()
			self.updateTitle()
		}
	}

	// MARK: Favorites

	@objc private func favoritesChanged() { refreshTabs() }

	/// Opens favorites, connecting to each one's site first if needed.
	func openFavorites(_ items: [FavoriteItem]) {
		for item in items {
			guard FTPSites.site(id: item.siteID) != nil else {
				let alert = NSAlert()
				alert.messageText = "The site for “\(item.name)” isn't in your FTP Sites any more."
				alert.informativeText = "It was on \(item.siteName). Add the site again in File > FTP Sites…, or remove this favorite."
				alert.runModal()
				continue
			}
			guard let client = sidebar.remote.client(for: item.siteID) else { continue }
			openRemote(client, item.path)
		}
	}

	/// The ★ button and Favorites > Add Current File: puts the current tab's FTP file in the current project.
	@objc func addCurrentToProject(_ sender: Any?) {
		guard let doc = current, let remote = doc.remote else {
			let alert = NSAlert()
			alert.messageText = "Open a file from your FTP server first"
			alert.informativeText = "This adds the file in the current tab to a project. To add files without opening them, right-click them in the FTP list and choose Add to Project, or drag them onto a project."
			alert.runModal()
			return
		}
		showFTPPanel(nil)
		if let p = sidebar.remote.favorites.add([(remote.client.site.id, remote.path, remote.client.site.name)]) {
			statusBar.setMessage("★ Added \(doc.displayName) to \(p.name)")
		}
	}

	private func toggleFavorite(at index: Int) {
		guard documents.indices.contains(index), let remote = documents[index].remote else { return }
		let store = FavoritesStore.shared
		if store.isFavorite(siteID: remote.client.site.id, path: remote.path) {
			store.removeEverywhere(siteID: remote.client.site.id, path: remote.path)
			statusBar.setMessage("Removed \(documents[index].displayName) from favorites")
		} else if let p = sidebar.remote.favorites.add([(remote.client.site.id, remote.path, remote.client.site.name)]) {
			statusBar.setMessage("★ Added \(documents[index].displayName) to \(p.name)")
		}
	}

	@objc func newFavoritesProject(_ sender: Any?) {
		showFTPPanel(nil)
		guard let name = FavoritesView.askName(title: "New project", message: "A project groups the files you're working on, from any of your sites.",
											   initial: "", ok: "Create") else { return }
		FavoritesStore.shared.newProject(named: name)
	}

	@objc func openCurrentProject(_ sender: Any?) {
		guard let p = FavoritesStore.shared.currentProject else { return }
		openFavorites(p.items)
	}

	/// Shows (or hides) the panel under the FTP tree; showing it also switches to the FTP tab.
	@objc func toggleFavoritesPanel(_ sender: Any?) {
		Preferences.showFavoritesPanel.toggle()
		if Preferences.showFavoritesPanel { showFTPPanel(nil) }
		FavoritesStore.settingsChanged()
	}

	@objc func showSiteManager(_ sender: Any?) {
		if siteManager == nil {
			siteManager = SiteManagerWindow()
			siteManager?.onChange = { [weak self] in self?.sidebar.remote.reloadSites() }
		}
		siteManager?.window?.center()
		siteManager?.showWindow(nil)
	}

	/// Opens the folder of local copies in Finder (created first if nothing has been opened yet).
	@objc func showFTPTemporaryFolder(_ sender: Any?) {
		let folder = FTPClient.cacheFolder
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		NSWorkspace.shared.open(folder)
	}

	@objc func showFTPPanel(_ sender: Any?) {
		if sidebar.isHidden { toggleDirectoryWindow(nil) }
		sidebar.showsRemote = true
	}

	@discardableResult
	func saveAs(_ doc: EditorDocument) -> Bool {
		let panel = NSSavePanel()
		panel.nameFieldStringValue = doc.displayName
		panel.directoryURL = doc.url?.deletingLastPathComponent() ?? Preferences.lastFolder.map { URL(fileURLWithPath: $0) }
		panel.isExtensionHidden = false
		panel.canCreateDirectories = true
		guard panel.runModal() == .OK, let url = panel.url else { return false }
		do {
			try doc.save(to: url)
			Preferences.noteRecent(url)
		} catch {
			showError("Couldn't save “\(url.lastPathComponent)”.", error)
			return false
		}
		refreshTabs()
		updateTitle()
		updateStatus()
		return true
	}

	/// The open tabs, in order, saved at quit: a local file's path, or "ftp://<site id>/<path>" for a file on a server.
	var openTabs: [String] {
		documents.compactMap { doc in
			if let r = doc.remote { return "ftp://\(r.client.site.id)/\(r.path)" }
			return doc.url?.path
		}
	}

	/// Reopens saved tabs in order, one at a time; files on a server are downloaded again.
	/// A site whose password you cancel, or that is no longer in FTP Sites, is skipped.
	func restoreTabs(_ entries: [String], skipRemote: Bool = false, then finish: @escaping () -> Void) {
		var rest = entries[...]
		var skippedSites = Set<String>()
		func next() {
			guard let entry = rest.popFirst() else { return finish() }
			if entry.hasPrefix("ftp://") {
				let parts = entry.dropFirst(6).split(separator: "/", maxSplits: 1).map(String.init)
				guard !skipRemote, parts.count == 2, !skippedSites.contains(parts[0]),
					  FTPSites.site(id: parts[0]) != nil else { return next() }
				guard let client = sidebar.remote.client(for: parts[0]) else {
					skippedSites.insert(parts[0])
					return next()
				}
				openRemote(client, parts[1], quiet: true) { _ in next() }
			} else {
				if FileManager.default.fileExists(atPath: entry) { open(URL(fileURLWithPath: entry)) }
				next()
			}
		}
		next()
	}

	// MARK: UI refresh

	private func refreshTabs() {
		tabBar.items = documents.map { doc in
			let mark = doc.uploadState == .uploading ? " ↑" : doc.uploadState == .failed ? " ⚠︎" : ""
			let star = doc.remote.map { FavoritesStore.shared.isFavorite(siteID: $0.client.site.id, path: $0.path) }
			return TabBarView.Item(title: doc.displayName + mark, dirty: doc.isDirty, tooltip: doc.location, star: star)
		}
		tabBar.selectedIndex = currentIndex
	}

	private func updateTitle() {
		guard let window else { return }
		guard let doc = current else {
			window.title = "IDEPlus"
			window.subtitle = ""
			window.representedURL = nil
			window.isDocumentEdited = false
			return
		}
		window.title = doc.displayName
		window.subtitle = doc.remote != nil ? (doc.location as NSString).deletingLastPathComponent : doc.url?.deletingLastPathComponent().path ?? ""
		window.representedURL = doc.remote == nil ? doc.url : nil
		window.isDocumentEdited = doc.isDirty
	}

	private func updateStatus() {
		statusBar.update(current)
	}

	// MARK: Find

	private func showFind(replace: Bool) {
		findBar.showsReplace = replace
		findBar.isHidden = false
		if let tv = current?.editor.textView {
			let sel = tv.selectedRange()
			if sel.length > 0 && sel.length < 200 {
				let s = (tv.string as NSString).substring(with: sel)
				if !s.contains("\n") { findBar.findField.stringValue = s }
			}
		}
		window?.makeFirstResponder(findBar.findField)
		findBar.findField.currentEditor()?.selectAll(nil)
		updateMatchCount()
	}

	private func hideFindBar() {
		findBar.isHidden = true
		if let tv = current?.editor.textView { window?.makeFirstResponder(tv) }
	}

	private func runFind(backward: Bool) {
		guard let ed = current?.editor else { return }
		switch ed.find(findBar.options, backward: backward) {
		case let .found(i, total, wrapped):
			findBar.setStatus("\(i) of \(total)" + (wrapped ? " (wrapped)" : ""))
		case .notFound:
			findBar.setStatus("Not found", error: true)
			NSSound.beep()
		case let .invalid(msg):
			findBar.setStatus(msg, error: true)
		case .empty:
			findBar.setStatus("")
		}
	}

	private func runReplace() {
		guard let ed = current?.editor else { return }
		_ = ed.replaceCurrent(findBar.options)
		runFind(backward: false)
	}

	private func runReplaceAll() {
		guard let ed = current?.editor else { return }
		let n = ed.replaceAll(findBar.options)
		findBar.setStatus(n == 0 ? "Not found" : "Replaced \(n)", error: n == 0)
	}

	private func updateMatchCount() {
		guard !findBar.isHidden, let ed = current?.editor else { return }
		let opt = findBar.options
		if opt.query.isEmpty {
			findBar.setStatus("")
		} else if (try? opt.makeRegex()) == nil {
			findBar.setStatus("Invalid regular expression", error: true)
		} else {
			let n = ed.countMatches(opt)
			findBar.setStatus(n == 1 ? "1 match" : "\(n) matches", error: n == 0)
		}
	}

	// MARK: Encoding and line endings

	private func changeEncoding(_ enc: FileEncoding) {
		guard let doc = current, doc.encoding != enc else { return }
		doc.encoding = enc
		markDirty(doc)
	}

	private func changeLineEnding(_ ending: LineEnding) {
		guard let doc = current, doc.lineEnding != ending else { return }
		doc.lineEnding = ending
		markDirty(doc)
	}

	private func markDirty(_ doc: EditorDocument) {
		doc.isDirty = true
		refreshTabs()
		updateTitle()
		updateStatus()
	}

	// MARK: Disk changes

	@objc private func appBecameActive() {
		guard !checkingDisk else { return }
		checkingDisk = true
		defer { checkingDisk = false }
		for doc in documents where doc.remote == nil {
			guard let url = doc.url, let date = EditorDocument.diskDate(url), let known = doc.modificationDate, date > known else { continue }
			doc.modificationDate = date
			let extra = doc.isDirty ? " Your unsaved changes here will be lost." : ""
			if confirm("“\(doc.displayName)” was changed by another app.", "Reload it from disk?" + extra, "Reload") {
				reload(doc, encoding: nil)
			}
		}
	}

	private func reload(_ doc: EditorDocument, encoding: FileEncoding?) {
		guard let url = doc.url else { return }
		if let remote = doc.remote, encoding == nil {
			// Fetch the server's current copy first.
			remote.client.download(remote.path, to: url) { [weak self] result in
				if case let .failure(error) = result {
					self?.showError("Couldn't download “\(remote.path)”.", error)
					return
				}
				try? doc.load(from: url)
				doc.remote = remote
				self?.refreshTabs()
				self?.updateTitle()
				self?.updateStatus()
			}
			return
		}
		let keepRemote = doc.remote
		defer { doc.remote = keepRemote }
		do {
			try doc.load(from: url, encoding: encoding)
		} catch {
			showError("Couldn't reload “\(doc.displayName)”.", error)
		}
		refreshTabs()
		updateTitle()
		updateStatus()
	}

	// MARK: Alerts

	private func confirm(_ message: String, _ info: String, _ ok: String) -> Bool {
		let alert = NSAlert()
		alert.messageText = message
		alert.informativeText = info
		alert.addButton(withTitle: ok)
		alert.addButton(withTitle: "Cancel")
		return alert.runModal() == .alertFirstButtonReturn
	}

	private func showError(_ message: String, _ error: Error) {
		let alert = NSAlert()
		alert.alertStyle = .warning
		alert.messageText = message
		alert.informativeText = error.localizedDescription
		alert.runModal()
	}

	// MARK: NSWindowDelegate

	func windowShouldClose(_ sender: NSWindow) -> Bool {
		// Closing the only window quits; the app delegate asks about unsaved files.
		NSApp.terminate(nil)
		return false
	}

	func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
		current?.editor.textView.ownUndoManager
	}

	// MARK: Menu actions — File

	@objc func newDocument(_ sender: Any?) { newUntitled() }

	@objc func openDocument(_ sender: Any?) {
		let panel = NSOpenPanel()
		panel.allowsMultipleSelection = true
		panel.canChooseDirectories = false
		panel.directoryURL = current?.url?.deletingLastPathComponent() ?? Preferences.lastFolder.map { URL(fileURLWithPath: $0) }
		guard panel.runModal() == .OK else { return }
		panel.urls.forEach(open)
	}

	@objc func openFolder(_ sender: Any?) {
		if sidebar.isHidden { toggleDirectoryWindow(nil) }
		sidebar.showsRemote = false
		sidebar.local.chooseFolder()
	}

	@objc func closeTab(_ sender: Any?) { closeDocument(at: currentIndex) }

	@objc func closeAllTabs(_ sender: Any?) {
		guard confirmCloseAll() else { return }
		documents.forEach { $0.editor.removeFromSuperview() }
		documents.removeAll()
		showEmptyState()
	}

	/// No tabs: the empty view (with its Space Rocks game) fills the editor area.
	func showEmptyState() {
		currentIndex = -1
		findBar.isHidden = true
		emptyView.isHidden = false
		window?.makeFirstResponder(emptyView)
		refreshTabs()
		updateTitle()
		updateStatus()
	}

	/// Snapshot hook: closes every tab and runs the game for a moment.
	func playEmptyStateDemo() {
		closeAllTabs(nil)
		emptyView.playDemo(seconds: 1.5)
	}

	@objc func saveDocument(_ sender: Any?) {
		if let doc = current { save(doc) }
	}

	@objc func saveDocumentAs(_ sender: Any?) {
		if let doc = current { saveAs(doc) }
	}

	@objc func saveAllDocuments(_ sender: Any?) {
		for doc in documents where doc.isDirty {
			if !save(doc) { break }
		}
	}

	@objc func reloadDocument(_ sender: Any?) {
		guard let doc = current else { return }
		if doc.isDirty && !confirm("Reload “\(doc.displayName)” from disk?", "Your unsaved changes will be lost.", "Reload") { return }
		reload(doc, encoding: nil)
	}

	@objc func reopenWithEncoding(_ sender: NSMenuItem) {
		guard let doc = current else { return }
		if doc.isDirty && !confirm("Reopen “\(doc.displayName)” as \(FileEncoding.all[sender.tag].name)?", "Your unsaved changes will be lost.", "Reopen") { return }
		reload(doc, encoding: FileEncoding.all[sender.tag])
	}

	@objc func revealInFinder(_ sender: Any?) {
		if let url = current?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
	}

	@objc func viewInBrowser(_ sender: Any?) {
		guard let doc = current else { return }
		if doc.isDirty, !save(doc) { return }
		if let url = doc.url { NSWorkspace.shared.open(url) }
	}

	// MARK: Menu actions — Search

	@objc func showFindBar(_ sender: Any?) { showFind(replace: false) }
	@objc func showReplaceBar(_ sender: Any?) { showFind(replace: true) }

	@objc func findNextMatch(_ sender: Any?) {
		if findBar.options.query.isEmpty { showFind(replace: false) } else { runFind(backward: false) }
	}

	@objc func findPreviousMatch(_ sender: Any?) {
		if findBar.options.query.isEmpty { showFind(replace: false) } else { runFind(backward: true) }
	}

	@objc func useSelectionForFind(_ sender: Any?) {
		guard let tv = current?.editor.textView else { return }
		let sel = tv.selectedRange()
		guard sel.length > 0 else { return }
		findBar.findField.stringValue = (tv.string as NSString).substring(with: sel)
		updateMatchCount()
	}

	@objc func goToLine(_ sender: Any?) {
		guard let ed = current?.editor else { return }
		let alert = NSAlert()
		alert.messageText = "Go to Line"
		alert.informativeText = "Line number (1–\(ed.lineCount)):"
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
		field.stringValue = "\(ed.caretPosition().line)"
		alert.accessoryView = field
		alert.addButton(withTitle: "Go")
		alert.addButton(withTitle: "Cancel")
		alert.window.initialFirstResponder = field
		guard alert.runModal() == .alertFirstButtonReturn, let n = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) else { return }
		ed.goToLine(n)
	}

	// MARK: Menu actions — Document

	@objc func selectLanguage(_ sender: NSMenuItem) {
		current?.language = Language.all[sender.tag]
		updateStatus()
	}

	@objc func selectEncoding(_ sender: NSMenuItem) { changeEncoding(FileEncoding.all[sender.tag]) }

	@objc func selectLineEnding(_ sender: NSMenuItem) { changeLineEnding(LineEnding.allCases[sender.tag]) }

	@objc func selectTabWidth(_ sender: NSMenuItem) {
		Preferences.tabWidth = sender.tag
		applyPreferencesToAll()
	}

	@objc func toggleUseSpaces(_ sender: Any?) {
		Preferences.useSpaces.toggle()
	}

	@objc func toggleWordWrap(_ sender: Any?) {
		Preferences.wordWrap.toggle()
		applyPreferencesToAll()
	}

	// MARK: Menu actions — View

	@objc func toggleLineNumbers(_ sender: Any?) {
		Preferences.showLineNumbers.toggle()
		applyPreferencesToAll()
	}

	@objc func toggleCurrentLineHighlight(_ sender: Any?) {
		Preferences.highlightLine.toggle()
		applyPreferencesToAll()
	}

	@objc func toggleDirectoryWindow(_ sender: Any?) {
		Preferences.showDirectory.toggle()
		sidebar.isHidden = !Preferences.showDirectory
		if Preferences.showDirectory {
			DispatchQueue.main.async { [weak self] in
				guard let self, self.sidebar.frame.width < 140 else { return }
				self.splitView.setPosition(230, ofDividerAt: 0)
			}
		}
	}

	@objc func toggleModernLook(_ sender: Any?) {
		Preferences.modernLook.toggle()
		applyPreferencesToAll()
	}

	@objc func toggleSmartEditing(_ sender: Any?) {
		Preferences.smartEditing.toggle()
	}

	@objc func toggleAutoComplete(_ sender: Any?) {
		Preferences.autoComplete.toggle()
	}

	@objc func showClips(_ sender: Any?) {
		if sidebar.isHidden { toggleDirectoryWindow(nil) }
		sidebar.showsClips = true
	}

	// MARK: Syntax files

	@objc func reloadSyntaxFiles(_ sender: Any?) {
		SyntaxLibrary.reload()
		for doc in documents {
			let path = doc.remote?.path ?? doc.url?.path
			let firstLine = String(doc.editor.string.prefix(200).split(separator: "\n", maxSplits: 1).first ?? "")
			doc.language = Language.forURL(path.map { URL(fileURLWithPath: $0) }, firstLine: firstLine)
		}
		statusBar.reloadLanguages()
		sidebar.clips.reload()
		updateStatus()
		statusBar.setMessage(SyntaxLibrary.summary)
	}

	@objc func chooseSyntaxFolder(_ sender: Any?) {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = false
		panel.directoryURL = SyntaxLibrary.folder
		panel.message = "Choose a folder with your own .ipsyntax, .ipsnip and .ipclip files"
		guard panel.runModal() == .OK, let url = panel.url else { return }
		Preferences.syntaxFolder = url.path
		reloadSyntaxFiles(nil)
	}

	/// Your own folder if you chose one, otherwise the files that ship with the app.
	@objc func openSyntaxFolder(_ sender: Any?) {
		NSWorkspace.shared.open(SyntaxLibrary.folder ?? SyntaxLibrary.builtInFolder)
	}

	@objc func selectEditorFont(_ sender: NSMenuItem) {
		Preferences.fontName = sender.title
		applyPreferencesToAll()
	}

	@objc func increaseFontSize(_ sender: Any?) {
		Preferences.fontSize += 1
		applyPreferencesToAll()
	}

	@objc func decreaseFontSize(_ sender: Any?) {
		Preferences.fontSize -= 1
		applyPreferencesToAll()
	}

	@objc func resetFontSize(_ sender: Any?) {
		Preferences.fontSize = 13
		applyPreferencesToAll()
	}

	@objc func selectNextTab(_ sender: Any?) {
		guard documents.count > 1 else { return }
		select((currentIndex + 1) % documents.count)
	}

	@objc func selectPreviousTab(_ sender: Any?) {
		guard documents.count > 1 else { return }
		select((currentIndex - 1 + documents.count) % documents.count)
	}

	func selectTab(number n: Int) {
		// Cmd-9 is always the last tab, as in browsers.
		select(n == 9 ? documents.count - 1 : n - 1)
	}

	private func applyPreferencesToAll() {
		documents.forEach { $0.editor.applyPreferences() }
		updateStatus()
	}

	// MARK: Menu validation

	func validateMenuItem(_ item: NSMenuItem) -> Bool {
		// With no tabs open, commands that work on a document are off.
		let needsDocument: Set<Selector?> = [
			#selector(closeTab(_:)), #selector(closeAllTabs(_:)), #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)),
			#selector(addCurrentToProject(_:)), #selector(showFindBar(_:)), #selector(showReplaceBar(_:)),
			#selector(findNextMatch(_:)), #selector(findPreviousMatch(_:)), #selector(useSelectionForFind(_:)),
			#selector(goToLine(_:)), #selector(selectLanguage(_:)), #selector(selectEncoding(_:)), #selector(selectLineEnding(_:)),
		]
		if current == nil, needsDocument.contains(item.action) { return false }
		switch item.action {
		case #selector(toggleWordWrap(_:)): item.state = Preferences.wordWrap ? .on : .off
		case #selector(toggleLineNumbers(_:)): item.state = Preferences.showLineNumbers ? .on : .off
		case #selector(toggleCurrentLineHighlight(_:)): item.state = Preferences.highlightLine ? .on : .off
		case #selector(toggleDirectoryWindow(_:)): item.state = Preferences.showDirectory ? .on : .off
		case #selector(toggleUseSpaces(_:)): item.state = Preferences.useSpaces ? .on : .off
		case #selector(toggleModernLook(_:)): item.state = Preferences.modernLook ? .on : .off
		case #selector(toggleSmartEditing(_:)): item.state = Preferences.smartEditing ? .on : .off
		case #selector(toggleFavoritesPanel(_:)): item.state = Preferences.showFavoritesPanel ? .on : .off
		case #selector(openCurrentProject(_:)):
			let p = FavoritesStore.shared.currentProject
			item.title = p.map { "Open All in “\($0.name)”" } ?? "Open All in Current Project"
			return p?.items.isEmpty == false
		case #selector(toggleAutoComplete(_:)): item.state = Preferences.autoComplete ? .on : .off
		case #selector(selectTabWidth(_:)): item.state = item.tag == Preferences.tabWidth ? .on : .off
		case #selector(selectEditorFont(_:)): item.state = item.title == Preferences.fontName ? .on : .off
		case #selector(selectLanguage(_:)):
			guard Language.all.indices.contains(item.tag) else { return false }
			item.state = current?.language === Language.all[item.tag] ? .on : .off
		case #selector(selectEncoding(_:)): item.state = current?.encoding == FileEncoding.all[item.tag] ? .on : .off
		case #selector(selectLineEnding(_:)): item.state = current?.lineEnding == LineEnding.allCases[item.tag] ? .on : .off
		case #selector(reloadDocument(_:)), #selector(reopenWithEncoding(_:)):
			return current?.url != nil
		case #selector(revealInFinder(_:)), #selector(viewInBrowser(_:)):
			return current?.url != nil && current?.remote == nil
		case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)):
			return documents.count > 1
		case #selector(saveAllDocuments(_:)):
			return documents.contains { $0.isDirty }
		default: break
		}
		return true
	}
}
