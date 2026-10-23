import AppKit

/// Checks of the editing commands, find/replace and file round-trips.
/// Run with IDEPLUS_SELFTEST=1; prints results and exits with 1 on any failure.
enum SelfTest {
	private static var failures = 0

	private static func check(_ name: String, _ got: String, _ want: String) {
		if got == want {
			print("PASS  \(name)")
		} else {
			failures += 1
			print("FAIL  \(name)\n      got:  \(got.debugDescription)\n      want: \(want.debugDescription)")
		}
	}

	private static func editor(_ text: String, sel: NSRange, language: Language = .plain) -> EditorView {
		let ed = EditorView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
		ed.language = language
		ed.setText(text)
		ed.textView.setSelectedRange(sel)
		return ed
	}

	private static func run(_ text: String, sel: NSRange, language: Language = .plain, _ f: (EditorTextView) -> Void) -> String {
		let ed = editor(text, sel: sel, language: language)
		f(ed.textView)
		return ed.string
	}

	private static func kindAt(_ ed: EditorView, _ needle: String, offset: Int = 0) -> String {
		let ns = ed.string as NSString
		let r = ns.range(of: needle)
		guard r.location != NSNotFound, let lm = ed.textView.layoutManager else { return "missing \(needle)" }
		let c = lm.temporaryAttribute(.foregroundColor, atCharacterIndex: r.location + offset, effectiveRange: nil) as? NSColor
		for k in [TokenKind.keyword, .type, .string, .comment, .number, .preprocessor, .tag, .attribute, .heading] where c == Theme.color(for: k) {
			return "\(k)"
		}
		return c == nil ? "plain" : "other"
	}

	private static func highlighted(_ text: String, _ lang: Language) -> EditorView {
		let ed = editor(text, sel: NSRange(location: 0, length: 0), language: lang)
		SyntaxHighlighter.apply(lang, to: ed.textView, range: nil)
		return ed
	}

