// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Morrow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "morrow-cli", targets: ["MorrowCLI"]),
        .executable(name: "MorrowMenuBar", targets: ["MorrowApp"]),
        .library(name: "MorrowCore", targets: ["MorrowCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .systemLibrary(name: "CLaunch"),
        .systemLibrary(name: "CArchive"),
        .target(name: "MorrowCore", dependencies: ["CLaunch", "CArchive"]),
        .executableTarget(name: "MorrowCLI", dependencies: ["MorrowCore"]),
        .executableTarget(name: "MorrowApp", dependencies: ["MorrowCore", .product(name: "Sparkle", package: "Sparkle")],
                          resources: [.copy("Assets")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "MorrowCoreTests", dependencies: ["MorrowCore"]),
        .testTarget(name: "MorrowAppTests", dependencies: ["MorrowApp", "MorrowCore"]),
    ],
    swiftLanguageModes: [.v5]
)
