import Foundation

enum LineEnding: String, CaseIterable {
	case lf = "LF", crlf = "CRLF", cr = "CR"

	var string: String {
		switch self {
		case .lf: return "\n"
		case .crlf: return "\r\n"
		case .cr: return "\r"
		}
	}

	var label: String {
		switch self {
		case .lf: return "LF (Unix/macOS)"
		case .crlf: return "CRLF (Windows)"
		case .cr: return "CR (Classic Mac)"
		}
	}

	/// The most common line ending in the text (LF when there are none).
	static func detect(_ s: String) -> LineEnding {
		var lf = 0, crlf = 0, cr = 0
		var prevCR = false
		for u in s.utf16 {
			if u == 13 {
				if prevCR { cr += 1 }
				prevCR = true
			} else {
				if u == 10 { if prevCR { crlf += 1 } else { lf += 1 } } else if prevCR { cr += 1 }
				prevCR = false
			}
		}
		if prevCR { cr += 1 }
		if crlf >= lf && crlf >= cr && crlf > 0 { return .crlf }
		if cr > lf { return .cr }
		return .lf
	}

	/// Converts every kind of line break to "\n", the editor's internal form.
	static func normalize(_ s: String) -> String {
		guard s.utf16.contains(13) else { return s }
		return s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
	}
}

struct FileEncoding: Equatable {
	let name: String
	let encoding: String.Encoding
	let bom: Bool

	private static func cf(_ e: CFStringEncodings) -> String.Encoding {
		String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(e.rawValue)))
	}

	static let utf8 = FileEncoding(name: "UTF-8", encoding: .utf8, bom: false)
	static let utf8BOM = FileEncoding(name: "UTF-8 with BOM", encoding: .utf8, bom: true)
	static let utf16LE = FileEncoding(name: "UTF-16 LE", encoding: .utf16LittleEndian, bom: true)
	static let utf16BE = FileEncoding(name: "UTF-16 BE", encoding: .utf16BigEndian, bom: true)
	static let ansi = FileEncoding(name: "Windows Latin 1 (ANSI)", encoding: .windowsCP1252, bom: false)
	static let latin1 = FileEncoding(name: "ISO Latin 1", encoding: .isoLatin1, bom: false)

	static let all: [FileEncoding] = [
		utf8, utf8BOM, utf16LE, utf16BE, ansi, latin1,
		FileEncoding(name: "Mac Roman", encoding: .macOSRoman, bom: false),
		FileEncoding(name: "Japanese (Shift JIS)", encoding: .shiftJIS, bom: false),
		FileEncoding(name: "Korean (EUC-KR)", encoding: cf(.EUC_KR), bom: false),
		FileEncoding(name: "Chinese (GB 18030)", encoding: cf(.GB_18030_2000), bom: false),
		FileEncoding(name: "Chinese (Big5)", encoding: cf(.big5), bom: false),
		FileEncoding(name: "Cyrillic (Windows-1251)", encoding: .windowsCP1251, bom: false),
	]

	var bomBytes: [UInt8] {
		guard bom else { return [] }
		switch encoding {
		case .utf8: return [0xEF, 0xBB, 0xBF]
		case .utf16LittleEndian: return [0xFF, 0xFE]
		case .utf16BigEndian: return [0xFE, 0xFF]
		default: return []
		}
	}

	func decode(_ data: Data) -> String? {
		let bomLen = bomBytes.count
		let body = bomLen > 0 && data.starts(with: bomBytes) ? data.dropFirst(bomLen) : data[...]
		return String(data: Data(body), encoding: encoding)
	}

	func encode(_ s: String) -> Data? {
		guard let d = s.data(using: encoding, allowLossyConversion: false) else { return nil }
		return Data(bomBytes) + d
	}

	/// Picks an encoding from the BOM, then tries UTF-8, then falls back to Windows Latin 1 / ISO Latin 1.
	static func detect(_ data: Data) -> (FileEncoding, String) {
		for e in [utf8BOM, utf16LE, utf16BE] where data.starts(with: e.bomBytes) {
			if let s = e.decode(data) { return (e, s) }
		}
		if let s = String(data: data, encoding: .utf8) { return (utf8, s) }
		if let s = String(data: data, encoding: .windowsCP1252) { return (ansi, s) }
		return (latin1, String(data: data, encoding: .isoLatin1) ?? "")
	}
}
