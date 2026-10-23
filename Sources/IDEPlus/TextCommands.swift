import AppKit

/// Edit and Format menu commands. Menu items target the first responder, so these reach the focused editor.
extension EditorTextView {
	private var indentUnit: String {
		Preferences.useSpaces ? String(repeating: " ", count: Preferences.tabWidth) : "\t"
	}

	/// Replaces text as one undoable step, keeping the editor's font.
	func replaceText(in range: NSRange, with s: String, selecting sel: NSRange?) {
		guard let storage = textStorage, shouldChangeText(in: range, replacementString: s) else { return }
		storage.beginEditing()
		storage.replaceCharacters(in: range, with: s)
		storage.setAttributes(baseAttributes, range: NSRange(location: range.location, length: (s as NSString).length))
		storage.endEditing()
		didChangeText()
		if let sel {
			setSelectedRange(sel)
			scrollRangeToVisible(sel)
		}
	}

	/// Whole lines touched by the selection. A selection ending at a line start leaves that line out.
	func selectedLinesRange() -> NSRange {
		let ns = string as NSString
		var r = selectedRange()
		if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 10 { r.length -= 1 }
		return ns.lineRange(for: r)
	}

	/// The selected lines, or the whole document when the selection is within one line.
	private func linesOrDocument() -> NSRange {
		let ns = string as NSString
		let sel = selectedRange()
		if sel.length == 0 || !ns.substring(with: sel).contains("\n") {
			return NSRange(location: 0, length: ns.length)
		}
		return selectedLinesRange()
	}

	private func transformLines(in range: NSRange? = nil, _ f: ([String]) -> [String]) {
		let range = range ?? selectedLinesRange()
		let sel = selectedRange()
		var block = (string as NSString).substring(with: range)
		let trailing = block.hasSuffix("\n")
		if trailing { block.removeLast() }
		var out = f(block.components(separatedBy: "\n")).joined(separator: "\n")
		if trailing { out += "\n" }
		let newLength = (out as NSString).length
		if out == (string as NSString).substring(with: range) { return }
		var newSel = NSRange(location: range.location, length: newLength)
		if sel.length == 0 {
			// Keep a plain caret where it was, shifted by the change on its line.
			let caret = min(max(range.location, sel.location + newLength - range.length), range.location + newLength)
			newSel = NSRange(location: caret, length: 0)
		}
		replaceText(in: range, with: out, selecting: newSel)
	}

	// MARK: Lines

	@objc func duplicateLine(_ sender: Any?) {
		let ns = string as NSString
		let sel = selectedRange()
		let range = selectedLinesRange()
		let block = ns.substring(with: range)
		let insertion = block.hasSuffix("\n") ? block : "\n" + block
		let shift = (insertion as NSString).length
		replaceText(in: NSRange(location: NSMaxRange(range), length: 0), with: insertion,
					selecting: NSRange(location: sel.location + shift, length: sel.length))
	}

	@objc func deleteCurrentLine(_ sender: Any?) {
		let ns = string as NSString
		var range = selectedLinesRange()
		guard ns.length > 0 else { return }
		if NSMaxRange(range) == ns.length, range.location > 0, !ns.substring(with: range).hasSuffix("\n") {
			range.location -= 1
			range.length += 1
		}
		replaceText(in: range, with: "", selecting: NSRange(location: range.location, length: 0))
	}

	@objc func moveLinesUp(_ sender: Any?) {
		let ns = string as NSString
		let range = selectedLinesRange()
		guard range.location > 0 else { return }
		let prev = ns.lineRange(for: NSRange(location: range.location - 1, length: 0))
		var block = ns.substring(with: range)
		var prevText = ns.substring(with: prev)
		if !block.hasSuffix("\n") {
			block += "\n"
			prevText.removeLast()
		}
		let sel = selectedRange()
		replaceText(in: NSRange(location: prev.location, length: prev.length + range.length), with: block + prevText,
					selecting: NSRange(location: sel.location - prev.length, length: sel.length))
	}

	@objc func moveLinesDown(_ sender: Any?) {
		let ns = string as NSString
		let range = selectedLinesRange()
		guard NSMaxRange(range) < ns.length else { return }
		let next = ns.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
		var block = ns.substring(with: range)
		var nextText = ns.substring(with: next)
		if !nextText.hasSuffix("\n") {
			nextText += "\n"
			block.removeLast()
		}
		let sel = selectedRange()
		replaceText(in: NSRange(location: range.location, length: range.length + next.length), with: nextText + block,
					selecting: NSRange(location: sel.location + (nextText as NSString).length, length: sel.length))
	}

	@objc func joinLines(_ sender: Any?) {
		let ns = string as NSString
		var range = selectedLinesRange()
		let lines = ns.substring(with: range)
		if !lines.dropLast().contains("\n"), NSMaxRange(range) < ns.length {
			range = NSUnionRange(range, ns.lineRange(for: NSRange(location: NSMaxRange(range), length: 0)))
		}
		let sel = selectedRange()
		transformLines(in: range) { lines in
			[lines.enumerated().map { i, l in i == 0 ? l : String(l.drop { $0 == " " || $0 == "\t" }) }
				.joined(separator: " ")]
		}
		setSelectedRange(NSRange(location: min(sel.location, (string as NSString).length), length: 0))
	}

