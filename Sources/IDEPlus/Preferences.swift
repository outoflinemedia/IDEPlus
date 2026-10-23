import AppKit

/// App-wide settings, stored in UserDefaults.
enum Preferences {
	private static let d = UserDefaults.standard

	static func register() {
		d.register(defaults: [
			"fontSize": 13.0,
			"fontName": "Menlo",
			"wordWrap": false,
			"showLineNumbers": true,
			"tabWidth": 4,
			"useSpaces": false,
			"showDirectory": true,
			"highlightLine": true,
			"modernLook": true,
			"smartEditing": true,
			"autoComplete": true,
			"showFavoritesPanel": true,
			"sidebarTab": 1,
		])
	}

	static var fontSize: CGFloat {
		get { CGFloat(d.double(forKey: "fontSize")) }
		set { d.set(Double(min(max(newValue, 8), 48)), forKey: "fontSize") }
	}
	static var fontName: String {
		get { d.string(forKey: "fontName") ?? "Menlo" }
		set { d.set(newValue, forKey: "fontName") }
	}
	static var wordWrap: Bool {
		get { d.bool(forKey: "wordWrap") }
		set { d.set(newValue, forKey: "wordWrap") }
	}
	static var showLineNumbers: Bool {
		get { d.bool(forKey: "showLineNumbers") }
		set { d.set(newValue, forKey: "showLineNumbers") }
	}
	static var tabWidth: Int {
		get { max(1, d.integer(forKey: "tabWidth")) }
		set { d.set(newValue, forKey: "tabWidth") }
	}
	static var useSpaces: Bool {
		get { d.bool(forKey: "useSpaces") }
		set { d.set(newValue, forKey: "useSpaces") }
	}
	static var showDirectory: Bool {
		get { d.bool(forKey: "showDirectory") }
		set { d.set(newValue, forKey: "showDirectory") }
	}
	static var highlightLine: Bool {
		get { d.bool(forKey: "highlightLine") }
		set { d.set(newValue, forKey: "highlightLine") }
	}
	static var modernLook: Bool {
		get { d.bool(forKey: "modernLook") }
		set { d.set(newValue, forKey: "modernLook") }
	}
	/// Auto-close brackets, quotes and tags; smart indent.
	static var smartEditing: Bool {
		get { d.bool(forKey: "smartEditing") }
		set { d.set(newValue, forKey: "smartEditing") }
	}
	/// Expand .ipsnip templates when a trigger word is followed by Space.
	static var autoComplete: Bool {
		get { d.bool(forKey: "autoComplete") }
		set { d.set(newValue, forKey: "autoComplete") }
	}
	/// The left panel's tab: 0 Local, 1 FTP, 2 Clips. Starts on FTP; then whichever you used last.
	static var sidebarTab: Int {
		get { d.integer(forKey: "sidebarTab") }
		set { d.set(newValue, forKey: "sidebarTab") }
	}
	/// Just the panel under the FTP tree.
	static var showFavoritesPanel: Bool {
		get { d.bool(forKey: "showFavoritesPanel") }
		set { d.set(newValue, forKey: "showFavoritesPanel") }
	}
	/// At launch, open the files of the current favorites project.
	static var lastClipLibrary: String? {
		get { d.string(forKey: "lastClipLibrary") }
		set { d.set(newValue, forKey: "lastClipLibrary") }
	}
	/// Overrides the project's syntax folder when set.
	static var syntaxFolder: String? {
		get { d.string(forKey: "syntaxFolder") }
		set { d.set(newValue, forKey: "syntaxFolder") }
	}
	static var lastSiteID: String? {
		get { d.string(forKey: "lastSiteID") }
		set { d.set(newValue, forKey: "lastSiteID") }
	}
	static var lastFolder: String? {
		get { d.string(forKey: "lastFolder") }
		set { d.set(newValue, forKey: "lastFolder") }
	}
	static var recentFiles: [String] {
		get { d.stringArray(forKey: "recentFiles") ?? [] }
		set { d.set(Array(newValue.prefix(15)), forKey: "recentFiles") }
	}
	/// The tabs open at quit: local paths and "ftp://<site id>/<path>" entries.
	static var openFiles: [String] {
		get { d.stringArray(forKey: "openFiles") ?? [] }
		set { d.set(newValue, forKey: "openFiles") }
	}

	static let systemMonoName = "System Monospaced"

	static var font: NSFont {
		if fontName != systemMonoName, let f = NSFont(name: fontName, size: fontSize) {
			return f
		}
		return .monospacedSystemFont(ofSize: fontSize, weight: .regular)
	}

	/// Monospaced fonts offered in View > Font (only the installed ones).
	static var fontChoices: [String] {
		let candidates = ["Menlo", "Monaco", "SF Mono", "Courier New", "Courier", "Andale Mono", "PT Mono",
						  "JetBrains Mono", "Fira Code", "Source Code Pro", "Consolas", "D2Coding"]
		return [systemMonoName] + candidates.filter { NSFont(name: $0, size: 12) != nil }
	}

	static func noteRecent(_ url: URL) {
		var list = recentFiles.filter { $0 != url.path }
		list.insert(url.path, at: 0)
		recentFiles = list
	}
}
