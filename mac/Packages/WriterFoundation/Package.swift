// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WriterFoundation",
    platforms: [.macOS(.v14)],
    products: [.library(name: "WriterFoundation", targets: ["WriterFoundation"])],
    targets: [
        .target(name: "WriterFoundation"),
        .testTarget(name: "WriterFoundationTests", dependencies: ["WriterFoundation"])
    ],
    swiftLanguageModes: [.v6]
)
