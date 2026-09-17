// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WriterHWP", platforms: [.macOS(.v14)],
    products: [.library(name: "WriterHWP", targets: ["WriterHWP"]), .executable(name: "hwp-verify", targets: ["HWPVerifyCLI"])],
    dependencies: [
        .package(path: "../WriterFoundation"),
        .package(url: "https://github.com/attaswift/BigInt.git", revision: "e07e00fa1fd435143a2dcf8b7eec9a7710b2fdfe")
    ],
    targets: [
        .target(name: "WriterHWP", dependencies: ["WriterFoundation", .product(name: "BigInt", package: "BigInt")]),
        .executableTarget(name: "HWPVerifyCLI", dependencies: ["WriterHWP"])
    ],
    swiftLanguageModes: [.v6]
)
