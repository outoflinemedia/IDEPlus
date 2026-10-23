import Foundation
import Security

/// A saved FTP server. The password is kept in the macOS Keychain, never in this record.
struct FTPSite: Codable, Equatable {
	var id = UUID().uuidString
	var name = "New Site"
	var host = ""
	var port = 21
	var username = ""
	/// Explicit FTPS (FTP over TLS).
	var secure = true
	/// Accept a TLS certificate issued for another name (shared hosting often uses the server's hostname).
	var allowCertMismatch = false
	/// Folder shown first, relative to the login folder ("" is the login folder).
	var rootPath = "public_html"
}

extension FTPSite {
	/// Fields missing in data saved by an older IDEPlus get their defaults.
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		let d = FTPSite()
		id = try c.decodeIfPresent(String.self, forKey: .id) ?? d.id
		name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
		host = try c.decodeIfPresent(String.self, forKey: .host) ?? d.host
		port = try c.decodeIfPresent(Int.self, forKey: .port) ?? d.port
		username = try c.decodeIfPresent(String.self, forKey: .username) ?? d.username
		secure = try c.decodeIfPresent(Bool.self, forKey: .secure) ?? d.secure
		allowCertMismatch = try c.decodeIfPresent(Bool.self, forKey: .allowCertMismatch) ?? d.allowCertMismatch
		rootPath = try c.decodeIfPresent(String.self, forKey: .rootPath) ?? d.rootPath
	}
}

enum FTPSites {
	/// Read through SavedData: a site that can't be read is skipped, and the saved data is kept aside first.
	static var all: [FTPSite] {
		get { SavedData.load([Lossy<FTPSite>].self, key: "ftpSites", what: "FTP sites")?.compactMap(\.value) ?? [] }
		set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "ftpSites") }
	}

	static func site(id: String) -> FTPSite? { all.first { $0.id == id } }
}

enum Keychain {
	private static let service = "IDEPlus FTP"

	private static func query(_ account: String) -> [String: Any] {
		[kSecClass as String: kSecClassGenericPassword,
		 kSecAttrService as String: service,
		 kSecAttrAccount as String: account]
	}

	static func password(for account: String) -> String? {
		var q = query(account)
		q[kSecReturnData as String] = true
		q[kSecMatchLimit as String] = kSecMatchLimitOne
		var out: AnyObject?
		guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func hasPassword(for account: String) -> Bool {
		var q = query(account)
		q[kSecReturnAttributes as String] = true
		return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
	}

	static func setPassword(_ password: String, for account: String) {
		SecItemDelete(query(account) as CFDictionary)
		var q = query(account)
		q[kSecValueData as String] = Data(password.utf8)
		q[kSecAttrLabel as String] = "IDEPlus FTP site"
		SecItemAdd(q as CFDictionary, nil)
	}

	static func deletePassword(for account: String) {
		SecItemDelete(query(account) as CFDictionary)
	}
}

struct RemoteEntry: Equatable {
	let name: String
	let isDirectory: Bool
	let size: Int?
}

struct FTPError: LocalizedError {
	let message: String
	let code: Int32
	var errorDescription: String? { message }
}

/// FTP and FTPS through /usr/bin/curl, one connection per operation.
/// Paths are relative to the login folder, e.g. "public_html/index.php".
final class FTPClient {
	let site: FTPSite
	private let password: String

	init(site: FTPSite, password: String) {
		self.site = site
		self.password = password
	}

	static func join(_ dir: String, _ name: String) -> String {
		dir.isEmpty ? name : dir + "/" + name
	}

	func displayURL(_ path: String) -> String {
		"ftp://\(site.username.isEmpty ? "" : site.username + "@")\(site.host)/\(path)"
	}

	func url(_ path: String, directory: Bool = false) -> String {
		var allowed = CharacterSet.urlPathAllowed
		allowed.remove(charactersIn: ";?#%")
		let encoded = path.split(separator: "/", omittingEmptySubsequences: true)
			.map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
			.joined(separator: "/")
		var u = "ftp://\(site.host):\(site.port)/\(encoded)"
		if directory && !u.hasSuffix("/") { u += "/" }
		return u
	}

	// MARK: Running curl

	private func curl(_ args: [String]) -> Result<Data, FTPError> {
		let p = Process()
		p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
		var base = ["-sS", "--connect-timeout", "15", "--max-time", "300", "-K", "-"]
		if site.secure { base.append("--ssl-reqd") }
		if site.allowCertMismatch { base.append("--insecure") }
		p.arguments = base + args
		let input = Pipe(), output = Pipe(), errors = Pipe()
		p.standardInput = input
		p.standardOutput = output
		p.standardError = errors
		do {
			try p.run()
		} catch {
			return .failure(FTPError(message: "Couldn't run curl: \(error.localizedDescription)", code: -1))
		}
		// The login goes through stdin so it never appears in the process list.
		let quoted = (site.username + ":" + password).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
		input.fileHandleForWriting.write(Data("user = \"\(quoted)\"\n".utf8))
		try? input.fileHandleForWriting.close()
		var errData = Data()
		let group = DispatchGroup()
		group.enter()
		DispatchQueue.global().async {
			errData = errors.fileHandleForReading.readDataToEndOfFile()
			group.leave()
		}
		let data = output.fileHandleForReading.readDataToEndOfFile()
		p.waitUntilExit()
		group.wait()
		if p.terminationStatus != 0 {
			let detail = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
				.replacingOccurrences(of: "curl: ", with: "") ?? ""
			return .failure(FTPError(message: Self.explain(p.terminationStatus, detail), code: p.terminationStatus))
		}
		return .success(data)
	}