	@objc func indentLines(_ sender: Any?) {
		let unit = indentUnit
		transformLines { $0.map { $0.isEmpty ? $0 : unit + $0 } }
	}

	@objc func unindentLines(_ sender: Any?) {
		let tw = Preferences.tabWidth
		transformLines {
			$0.map { line in
				if line.hasPrefix("\t") { return String(line.dropFirst()) }
				let spaces = line.prefix { $0 == " " }.count
				return String(line.dropFirst(min(spaces, tw)))
			}
		}
	}

	@objc func toggleLineComment(_ sender: Any?) {
		if let lc = language.lineComment {
			transformLines { lines in
				let code = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
				let uncomment = !code.isEmpty && code.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(lc) }
				return lines.map { line in
					let indent = String(line.prefix { $0 == " " || $0 == "\t" })
					let rest = String(line.dropFirst(indent.count))
					if uncomment {
						guard rest.hasPrefix(lc) else { return line }
						var body = rest.dropFirst(lc.count)
						if body.hasPrefix(" ") { body = body.dropFirst() }
						return indent + body
					}
					return rest.isEmpty ? line : indent + lc + " " + rest
				}
			}
		} else if let bc = language.blockComment {
			let ns = string as NSString
			var range = selectedRange()
			if range.length == 0 { range = selectedLinesRange() }
			var text = ns.substring(with: range)
			var trailing = ""
			if text.hasSuffix("\n") {
				text.removeLast()
				trailing = "\n"
			}
			let trimmed = text.trimmingCharacters(in: .whitespaces)
			let out: String
			if trimmed.hasPrefix(bc.start) && trimmed.hasSuffix(bc.end) && trimmed.count >= bc.start.count + bc.end.count {
				var inner = String(trimmed.dropFirst(bc.start.count).dropLast(bc.end.count))
				if inner.hasPrefix(" ") { inner.removeFirst() }
				if inner.hasSuffix(" ") { inner.removeLast() }
				let indent = String(text.prefix { $0 == " " || $0 == "\t" })
				out = indent + inner + trailing
			} else {
				out = bc.start + " " + text + " " + bc.end + trailing
			}
			replaceText(in: range, with: out, selecting: NSRange(location: range.location, length: (out as NSString).length))
		}
	}

	@objc func sortLinesAscending(_ sender: Any?) {
		transformLines(in: linesOrDocument()) { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
	}

	@objc func sortLinesDescending(_ sender: Any?) {
		transformLines(in: linesOrDocument()) { $0.sorted { $0.localizedStandardCompare($1) == .orderedDescending } }
	}

	@objc func removeDuplicateLines(_ sender: Any?) {
		transformLines(in: linesOrDocument()) { lines in
			var seen = Set<String>()
			return lines.filter { seen.insert($0).inserted }
		}
	}

	@objc func trimTrailingWhitespace(_ sender: Any?) {
		let ns = string as NSString
		transformLines(in: NSRange(location: 0, length: ns.length)) { lines in
			lines.map { line in
				var l = Substring(line)
				while let last = l.last, last == " " || last == "\t" { l = l.dropLast() }
				return String(l)
			}
		}
	}

	@objc func convertTabsToSpaces(_ sender: Any?) {
		let tw = Preferences.tabWidth
		transformLines(in: linesOrDocument()) { lines in
			lines.map { line in
				var out = ""
				var col = 0
				for ch in line {
					if ch == "\t" {
						let n = tw - col % tw
						out += String(repeating: " ", count: n)
						col += n
					} else {
						out.append(ch)
						col += 1
					}
				}
				return out
			}
		}
	}

	@objc func convertLeadingSpacesToTabs(_ sender: Any?) {
		let tw = Preferences.tabWidth
		transformLines(in: linesOrDocument()) { lines in
			lines.map { line in
				let lead = line.prefix { $0 == " " || $0 == "\t" }
				var col = 0
				for ch in lead { col += ch == "\t" ? tw - col % tw : 1 }
				return String(repeating: "\t", count: col / tw) + String(repeating: " ", count: col % tw) + line.dropFirst(lead.count)
			}
		}
	}

	// MARK: Case

	private func changeCase(_ f: (String) -> String) {
		var r = selectedRange()
		if r.length == 0 { r = selectionRange(forProposedRange: r, granularity: .selectByWord) }
		guard r.length > 0 else { return }
		let s = f((string as NSString).substring(with: r))
		replaceText(in: r, with: s, selecting: NSRange(location: r.location, length: (s as NSString).length))
	}

	@objc func makeUppercase(_ sender: Any?) { changeCase { $0.uppercased() } }
	@objc func makeLowercase(_ sender: Any?) { changeCase { $0.lowercased() } }
	@objc func makeCapitalized(_ sender: Any?) { changeCase { $0.capitalized } }
	@objc func invertCase(_ sender: Any?) {
		changeCase { s in
			String(s.map { ch -> String in
				let str = String(ch)
				return str == str.uppercased() ? str.lowercased() : str.uppercased()
			}.joined())
		}
	}

	// MARK: Insert

	@objc func insertDateTime(_ sender: Any?) {
		let f = DateFormatter()
		f.dateStyle = .short
		f.timeStyle = .short
		insertPlain(f.string(from: Date()), replacementRange: selectedRange())
	}
}
