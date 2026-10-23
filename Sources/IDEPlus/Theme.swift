import AppKit

enum TokenKind: Int {
	case keyword, type, string, comment, number, preprocessor, tag, attribute, heading
}

/// Colors, each with a light and a dark variant. "Modern" follows VS Code's Light+/Dark+;
/// "Classic" is a traditional text-editor palette in light mode.
enum Theme {
	static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
		NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
	}

	static func hex(_ v: UInt32, alpha: CGFloat = 1) -> NSColor {
		NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
				blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
	}

	// Dark+ (shared by both themes in dark mode)
	private static let dark: [TokenKind: UInt32] = [
		.keyword: 0x569CD6, .type: 0x4EC9B0, .string: 0xCE9178, .comment: 0x6A9955, .number: 0xB5CEA8,
		.preprocessor: 0xC586C0, .tag: 0x569CD6, .attribute: 0x9CDCFE, .heading: 0x4FC1FF,
	]
	// Light+
	private static let modernLight: [TokenKind: UInt32] = [
		.keyword: 0x0000FF, .type: 0x267F99, .string: 0xA31515, .comment: 0x008000, .number: 0x098658,
		.preprocessor: 0xAF00DB, .tag: 0x800000, .attribute: 0xE50000, .heading: 0x0451A5,
	]
	// Classic: blue keywords, green comments, magenta strings, red numbers.
	private static let classicLight: [TokenKind: UInt32] = [
		.keyword: 0x0000FF, .type: 0x2B7A8C, .string: 0xA0179A, .comment: 0x008000, .number: 0xD00000,
		.preprocessor: 0x7A4A00, .tag: 0x0000C0, .attribute: 0xB03000, .heading: 0x0000FF,
	]

	private static let modernColors: [TokenKind: NSColor] = makeColors(modernLight)
	private static let classicColors: [TokenKind: NSColor] = makeColors(classicLight)

	private static func makeColors(_ light: [TokenKind: UInt32]) -> [TokenKind: NSColor] {
		var out: [TokenKind: NSColor] = [:]
		for (k, v) in light { out[k] = dynamic(hex(v), hex(dark[k]!)) }
		return out
	}

	static func color(for kind: TokenKind) -> NSColor {
		(Preferences.modernLook ? modernColors : classicColors)[kind]!
	}

	static let currentLine = dynamic(hex(0xFFF8D6), hex(0xFFFFFF, alpha: 0.06))
	static let modernCurrentLine = dynamic(hex(0x000000, alpha: 0.045), hex(0xFFFFFF, alpha: 0.055))
	static let rulerBackground = dynamic(hex(0xF3F3F3), hex(0x252527))
	static let barBackground = dynamic(hex(0xE9E9E9), hex(0x2A2A2C))
	static let bracketMatch = dynamic(hex(0x0064C8, alpha: 0.20), hex(0xFFFFFF, alpha: 0.22))
	static let indentGuide = dynamic(hex(0x000000, alpha: 0.10), hex(0xFFFFFF, alpha: 0.10))
}
