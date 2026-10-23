import Foundation

/// A syntax: file extensions, comment markers and highlight rules, built from an .ipsyntax file
/// (see SyntaxFiles.swift). Rules are tried left to right at each position, so comments and
/// strings listed first win. Rule patterns must not contain capturing groups (use (?:...)).
final class Language {
	let name: String
	let extensions: [String]
	let lineComment: String?
	let blockComment: (start: String, end: String)?
	/// HTML-style: tags get auto-closed and indented.
	let isMarkup: Bool
	/// Regions highlighted with another language, such as <script> or <?php ... ?> inside HTML.
	let embedded: [Embedded]
	let rules: [(TokenKind, String)]

	struct Embedded {
		let start: NSRegularExpression
		let end: NSRegularExpression
		let language: Language
	}

	init(_ name: String, _ extensions: [String], line: String? = nil, block: (String, String)? = nil,
		 markup: Bool = false, embedded: [Embedded] = [], rules: [(TokenKind, String)]) {
		self.name = name
		self.extensions = extensions
		self.lineComment = line
		self.blockComment = block.map { (start: $0.0, end: $0.1) }
		self.isMarkup = markup
		self.embedded = embedded
		self.rules = rules
	}

	var kinds: [TokenKind] { rules.map { $0.0 } }

	private(set) lazy var regex: NSRegularExpression? = {
		guard !rules.isEmpty else { return nil }
		let pattern = rules.map { "(" + $0.1 + ")" }.joined(separator: "|")
		do {
			return try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
		} catch {
			NSLog("IDEPlus: bad highlight pattern for \(name): \(error)")
			return nil
		}
	}()

	static func forURL(_ url: URL?, firstLine: String = "") -> Language {
		if let url {
			let ext = url.pathExtension.lowercased()
			let file = url.lastPathComponent.lowercased()
			if !ext.isEmpty, let lang = SyntaxLibrary.language(forExtension: ext) { return lang }
			// Names such as Makefile or .bashrc can be listed as extensions too.
			if let lang = SyntaxLibrary.language(forExtension: file) { return lang }
		}
		if firstLine.hasPrefix("#!") {
			if firstLine.contains("python") { return python }
			if firstLine.contains("ruby") { return named("Ruby") ?? plain }
			if firstLine.contains("php") { return php }
			if firstLine.contains("node") { return javascript }
			return named("Shell") ?? plain
		}
		if firstLine.hasPrefix("<?xml") || firstLine.lowercased().hasPrefix("<!doctype html") { return html }
		return plain
	}

	static func named(_ name: String) -> Language? { SyntaxLibrary.named(name) }

	static let num = #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)[uUlLfFnm]*\b"#

	/// Always there, even with no .ipsyntax files.
	static let plain = Language("Plain Text", ["txt", "text", "log"], rules: [])

	static var all: [Language] { [plain] + SyntaxLibrary.languages }

	// Languages the editor itself refers to (smart indent, shebang lines, tests).
	static var javascript: Language { named("JavaScript") ?? plain }
	static var python: Language { named("Python") ?? plain }
	static var php: Language { named("PHP") ?? plain }
	static var html: Language { named("HTML / XML") ?? plain }
	static var markdown: Language { named("Markdown") ?? plain }
}
