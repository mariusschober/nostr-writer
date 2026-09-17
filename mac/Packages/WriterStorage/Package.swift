// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WriterStorage", platforms: [.macOS(.v14)],
    products: [.library(name: "WriterStorage", targets: ["WriterStorage"])],
    dependencies: [
        .package(path: "../WriterFoundation")
    ],
    targets: [
        .target(name: "WriterStorage", dependencies: ["WriterFoundation"])
    ],
    swiftLanguageModes: [.v6]
)
