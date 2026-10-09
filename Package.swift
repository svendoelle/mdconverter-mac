// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MDConverter",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ConverterCore"),
        .executableTarget(name: "MDConverter", dependencies: ["ConverterCore"]),
        .testTarget(name: "ConverterCoreTests", dependencies: ["ConverterCore"]),
    ]
)
