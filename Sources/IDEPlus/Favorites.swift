import Foundation

/// A shortcut to a file on an FTP site. Removing it never touches the file on the server.
final class FavoriteItem: Codable {
	var id = UUID().uuidString
	var siteID: String
	var path: String
	/// The site's name when the favorite was added, shown if the site is later removed.
	var siteName: String

	init(siteID: String, path: String, siteName: String) {
		self.siteID = siteID
		self.path = path
		self.siteName = siteName
	}

	private enum CodingKeys: String, CodingKey { case id, siteID, path, siteName }

	/// The site and path are needed; anything else missing in older data gets a default.
	required init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
		siteID = try c.decode(String.self, forKey: .siteID)
		path = try c.decode(String.self, forKey: .path)
		siteName = try c.decodeIfPresent(String.self, forKey: .siteName) ?? ""
	}

	var name: String { (path as NSString).lastPathComponent }

	/// The site's current name, or the remembered one.
	var siteLabel: String { FTPSites.site(id: siteID)?.name ?? siteName }

	func same(_ siteID: String, _ path: String) -> Bool { self.siteID == siteID && self.path == path }
}

/// A named group of favorites: the files of one project, possibly from several sites.
final class FavoriteProject: Codable {
	var id = UUID().uuidString
	var name: String
	var items: [FavoriteItem] = []
	var expanded = true
	var lastUsed = Date()

	init(name: String) { self.name = name }

	private enum CodingKeys: String, CodingKey { case id, name, items, expanded, lastUsed }

	/// Older data may lack fields; a file entry that can't be read is skipped, not the whole project.
	required init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
		name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Project"
		items = c.lossyArray(FavoriteItem.self, forKey: .items, decoder: decoder)
		expanded = try c.decodeIfPresent(Bool.self, forKey: .expanded) ?? true
		lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed) ?? Date()
	}
}

extension Notification.Name {
	static let favoritesChanged = Notification.Name("IDEPlusFavoritesChanged")
}

extension FavoritesStore {
	/// Tell every view to redraw after the Favorites settings change.
	static func settingsChanged() {
		NotificationCenter.default.post(name: .favoritesChanged, object: nil)
	}
}

/// All favorites: projects, plus favorites outside any project. Saved in IDEPlus' settings on this Mac.
final class FavoritesStore {
	struct Saved: Codable {
		var projects: [FavoriteProject]
		var loose: [FavoriteItem]
		var currentProjectID: String?

		init(projects: [FavoriteProject], loose: [FavoriteItem], currentProjectID: String?) {
			self.projects = projects
			self.loose = loose
			self.currentProjectID = currentProjectID
		}

		private enum CodingKeys: String, CodingKey { case projects, loose, currentProjectID }

		init(from decoder: Decoder) throws {
			let c = try decoder.container(keyedBy: CodingKeys.self)
			projects = c.lossyArray(FavoriteProject.self, forKey: .projects, decoder: decoder)
			loose = c.lossyArray(FavoriteItem.self, forKey: .loose, decoder: decoder)
			currentProjectID = try? c.decodeIfPresent(String.self, forKey: .currentProjectID)
		}
	}

	static let shared = FavoritesStore(persistent: ProcessInfo.processInfo.environment["IDEPLUS_FAVORITES_DEMO"] == nil)

	private(set) var projects: [FavoriteProject] = []
	private(set) var loose: [FavoriteItem] = []
	private(set) var currentProjectID: String?
	private let persistent: Bool
	private static let key = "favorites"

	init(persistent: Bool) {
		self.persistent = persistent
		// Read through SavedData: entries that can't be read are skipped, and the saved data is kept aside first.
		if persistent, let saved = SavedData.load(Saved.self, key: Self.key, what: "favorites") {
			projects = saved.projects
			loose = saved.loose
			currentProjectID = saved.currentProjectID
			collapseIfCrowded()
		}
	}

	/// More projects than this and they all start closed at launch, so the list stays short.
	static let crowdedProjectCount = 10

	/// With more than ten projects, every project starts closed; opening one later is remembered until the next launch.
	func collapseIfCrowded() {
		guard projects.count > Self.crowdedProjectCount else { return }
		for p in projects { p.expanded = false }
	}

	var currentProject: FavoriteProject? { projects.first { $0.id == currentProjectID } }

	/// Projects with the most recently used first, for the "which project?" step.
	var recentProjects: [FavoriteProject] { projects.sorted { $0.lastUsed > $1.lastUsed } }

	var isEmpty: Bool { projects.isEmpty && loose.isEmpty }

	private func changed() {
		if persistent, let data = try? JSONEncoder().encode(Saved(projects: projects, loose: loose, currentProjectID: currentProjectID)) {
			UserDefaults.standard.set(data, forKey: Self.key)
		}
		NotificationCenter.default.post(name: .favoritesChanged, object: self)
	}

	// MARK: Projects