	private static func highlightTests() {
		func lang(_ json: String) -> Language {
			do {
				return SyntaxLibrary.make(try JSONDecoder().decode(SyntaxDefinition.self, from: Data(json.utf8)))
			} catch {
				check("parse test syntax", "\(error)", "ok")
				return .plain
			}
		}
		let test = lang(#"""
		{"name": "TestLang", "delimiters": ",(){}[]-+*%/=\"'~!&|<>?:;.", "caseSensitive": false,
		 "quotes": ["'", "\""], "escape": "\\", "lineComments": ["//"], "blockComments": [["/*", "*/"]],
		 "keywordGroups": [{"color": "keyword", "words": ["function", "return", "#pragma"]}, {"color": "type", "words": ["print"]}],
		 "prefixes": [{"prefix": "$", "color": "keyword"}], "numbers": true}
		"""#)
		let ed = highlighted("FUNCTION f() { return $x; } // c\nprint \"s\\\"q\" /* b */ #pragma returned 42", test)
		check("keyword ignores case", kindAt(ed, "FUNCTION"), "keyword")
		check("prefix $", kindAt(ed, "$x"), "keyword")
		check("line comment", kindAt(ed, "// c"), "comment")
		check("second keyword group", kindAt(ed, "print"), "type")
		check("escaped quote stays string", kindAt(ed, "q\""), "string")
		check("block comment", kindAt(ed, "/* b"), "comment")
		check("keyword with symbol", kindAt(ed, "#pragma"), "keyword")
		check("whole words only", kindAt(ed, "returned"), "plain")
		check("numbers", kindAt(ed, "42"), "number")

		let inside = lang(#"{"name": "MyPHP", "lineComments": ["//"], "keywordGroups": [{"color": "keyword", "words": ["echo"]}], "codeInside": {"language": "HTML / XML", "start": "<\\?(?:php\\b|=)?", "end": "\\?>"}}"#)
		let ed2 = highlighted("<p class=\"a\">echo</p><?php echo 1; ?>", inside)
		check("codeInside html tag", kindAt(ed2, "<p"), "tag")
		check("codeInside html text not keyword", kindAt(ed2, "echo</p>"), "plain")
		check("codeInside code keyword", kindAt(ed2, "echo 1"), "keyword")

		let js = lang(#"{"name": "J", "delimiters": ",(){}[]-+*%/\\=\"'~!&|<>?:;.", "quotes": ["\""], "quotesMustClose": true, "regexLiterals": true, "escape": "\\", "lineComments": ["//"], "keywordGroups": [{"color": "keyword", "words": ["var"]}]}"#)
		let ed4 = highlighted("var r = /a+b/; x = a / b / c; } // done", js)
		check("regex literal", kindAt(ed4, "/a+b/"), "string")
		check("division is not regex", kindAt(ed4, "/ b /"), "plain")
		check("comment after brace", kindAt(ed4, "// done"), "comment")
		let md = highlighted("# Title\nnot # this", lang(##"{"name": "M", "lineStartComments": ["#"]}"##))
		check("line-start comment", kindAt(md, "# Title"), "comment")
		check("not mid-line", kindAt(md, "# this"), "plain")
		let pat = highlighted("<p>a b c</p>", lang(#"{"name": "P", "patterns": [{"color": "tag", "regex": "</?[a-z]+>"}]}"#))
		check("patterns", kindAt(pat, "<p>"), "tag")
		check("pattern text plain", kindAt(pat, "b c"), "plain")
		check("bad JSON is reported", (try? JSONDecoder().decode(SyntaxDefinition.self, from: Data("{\"nam\": 1}".utf8))) == nil ? "rejected" : "accepted", "rejected")

		let ed3 = highlighted("<p class=\"a\">Hi</p><?php echo \"x\"; ?><script>var y = 'z';</script><style>a { color: red; }</style>", .php)
		check("php attribute", kindAt(ed3, "class"), "attribute")
		check("php code keyword", kindAt(ed3, "echo"), "keyword")
		check("php code string", kindAt(ed3, "\"x\""), "string")
		check("script keyword", kindAt(ed3, "var"), "keyword")
		check("script string", kindAt(ed3, "'z'"), "string")
		check("style property", kindAt(ed3, "color"), "keyword")
		let names = Language.all.map(\.name)
		check("each language listed once", "\(names.count == Set(names).count)", "true")
		let byExt = ["ts", "kt", "scss", "php", "js", "css", "py", "sql"].map { "\($0)=\(Language.forURL(URL(fileURLWithPath: "/x/a." + $0)).name)" }
		check("extensions", byExt.joined(separator: ", "),
			  "ts=TypeScript / ActionScript, kt=Kotlin / Groovy / Scala, scss=SCSS / Sass / Less, php=PHP, js=JavaScript, css=CSS, py=Python, sql=SQL")
	}

	private static func type(_ tv: EditorTextView, _ s: String) {
		for ch in s { tv.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0)) }
	}

	private static func smartEditingTests() {
		Preferences.smartEditing = true
		var ed = editor("", sel: NSRange(location: 0, length: 0), language: .javascript)
		type(ed.textView, "f(")
		check("auto-close paren", ed.string + "|\(ed.textView.selectedRange().location)", "f()|2")
		type(ed.textView, ")")
		check("step over closer", ed.string + "|\(ed.textView.selectedRange().location)", "f()|3")
		ed = editor("if (x) ", sel: NSRange(location: 7, length: 0), language: .javascript)
		type(ed.textView, "{")
		ed.textView.insertNewline(nil)
		check("brace newline indents", ed.string + "|\(ed.textView.selectedRange().location)", "if (x) {\n\t\n}|10")
		ed = editor("\t\t", sel: NSRange(location: 2, length: 0), language: .javascript)
		type(ed.textView, "}")
		check("closer dedents", ed.string, "\t}")
		ed = editor("x = ", sel: NSRange(location: 4, length: 0), language: .javascript)
		type(ed.textView, "\"")
		check("auto-close quote", ed.string, "x = \"\"")
		ed.textView.deleteBackward(nil)
		check("backspace deletes pair", ed.string, "x = ")
		ed = editor("don", sel: NSRange(location: 3, length: 0), language: .javascript)
		type(ed.textView, "'")
		check("no quote pair after letter", ed.string, "don'")
		ed = editor("abc", sel: NSRange(location: 0, length: 3), language: .javascript)
		type(ed.textView, "[")
		check("wrap selection", ed.string, "[abc]")
		ed = editor("<div class=\"a\"", sel: NSRange(location: 14, length: 0), language: .html)
		type(ed.textView, ">")
		check("auto-close tag", ed.string + "|\(ed.textView.selectedRange().location)", "<div class=\"a\"></div>|15")
		ed.textView.insertNewline(nil)
		check("newline inside tag pair", ed.string, "<div class=\"a\">\n\t\n</div>")
		ed = editor("<br", sel: NSRange(location: 3, length: 0), language: .php)
		type(ed.textView, ">")
		check("void tag not closed", ed.string, "<br>")
		ed = editor("def f():", sel: NSRange(location: 8, length: 0), language: .python)
		ed.textView.insertNewline(nil)
		check("python colon indents", ed.string, "def f():\n\t")
		ed = editor("", sel: NSRange(location: 0, length: 0), language: .php)
		type(ed.textView, "echo(\"hello")
		ed.textView.insertTab(nil)
		type(ed.textView, ";")
		check("tab out of quote and paren", ed.string, "echo(\"hello\");")
		ed = editor("x", sel: NSRange(location: 0, length: 0), language: .javascript)
		ed.textView.insertTab(nil)
		check("tab elsewhere is a tab", ed.string, "\tx")
		Preferences.smartEditing = false
		ed = editor("", sel: NSRange(location: 0, length: 0), language: .javascript)
		type(ed.textView, "(")
		check("smart editing off", ed.string, "(")
		Preferences.smartEditing = true
	}

	private static func snippetTests() {
		let snips = try? SnippetSet.snippets(Data(#"{"name": "T", "language": "JavaScript", "caseSensitive": false, "snippets": [{"trigger": "if", "body": "if ({{cursor}}) {\n}"}, {"trigger": "def", "lineStart": true, "body": "def {{cursor}}:"}]}"#.utf8))
		check("ipsnip entries", snips?.entries.map(\.title).joined(separator: ",") ?? "parse failed", "if,def")
		check("ipsnip case", "\(snips?.caseSensitive ?? true)", "false")
		check("expand with spaces", SnippetSet.expand("if x:\n\t{{cursor}}", indent: "  ", unit: "    ").text, "if x:\n      ")
		check("expand caret and indent", "\(SnippetSet.expand("if ({{cursor}}) {\n}", indent: "\t"))", "(text: \"if () {\\n\\t}\", caret: Optional(4))")
		let acp = snips ?? SnippetSet()
		let ac = Autocompletion(acp)
		let shippedJS = SyntaxLibrary.autocompletion(for: .javascript)
		SyntaxLibrary.setAutocompletion(ac, for: .javascript)
		var ed = editor("\tIF", sel: NSRange(location: 3, length: 0), language: .javascript)
		type(ed.textView, " ")
		check("space expands trigger", ed.string + "|\(ed.textView.selectedRange().location)", "\tif () {\n\t}|5")
		ed = editor("x = def", sel: NSRange(location: 7, length: 0), language: .javascript)
		type(ed.textView, " ")
		check("line-start trigger mid-line", ed.string, "x = def ")
		ed = editor("  def", sel: NSRange(location: 5, length: 0), language: .javascript)
		type(ed.textView, " ")
		check("line-start trigger", ed.string, "  def :")
		ed = editor("diff", sel: NSRange(location: 4, length: 0), language: .javascript)
		type(ed.textView, " ")
		check("non-trigger word", ed.string, "diff ")
		Preferences.autoComplete = false
		ed = editor("if", sel: NSRange(location: 2, length: 0), language: .javascript)
		type(ed.textView, " ")
		check("autocomplete off", ed.string, "if ")
		Preferences.autoComplete = true
		SyntaxLibrary.setAutocompletion(shippedJS, for: .javascript)

		let clips = try? SnippetSet.clips(Data(#"{"name": "Lib", "description": "About this\nlibrary", "clips": [{"title": "b", "body": "<b>{{cursor}}</b>"}]}"#.utf8), fallbackName: "x")
		let clipTitles: String = clips?.entries.map(\.title).joined() ?? ""
		let clipSummary: String = [clips?.title ?? "", clips?.info ?? "", clipTitles].joined(separator: "|")
		check("ipclip", clipSummary, "Lib|About this\nlibrary|b")
		ed = editor("  x\n  y", sel: NSRange(location: 3, length: 0), language: .html)
		ed.textView.insertSnippet("<ul>\n\t<li>{{cursor}}</li>\n</ul>")
		check("insert clip with indent", ed.string + "|\(ed.textView.selectedRange().location)", "  x<ul>\n  \t<li></li>\n  </ul>\n  y|15")
	}

	/// The templates and clips that ship with the app.
	private static func shippedSnippetTests() {
		var ed = editor("<?php\n\tif", sel: NSRange(location: 9, length: 0), language: .php)
		type(ed.textView, " ")
		check("php if template", ed.string + "|\(ed.textView.selectedRange().location)", "<?php\n\tif () {\n\t\t\n\t}|11")
		ed = editor("y = 1 if", sel: NSRange(location: 8, length: 0), language: .python)
		type(ed.textView, " ")
		check("python inline if left alone", ed.string, "y = 1 if ")
		Preferences.useSpaces = true
		ed = editor("def", sel: NSRange(location: 3, length: 0), language: .python)
		type(ed.textView, " ")
		check("python def with spaces", ed.string, "def ():\n    ")
		Preferences.useSpaces = false
		ed = editor("x", sel: NSRange(location: 1, length: 0), language: .javascript)
		type(ed.textView, "\ncl ")
		check("js console.log", ed.string, "x\nconsole.log();")
		let names = SyntaxLibrary.clipLibraries.map(\.title).joined(separator: ", ")
		check("clip libraries", names, "Characters, Control characters, CSS, HTML entities, HTML elements")
		let div = SyntaxLibrary.clipLibraries.first { $0.title == "HTML elements" }?.entries.first { $0.title == "div" }?.body ?? ""
		check("div clip", div, "<div>\n\t{{cursor}}\n</div>")
	}

	private static func savedDataTests() {
		// Older data: fields missing.
		let oldSite = #"[{"id":"s1","host":"ftp.example.com","username":"me"}]"#
		let sites = (try? JSONDecoder().decode([Lossy<FTPSite>].self, from: Data(oldSite.utf8)))?.compactMap(\.value) ?? []
		check("old site gets defaults", sites.map { "\($0.host) \($0.port) \($0.rootPath) \($0.secure)" }.joined(), "ftp.example.com 21 public_html true")

		let oldFavs = #"{"projects":[{"name":"A","items":[{"siteID":"s1","path":"x.php"},{"path":"no-site.php"}]}],"loose":[]}"#
		let counter = DropCounter()
		let dec = JSONDecoder()
		dec.userInfo[.dropCounter] = counter
		let saved = try? dec.decode(FavoritesStore.Saved.self, from: Data(oldFavs.utf8))
		check("old favorites load", saved.map { "\($0.projects.count) \($0.projects[0].items.count) \($0.projects[0].expanded)" } ?? "nil", "1 1 true")
		check("unreadable favorite is counted", "\(counter.count)", "1")

		// Unreadable data is copied aside once, and reported once.
		guard let defaults = UserDefaults(suiteName: "IDEPlusSelfTest") else { return }
		defaults.removePersistentDomain(forName: "IDEPlusSelfTest")
		SavedData.clearProblems()
		defaults.set(Data("not json".utf8), forKey: "list")
		let first = SavedData.load([Lossy<FTPSite>].self, key: "list", what: "test list", defaults: defaults)
		check("unreadable data loads as nothing", first == nil ? "nil" : "value", "nil")
		let copies = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("list.unreadable-") }
		check("unreadable data is kept", "\(copies.count) \(copies.first.flatMap { defaults.data(forKey: $0) }.map { String(decoding: $0, as: UTF8.self) } ?? "")", "1 not json")
		_ = SavedData.load([Lossy<FTPSite>].self, key: "list", what: "test list", defaults: defaults)
		check("reported once", "\(SavedData.problems.count)", "1")

		defaults.set(Data(#"[{"id":"a"},{"port":"twenty-one"}]"#.utf8), forKey: "list2")
		let partial = SavedData.load([Lossy<FTPSite>].self, key: "list2", what: "test list", defaults: defaults)?.compactMap(\.value)
		check("readable entries kept", "\(partial?.count ?? -1)", "1")
		check("partly unreadable data is kept", "\(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("list2.unreadable-") }.count)", "1")
		defaults.removePersistentDomain(forName: "IDEPlusSelfTest")
		SavedData.clearProblems()
	}

	private static func spaceRocksTests() {
		let v = EmptyStateView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
		v.layout()
		v.playDemo(seconds: 1.5)
		print("space rocks:", v.debugSummary)
		check("game is running", String(v.debugSummary.prefix(12)), "mode=playing")
		check("ship turned", v.debugSummary.contains("angle=157 ") ? "no" : "yes", "yes")
	}

	private static func favoritesTests() {
		let crowd = FavoritesStore(persistent: false)
		for n in 1...10 { crowd.newProject(named: "P\(n)") }
		crowd.collapseIfCrowded()
		check("ten projects stay open", "\(crowd.projects.filter(\.expanded).count)", "10")
		crowd.newProject(named: "P11")
		crowd.collapseIfCrowded()
		check("more than ten start closed", "\(crowd.projects.filter(\.expanded).count)", "0")

		let store = FavoritesStore(persistent: false)
		check("starts empty", "\(store.isEmpty) \(store.currentProject == nil)", "true true")
		let offer0 = ProjectPicker.offer(for: [("s1", "public_html/a.php", "mysite.com")], store: store)
		check("first project name suggested from site", "\(offer0.projects.count) \(offer0.suggestedName)", "0 mysite.com")
		let a = store.newProject(named: "Client A")
		let a2 = store.newProject(named: "Client A")
		check("unique project names", a2.name, "Client A 2")
		check("new project becomes current", store.currentProject?.name ?? "none", "Client A 2")
		store.removeProject(a2)
		check("removing current clears it", store.currentProject == nil ? "none" : "set", "none")
		store.setCurrent(a)
		let n = store.add([("s1", "public_html/a.php", "mysite.com"), ("s2", "b.php", "staging.com"), ("s1", "public_html/a.php", "mysite.com")], to: a)
		check("add skips duplicates", "\(n) \(a.items.map(\.name).joined(separator: ","))", "2 a.php,b.php")
		check("isFavorite", "\(store.isFavorite(siteID: "s1", path: "public_html/a.php")) \(store.isFavorite(siteID: "s1", path: "b.php"))", "true false")
		let b = store.newProject(named: "Blog", makeCurrent: false)
		store.move([a.items[1]], to: b, at: nil)
		check("move to another project", "\(a.items.map(\.name)) \(b.items.map(\.name))", "[\"a.php\"] [\"b.php\"]")
		store.add([("s1", "c.php", "mysite.com"), ("s1", "d.php", "mysite.com")], to: b)
		store.move([b.items[2]], to: b, at: 0)
		check("reorder within project", b.items.map(\.name).joined(separator: ","), "d.php,b.php,c.php")
		store.move([b.items[0]], to: nil, at: nil)
		check("move outside any project", "\(store.loose.map(\.name)) \(b.items.count)", "[\"d.php\"] 2")
		let f = store.filtered("staging")
		check("filter by site", f.projects.map { "\($0.0.name):\($0.1.map(\.name).joined())" }.joined(separator: " "), "Blog:b.php")
		check("filter by project name keeps all its files", store.filtered("client").projects.first?.1.count.description ?? "none", "1")
		store.removeEverywhere(siteID: "s1", path: "public_html/a.php")
		check("unstar removes everywhere", "\(a.items.count) \(store.isFavorite(siteID: "s1", path: "public_html/a.php"))", "0 false")
		store.setCurrent(b)
		let offer = ProjectPicker.offer(for: [("s1", "x.php", "mysite.com")], store: store)
		check("picker lists recent first", offer.projects.map(\.name).joined(separator: ","), "Blog,Client A")
	}

	private static func ftpParseTests() {
		let mlsd = "type=cdir;modify=20260101000000; .\r\ntype=dir;modify=20260101000000; images\r\ntype=file;size=120;modify=20260101000000; index.php\r\ntype=file;size=5; my file.txt\r\n"
		check("parse MLSD", FTPClient.parseMLSD(mlsd).map { $0.map { "\($0.isDirectory ? "d" : "f"):\($0.name)" }.joined(separator: ",") } ?? "nil",
			  "d:images,f:index.php,f:my file.txt")
		var cacheSite = FTPSite()
		cacheSite.host = "ftp.example.com"
		cacheSite.username = "me"
		check("temp folder names the login", FTPClient.cacheFolderName(for: cacheSite), "me@ftp.example.com")
		cacheSite.port = 2121
		check("temp folder shows a non-standard port", FTPClient.cacheFolderName(for: cacheSite), "me@ftp.example.com (port 2121)")
		check("MLSD rejects LIST text", FTPClient.parseMLSD("drwxr-xr-x 2 u g 4096 Jan 1 00:00 x") == nil ? "nil" : "parsed", "nil")
		let list = "drwxr-xr-x    2 user  group  4096 Jan 01 10:00 css\r\n-rw-r--r--    1 user  group   512 Feb 03  2025 a b.html\r\nlrwxrwxrwx    1 user  group     9 Jan 01 10:00 www -> public_html\r\n"
		check("parse LIST", FTPClient.parseLIST(list).map { "\($0.isDirectory ? "d" : "f"):\($0.name)" }.joined(separator: ","), "d:css,f:a b.html,f:www")
		let client = FTPClient(site: FTPSite(host: "example.com", port: 21), password: "")
		check("ftp url encoding", client.url("public_html/my file#1.php"), "ftp://example.com:21/public_html/my%20file%231.php")
		check("ftp dir url", client.url("", directory: true), "ftp://example.com:21/")
	}

	/// Against a local test server: IDEPLUS_FTP_TEST=host:port:user:password
	private static func ftpLiveTests(_ spec: String) {
		let parts = spec.split(separator: ":", maxSplits: 3).map(String.init)
		guard parts.count == 4 else { check("ftp spec", spec, "host:port:user:password"); return }
		let site = FTPSite(name: "test", host: parts[0], port: Int(parts[1]) ?? 21, username: parts[2], secure: false, rootPath: "")
		let client = FTPClient(site: site, password: parts[3])
		let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ideplus-ftp-\(getpid())")
		try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
		let local = tmp.appendingPathComponent("up.php")
		try? Data("<?php echo 'hi'; ?>\n".utf8).write(to: local)

		func ok<T>(_ name: String, _ r: Result<T, FTPError>) -> T? {
			switch r {
			case let .success(v): check(name, "ok", "ok"); return v
			case let .failure(e): check(name, e.message, "ok"); return nil
			}
		}
		_ = ok("ftp upload creates folders", client.uploadSync(local, to: "site/new dir/up.php"))
		let entries = ok("ftp list", client.listSync("site/new dir"))
		check("ftp list contents", entries?.map(\.name).joined(separator: ",") ?? "", "up.php")
		let back = tmp.appendingPathComponent("down.php")
		_ = ok("ftp download", client.downloadSync("site/new dir/up.php", to: back))
		check("ftp round trip bytes", (try? String(contentsOf: back, encoding: .utf8)) ?? "", "<?php echo 'hi'; ?>\n")

		// Open, edit, save, upload: what Save does for an FTP file.
		let doc = EditorDocument()
		let cache = client.cacheURL(for: "site/new dir/up.php")
		_ = ok("ftp download to cache", client.downloadSync("site/new dir/up.php", to: cache))
		try? doc.load(from: cache)
		check("ftp doc language", doc.language.name, Language.php.name)
		doc.editor.textView.replaceText(in: NSRange(location: 11, length: 4), with: "'changed'", selecting: nil)
		try? doc.save(to: cache)
		_ = ok("ftp save uploads", client.uploadSync(cache, to: "site/new dir/up.php"))
		_ = ok("ftp download again", client.downloadSync("site/new dir/up.php", to: back))
		check("ftp server has edit", (try? String(contentsOf: back, encoding: .utf8)) ?? "", "<?php echo 'changed'; ?>\n")

		_ = ok("ftp mkdir", client.commandSync(["MKD site/made"]))
		_ = ok("ftp rename", client.commandSync(["RNFR site/new dir/up.php", "RNTO site/made/renamed.php"]))
		check("ftp after rename", (try? client.listSync("site/made").get())?.map(\.name).joined(separator: ",") ?? "error", "renamed.php")
		_ = ok("ftp delete", client.commandSync(["DELE site/made/renamed.php"]))
		_ = ok("ftp rmdir", client.commandSync(["RMD site/made"]))
		let bad = FTPClient(site: site, password: "wrong-password")
		if case let .failure(e) = bad.listSync("") { check("ftp bad password message", String(e.message.prefix(13)), "Login failed.") } else { check("ftp bad password", "succeeded", "failure") }
		try? FileManager.default.removeItem(at: tmp)
	}

	/// IDEPLUS_SYNTAX_REPORT=1: loads the syntax folder and shows how sample code is coloured.
	static func syntaxReport() -> Never {
		Preferences.register()
		SyntaxLibrary.reload()
		print(SyntaxLibrary.summary)
		for lang in SyntaxLibrary.languages {
			print("  \(lang.name): .\(lang.extensions.joined(separator: " .")) | rules \(lang.kinds.count)\(lang.regex == nil && lang.kinds.count > 0 ? " INVALID REGEX" : "")\(lang.isMarkup ? " | markup" : "")\(lang.embedded.isEmpty ? "" : " | embeds " + lang.embedded.map(\.language.name).joined(separator: ", "))")
		}
		let samples: [(String, String, [String])] = [
			("php", "<div class=\"box\">Hi</div>\n<?php\n// note\n$name = strlen(\"abc\");\nif ($name) { echo 'x'; }\n?>\n<script>var y = /ab+c/; let z = a / b / c;</script>",
			 ["div", "class", "Hi", "// note", "$name", "strlen", "\"abc\"", "if", "echo", "var", "/ab+c/", "/ b /"]),
			("js", "function f(a) { return a.length / 2; } // c\nconst re = /x+/g; `tpl`", ["function", "return", "length", "// c", "/x+/", "`tpl`", "const"]),
			("css", "#main .box { color: red; margin: 0.5em; } /* c */", ["#main", ".box", "color", "red", "0.5", "/* c */"]),
			("md", "# Title\n> quote\nsome *em* and `code`", ["# Title", "> quote", "`code`"]),
			("html", "<p class=\"a\">text &amp; <b>bold</b></p>", ["<p", "class", "text", "&amp;", "<b"]),
			("py", "def f(x):\n    return len(x)  # c", ["def", "return", "len", "# c"]),
			("sql", "SELECT name FROM users WHERE id = 1 -- c", ["SELECT", "FROM", "WHERE", "-- c"]),
		]
		print("\nAutocomplete:")
		for lang in Language.all {
			if let ac = SyntaxLibrary.autocompletion(for: lang) { print("  \(lang.name) <- \(ac.set.title): \(ac.set.entries.count) templates") }
		}
		print("Clip libraries:")
		for lib in SyntaxLibrary.clipLibraries { print("  \(lib.title): \(lib.entries.count) clips") }
		let php = Language.forURL(URL(fileURLWithPath: "/x/a.php"))
		let ed0 = editor("<?php\n\tif", sel: NSRange(location: 9, length: 0), language: php)
		type(ed0.textView, " ")
		print("php 'if' + Space ->", ed0.string.debugDescription, "caret", ed0.textView.selectedRange().location)
		for (ext, text, probes) in samples {
			guard let lang = Language.forURL(URL(fileURLWithPath: "/x/sample." + ext)) as Language? else { continue }
			let ed = highlighted(text, lang)
			print("\n.\(ext) -> \(lang.name)")
			for p in probes { print("    \(p.padding(toLength: 12, withPad: " ", startingAt: 0)) \(kindAt(ed, p))") }
		}
		exit(0)
	}

	static func runAll() -> Never {
		Preferences.register()
		SyntaxLibrary.reload()
		check("built-in syntax files load", SyntaxLibrary.problems.joined(separator: "; "), "")
		Preferences.tabWidth = 4
		Preferences.useSpaces = false

		check("duplicate line", run("a\nb\nc", sel: NSRange(location: 2, length: 0)) { $0.duplicateLine(nil) }, "a\nb\nb\nc")
		check("duplicate last line", run("a\nb", sel: NSRange(location: 3, length: 0)) { $0.duplicateLine(nil) }, "a\nb\nb")
		check("delete line", run("a\nb\nc", sel: NSRange(location: 2, length: 0)) { $0.deleteCurrentLine(nil) }, "a\nc")
		check("delete last line", run("a\nb", sel: NSRange(location: 2, length: 0)) { $0.deleteCurrentLine(nil) }, "a")
		check("move line up", run("a\nb\nc", sel: NSRange(location: 2, length: 0)) { $0.moveLinesUp(nil) }, "b\na\nc")
		check("move last line up", run("a\nb", sel: NSRange(location: 2, length: 0)) { $0.moveLinesUp(nil) }, "b\na")
		check("move line down", run("a\nb\nc", sel: NSRange(location: 0, length: 0)) { $0.moveLinesDown(nil) }, "b\na\nc")
		check("move to last line", run("a\nb", sel: NSRange(location: 0, length: 0)) { $0.moveLinesDown(nil) }, "b\na")
		check("join lines", run("a\n   b\nc", sel: NSRange(location: 0, length: 0)) { $0.joinLines(nil) }, "a b\nc")
		check("indent block", run("a\n\nb\n", sel: NSRange(location: 0, length: 4)) { $0.indentLines(nil) }, "\ta\n\n\tb\n")
		check("unindent block", run("\ta\n    b\n  c", sel: NSRange(location: 0, length: 11)) { $0.unindentLines(nil) }, "a\nb\nc")
		check("comment lines", run("x\n  y", sel: NSRange(location: 0, length: 5), language: .javascript) { $0.toggleLineComment(nil) }, "// x\n  // y")
		check("uncomment lines", run("// x\n  // y", sel: NSRange(location: 0, length: 11), language: .javascript) { $0.toggleLineComment(nil) }, "x\n  y")
		check("python comment", run("x = 1", sel: NSRange(location: 0, length: 0), language: .python) { $0.toggleLineComment(nil) }, "# x = 1")
		check("html comment", run("<b>x</b>", sel: NSRange(location: 0, length: 0), language: .html) { $0.toggleLineComment(nil) }, "<!-- <b>x</b> -->")
		check("html uncomment", run("<!-- <b>x</b> -->", sel: NSRange(location: 0, length: 0), language: .html) { $0.toggleLineComment(nil) }, "<b>x</b>")
		check("sort whole doc", run("b\nc\na\n", sel: NSRange(location: 0, length: 0)) { $0.sortLinesAscending(nil) }, "a\nb\nc\n")
		check("sort natural", run("file10\nfile2", sel: NSRange(location: 0, length: 0)) { $0.sortLinesAscending(nil) }, "file2\nfile10")
		check("remove duplicates", run("a\nb\na\n", sel: NSRange(location: 0, length: 0)) { $0.removeDuplicateLines(nil) }, "a\nb\n")
		check("trim trailing", run("a  \nb\t\n", sel: NSRange(location: 0, length: 0)) { $0.trimTrailingWhitespace(nil) }, "a\nb\n")
		check("tabs to spaces", run("\tx\ta", sel: NSRange(location: 0, length: 0)) { $0.convertTabsToSpaces(nil) }, "    x   a")
		check("spaces to tabs", run("      x", sel: NSRange(location: 0, length: 0)) { $0.convertLeadingSpacesToTabs(nil) }, "\t  x")
		check("uppercase word", run("hello world", sel: NSRange(location: 1, length: 0)) { $0.makeUppercase(nil) }, "HELLO world")
		check("invert case", run("aBc", sel: NSRange(location: 0, length: 3)) { $0.invertCase(nil) }, "AbC")
		check("auto indent", run("\tif x", sel: NSRange(location: 5, length: 0)) { $0.insertNewline(nil) }, "\tif x\n\t")
		check("undo", run("abc", sel: NSRange(location: 0, length: 0)) { tv in
			tv.duplicateLine(nil)
			tv.undoManager?.undo()
		}, "abc")

		// Find and replace
		let ed = editor("cat Cat cat", sel: NSRange(location: 0, length: 0))
		var opt = FindOptions(query: "cat")
		check("count ignore case", "\(ed.countMatches(opt))", "3")
		opt.matchCase = true
		check("count match case", "\(ed.countMatches(opt))", "2")
		if case let .found(i, total, _) = ed.find(opt, backward: false) { check("find next", "\(i)/\(total)", "1/2") }
		if case let .found(i, _, _) = ed.find(opt, backward: false) { check("find next again", "\(i)", "2") }
		if case let .found(i, _, wrapped) = ed.find(opt, backward: false) { check("find wraps", "\(i) \(wrapped)", "1 true") }
		opt.replacement = "dog"
		_ = ed.replaceCurrent(opt)
		check("replace current", ed.string, "dog Cat cat")
		check("replace all", "\(ed.replaceAll(opt)) \(ed.string)", "1 dog Cat dog")

		let ed2 = editor("a1 b22", sel: NSRange(location: 0, length: 0))
		let re = FindOptions(query: #"([a-z])(\d+)"#, replacement: #"$2-$1\n"#, regex: true)
		_ = ed2.replaceAll(re)
		check("regex replace with \\n", ed2.string, "1-a\n 22-b\n")
		let ed3 = editor("cart cat", sel: NSRange(location: 0, length: 0))
		check("whole word", "\(ed3.countMatches(FindOptions(query: "cat", wholeWord: true)))", "1")
		check("literal dot", "\(editor("a.b axb", sel: NSRange()).countMatches(FindOptions(query: ".")))", "1")

		// File round-trips
		let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ideplus-selftest-\(getpid())")
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		func roundTrip(_ name: String, _ bytes: [UInt8], expectText: String, expectEncoding: String, expectEnding: LineEnding) {
			let url = dir.appendingPathComponent(name)
			try? Data(bytes).write(to: url)
			let doc = EditorDocument()
			do {
				try doc.load(from: url)
				check("load \(name) text", doc.editor.string, expectText)
				check("load \(name) encoding", doc.encoding.name, expectEncoding)
				check("load \(name) ending", doc.lineEnding.rawValue, expectEnding.rawValue)
				try doc.save(to: url)
				check("save \(name) bytes", (try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined(),
					  bytes.map { String(format: "%02x", $0) }.joined())
			} catch {
				check("load/save \(name)", "\(error)", "no error")
			}
		}
		roundTrip("utf8.txt", Array("a\nb\n".utf8), expectText: "a\nb\n", expectEncoding: "UTF-8", expectEnding: .lf)
		roundTrip("crlf.txt", Array("a\r\nb\r\n".utf8), expectText: "a\nb\n", expectEncoding: "UTF-8", expectEnding: .crlf)
		roundTrip("bom.txt", [0xEF, 0xBB, 0xBF] + Array("hi".utf8), expectText: "hi", expectEncoding: "UTF-8 with BOM", expectEnding: .lf)
		roundTrip("utf16.txt", [0xFF, 0xFE, 0x68, 0x00, 0x0A, 0x00], expectText: "h\n", expectEncoding: "UTF-16 LE", expectEnding: .lf)
		roundTrip("ansi.txt", [0x63, 0x61, 0x66, 0xE9], expectText: "café", expectEncoding: "Windows Latin 1 (ANSI)", expectEnding: .lf)

		let conv = EditorDocument()
		conv.editor.setText("x\ny")
		conv.lineEnding = .crlf
		conv.encoding = .utf16LE
		check("convert to CRLF UTF-16", ((try? conv.data()) ?? Data()).map { String(format: "%02x", $0) }.joined(), "fffe78000d000a007900")
		try? FileManager.default.removeItem(at: dir)

		highlightTests()
		smartEditingTests()
		ftpParseTests()
		snippetTests()
		favoritesTests()
		spaceRocksTests()
		savedDataTests()
		shippedSnippetTests()
		if let spec = ProcessInfo.processInfo.environment["IDEPLUS_FTP_TEST"] { ftpLiveTests(spec) }

		// Every highlight pattern compiles.
		for lang in Language.all where lang !== Language.plain {
			check("regex \(lang.name)", lang.regex == nil ? "invalid" : "ok", "ok")
		}

		print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
		exit(failures == 0 ? 0 : 1)
	}
}
