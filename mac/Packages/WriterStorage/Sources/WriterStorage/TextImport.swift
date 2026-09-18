import Foundation
import WriterFoundation

public enum TextImportEncoding: String, Codable, CaseIterable, Sendable {
    case utf8, utf16LittleEndian, utf16BigEndian, windows1252, latin1
    public var title: String {
        switch self {
        case .utf8: "UTF-8 (preserve exact bytes)"
        case .utf16LittleEndian: "UTF-16 Little Endian"
        case .utf16BigEndian: "UTF-16 Big Endian"
        case .windows1252: "Windows-1252"
        case .latin1: "ISO Latin-1"
        }
    }
}

public struct TextImportReceipt: Codable, Sendable, Equatable {
    public let encoding: TextImportEncoding
    public let originalDigest: Data
    public let originalByteCount: Int
    public let convertedDigest: Data
    func validate() throws {
        guard originalByteCount >= 0, originalByteCount <= CoordinatedSourceFiles.maximumBytes,
              originalDigest.count == 32, convertedDigest.count == 32 else { throw SourceFileError.invalidUTF8 }
    }
}

public struct TextImportCopy: Sendable {
    public let bytes: Data
    public let receipt: TextImportReceipt
}

public enum TextImport {
    /// Never guesses an encoding and never inserts replacement characters.
    /// This produces a new imported source; it does not write the selected file.
    public static func convert(_ original: Data, encoding: TextImportEncoding) throws -> TextImportCopy {
        guard original.count <= CoordinatedSourceFiles.maximumBytes else { throw SourceFileError.sourceTooLarge }
        let result: Data
        switch encoding {
        case .utf8:
            guard SourceSnapshot.firstInvalidUTF8Offset(in: original) == nil else { throw SourceFileError.invalidUTF8 }
            result = original // Preserve BOM, normalization, CRLF and whitespace.
        case .utf16LittleEndian, .utf16BigEndian:
            let raw = Array(original)
            guard raw.count.isMultiple(of: 2) else { throw SourceFileError.invalidUTF8 }
            let little = encoding == .utf16LittleEndian
            var units: [UInt16] = []; units.reserveCapacity(raw.count / 2)
            for i in stride(from: 0, to: raw.count, by: 2) {
                units.append(little ? UInt16(raw[i]) | UInt16(raw[i+1]) << 8 : UInt16(raw[i]) << 8 | UInt16(raw[i+1]))
            }
            if units.first == 0xfeff { units.removeFirst() } // Explicit conversion consumes the matching encoding marker.
            var i = 0
            while i < units.count {
                let unit = units[i]
                if (0xd800...0xdbff).contains(unit) {
                    guard i + 1 < units.count, (0xdc00...0xdfff).contains(units[i+1]) else { throw SourceFileError.invalidUTF8 }
                    i += 2
                } else {
                    guard !(0xdc00...0xdfff).contains(unit) else { throw SourceFileError.invalidUTF8 }
                    i += 1
                }
            }
            result = Data(String(decoding: units, as: UTF16.self).utf8)
        case .windows1252, .latin1:
            let selected: String.Encoding = encoding == .windows1252 ? .windowsCP1252 : .isoLatin1
            guard let text = String(data: original, encoding: selected),
                  text.data(using: selected, allowLossyConversion: false) == original else { throw SourceFileError.invalidUTF8 }
            result = Data(text.utf8)
        }
        guard result.count <= CoordinatedSourceFiles.maximumBytes,
              String(decoding: result, as: UTF8.self).unicodeScalars.count <= CoordinatedSourceFiles.maximumScalars else { throw SourceFileError.sourceTooLarge }
        return TextImportCopy(bytes: result, receipt: TextImportReceipt(encoding: encoding,
            originalDigest: SourceSnapshot.sha256(original), originalByteCount: original.count,
            convertedDigest: SourceSnapshot.sha256(result)))
    }
}
