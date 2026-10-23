// swift-tools-version:5.9
import PackageDescription

let package = Package(
	name: "IDEPlus",
	platforms: [.macOS(.v13)],
	targets: [
		.executableTarget(name: "IDEPlus", path: "Sources/IDEPlus")
	]
)
