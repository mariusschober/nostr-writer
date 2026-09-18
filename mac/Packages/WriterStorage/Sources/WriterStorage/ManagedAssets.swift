import Foundation
import ImageIO
import UniformTypeIdentifiers
import WriterFoundation

public struct ManagedAsset: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let relativePath: String
    public let digest: Data
    public let byteCount: Int
    public let width: Int
    public let height: Int
    public var markdownPath: String {
        relativePath.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/"))!
    }

    public func validate() throws {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].hasSuffix(".assets"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains("\0") }),
              relativePath.utf8.count <= 1024, ["png", "jpg"].contains(URL(fileURLWithPath: relativePath).pathExtension.lowercased()),
              digest.count == 32, byteCount > 0, byteCount <= 20 * 1024 * 1024,
              width > 0, height > 0, width <= 50_000_000 / height else { throw SourceFileError.invalidLocation }
    }

    public static func validateSet(_ assets: [ManagedAsset]) throws {
        guard assets.count <= 4096, Set(assets.map(\.relativePath)).count == assets.count,
              Set(assets.map(\.id)).count == assets.count else { throw SourceFileError.sourceTooLarge }
        var total = 0
        for asset in assets {
            try asset.validate(); total += asset.byteCount
            guard total <= 100 * 1024 * 1024 else { throw SourceFileError.sourceTooLarge }
        }
    }
}

/// Image I/O stays outside the editor. The caller must acquire the selected
/// image and exact source/destination folder grants for these operations.
public actor ManagedAssets {
    private let files = CoordinatedSourceFiles()
    public init() {}

    public func importImage(_ selected: URL, documentName: String, into folder: URL, existing: [ManagedAsset]) async throws -> ManagedAsset {
        try ManagedAsset.validateSet(existing)
        let bytes = try await files.readBinaryInput(selected, maximumBytes: 20 * 1024 * 1024)
        guard let image = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(image) == 1, let type = CGImageSourceGetType(image) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 50_000_000 / height else { throw SourceFileError.sourceTooLarge }
        guard CGImageSourceCreateThumbnailAtIndex(image, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else { throw SourceFileError.notRegularFile }
        let stem = URL(fileURLWithPath: documentName).deletingPathExtension().lastPathComponent
        guard !stem.isEmpty, stem != ".", stem != "..", !stem.contains("/"), !stem.contains("\\") else { throw SourceFileError.invalidLocation }
        let id = UUID()
        let asset = ManagedAsset(id: id, relativePath: "\(stem).assets/\(id.uuidString.lowercased()).\(type == UTType.png.identifier ? "png" : "jpg")",
            digest: SourceSnapshot.sha256(bytes), byteCount: bytes.count, width: width, height: height)
        try ManagedAsset.validateSet(existing + [asset])
        let target = try assetURL(asset, root: folder)
        try prepareDirectory(target.deletingLastPathComponent(), root: folder)
        try await files.createAssetBytes(bytes, at: target)
        return asset
    }

    /// Keep relative links stable. An occupied destination is never adopted or
    /// replaced just because its bytes happen to match. Same-folder Save As can
    /// explicitly share the already-owned paths without another physical copy.
    public func copy(_ assets: [ManagedAsset], from sourceFolder: URL, to destinationFolder: URL) async throws {
        try ManagedAsset.validateSet(assets)
        let sameFolder = sourceFolder.standardizedFileURL.resolvingSymlinksInPath() == destinationFolder.standardizedFileURL.resolvingSymlinksInPath()
        for asset in assets {
            try Task.checkCancellation()
            let source = try assetURL(asset, root: sourceFolder)
            let bytes = try await files.readBinaryInput(source, maximumBytes: 20 * 1024 * 1024)
            guard bytes.count == asset.byteCount, SourceSnapshot.sha256(bytes) == asset.digest else { throw SourceFileError.externalChange }
            if sameFolder { continue }
            let target = try assetURL(asset, root: destinationFolder)
            try prepareDirectory(target.deletingLastPathComponent(), root: destinationFolder)
            try await files.createAssetBytes(bytes, at: target)
        }
    }

    public func verify(_ assets: [ManagedAsset], in folder: URL) async throws {
        try await copy(assets, from: folder, to: folder)
    }

    private func assetURL(_ asset: ManagedAsset, root: URL) throws -> URL {
        try asset.validate()
        guard root.isFileURL else { throw SourceFileError.invalidLocation }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = asset.relativePath.split(separator: "/").reduce(base) { $0.appendingPathComponent(String($1)) }.standardizedFileURL
        guard LibraryFolders.contains(candidate, in: base) else { throw SourceFileError.invalidLocation }
        return candidate
    }

    private func prepareDirectory(_ directory: URL, root: URL) throws {
        guard LibraryFolders.contains(directory, in: root) else { throw SourceFileError.invalidLocation }
        var error: NSError?, result: Result<Void, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: directory, options: [], error: &error) { target in
            result = Result {
                if FileManager.default.fileExists(atPath: target.path) {
                    let values = try target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values.isDirectory == true, values.isSymbolicLink != true else { throw SourceFileError.invalidLocation }
                } else { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
            }
        }
        if error != nil { throw SourceFileError.permissionDenied }
        guard let result else { throw SourceFileError.unavailable }; try result.get()
    }
}
