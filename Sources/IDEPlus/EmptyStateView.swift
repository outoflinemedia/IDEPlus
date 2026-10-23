import AppKit

/// Shown when no files are open: how to open one, with rocks drifting behind.
/// Space starts a small game, Space Rocks (arrows turn and thrust, Space fires, Esc stops).
final class EmptyStateView: NSView {
	/// Double-click on the empty area: a new file, like double-clicking an empty tab bar.
	var onNewFile: (() -> Void)?

	private struct Rock {
		var pos: CGPoint
		var vel: CGVector
		var radius: CGFloat
		var angle: CGFloat
		var spin: CGFloat
		/// Outline as radius factors, one per vertex, so each rock keeps its shape.
		var shape: [CGFloat]
	}

	private struct Shot {
		var pos: CGPoint
		var vel: CGVector
		var life: Double
	}

	private struct Spark {
		var pos: CGPoint
		var vel: CGVector
		var life: Double
	}

	private enum Mode { case idle, playing, over }

	private var mode = Mode.idle
	private var rocks: [Rock] = []
	private var shots: [Shot] = []
	private var sparks: [Spark] = []
	private var ship = CGPoint.zero
	private var shipVel = CGVector.zero
	/// Radians, 0 = pointing right, counter-clockwise.
	private var shipAngle = CGFloat.pi / 2
	private var thrusting = false
	/// Seconds left of the blinking "can't be hit" time after a new ship appears.
	private var safeTime = 0.0
	private var keys = Set<UInt16>()
	private var score = 0
	private var lives = 3
	private var level = 1
	private var fireCooldown = 0.0
	private var timer: Timer?
	private var lastTick = Date()
	private var built = false

	private static let highScoreKey = "spaceRocksHighScore"
	private var highScore: Int {
		get { UserDefaults.standard.integer(forKey: Self.highScoreKey) }
		set { UserDefaults.standard.set(newValue, forKey: Self.highScoreKey) }
	}

	private enum Key {
		static let left: UInt16 = 123, right: UInt16 = 124, up: UInt16 = 126, space: UInt16 = 49, escape: UInt16 = 53
	}

