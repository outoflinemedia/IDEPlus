import Foundation

/// An .ipsyntax file: one language's highlighting, as JSON. Every field except "name" is optional.
///
///	{
///		"name": "PHP",
///		"extensions": ["php", "inc"],
///		"caseSensitive": false,                  keyword matching (default true)
///		"delimiters": ",(){}[]…",                characters that end a word
///		"lineComments": ["//", "#"],
///		"lineStartComments": ["#"],              comments only at the start of a line
///		"blockComments": [["/*", "*/"]],
///		"quotes": ["'", "\""],
///		"escape": "\\",
///		"multilineStrings": true,                strings may span lines
///		"quotesMustClose": true,                 a quote counts only if it closes on the line
///		"regexLiterals": true,                   /…/ after an operator is a regex
///		"patterns": [{"color": "tag", "regex": "…"}],
///		"keywordGroups": [{"name": "…", "color": "keyword", "words": ["if", "else"]}],
///		"prefixes": [{"prefix": "$", "color": "attribute"}],
///		"numbers": true,
///		"markup": true,                          HTML-like: tags auto-close and indent
///		"embedded": [{"start": "regex", "end": "regex", "language": "JavaScript"}],
///		"codeInside": {"language": "HTML / XML", "start": "regex", "end": "regex"},
///		"commentToggle": {"line": "//", "block": ["/*", "*/"]}
///	}
///
/// Colors: keyword, type, string, comment, number, preprocessor, tag, attribute, heading.
/// Rules are tried in this order: comments, quotes, regex literals, patterns, keywords, prefixes, numbers;
/// at each position the earliest-starting match wins.
struct SyntaxDefinition: Decodable {
	struct KeywordGroup: Decodable {
		var name: String?
		var color: String
		var words: [String]
	}
	struct Prefix: Decodable {
		var prefix: String
		var color: String
	}
	struct Pattern: Decodable {
		var color: String
		var regex: String
	}
	struct Embed: Decodable {
		var start: String
		var end: String
		var language: String
	}
	struct CodeInside: Decodable {
		var language: String
		var start: String
		var end: String
	}
	struct CommentToggle: Decodable {
		var line: String?
		var block: [String]?
	}

	var name: String
	var extensions: [String]?
	var caseSensitive: Bool?
	var delimiters: String?
	var lineComments: [String]?
	var lineStartComments: [String]?
	var blockComments: [[String]]?
	var quotes: [String]?
	var escape: String?
	var multilineStrings: Bool?
	var quotesMustClose: Bool?
	var regexLiterals: Bool?
	var patterns: [Pattern]?
	var keywordGroups: [KeywordGroup]?
	var prefixes: [Prefix]?
	var numbers: Bool?
	var markup: Bool?
	var embedded: [Embed]?
	var codeInside: CodeInside?
	var commentToggle: CommentToggle?

	static func color(_ name: String) -> TokenKind {
		switch name.lowercased() {
		case "type": return .type
		case "string": return .string
		case "comment": return .comment
		case "number": return .number
		case "preprocessor": return .preprocessor
		case "tag": return .tag
		case "attribute": return .attribute
		case "heading": return .heading
		default: return .keyword
		}
	}

	private static func esc(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }

	/// Escapes every non-alphanumeric character for use inside [...].
	private static func classEsc(_ s: String) -> String {
		s.map { $0.isLetter || $0.isNumber ? String($0) : "\\" + String($0) }.joined()
	}

	var lineComment: String? { commentToggle?.line ?? lineComments?.first ?? lineStartComments?.first }

	var blockComment: (String, String)? {
		if let b = commentToggle?.block, b.count == 2 { return (b[0], b[1]) }
		if let b = blockComments?.first, b.count == 2 { return (b[0], b[1]) }
		return nil
	}

