import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	private var controller: MainWindowController!
	private var pendingURLs: [URL] = []
	private let recentMenu = NSMenu(title: "Open Recent")
	private let syntaxMenu = NSMenu(title: "Syntax")
	private var keyMonitor: Any?

	func applicationDidFinishLaunching(_ notification: Notification) {
		Preferences.register()
		SyntaxLibrary.reload()
		NSApp.mainMenu = buildMenu()
		controller = MainWindowController()

		controller.showWindow(nil)
		// The tabs open at the last quit (FTP files are downloaded again), then files passed on the command line or from Finder.
		let env = ProcessInfo.processInfo.environment
		controller.restoreTabs(Preferences.openFiles, skipRemote: env["IDEPLUS_SNAPSHOT_DIR"] != nil) { [self] in
			let urls = Self.fileArguments().map { URL(fileURLWithPath: $0) } + pendingURLs
			pendingURLs = []
			urls.forEach(controller.open)
			if controller.documents.isEmpty { controller.newUntitled() }
		}
		installKeyMonitor()
		if env["IDEPLUS_SNAPSHOT_DIR"] == nil { DispatchQueue.main.async { self.reportUnreadableData() } }
		if env["IDEPLUS_FAVORITES_DEMO"] != nil { FavoritesStore.shared.loadDemo() }
		if env["IDEPLUS_SNAPSHOT_FTP"] != nil { controller.showFTPPanel(nil) }
		NSApp.activate(ignoringOtherApps: true)
		if let dir = ProcessInfo.processInfo.environment["IDEPLUS_SNAPSHOT_DIR"] { snapshotTabs(to: dir) }
	}

	/// Tells you once when saved sites or favorites couldn't be fully read (for example after going back to an older IDEPlus).
	private func reportUnreadableData() {
		_ = FTPSites.all
		guard !SavedData.problems.isEmpty, let window = controller.window else { return }
		let alert = NSAlert()
		alert.messageText = "Some saved data couldn't be read"
		alert.informativeText = SavedData.problems.joined(separator: "\n") + "\n\nA copy of it was kept in IDEPlus' settings on this Mac, so nothing has been deleted. This can happen after installing an older version of IDEPlus."
		alert.beginSheetModal(for: window)
		SavedData.clearProblems()
	}

	/// Command-line file paths. "-Key value" pairs are AppKit defaults, so the value is skipped too.
	private static func fileArguments() -> [String] {
		var out: [String] = []
		var args = CommandLine.arguments.dropFirst().makeIterator()
		while let a = args.next() {
			if a.hasPrefix("-") { _ = args.next() } else { out.append(a) }
		}
		return out
	}

	/// Debug aid: renders each tab to tab-N.png in `dir`, then quits without saving the session.
	private func snapshotTabs(to dir: String) {
		var i = 0
		func step() {
			guard i < controller.documents.count, let view = controller.window?.contentView else {
				exit(0)
			}
			controller.select(i)
			// IDEPLUS_SNAPSHOT_SCROLL=n scrolls the editor down n points first, leaving a line half visible.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
				if let y = ProcessInfo.processInfo.environment["IDEPLUS_SNAPSHOT_SCROLL"].flatMap(Double.init),
				   let sv = self.controller.current?.editor.scrollView {
					sv.contentView.scroll(to: NSPoint(x: sv.contentView.bounds.origin.x, y: y))
					sv.reflectScrolledClipView(sv.contentView)
				}
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
				if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
					view.cacheDisplay(in: view.bounds, to: rep)
					try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/tab-\(i + 1).png"))
				}
				i += 1
				step()
			}
		}
		// IDEPLUS_SNAPSHOT_EMPTY=1: the no-tabs view, idle (empty.png) and mid-game (empty-game.png).
		if ProcessInfo.processInfo.environment["IDEPLUS_SNAPSHOT_EMPTY"] != nil, let view = controller.window?.contentView {
			func shot(_ name: String) {
				if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
					view.cacheDisplay(in: view.bounds, to: rep)
					try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
				}
			}
			controller.closeAllTabs(nil)
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
				shot("empty")
				self.controller.playEmptyStateDemo()
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { shot("empty-game"); exit(0) }
			}
			return
		}
		// IDEPLUS_SNAPSHOT_SITES=1: the FTP Sites window (sites.png).
		if ProcessInfo.processInfo.environment["IDEPLUS_SNAPSHOT_SITES"] != nil {
			controller.showSiteManager(nil)
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
				if let view = NSApp.windows.first(where: { $0 !== self.controller.window && $0.isVisible })?.contentView,
				   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
					view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
					try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/sites.png"))
				}
				exit(0)
			}
			return
		}
		if ProcessInfo.processInfo.environment["IDEPLUS_SNAPSHOT_FIND"] != nil { controller.showReplaceBar(nil) }
		if ProcessInfo.processInfo.environment["IDEPLUS_SNAPSHOT_CLIPS"] != nil { controller.showClips(nil) }
		DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: step)
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		if let controller {
			urls.forEach(controller.open)
		} else {
			pendingURLs += urls
		}
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		guard let controller else { return .terminateNow }
		Preferences.openFiles = controller.openTabs
		return controller.confirmCloseAll() ? .terminateNow : .terminateCancel
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

	/// Ctrl-Tab / Ctrl-Shift-Tab and Cmd-1…9 switch tabs.
	private func installKeyMonitor() {
		keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard let c = self?.controller, event.window === c.window else { return event }
			let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
			if event.keyCode == 48, mods.contains(.control) {
				if mods.contains(.shift) { c.selectPreviousTab(nil) } else { c.selectNextTab(nil) }
				return nil
			}
			if mods == .command, let ch = event.charactersIgnoringModifiers, let n = Int(ch), (1...9).contains(n) {
				c.selectTab(number: n)
				return nil
			}
			return event
		}
	}

	// MARK: Recent files

	func menuNeedsUpdate(_ menu: NSMenu) {
		if menu === syntaxMenu {
			rebuildSyntaxMenu()
			return
		}
		guard menu === recentMenu else { return }
		menu.removeAllItems()
		let paths = Preferences.recentFiles
		for path in paths {
			let item = NSMenuItem(title: (path as NSString).abbreviatingWithTildeInPath, action: #selector(openRecent(_:)), keyEquivalent: "")
			item.representedObject = path
			item.target = self
			menu.addItem(item)
		}
		if !paths.isEmpty { menu.addItem(.separator()) }
		let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
		clear.target = self
		clear.isEnabled = !paths.isEmpty
		menu.addItem(clear)
	}

	/// All languages, then the syntax folder commands.
	private func rebuildSyntaxMenu() {
		syntaxMenu.removeAllItems()
		for (i, lang) in Language.all.enumerated() {
			if i == 1 { syntaxMenu.addItem(.separator()) }
			syntaxMenu.addItem(item(lang.name, #selector(MainWindowController.selectLanguage(_:)), tag: i))
		}
		syntaxMenu.addItem(.separator())
		let info = NSMenuItem(title: SyntaxLibrary.summary, action: nil, keyEquivalent: "")
		info.isEnabled = false
		syntaxMenu.addItem(info)
		syntaxMenu.addItem(item("Reload Syntax Files", #selector(MainWindowController.reloadSyntaxFiles(_:))))
		syntaxMenu.addItem(item("Open Syntax Folder", #selector(MainWindowController.openSyntaxFolder(_:))))
		syntaxMenu.addItem(item("Choose Syntax Folder…", #selector(MainWindowController.chooseSyntaxFolder(_:))))
	}

	@objc private func openRecent(_ sender: NSMenuItem) {
		guard let path = sender.representedObject as? String else { return }
		controller.open(URL(fileURLWithPath: path))
	}

	@objc private func clearRecent(_ sender: Any?) {
		Preferences.recentFiles = []
	}

	// MARK: Menu bar

	private func item(_ title: String, _ action: Selector?, _ key: String = "",
					  _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
		let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
		i.keyEquivalentModifierMask = mods
		i.tag = tag
		return i
	}

	private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
		let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
		let menu = NSMenu(title: title)
		items.forEach(menu.addItem)
		parent.submenu = menu
		return parent
	}

	private func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
		submenu(title, items)
	}

	private func key(_ functionKey: Int) -> String {
		String(Character(UnicodeScalar(functionKey)!))
	}

	private func buildMenu() -> NSMenu {
		let main = NSMenu()
		let sep = { NSMenuItem.separator() }

		main.addItem(menu("IDEPlus", [
			item("About IDEPlus", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""),
			sep(),
			item("Hide IDEPlus", #selector(NSApplication.hide(_:)), "h"),
			item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
			item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""),
			sep(),
			item("Quit IDEPlus", #selector(NSApplication.terminate(_:)), "q"),
		]))

		let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
		recent.submenu = recentMenu
		recentMenu.delegate = self
		main.addItem(menu("File", [
			item("New", #selector(MainWindowController.newDocument(_:)), "n"),
			item("Open…", #selector(MainWindowController.openDocument(_:)), "o"),
			item("Open Folder…", #selector(MainWindowController.openFolder(_:)), "o", [.command, .shift]),
			recent,
			sep(),
			item("Open from FTP…", #selector(MainWindowController.showFTPPanel(_:)), "o", [.command, .control]),
			item("FTP Sites…", #selector(MainWindowController.showSiteManager(_:)), "f", [.command, .shift]),
			item("Show FTP Temporary Folder", #selector(MainWindowController.showFTPTemporaryFolder(_:)), ""),
			sep(),
			item("Close", #selector(MainWindowController.closeTab(_:)), "w"),
			item("Close All", #selector(MainWindowController.closeAllTabs(_:)), "w", [.command, .option]),
			sep(),
			item("Save", #selector(MainWindowController.saveDocument(_:)), "s"),
			item("Save As…", #selector(MainWindowController.saveDocumentAs(_:)), "s", [.command, .shift]),
			item("Save All", #selector(MainWindowController.saveAllDocuments(_:)), "s", [.command, .option]),
			sep(),
			item("Reload from Disk", #selector(MainWindowController.reloadDocument(_:)), "r"),
			submenu("Reopen with Encoding", FileEncoding.all.enumerated().map {
				item($1.name, #selector(MainWindowController.reopenWithEncoding(_:)), tag: $0)
			}),
			sep(),
			item("Reveal in Finder", #selector(MainWindowController.revealInFinder(_:)), "r", [.command, .shift]),
			item("View in Browser", #selector(MainWindowController.viewInBrowser(_:)), "b"),
			sep(),
			item("Print…", #selector(NSView.printView(_:)), "p"),
		]))

		main.addItem(menu("Edit", [
			item("Undo", Selector(("undo:")), "z"),
			item("Redo", Selector(("redo:")), "z", [.command, .shift]),
			sep(),
			item("Cut", #selector(NSText.cut(_:)), "x"),
			item("Copy", #selector(NSText.copy(_:)), "c"),
			item("Paste", #selector(NSText.paste(_:)), "v"),
			item("Delete", #selector(NSText.delete(_:)), ""),
			item("Select All", #selector(NSText.selectAll(_:)), "a"),
			sep(),
			item("Duplicate Line", #selector(EditorTextView.duplicateLine(_:)), "d"),
			item("Delete Line", #selector(EditorTextView.deleteCurrentLine(_:)), "k", [.command, .shift]),
			item("Move Line Up", #selector(EditorTextView.moveLinesUp(_:)), key(NSUpArrowFunctionKey), [.command, .control]),
			item("Move Line Down", #selector(EditorTextView.moveLinesDown(_:)), key(NSDownArrowFunctionKey), [.command, .control]),
			item("Join Lines", #selector(EditorTextView.joinLines(_:)), "j"),
			sep(),
			item("Insert Date/Time", #selector(EditorTextView.insertDateTime(_:)), key(NSF5FunctionKey), []),
		]))

		main.addItem(menu("Search", [
			item("Find…", #selector(MainWindowController.showFindBar(_:)), "f"),
			item("Replace…", #selector(MainWindowController.showReplaceBar(_:)), "f", [.command, .option]),
			item("Find Next", #selector(MainWindowController.findNextMatch(_:)), "g"),
			item("Find Previous", #selector(MainWindowController.findPreviousMatch(_:)), "g", [.command, .shift]),
			item("Use Selection for Find", #selector(MainWindowController.useSelectionForFind(_:)), "e"),
			sep(),
			item("Go to Line…", #selector(MainWindowController.goToLine(_:)), "l"),
		]))

		let syntaxItem = NSMenuItem(title: "Syntax", action: nil, keyEquivalent: "")
		syntaxItem.submenu = syntaxMenu
		syntaxMenu.delegate = self
		rebuildSyntaxMenu()
		main.addItem(menu("Document", [
			syntaxItem,
			submenu("Encoding (for Saving)", FileEncoding.all.enumerated().map {
				item($1.name, #selector(MainWindowController.selectEncoding(_:)), tag: $0)
			}),
			submenu("Line Ending", LineEnding.allCases.enumerated().map {
				item($1.label, #selector(MainWindowController.selectLineEnding(_:)), tag: $0)
			}),
			sep(),
			submenu("Tab Width", [2, 3, 4, 8].map { item("\($0)", #selector(MainWindowController.selectTabWidth(_:)), tag: $0) }),
			item("Insert Spaces for Tabs", #selector(MainWindowController.toggleUseSpaces(_:))),
			item("Word Wrap", #selector(MainWindowController.toggleWordWrap(_:)), "w", [.control, .shift]),
			item("Smart Editing (auto-close brackets, quotes, tags)", #selector(MainWindowController.toggleSmartEditing(_:))),
			item("Auto-completion (word + Space)", #selector(MainWindowController.toggleAutoComplete(_:))),
			sep(),
			submenu("Format", [
				item("Toggle Comment", #selector(EditorTextView.toggleLineComment(_:)), "/"),
				item("Indent", #selector(EditorTextView.indentLines(_:)), "]"),
				item("Unindent", #selector(EditorTextView.unindentLines(_:)), "["),
				sep(),
				item("UPPERCASE", #selector(EditorTextView.makeUppercase(_:)), "u", [.command, .shift]),
				item("lowercase", #selector(EditorTextView.makeLowercase(_:)), "l", [.command, .shift]),
				item("Capitalize", #selector(EditorTextView.makeCapitalized(_:))),
				item("Invert Case", #selector(EditorTextView.invertCase(_:))),
				sep(),
				item("Sort Lines Ascending", #selector(EditorTextView.sortLinesAscending(_:))),
				item("Sort Lines Descending", #selector(EditorTextView.sortLinesDescending(_:))),
				item("Remove Duplicate Lines", #selector(EditorTextView.removeDuplicateLines(_:))),
				item("Trim Trailing Whitespace", #selector(EditorTextView.trimTrailingWhitespace(_:))),
				sep(),
				item("Tabs to Spaces", #selector(EditorTextView.convertTabsToSpaces(_:))),
				item("Leading Spaces to Tabs", #selector(EditorTextView.convertLeadingSpacesToTabs(_:))),
			]),
		]))

		main.addItem(menu("View", [
			item("Directory Window", #selector(MainWindowController.toggleDirectoryWindow(_:)), "d", [.command, .shift]),
			item("Clip Library", #selector(MainWindowController.showClips(_:)), "c", [.command, .control]),
			item("Line Numbers", #selector(MainWindowController.toggleLineNumbers(_:)), "l", [.control, .shift]),
			item("Highlight Current Line", #selector(MainWindowController.toggleCurrentLineHighlight(_:))),
			item("Modern Look (VS Code colors, indent guides)", #selector(MainWindowController.toggleModernLook(_:))),
			sep(),
			submenu("Font", Preferences.fontChoices.map { item($0, #selector(MainWindowController.selectEditorFont(_:))) }),
			item("Bigger", #selector(MainWindowController.increaseFontSize(_:)), "="),
			item("Smaller", #selector(MainWindowController.decreaseFontSize(_:)), "-"),
			item("Actual Size", #selector(MainWindowController.resetFontSize(_:)), "0"),
			sep(),
			item("Next Tab", #selector(MainWindowController.selectNextTab(_:)), "]", [.command, .shift]),
			item("Previous Tab", #selector(MainWindowController.selectPreviousTab(_:)), "[", [.command, .shift]),
		]))

		main.addItem(menu("Favorites", [
			item("Add Current File to Project", #selector(MainWindowController.addCurrentToProject(_:)), "a", [.command, .shift]),
			item("New Project…", #selector(MainWindowController.newFavoritesProject(_:))),
			item("Open All in Current Project", #selector(MainWindowController.openCurrentProject(_:))),
			sep(),
			item("Show Favorites Panel", #selector(MainWindowController.toggleFavoritesPanel(_:))),
		]))

		let window = menu("Window", [
			item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
			item("Zoom", #selector(NSWindow.performZoom(_:)), ""),
		])
		NSApp.windowsMenu = window.submenu
		main.addItem(window)
		return main
	}
}
