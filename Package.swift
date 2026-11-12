// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AulaStudio",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AulaCore", path: "Sources/AulaCore"),
        .executableTarget(name: "AulaStudio", dependencies: ["AulaCore"], path: "Sources/AulaStudio"),
        // Hardware-free checks of the protocol encoders: `swift run SelfCheck`.
        .executableTarget(name: "SelfCheck", dependencies: ["AulaCore"], path: "Sources/SelfCheck"),
    ]
)
