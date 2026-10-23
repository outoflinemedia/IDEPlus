import AppKit

/// Add, edit and remove FTP sites. Passwords go straight to the Keychain.
final class SiteManagerWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
	private var sites = FTPSites.all
	private let table = NSTableView()
	private let nameField = NSTextField()
	private let hostField = NSTextField()
	private let portField = NSTextField()
	private let userField = NSTextField()
	private let passwordField = NSSecureTextField()
	private let rootField = NSTextField()
	private let secureBox = NSButton(checkboxWithTitle: "Use FTPS (FTP over TLS, encrypted)", target: nil, action: nil)
	private let mismatchBox = NSButton(checkboxWithTitle: "Allow certificate name mismatch", target: nil, action: nil)
	private let testButton = NSButton(title: "Test Connection", target: nil, action: nil)
	private var form: NSView!
	var onChange: (() -> Void)?

	init() {
		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360), styleMask: [.titled, .closable],
							  backing: .buffered, defer: false)
		window.title = "FTP Sites"
		super.init(window: window)
		build()
		if !sites.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
		showSelected()
	}

	required init?(coder: NSCoder) { fatalError("not used") }

	private func build() {
		guard let content = window?.contentView else { return }
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
		table.addTableColumn(column)
		table.headerView = nil
		table.dataSource = self
		table.delegate = self
		table.style = .sourceList
		let scroll = NSScrollView()
		scroll.documentView = table
		scroll.hasVerticalScroller = true
		scroll.borderType = .bezelBorder

		let add = NSButton(image: NSImage(named: NSImage.addTemplateName)!, target: self, action: #selector(addSite))
		let remove = NSButton(image: NSImage(named: NSImage.removeTemplateName)!, target: self, action: #selector(removeSite))
		for b in [add, remove] { b.bezelStyle = .smallSquare }
		let buttons = NSStackView(views: [add, remove])
		buttons.spacing = 0
		let left = NSStackView(views: [scroll, buttons])
		left.orientation = .vertical
		left.alignment = .leading
		left.spacing = 0
		scroll.widthAnchor.constraint(equalToConstant: 180).isActive = true

		for f in [nameField, hostField, portField, userField, passwordField, rootField] {
			f.delegate = self
			f.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
		}
		hostField.placeholderString = "ftp.example.com"
		portField.placeholderString = "21"
		passwordField.placeholderString = "Not saved"
		rootField.placeholderString = "public_html (blank = login folder)"
		for b in [secureBox, mismatchBox] {
			b.target = self
			b.action = #selector(fieldChanged)
		}
		mismatchBox.toolTip = "Needed when the server's certificate is issued for a different name than the host you type. Less secure."
		testButton.target = self
		testButton.action = #selector(testConnection)
		let done = NSButton(title: "Done", target: self, action: #selector(closeWindow))
		done.keyEquivalent = "\r"

		func label(_ s: String) -> NSTextField {
			let l = NSTextField(labelWithString: s)
			l.alignment = .right
			return l
		}
		let grid = NSGridView(views: [
			[label("Name:"), nameField],
			[label("Host:"), hostField],
			[label("Port:"), portField],
			[label("Username:"), userField],
			[label("Password:"), passwordField],
			[label("Start folder:"), rootField],
			[NSGridCell.emptyContentView, secureBox],
			[NSGridCell.emptyContentView, mismatchBox],
		])
		grid.rowSpacing = 8
		grid.column(at: 0).xPlacement = .trailing
		let actions = NSStackView(views: [testButton, NSView(), done])
		let privacy = Self.privacyNote()
		let right = NSStackView(views: [grid, NSView(), privacy, actions])
		right.orientation = .vertical
		right.alignment = .leading
		actions.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
		privacy.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
		form = grid

		let main = NSStackView(views: [left, right])
		main.spacing = 16
		main.alignment = .top
		main.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
		main.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(main)
		NSLayoutConstraint.activate([
			main.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			main.trailingAnchor.constraint(equalTo: content.trailingAnchor),
			main.topAnchor.constraint(equalTo: content.topAnchor),
			main.bottomAnchor.constraint(equalTo: content.bottomAnchor),
			left.heightAnchor.constraint(equalTo: right.heightAnchor),
		])
	}

	private var selectedIndex: Int? {
		let r = table.selectedRow
		return sites.indices.contains(r) ? r : nil
	}

	private func showSelected() {
		let enabled = selectedIndex != nil
		for c in [nameField, hostField, portField, userField, passwordField, rootField, secureBox, mismatchBox, testButton] as [NSControl] {
			c.isEnabled = enabled
		}
		guard let i = selectedIndex else {
			for f in [nameField, hostField, portField, userField, passwordField, rootField] { f.stringValue = "" }
			return
		}
		let s = sites[i]
		nameField.stringValue = s.name
		hostField.stringValue = s.host
		portField.stringValue = "\(s.port)"
		userField.stringValue = s.username
		rootField.stringValue = s.rootPath
		passwordField.stringValue = ""
		passwordField.placeholderString = Keychain.hasPassword(for: s.id) ? "Saved in Keychain (type to change)" : "Not saved (asked when connecting)"
		secureBox.state = s.secure ? .on : .off
		mismatchBox.state = s.allowCertMismatch ? .on : .off
	}

	private func save() {
		FTPSites.all = sites
		onChange?()
	}

	@objc private func fieldChanged() {
		guard let i = selectedIndex else { return }
		sites[i].name = nameField.stringValue.isEmpty ? "Untitled" : nameField.stringValue
		sites[i].host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
			.replacingOccurrences(of: "ftp://", with: "").replacingOccurrences(of: "/", with: "")
		sites[i].port = Int(portField.stringValue) ?? 21
		sites[i].username = userField.stringValue.trimmingCharacters(in: .whitespaces)
		sites[i].rootPath = rootField.stringValue.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
		sites[i].secure = secureBox.state == .on
		sites[i].allowCertMismatch = mismatchBox.state == .on
		table.reloadData(forRowIndexes: [i], columnIndexes: [0])
		save()
	}

	func controlTextDidChange(_ obj: Notification) {
		guard (obj.object as? NSTextField) !== passwordField else { return }
		fieldChanged()
	}

	func controlTextDidEndEditing(_ obj: Notification) {
		guard (obj.object as? NSTextField) === passwordField, let i = selectedIndex, !passwordField.stringValue.isEmpty else { return }
		Keychain.setPassword(passwordField.stringValue, for: sites[i].id)
		showSelected()
	}

	@objc private func addSite() {
		sites.append(FTPSite())
		save()
		table.reloadData()
		table.selectRowIndexes([sites.count - 1], byExtendingSelection: false)
		window?.makeFirstResponder(nameField)
	}

	@objc private func removeSite() {
		guard let i = selectedIndex else { return }
		let alert = NSAlert()
		alert.messageText = "Remove “\(sites[i].name)”?"
		alert.informativeText = "Its saved password is removed from the Keychain too. Files on the server are not touched."
		alert.addButton(withTitle: "Remove")
		alert.addButton(withTitle: "Cancel")
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		Keychain.deletePassword(for: sites[i].id)
		sites.remove(at: i)
		save()
		table.reloadData()
		showSelected()
	}

	@objc private func testConnection() {
		guard let i = selectedIndex else { return }
		if !passwordField.stringValue.isEmpty { Keychain.setPassword(passwordField.stringValue, for: sites[i].id) }
		let site = sites[i]
		guard let password = Keychain.password(for: site.id) else {
			info("Enter the password first.", "")
			return
		}
		testButton.isEnabled = false
		testButton.title = "Testing…"
		FTPClient(site: site, password: password).list(site.rootPath) { [weak self] result in
			self?.testButton.isEnabled = true
			self?.testButton.title = "Test Connection"
			switch result {
			case let .success(entries):
				self?.info("Connected.", "/\(site.rootPath) has \(entries.count) item\(entries.count == 1 ? "" : "s").")
			case let .failure(e):
				self?.info("Connection failed.", e.message)
			}
		}
	}

	private func info(_ message: String, _ detail: String) {
		let alert = NSAlert()
		alert.messageText = message
		alert.informativeText = detail
		if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
	}

	@objc private func closeWindow() {
		window?.makeFirstResponder(nil)
		window?.close()
	}

	// MARK: Table

	func numberOfRows(in tableView: NSTableView) -> Int { sites.count }

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let l = NSTextField(labelWithString: sites[row].name)
		l.lineBreakMode = .byTruncatingTail
		return l
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		showSelected()
	}
}

extension SiteManagerWindow {
	/// Where sites and passwords are kept, shown under the form.
	static func privacyNote() -> NSView {
		let icon = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Private") ?? NSImage())
		icon.contentTintColor = .secondaryLabelColor
		icon.setContentHuggingPriority(.required, for: .horizontal)
		let text = NSTextField(wrappingLabelWithString:
			"Your sites stay on this Mac. They're saved only in IDEPlus' settings on this computer, and passwords are kept by macOS in your Keychain, not by IDEPlus. Nothing is sent anywhere except to your own FTP server when you connect. Tick Use FTPS so the login is encrypted on its way there.")
		text.font = .systemFont(ofSize: 11)
		text.textColor = .secondaryLabelColor
		text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let row = NSStackView(views: [icon, text])
		row.alignment = .top
		row.spacing = 6
		return row
	}
}
