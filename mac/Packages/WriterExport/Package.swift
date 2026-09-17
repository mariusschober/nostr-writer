// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WriterExport", platforms: [.macOS(.v14)],
    products: [.library(name: "WriterExport", targets: ["WriterExport"])],
    dependencies: [
        .package(path: "../WriterFoundation"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", revision: "7d9a5ce307528578dfa777d505496bd5f544ad94"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", revision: "22787ffb59de99e5dc1fbfe80b19c97a904ad48d"),
        .package(url: "https://github.com/swiftlang/swift-cmark.git", revision: "924936d0427cb25a61169739a7660230bffa6ea6")
    ],
    targets: [
        .target(name: "WriterExport", dependencies: ["WriterFoundation", .product(name: "Markdown", package: "swift-markdown"), .product(name: "ZIPFoundation", package: "ZIPFoundation")])
    ],
    swiftLanguageModes: [.v6]
)