	static func explain(_ code: Int32, _ detail: String) -> String {
		let reason: String
		switch code {
		case 6: reason = "Couldn't find the server. Check the host name."
		case 7: reason = "Couldn't connect to the server. Check the host and port."
		case 9: reason = "The server refused access to that folder."
		case 28: reason = "The connection timed out."
		case 35, 60, 64, 83:
			reason = "The secure (FTPS) connection failed. If the certificate is for a different name, use the server's own hostname, or turn on \"Allow certificate name mismatch\" for this site."
		case 67: reason = "Login failed. Check the username and password."
		case 78: reason = "That file doesn't exist on the server."
		case 25: reason = "The server refused the upload."
		case 21: reason = "The server refused the command."
		default: reason = "FTP error \(code)."
		}
		return detail.isEmpty ? reason : "\(reason)\n\n(\(detail))"
	}

	// MARK: Operations (blocking; call off the main thread or use the async versions)

	func listSync(_ path: String) -> Result<[RemoteEntry], FTPError> {
		if case let .success(data) = curl([url(path, directory: true), "-X", "MLSD"]),
		   let entries = Self.parseMLSD(String(decoding: data, as: UTF8.self)) {
			return .success(entries)
		}
		return curl([url(path, directory: true)]).map { Self.parseLIST(String(decoding: $0, as: UTF8.self)) }
	}

	func downloadSync(_ path: String, to local: URL) -> Result<Void, FTPError> {
		try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
		return curl([url(path), "-o", local.path]).map { _ in () }
	}

	func uploadSync(_ local: URL, to path: String) -> Result<Void, FTPError> {
		curl(["-T", local.path, "--ftp-create-dirs", url(path)]).map { _ in () }
	}

	/// Raw FTP commands such as "MKD dir", sent after login.
	func commandSync(_ commands: [String]) -> Result<Void, FTPError> {
		curl([url("", directory: true), "--list-only", "-o", "/dev/null"] + commands.flatMap { ["-Q", $0] }).map { _ in () }
	}

	private func async<T>(_ work: @escaping () -> Result<T, FTPError>, _ done: @escaping (Result<T, FTPError>) -> Void) {
		DispatchQueue.global(qos: .userInitiated).async {
			let r = work()
			DispatchQueue.main.async { done(r) }
		}
	}

	func list(_ path: String, _ done: @escaping (Result<[RemoteEntry], FTPError>) -> Void) {
		async({ self.listSync(path) }, done)
	}

	func download(_ path: String, to local: URL, _ done: @escaping (Result<Void, FTPError>) -> Void) {
		async({ self.downloadSync(path, to: local) }, done)
	}

	func upload(_ local: URL, to path: String, _ done: @escaping (Result<Void, FTPError>) -> Void) {
		async({ self.uploadSync(local, to: path) }, done)
	}

	func command(_ commands: [String], _ done: @escaping (Result<Void, FTPError>) -> Void) {
		async({ self.commandSync(commands) }, done)
	}

	/// The folder holding the local copies of files opened from FTP sites.
	static let cacheFolder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("IDEPlus-FTP")

	/// Where a remote file is kept while it is open: one folder per login, named so it shows the server,
	/// for example "IDEPlus-FTP/me@ftp.example.com/public_html/index.php".
	func cacheURL(for path: String) -> URL {
		Self.cacheFolder.appendingPathComponent(Self.cacheFolderName(for: site)).appendingPathComponent(path)
	}

	/// "user@host", plus " (port N)" when it isn't 21, with characters a folder name can't hold replaced.
	static func cacheFolderName(for site: FTPSite) -> String {
		var name = site.username.isEmpty ? site.host : "\(site.username)@\(site.host)"
		name = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
		if site.port != 21 { name += " (port \(site.port))" }
		return name.isEmpty ? site.id : name
	}

	// MARK: Listing formats

	/// MLSD lines: "type=file;size=12;modify=...; name". Nil when the text isn't MLSD.
	static func parseMLSD(_ text: String) -> [RemoteEntry]? {
		var out: [RemoteEntry] = []
		for raw in text.components(separatedBy: "\n") {
			let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
			if line.isEmpty { continue }
			guard let space = line.firstIndex(of: " ") else { return nil }
			let facts = line[..<space].lowercased()
			let name = String(line[line.index(after: space)...])
			guard facts.contains("type=") else { return nil }
			var type = "", size: Int?
			for fact in facts.split(separator: ";") {
				let kv = fact.split(separator: "=", maxSplits: 1)
				guard kv.count == 2 else { continue }
				if kv[0] == "type" { type = String(kv[1]) }
				if kv[0] == "size" { size = Int(kv[1]) }
			}
			if type == "cdir" || type == "pdir" || name == "." || name == ".." { continue }
			out.append(RemoteEntry(name: name, isDirectory: type == "dir", size: size))
		}
		return sort(out)
	}

	/// Unix "ls -l" style LIST output.
	static func parseLIST(_ text: String) -> [RemoteEntry] {
		let re = try! NSRegularExpression(pattern: #"^([\-dlcbps])\S*\s+\S+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\S+\s+\S+\s+(.+)$"#)
		var out: [RemoteEntry] = []
		for raw in text.components(separatedBy: "\n") {
			let line = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
			let ns = line as NSString
			guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
			let kind = ns.substring(with: m.range(at: 1))
			var name = ns.substring(with: m.range(at: 3))
			if kind == "l", let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
			if name == "." || name == ".." { continue }
			out.append(RemoteEntry(name: name, isDirectory: kind == "d", size: Int(ns.substring(with: m.range(at: 2)))))
		}
		return sort(out)
	}

	private static func sort(_ entries: [RemoteEntry]) -> [RemoteEntry] {
		entries.sorted {
			if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
			return $0.name.localizedStandardCompare($1.name) == .orderedAscending
		}
	}
}
