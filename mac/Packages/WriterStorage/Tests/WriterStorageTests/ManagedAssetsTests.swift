import XCTest
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import WriterStorage
import WriterFoundation

@MainActor
final class ManagedAssetsTests: XCTestCase {
    func testImageImportCopiesExactBytesAndNeverOverwritesOrFollowsLinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nw-assets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
        for folder in [source, destination] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
        let pixels = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = NSMutableData(), image = try XCTUnwrap(pixels.makeImage())
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, image, nil); XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let bytes = data as Data, original = root.appendingPathComponent("selected.png")
        try bytes.write(to: original)
        let io = ManagedAssets()
        let owned = try await io.importImage(original, documentName: "Café Draft.md", into: source, existing: [])
        XCTAssertEqual(owned.width, 2); XCTAssertEqual(owned.height, 2)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathComponent(owned.relativePath)), bytes)
        XCTAssertEqual(owned.markdownPath.removingPercentEncoding, owned.relativePath)
        try await io.copy([owned], from: source, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(owned.relativePath)), bytes)
        let neighbor = destination.appendingPathComponent("unrelated.png"), unrelated = Data("unrelated".utf8)
        try unrelated.write(to: neighbor)
        do { try await io.copy([owned], from: source, to: destination); XCTFail("Occupied destination must be refused") }
        catch { XCTAssertEqual(error as? SourceFileError, .alreadyExists) }
        XCTAssertEqual(try Data(contentsOf: neighbor), unrelated)
        let linkRoot = root.appendingPathComponent("symlink-root")
        try FileManager.default.createDirectory(at: linkRoot, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: linkRoot.appendingPathComponent("Linked.assets"), withDestinationURL: destination)
        do { _ = try await io.importImage(original, documentName: "Linked.md", into: linkRoot, existing: []); XCTFail("Symlink must be refused") }
        catch { XCTAssertEqual(error as? SourceFileError, .invalidLocation) }
        try Data("tampered".utf8).write(to: source.appendingPathComponent(owned.relativePath))
        do { try await io.verify([owned], in: source); XCTFail("Changed bytes must be refused") }
        catch { XCTAssertEqual(error as? SourceFileError, .externalChange) }
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        let invalid = ManagedAsset(id: UUID(), relativePath: "../escape.png", digest: owned.digest, byteCount: 10, width: 1, height: 1)
        XCTAssertThrowsError(try invalid.validate())
        let tooLarge = ManagedAsset(id: UUID(), relativePath: "Valid.assets/test.png", digest: owned.digest, byteCount: 20*1024*1024+1, width: 1, height: 1)
        XCTAssertThrowsError(try tooLarge.validate())
        let tooManyPixels = ManagedAsset(id: UUID(), relativePath: "Valid.assets/test.png", digest: owned.digest, byteCount: 10, width: Int.max, height: 2)
        XCTAssertThrowsError(try tooManyPixels.validate())
    }
}