	@discardableResult
	func newProject(named name: String, makeCurrent: Bool = true) -> FavoriteProject {
		let base = name.trimmingCharacters(in: .whitespaces).isEmpty ? "New project" : name.trimmingCharacters(in: .whitespaces)
		var unique = base
		var n = 2
		while projects.contains(where: { $0.name == unique }) {
			unique = "\(base) \(n)"
			n += 1
		}
		let p = FavoriteProject(name: unique)
		projects.append(p)
		if makeCurrent { currentProjectID = p.id }
		changed()
		return p
	}

	func setCurrent(_ project: FavoriteProject?) {
		guard currentProjectID != project?.id else { return }
		currentProjectID = project?.id
		project?.lastUsed = Date()
		changed()
	}

	func rename(_ project: FavoriteProject, to name: String) {
		let t = name.trimmingCharacters(in: .whitespaces)
		guard !t.isEmpty else { return }
		project.name = t
		changed()
	}

	func removeProject(_ project: FavoriteProject) {
		projects.removeAll { $0 === project }
		if currentProjectID == project.id { currentProjectID = nil }
		changed()
	}

	func setExpanded(_ project: FavoriteProject, _ expanded: Bool) {
		guard project.expanded != expanded else { return }
		project.expanded = expanded
		changed()
	}

	// MARK: Items

	/// Adds files to a project (or outside any project when nil), skipping ones already there.
	/// Returns how many were added.
	@discardableResult
	func add(_ files: [(siteID: String, path: String, siteName: String)], to project: FavoriteProject?) -> Int {
		var added = 0
		for f in files {
			let existing = project?.items ?? loose
			guard !existing.contains(where: { $0.same(f.siteID, f.path) }) else { continue }
			let item = FavoriteItem(siteID: f.siteID, path: f.path, siteName: f.siteName)
			if let project { project.items.append(item) } else { loose.append(item) }
			added += 1
		}
		project?.lastUsed = Date()
		changed()
		return added
	}

	func remove(_ items: [FavoriteItem]) {
		let ids = Set(items.map(\.id))
		for p in projects { p.items.removeAll { ids.contains($0.id) } }
		loose.removeAll { ids.contains($0.id) }
		changed()
	}

	/// Removes a file from every project it's in (the tab star's "un-favorite").
	func removeEverywhere(siteID: String, path: String) {
		for p in projects { p.items.removeAll { $0.same(siteID, path) } }
		loose.removeAll { $0.same(siteID, path) }
		changed()
	}

	func project(containing item: FavoriteItem) -> FavoriteProject? {
		projects.first { $0.items.contains { $0 === item } }
	}

	/// Moves favorites into a project (nil = outside any project) at an index (nil = the end).
	func move(_ items: [FavoriteItem], to project: FavoriteProject?, at index: Int?) {
		let ids = Set(items.map(\.id))
		var target = project?.items ?? loose
		// Removing earlier items from the same list shifts the drop position.
		var insertAt = index ?? target.count
		insertAt -= target.prefix(min(insertAt, target.count)).filter { ids.contains($0.id) }.count
		for p in projects { p.items.removeAll { ids.contains($0.id) } }
		loose.removeAll { ids.contains($0.id) }
		target = project?.items ?? loose
		var moving = items
		moving.removeAll { m in target.contains { $0.same(m.siteID, m.path) } }
		target.insert(contentsOf: moving, at: max(0, min(insertAt, target.count)))
		if let project { project.items = target } else { loose = target }
		changed()
	}

	func isFavorite(siteID: String, path: String) -> Bool {
		loose.contains { $0.same(siteID, path) } || projects.contains { $0.items.contains { $0.same(siteID, path) } }
	}

	// MARK: Filter

	/// What the panel shows for a filter: projects whose name matches keep all their files,
	/// others keep only matching files and disappear when none match.
	func filtered(_ text: String) -> (projects: [(FavoriteProject, [FavoriteItem])], loose: [FavoriteItem]) {
		let q = text.trimmingCharacters(in: .whitespaces).lowercased()
		guard !q.isEmpty else { return (projects.map { ($0, $0.items) }, loose) }
		func hit(_ i: FavoriteItem) -> Bool { i.name.lowercased().contains(q) || i.siteLabel.lowercased().contains(q) || i.path.lowercased().contains(q) }
		let ps = projects.compactMap { p -> (FavoriteProject, [FavoriteItem])? in
			if p.name.lowercased().contains(q) { return (p, p.items) }
			let items = p.items.filter(hit)
			return items.isEmpty ? nil : (p, items)
		}
		return (ps, loose.filter(hit))
	}

	// MARK: Demo data (IDEPLUS_FAVORITES_DEMO, for screenshots)

	func loadDemo() {
		let a = newProject(named: "Client A redesign")
		add([("demo1", "public_html/wp-content/themes/clienta/header.php", "mysite.com"),
			 ("demo1", "public_html/wp-content/themes/clienta/style.css", "mysite.com"),
			 ("demo2", "public_html/config.php", "staging.long-client-domain.com")], to: a)
		let b = newProject(named: "Blog fixes", makeCurrent: false)
		add([("demo1", "public_html/blog/index.php", "mysite.com")], to: b)
		b.expanded = false
		add([("demo1", "public_html/.htaccess", "mysite.com")], to: nil)
		setCurrent(a)
	}
}