	override var acceptsFirstResponder: Bool { true }
	override var isFlipped: Bool { false }

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		updateTimer()
	}

	override var isHidden: Bool {
		didSet {
			if isHidden { stopGame() }
			updateTimer()
		}
	}

	override func layout() {
		super.layout()
		if !built, bounds.width > 50 {
			built = true
			rocks = (0..<6).map { _ in makeRock(radius: .random(in: 18...46), near: nil, speed: 14) }
		}
	}

	// MARK: Timer

	/// Runs only while the view is on screen: 60 frames a second in a game, 30 while idle.
	private func updateTimer() {
		let shouldRun = window != nil && !isHidden
		if !shouldRun {
			timer?.invalidate()
			timer = nil
			return
		}
		let interval = mode == .playing ? 1.0 / 60 : 1.0 / 30
		if let timer, abs(timer.timeInterval - interval) < 0.001 { return }
		timer?.invalidate()
		lastTick = Date()
		let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
		RunLoop.main.add(t, forMode: .common)
		timer = t
	}

	private func tick() {
		let now = Date()
		let dt = min(now.timeIntervalSince(lastTick), 0.05)
		lastTick = now
		// Nothing to animate while the window is hidden behind others or minimised.
		guard let window, window.occlusionState.contains(.visible) else { return }
		step(CGFloat(dt))
		needsDisplay = true
	}

	// MARK: Game

	private func startGame() {
		mode = .playing
		score = 0
		lives = 3
		level = 1
		shots = []
		sparks = []
		newShip()
		newLevel()
		updateTimer()
	}

	private func stopGame() {
		guard mode != .idle else { return }
		mode = .idle
		keys = []
		thrusting = false
		shots = []
		if rocks.isEmpty { rocks = (0..<6).map { _ in makeRock(radius: .random(in: 18...46), near: nil, speed: 14) } }
		updateTimer()
		needsDisplay = true
	}

	private func newShip() {
		ship = CGPoint(x: bounds.midX, y: bounds.midY)
		shipVel = .zero
		shipAngle = .pi / 2
		safeTime = 2
	}

	private func newLevel() {
		// New rocks keep away from the ship.
		rocks = (0..<(3 + level)).map { _ in makeRock(radius: 44, near: ship, speed: 40 + CGFloat(level) * 8) }
	}

	private func makeRock(radius: CGFloat, near avoid: CGPoint?, speed: CGFloat) -> Rock {
		var pos: CGPoint
		repeat {
			pos = CGPoint(x: .random(in: 0...max(1, bounds.width)), y: .random(in: 0...max(1, bounds.height)))
		} while avoid.map { hypot(pos.x - $0.x, pos.y - $0.y) < 160 } ?? false && bounds.width > 400
		let dir = CGFloat.random(in: 0..<(2 * .pi))
		let v = speed * .random(in: 0.6...1.2)
		return Rock(pos: pos, vel: CGVector(dx: cos(dir) * v, dy: sin(dir) * v), radius: radius,
					angle: .random(in: 0..<(2 * .pi)), spin: .random(in: -0.8...0.8),
					shape: (0..<11).map { _ in .random(in: 0.72...1.12) })
	}

	private func wrap(_ p: inout CGPoint, margin: CGFloat) {
		let w = bounds.width, h = bounds.height
		if p.x < -margin { p.x += w + 2 * margin } else if p.x > w + margin { p.x -= w + 2 * margin }
		if p.y < -margin { p.y += h + 2 * margin } else if p.y > h + margin { p.y -= h + 2 * margin }
	}

	private func step(_ dt: CGFloat) {
		for i in rocks.indices {
			rocks[i].pos.x += rocks[i].vel.dx * dt
			rocks[i].pos.y += rocks[i].vel.dy * dt
			rocks[i].angle += rocks[i].spin * dt
			wrap(&rocks[i].pos, margin: rocks[i].radius)
		}
		for i in sparks.indices {
			sparks[i].pos.x += sparks[i].vel.dx * dt
			sparks[i].pos.y += sparks[i].vel.dy * dt
			sparks[i].life -= Double(dt)
		}
		sparks.removeAll { $0.life <= 0 }
		guard mode == .playing else { return }

		// Ship
		if keys.contains(Key.left) { shipAngle += 4.2 * dt }
		if keys.contains(Key.right) { shipAngle -= 4.2 * dt }
		thrusting = keys.contains(Key.up)
		if thrusting {
			shipVel.dx += cos(shipAngle) * 260 * dt
			shipVel.dy += sin(shipAngle) * 260 * dt
		}
		let drag = pow(0.55, dt)
		shipVel.dx *= drag
		shipVel.dy *= drag
		ship.x += shipVel.dx * dt
		ship.y += shipVel.dy * dt
		wrap(&ship, margin: 10)
		safeTime = max(0, safeTime - Double(dt))

		// Shots
		fireCooldown = max(0, fireCooldown - Double(dt))
		if keys.contains(Key.space), fireCooldown == 0, shots.count < 6 {
			let nose = CGPoint(x: ship.x + cos(shipAngle) * 12, y: ship.y + sin(shipAngle) * 12)
			shots.append(Shot(pos: nose, vel: CGVector(dx: cos(shipAngle) * 520 + shipVel.dx, dy: sin(shipAngle) * 520 + shipVel.dy), life: 0.9))
			fireCooldown = 0.22
		}
		for i in shots.indices {
			shots[i].pos.x += shots[i].vel.dx * dt
			shots[i].pos.y += shots[i].vel.dy * dt
			shots[i].life -= Double(dt)
			wrap(&shots[i].pos, margin: 0)
		}
		shots.removeAll { $0.life <= 0 }

		// Shots hit rocks: big rocks split in two, small ones break up.
		var newRocks: [Rock] = []
		rocks.removeAll { rock in
			guard let hit = shots.firstIndex(where: { hypot($0.pos.x - rock.pos.x, $0.pos.y - rock.pos.y) < rock.radius }) else { return false }
			shots.remove(at: hit)
			score += rock.radius > 30 ? 20 : rock.radius > 16 ? 50 : 100
			burst(at: rock.pos, count: 10)
			if rock.radius > 16 {
				for _ in 0..<2 {
					var piece = makeRock(radius: rock.radius / 2, near: nil, speed: 70 + CGFloat(level) * 10)
					piece.pos = rock.pos
					newRocks.append(piece)
				}
			}
			return true
		}
		rocks += newRocks
		if rocks.isEmpty {
			level += 1
			newLevel()
		}

		// Rocks hit the ship.
		if safeTime == 0, rocks.contains(where: { hypot($0.pos.x - ship.x, $0.pos.y - ship.y) < $0.radius + 8 }) {
			burst(at: ship, count: 24)
			lives -= 1
			if lives > 0 {
				newShip()
			} else {
				mode = .over
				keys = []
				thrusting = false
				highScore = max(highScore, score)
				updateTimer()
			}
		}
	}

	private func burst(at p: CGPoint, count: Int) {
		for _ in 0..<count {
			let dir = CGFloat.random(in: 0..<(2 * .pi)), v = CGFloat.random(in: 30...160)
			sparks.append(Spark(pos: p, vel: CGVector(dx: cos(dir) * v, dy: sin(dir) * v), life: .random(in: 0.3...0.8)))
		}
	}

	// MARK: Keys and mouse

	override func keyDown(with event: NSEvent) {
		let code = event.keyCode
		switch mode {
		case .idle, .over:
			if code == Key.space { startGame() } else if code == Key.escape, mode == .over { stopGame() } else { super.keyDown(with: event) }
		case .playing:
			if code == Key.escape { stopGame(); return }
			if [Key.left, Key.right, Key.up, Key.space].contains(code) { keys.insert(code) } else { super.keyDown(with: event) }
		}
	}

	override func keyUp(with event: NSEvent) {
		keys.remove(event.keyCode)
	}

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		if event.clickCount == 2, mode != .playing { onNewFile?() }
	}

	override func resignFirstResponder() -> Bool {
		keys = []
		return true
	}

	// MARK: Drawing

	override func draw(_ dirtyRect: NSRect) {
		NSColor.textBackgroundColor.setFill()
		bounds.fill()

		let line = mode == .idle ? NSColor.tertiaryLabelColor : NSColor.secondaryLabelColor
		line.setStroke()
		for rock in rocks {
			let path = NSBezierPath()
			for (i, f) in rock.shape.enumerated() {
				let a = rock.angle + CGFloat(i) / CGFloat(rock.shape.count) * 2 * .pi
				let p = CGPoint(x: rock.pos.x + cos(a) * rock.radius * f, y: rock.pos.y + sin(a) * rock.radius * f)
				if i == 0 { path.move(to: p) } else { path.line(to: p) }
			}
			path.close()
			path.lineWidth = 1.5
			path.stroke()
		}
		for s in sparks {
			NSColor.controlAccentColor.withAlphaComponent(CGFloat(min(1, s.life * 2))).setFill()
			NSRect(x: s.pos.x - 1, y: s.pos.y - 1, width: 2, height: 2).fill()
		}

		switch mode {
		case .idle:
			drawCentered([
				("No files open", .systemFont(ofSize: 20, weight: .semibold), .secondaryLabelColor),
				("⌘N  New file      ⌘O  Open      ⌃⌘O  Open from FTP", .systemFont(ofSize: 12), .tertiaryLabelColor),
				("", .systemFont(ofSize: 8), .clear),
				("Press Space to play Space Rocks", .systemFont(ofSize: 12, weight: .medium), .controlAccentColor),
			])
		case .playing:
			drawShip()
			NSColor.labelColor.setFill()
			for s in shots { NSBezierPath(ovalIn: NSRect(x: s.pos.x - 1.5, y: s.pos.y - 1.5, width: 3, height: 3)).fill() }
			drawHUD()
		case .over:
			drawHUD()
			drawCentered([
				("Game over", .systemFont(ofSize: 20, weight: .semibold), .secondaryLabelColor),
				("Score \(score)    Best \(highScore)", .monospacedDigitSystemFont(ofSize: 12, weight: .regular), .tertiaryLabelColor),
				("", .systemFont(ofSize: 8), .clear),
				("Space to play again    Esc to stop", .systemFont(ofSize: 12, weight: .medium), .controlAccentColor),
			])
		}
	}

	private func drawShip() {
		// Blink while the new ship can't be hit.
		if safeTime > 0, Int(safeTime * 8) % 2 == 0 { return }
		func pt(_ a: CGFloat, _ r: CGFloat) -> CGPoint { CGPoint(x: ship.x + cos(shipAngle + a) * r, y: ship.y + sin(shipAngle + a) * r) }
		let hull = NSBezierPath()
		hull.move(to: pt(0, 13))
		hull.line(to: pt(2.5, 10))
		hull.line(to: pt(.pi, 4))
		hull.line(to: pt(-2.5, 10))
		hull.close()
		hull.lineWidth = 1.6
		NSColor.labelColor.setStroke()
		hull.stroke()
		if thrusting, Int(Date().timeIntervalSince1970 * 20) % 2 == 0 {
			let flame = NSBezierPath()
			flame.move(to: pt(2.75, 7))
			flame.line(to: pt(.pi, 13))
			flame.line(to: pt(-2.75, 7))
			flame.lineWidth = 1.4
			NSColor.systemOrange.setStroke()
			flame.stroke()
		}
	}

	private func drawHUD() {
		let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
		NSAttributedString(string: "\(score)", attributes: attrs).draw(at: CGPoint(x: 14, y: bounds.maxY - 26))
		let right = NSAttributedString(string: String(repeating: "▲ ", count: max(0, lives)) + "  Level \(level)   Esc to stop", attributes: attrs)
		right.draw(at: CGPoint(x: bounds.maxX - right.size().width - 14, y: bounds.maxY - 26))
	}

	private func drawCentered(_ lines: [(String, NSFont, NSColor)]) {
		let strings = lines.map { NSAttributedString(string: $0.0, attributes: [.font: $0.1, .foregroundColor: $0.2]) }
		let gap: CGFloat = 8
		let total = strings.reduce(0) { $0 + $1.size().height } + gap * CGFloat(strings.count - 1)
		var y = bounds.midY + total / 2
		for s in strings {
			let size = s.size()
			y -= size.height
			s.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: y))
			y -= gap
		}
	}

	// MARK: Snapshot hook (IDEPLUS_SNAPSHOT_EMPTY)

	/// For the self-test: where the game stands.
	var debugSummary: String {
		"mode=\(mode) lives=\(lives) score=\(score) rocks=\(rocks.count) shots=\(shots.count) angle=\(Int(shipAngle * 100)) ship=\(Int(ship.x)),\(Int(ship.y))"
	}

	/// Starts a game and runs it for a moment with the ship turning and firing, for a screenshot.
	func playDemo(seconds: Double) {
		startGame()
		keys = [Key.left, Key.space, Key.up]
		for _ in 0..<Int(seconds * 60) { step(1.0 / 60) }
		keys = []
		safeTime = 0
		needsDisplay = true
	}
}
