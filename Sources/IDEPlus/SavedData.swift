import Foundation
import CryptoKit

/// Loads lists saved in IDEPlus' settings (FTP sites, favorites) so an update can never lose them:
/// - fields missing in older data get their defaults,
/// - an entry that can't be read is skipped instead of failing the whole list,
/// - and whenever anything couldn't be read, the saved data is first copied to "<key>.unreadable-<checksum>",
///   so a later save can't destroy it.
enum SavedData {
	/// Problems found while loading, shown once after launch.
	private(set) static var problems: [String] = []

	static func load<T: Decodable>(_ type: T.Type, key: String, what: String, defaults: UserDefaults = .standard) -> T? {
		guard let data = defaults.data(forKey: key) else { return nil }
		let counter = DropCounter()
		let decoder = JSONDecoder()
		decoder.userInfo[.dropCounter] = counter
		let value = try? decoder.decode(T.self, from: data)
		if value == nil || counter.count > 0, keepCopy(of: data, key: key, defaults: defaults) {
			problems.append(value == nil
				? "Your saved \(what) couldn't be read."
				: "\(counter.count) saved \(counter.count == 1 ? "entry" : "entries") in your \(what) couldn't be read.")
		}
		return value
	}

	/// Copies data that couldn't be fully read. False when the same data was already copied (nothing new to report).
	@discardableResult
	static func keepCopy(of data: Data, key: String, defaults: UserDefaults = .standard) -> Bool {
		let sum = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
		let copyKey = "\(key).unreadable-\(sum)"
		guard defaults.data(forKey: copyKey) == nil else { return false }
		defaults.set(data, forKey: copyKey)
		return true
	}

	static func clearProblems() { problems = [] }
}

final class DropCounter {
	var count = 0
}

extension CodingUserInfoKey {
	static let dropCounter = CodingUserInfoKey(rawValue: "IDEPlusDropCounter")!
}

/// One array element that may fail to decode; failures are counted, not thrown.
struct Lossy<T: Decodable>: Decodable {
	let value: T?

	init(from decoder: Decoder) throws {
		do {
			value = try T(from: decoder)
		} catch {
			value = nil
			(decoder.userInfo[.dropCounter] as? DropCounter)?.count += 1
		}
	}
}

extension KeyedDecodingContainer {
	/// An array that keeps every element it can read. A missing key is an empty list; a key holding
	/// something that isn't a list counts as one unreadable entry.
	func lossyArray<T: Decodable>(_ type: T.Type, forKey key: Key, decoder: Decoder) -> [T] {
		do {
			return try decodeIfPresent([Lossy<T>].self, forKey: key)?.compactMap(\.value) ?? []
		} catch {
			(decoder.userInfo[.dropCounter] as? DropCounter)?.count += 1
			return []
		}
	}
}
