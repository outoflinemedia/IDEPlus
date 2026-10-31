import AppKit

/// The confirmation for Save to FTP: shows the server and the folder the file goes to, the full address it will
/// have, and saves nothing until you click Save to Server.
final class SaveToFTPDialog: NSObject {
	struct Choice {
		let siteID: String
		let path: String
	}

	private let sites: [FTPSite]
	/// The site and folder from the FTP tree; nil when no site is connected (the dialog then offers a site menu).
	private let fixed: (site: FTPSite, folder: String)?
	private let sitePopup = NSPopUpButton(frame: .zero, pullsDown: false)
	private let serverLabel = NSTextField(labelWithString: "")
	private let folderLabel = NSTextField(labelWithString: "")
	private let nameField = NSTextField(string: "")
	private let addressLabel = NSTextField(wrappingLabelWithString: "")
	private var saveButton: NSButton?

	private init(sites: [FTPSite], fixed: (site: FTPSite, folder: String)?, name: String) {
		self.sites = sites
		self.fixed = fixed
		super.init()
		nameField.stringValue = name
	}

	/// Asks where to save; nil if cancelled.
	static func run(sites: [FTPSite], fixed: (site: FTPSite, folder: String)?, name: String) -> Choice? {
		SaveToFTPDialog(sites: sites, fixed: fixed, name: name).run()
	}

	private var site: FTPSite? {
		if let fixed { return fixed.site }
		let i = sitePopup.indexOfSelectedItem
		return sites.indices.contains(i) ? sites[i] : nil
	}

	private var folder: String { fixed?.folder ?? site?.rootPath ?? "" }

	private var path: String? { FTPClient.savePath(folder: folder, name: nameField.stringValue) }

	private static func login(_ site: FTPSite) -> String {
		site.username.isEmpty ? site.host : "\(site.username)@\(site.host)"
	}

	private func run() -> Choice? {
		let alert = makeAlert()
		defer { NotificationCenter.default.removeObserver(self) }
		guard alert.runModal() == .alertFirstButtonReturn, let site, let path else { return nil }
		return Choice(siteID: site.id, path: path)
	}

	/// Snapshot hook (IDEPLUS_SNAPSHOT_SAVEFTP): the dialog's window, laid out but not shown.
	static func previewWindow(sites: [FTPSite], fixed: (site: FTPSite, folder: String)?, name: String) -> NSWindow {
		let d = SaveToFTPDialog(sites: sites, fixed: fixed, name: name)
		let alert = d.makeAlert()
		alert.layout()
		objc_setAssociatedObject(alert.window, "dialog", d, .OBJC_ASSOCIATION_RETAIN)
		return alert.window
	}

	private func makeAlert() -> NSAlert {
		let alert = NSAlert()
		alert.messageText = "Save to the server?"
		alert.informativeText = "Check the server and folder below. Nothing is uploaded until you click Save to Server."
		saveButton = alert.addButton(withTitle: "Save to Server")
		alert.addButton(withTitle: "Cancel")

		for l in [serverLabel, folderLabel] {
			l.font = .systemFont(ofSize: 12, weight: .semibold)
			l.lineBreakMode = .byTruncatingMiddle
			l.isSelectable = true
		}
		addressLabel.font = .systemFont(ofSize: 11)
		addressLabel.textColor = .secondaryLabelColor
		addressLabel.isSelectable = true
		nameField.placeholderString = "file name, e.g. contact.php"
		NotificationCenter.default.addObserver(self, selector: #selector(update), name: NSControl.textDidChangeNotification, object: nameField)

		let serverView: NSView
		if let fixed {
			serverLabel.stringValue = "\(fixed.site.name)  (\(Self.login(fixed.site)))"
			serverView = serverLabel
		} else {
			// Not connected in the FTP panel: pick the site here; the file goes to its start folder.
			sitePopup.addItems(withTitles: sites.map { "\($0.name)  (\(Self.login($0)))" })
			if let last = Preferences.lastSiteID, let i = sites.firstIndex(where: { $0.id == last }) { sitePopup.selectItem(at: i) }
			sitePopup.target = self
			sitePopup.action = #selector(update)
			serverView = sitePopup
		}

		func label(_ s: String) -> NSTextField {
			let l = NSTextField(labelWithString: s)
			l.alignment = .right
			l.textColor = .secondaryLabelColor
			return l
		}
		let grid = NSGridView(views: [
			[label("Server:"), serverView],
			[label("Folder:"), folderLabel],
			[label("Name:"), nameField],
			[NSGridCell.emptyContentView, addressLabel],
		])
		grid.rowSpacing = 8
		grid.column(at: 0).xPlacement = .trailing
		grid.column(at: 1).width = 300
		grid.frame = NSRect(x: 0, y: 0, width: 380, height: 120)
		alert.accessoryView = grid
		alert.window.initialFirstResponder = nameField
		update()
		// Select the name without the extension, ready to type over.
		DispatchQueue.main.async {
			let ext = (self.nameField.stringValue as NSString).pathExtension
			let length = (self.nameField.stringValue as NSString).length - (ext.isEmpty ? 0 : ext.count + 1)
			self.nameField.currentEditor()?.selectedRange = NSRange(location: 0, length: max(0, length))
		}
		return alert
	}

	/// Keeps the folder and the full address in step with the site and the name.
	@objc private func update() {
		folderLabel.stringValue = "/" + (folder.isEmpty ? "" : folder + "/")
		if let site, let path {
			addressLabel.stringValue = "Saves as ftp://\(Self.login(site))/\(path)"
			addressLabel.textColor = .secondaryLabelColor
			saveButton?.isEnabled = true
		} else {
			addressLabel.stringValue = "Type a file name. Use / for a subfolder; “..” isn't allowed."
			addressLabel.textColor = .systemRed
			saveButton?.isEnabled = false
		}
	}
}
