import AppKit

/// Colors tokens with layout-manager temporary attributes, so highlighting never touches the text or the undo stack.
enum SyntaxHighlighter {
	static func apply(_ language: Language, to textView: NSTextView, range: NSRange?) {
		guard let lm = textView.layoutManager else { return }
		let text = textView.string
		let length = (text as NSString).length
		let target = range ?? NSRange(location: 0, length: length)
		guard NSMaxRange(target) <= length else { return }
		colorize(language, text: text, length: length, range: target, lm: lm)
	}

	private static func colorize(_ language: Language, text: String, length: Int, range target: NSRange, lm: NSLayoutManager) {
		lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: target)
		guard target.length > 0 else { return }
		if let regex = language.regex {
			let kinds = language.kinds
			let colors = kinds.map { Theme.color(for: $0) }
			regex.enumerateMatches(in: text, options: [], range: target) { match, _, _ in
				guard let match else { return }
				for i in 0..<kinds.count {
					let r = match.range(at: i + 1)
					if r.location != NSNotFound {
						if r.length > 0 { lm.addTemporaryAttribute(.foregroundColor, value: colors[i], forCharacterRange: r) }
						break
					}
				}
			}
		}
		// Embedded code (<script>, <style>, <?php ... ?>) is recoloured with its own language.
		let end = NSMaxRange(target)
		for emb in language.embedded {
			var pos = target.location
			while pos < end, let s = emb.start.firstMatch(in: text, range: NSRange(location: pos, length: end - pos)) {
				let contentStart = NSMaxRange(s.range)
				let e = emb.end.firstMatch(in: text, range: NSRange(location: contentStart, length: end - contentStart))
				let contentEnd = e?.range.location ?? end
				if contentEnd > contentStart {
					colorize(emb.language, text: text, length: length,
							 range: NSRange(location: contentStart, length: contentEnd - contentStart), lm: lm)
				}
				let next = e.map { NSMaxRange($0.range) } ?? end
				if next <= pos { break }
				pos = next
			}
		}
	}
}
