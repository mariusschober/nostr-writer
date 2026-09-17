// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WriterStorage", platforms: [.macOS(.v14)],
    products: [.library(name: "WriterStorage", targets: ["WriterStorage"])],
    dependencies: [
        .package(path: "../WriterFoundation")
    ],
    targets: [
        // Narrow system-library shim so the core can use the platform SQLite
        // library directly. No third-party dependency is introduced.
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "WriterStorage", dependencies: ["WriterFoundation", "CSQLite"]),
        .testTarget(
            name: "WriterStorageTests",
            dependencies: ["WriterStorage", "WriterFoundation", "CSQLite"]
        )
    ],
    swiftLanguageModes: [.v6]
)