	/// The highlight rules, in the order they are tried.
	func rules() -> [(TokenKind, String)] {
		let wordChar = "[^\\s" + Self.classEsc(delimiters ?? "") + "]"
		var rules: [(TokenKind, String)] = []
		for b in blockComments ?? [] where b.count == 2 {
			rules.append((.comment, Self.esc(b[0]) + #"[\s\S]*?(?:"# + Self.esc(b[1]) + #"|\z)"#))
		}
		for lc in lineComments ?? [] where !lc.isEmpty {
			var p = Self.esc(lc) + #"[^\n]*"#
			// Word-like markers such as REM must stand alone.
			if lc.allSatisfy({ $0.isLetter }) { p = "(?i:(?<!" + wordChar + ")" + p + ")" }
			rules.append((.comment, p))
		}
		for lc in lineStartComments ?? [] where !lc.isEmpty {
			rules.append((.comment, "^" + Self.esc(lc) + #"[^\n]*"#))
		}
		let nl = multilineStrings == true ? "" : #"\n"#
		func quoted(_ q: String) -> String {
			let body: String
			if let e = escape, !e.isEmpty {
				body = "(?:[^" + Self.classEsc(q + e) + nl + "]|" + Self.esc(e) + #"[\s\S])*"#
			} else {
				body = "[^" + Self.classEsc(q) + nl + "]*"
			}
			return body
		}
		for q in quotes ?? [] where !q.isEmpty {
			let close = quotesMustClose == true ? Self.esc(q) : "(?:" + Self.esc(q) + ")?"
			rules.append((.string, Self.esc(q) + quoted(q) + close))
		}
		if regexLiterals == true {
			// Only after an operator or at a line start, so a / b / c stays a division.
			rules.append((.string, #"(?:^|(?<=[(,=:\[!&|?{;]))[ \t]*/(?![/*])"# + quoted("/") + "/"))
		}
		for p in patterns ?? [] {
			rules.append((Self.color(p.color), p.regex))
		}
		for g in keywordGroups ?? [] where !g.words.isEmpty {
			let words = Array(Set(g.words)).sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
			var p = "(?<!" + wordChar + ")(?:" + words.map(Self.esc).joined(separator: "|") + ")(?!" + wordChar + ")"
			if caseSensitive == false { p = "(?i:" + p + ")" }
			rules.append((Self.color(g.color), p))
		}
		for pre in prefixes ?? [] where !pre.prefix.isEmpty {
			rules.append((Self.color(pre.color), "(?<!" + wordChar + ")" + Self.esc(pre.prefix) + wordChar + "*"))
		}
		if numbers == true { rules.append((.number, Language.num)) }
		return rules
	}
}

/// An .ipsnip file: autocomplete templates for one language. Typing a trigger and Space inserts the body.
///	{"name": "PHP", "language": "PHP", "caseSensitive": false,
///	 "snippets": [{"trigger": "if", "lineStart": false, "body": "if ({{cursor}}) {\n}"}]}
/// And an .ipclip file: a clip library for the Clips tab.
///	{"name": "HTML 5", "description": "…", "clips": [{"title": "a", "body": "<a href=\"\">{{cursor}}</a>"}]}
/// In both, {{cursor}} marks where the cursor goes.
struct SnippetSet {
	struct Entry {
		let title: String
		let body: String
		var lineStart = false
	}

	var title = ""
	var info = ""
	var language = ""
	var caseSensitive = true
	var entries: [Entry] = []

	private struct SnipFile: Decodable {
		struct Snip: Decodable {
			var trigger: String
			var body: String
			var lineStart: Bool?
		}
		var name: String?
		var language: String
		var description: String?
		var caseSensitive: Bool?
		var snippets: [Snip]
	}

	private struct ClipFile: Decodable {
		struct Clip: Decodable {
			var title: String
			var body: String
		}
		var name: String?
		var description: String?
		var clips: [Clip]
	}

	static func snippets(_ data: Data) throws -> SnippetSet {
		let f = try JSONDecoder().decode(SnipFile.self, from: data)
		return SnippetSet(title: f.name ?? f.language, info: f.description ?? "", language: f.language,
						  caseSensitive: f.caseSensitive ?? true,
						  entries: f.snippets.map { Entry(title: $0.trigger, body: $0.body, lineStart: $0.lineStart ?? false) })
	}

	static func clips(_ data: Data, fallbackName: String) throws -> SnippetSet {
		let f = try JSONDecoder().decode(ClipFile.self, from: data)
		return SnippetSet(title: f.name ?? fallbackName, info: f.description ?? "",
						  entries: f.clips.map { Entry(title: $0.title, body: $0.body) })
	}

	static let cursorMarker = "{{cursor}}"

	/// The text to insert and where the cursor goes (UTF-16 offset). Each new line gets `indent`,
	/// and tabs at the start of a template line become `unit` (spaces, if you indent with spaces).
	static func expand(_ body: String, indent: String, unit: String = "\t") -> (text: String, caret: Int?) {
		let lines = body.components(separatedBy: "\n").map { line -> String in
			let tabs = line.prefix { $0 == "\t" }.count
			return String(repeating: unit, count: tabs) + line.dropFirst(tabs)
		}
		var text = lines.joined(separator: "\n" + indent)
		var caret: Int?
		if let r = text.range(of: cursorMarker) {
			caret = (String(text[..<r.lowerBound]) as NSString).length
			text.removeSubrange(r)
			text = text.replacingOccurrences(of: cursorMarker, with: "")
		}
		return (text, caret)
	}
}

/// Autocomplete templates for one language, looked up by trigger word.
struct Autocompletion {
	let set: SnippetSet
	private var exact: [String: SnippetSet.Entry] = [:]

	init(_ set: SnippetSet) {
		self.set = set
		for e in set.entries where exact[key(e.title)] == nil { exact[key(e.title)] = e }
	}

	private func key(_ s: String) -> String { set.caseSensitive ? s : s.lowercased() }

	/// The template for a word just typed; `atLineStart` says whether only indentation precedes it.
	func entry(for word: String, atLineStart: Bool) -> SnippetSet.Entry? {
		guard let e = exact[key(word)] else { return nil }
		return e.lineStart && !atLineStart ? nil : e
	}
}

/// Loads the languages (.ipsyntax), autocomplete (.ipsnip) and clip libraries (.ipclip) that ship
/// with the app, then any in your own folder (Document > Syntax > Choose Syntax Folder…), which
/// add to or replace the built-in ones by name.
enum SyntaxLibrary {
	private(set) static var languages: [Language] = []
	private static var byName: [String: Language] = [:]
	private static var byExtension: [String: Language] = [:]
	private static var completions: [ObjectIdentifier: Autocompletion] = [:]
	private(set) static var clipLibraries: [SnippetSet] = []
	private(set) static var summary = ""
	private(set) static var problems: [String] = []

	/// The app's own files: inside the app, or the project's Resources folder when run from a build folder.
	static var builtInFolder: URL {
		if let env = ProcessInfo.processInfo.environment["IDEPLUS_RESOURCES"] { return URL(fileURLWithPath: env) }
		if let r = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: r.appendingPathComponent("Syntax").path) { return r }
		return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Resources")
	}

	/// Your own extra folder, if you chose one.
	static var folder: URL? {
		if let p = ProcessInfo.processInfo.environment["IDEPLUS_SYNTAX_DIR"] { return URL(fileURLWithPath: p) }
		return Preferences.syntaxFolder.map { URL(fileURLWithPath: $0) }
	}

	static func named(_ name: String) -> Language? { byName[name] }

	static func language(forExtension ext: String) -> Language? { byExtension[ext.lowercased()] }

	static func autocompletion(for language: Language) -> Autocompletion? { completions[ObjectIdentifier(language)] }

	/// For tests: use these templates for a language.
	static func setAutocompletion(_ ac: Autocompletion?, for language: Language) {
		completions[ObjectIdentifier(language)] = ac
	}

	/// Files with this extension in a folder, by base name.
	private static func files(_ ext: String, in folder: URL) -> [URL] {
		((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
			.filter { $0.pathExtension.lowercased() == ext }
			.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
	}

	/// Built-in files first, then your folder's; a later file with the same name replaces an earlier one.
	private static func gather(_ ext: String, _ sub: String) -> [URL] {
		var out = files(ext, in: builtInFolder.appendingPathComponent(sub))
		if let folder { out += files(ext, in: folder) }
		return out
	}

	static func reload() {
		languages = []
		byName = [:]
		byExtension = [:]
		completions = [:]
		clipLibraries = []
		problems = []

		var defs: [String: SyntaxDefinition] = [:]
		var order: [String] = []
		for url in gather("ipsyntax", "Syntax") {
			do {
				let def = try JSONDecoder().decode(SyntaxDefinition.self, from: Data(contentsOf: url))
				if defs[def.name] == nil { order.append(def.name) }
				defs[def.name] = def
			} catch {
				problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
			}
		}
		// Plain languages first, then ones that embed others, then code inside another language (PHP in HTML).
		func stage(_ d: SyntaxDefinition) -> Int { d.codeInside != nil ? 2 : (d.embedded?.isEmpty == false ? 1 : 0) }
		for name in order.sorted(by: { stage(defs[$0]!) < stage(defs[$1]!) }) {
			let d = defs[name]!
			let lang = make(d)
			let exts = lang.extensions
			if lang.regex == nil && !lang.kinds.isEmpty { problems.append("\(d.name): a highlight pattern is not a valid regular expression") }
			languages.append(lang)
			byName[d.name] = lang
			for e in exts { byExtension[e] = lang }
		}
		languages.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

		for url in gather("ipsnip", "Snippets") {
			do {
				let set = try SnippetSet.snippets(Data(contentsOf: url))
				// Templates for a language that isn't installed are simply unused.
				guard let lang = byName[set.language] else { continue }
				completions[ObjectIdentifier(lang)] = Autocompletion(set)
			} catch {
				problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
			}
		}
		var clips: [String: SnippetSet] = [:]
		var clipOrder: [String] = []
		for url in gather("ipclip", "Clips") {
			do {
				let set = try SnippetSet.clips(Data(contentsOf: url), fallbackName: url.deletingPathExtension().lastPathComponent)
				if clips[set.title] == nil { clipOrder.append(set.title) }
				clips[set.title] = set
			} catch {
				problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
			}
		}
		clipLibraries = clipOrder.map { clips[$0]! }

		summary = "\(languages.count) languages, \(completions.count) autocomplete, \(clipLibraries.count) clip libraries"
			+ (problems.isEmpty ? "" : " — \(problems.count) problem\(problems.count == 1 ? "" : "s")")
		for p in problems { NSLog("IDEPlus syntax: \(p)") }
	}

	/// A Language from a definition; languages it embeds or sits inside must already be loaded.
	static func make(_ d: SyntaxDefinition) -> Language {
		let exts = (d.extensions ?? []).map { $0.lowercased() }
		if let inside = d.codeInside {
			let code = Language(d.name, [], line: d.lineComment, block: d.blockComment, rules: d.rules())
			let host = byName[inside.language] ?? Language.plain
			return Language(d.name, exts, line: d.lineComment, block: d.blockComment ?? host.blockComment.map { ($0.start, $0.end) },
							markup: host.isMarkup, embedded: [embed(inside.start, inside.end, code, in: d.name)].compactMap { $0 } + host.embedded,
							rules: host.rules)
		}
		let embeds = (d.embedded ?? []).compactMap { e in byName[e.language].flatMap { embed(e.start, e.end, $0, in: d.name) } }
		return Language(d.name, exts, line: d.lineComment, block: d.blockComment, markup: d.markup ?? false,
						embedded: embeds, rules: d.rules())
	}

	private static func embed(_ start: String, _ end: String, _ lang: Language, in owner: String) -> Language.Embedded? {
		guard let s = try? NSRegularExpression(pattern: start), let e = try? NSRegularExpression(pattern: end) else {
			problems.append("\(owner): an embedded start/end is not a valid regular expression")
			return nil
		}
		return Language.Embedded(start: s, end: e, language: lang)
	}
}
