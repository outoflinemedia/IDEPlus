import AppKit

struct EditorError: LocalizedError {
	let message: String
	var errorDescription: String? { message }
}

/// An open file (or an untitled buffer) and how it is stored on disk.
final class EditorDocument {
	private static var untitledCounter = 0

	/// For FTP files this is the local copy; `remote` says where it lives on the server.
	var url: URL?
	var remote: RemoteFile?
	var uploadState = UploadState.idle
	var encoding: FileEncoding = .utf8
	var lineEnding: LineEnding = .lf
	var isDirty = false
	var modificationDate: Date?
	let editor = EditorView(frame: .zero)
	private let untitledName: String

	init() {
		Self.untitledCounter += 1
		untitledName = "Untitled \(Self.untitledCounter)"
	}

	struct RemoteFile {
		let client: FTPClient
		let path: String
	}

	enum UploadState { case idle, uploading, failed }

	var displayName: String {
		if let remote { return (remote.path as NSString).lastPathComponent }
		return url?.lastPathComponent ?? untitledName
	}

	/// Full path or ftp:// address, for tooltips and the window subtitle.
	var location: String {
		if let remote { return remote.client.displayURL(remote.path) }
		return url?.path ?? displayName
	}

	var language: Language {
		get { editor.language }
		set { editor.language = newValue }
	}

	var isEmptyUntitled: Bool { url == nil && !isDirty && editor.string.isEmpty }

	static func diskDate(_ url: URL) -> Date? {
		(try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
	}

	/// Reads the file. With `forced`, decodes with that encoding instead of detecting one.
	func load(from url: URL, encoding forced: FileEncoding? = nil) throws {
		let data = try Data(contentsOf: url)
		let decoded: (FileEncoding, String)
		if let forced {
			guard let s = forced.decode(data) else {
				throw EditorError(message: "The file can't be read as \(forced.name).")
			}
			decoded = (forced, s)
		} else {
			decoded = FileEncoding.detect(data)
		}
		self.url = url
		encoding = decoded.0
		lineEnding = LineEnding.detect(decoded.1)
		let text = LineEnding.normalize(decoded.1)
		let firstLine = String(text.prefix(200).split(separator: "\n", maxSplits: 1).first ?? "")
		editor.language = Language.forURL(url, firstLine: firstLine)
		editor.setText(text)
		modificationDate = Self.diskDate(url)
		isDirty = false
	}

	func data() throws -> Data {
		let text = LineEnding.normalize(editor.string)
		let out = lineEnding == .lf ? text : text.replacingOccurrences(of: "\n", with: lineEnding.string)
		guard let d = encoding.encode(out) else {
			throw EditorError(message: "Some characters can't be saved as \(encoding.name).")
		}
		return d
	}

	func save(to url: URL) throws {
		let d = try data()
		try d.write(to: url, options: .atomic)
		let wasUntitled = self.url == nil
		self.url = url
		if wasUntitled || editor.language === Language.plain {
			let lang = Language.forURL(url)
			if lang !== Language.plain { editor.language = lang }
		}
		modificationDate = Self.diskDate(url)
		isDirty = false
	}
}
