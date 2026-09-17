// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "WriterNostr", platforms: [.macOS(.v14)],
    products: [.library(name: "WriterNostr", targets: ["WriterNostr"])],
    dependencies: [
        .package(path: "../WriterFoundation"),
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1.git", revision: "e70a10e036a55fffea31568f0af92d69b6d449cd"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", revision: "e45a26384239e028ec87fbcc788f513b67e10d8f")
    ],
    targets: [
        .target(name: "WriterNostr", dependencies: ["WriterFoundation", .product(name: "P256K", package: "swift-secp256k1"), .product(name: "CryptoSwift", package: "CryptoSwift")])
    ],
    swiftLanguageModes: [.v6]
)
