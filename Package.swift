// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "AetherSeekCore", platforms: [.macOS("26.0")],
  products: [.library(name: "AetherSeekCore", targets: ["AetherSeekCore"])],
  targets: [
    .target(name: "AetherSeekCore", path: "Sources/Core"),
    .testTarget(name: "AetherSeekCoreTests", dependencies: ["AetherSeekCore"], path: "Tests/Core"),
  ])
