import Foundation
import WriterFoundation

/// One navigable outline entry derived from the document's Markdown structure.
///
/// The outline is a view of exact source: it never rewrites text and never
/// invents structure. Unsupported or malformed content is left as ordinary
/// editable source.
struct OutlineItem: Hashable, Sendable {
    let level: Int
    let title: String
    /// Exact scalar-aligned byte range of the heading's text in the source.
    let byteRange: ByteRange
}

/// A pure, revision-bound Markdown outline reader using the EXPORT grammar's
/// ATX (`#`) and Setext (`===`/`---`) headings. Fenced code blocks are excluded.
struct EditorOutline {
    /// Computes the outline for `source`. Results are bound to the source the
    /// caller parsed: a later revision must re-run rather than reuse them.
    static func items(in source: SourceSnapshot) -> [OutlineItem] {
        var items: [OutlineItem] = []
        var scalarOffset = 0   // UTF-8 byte offset of the current line
        var inFence = false
        var fenceMarker: Character?
        let text = source.string
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : String(rawLine)
            let lineBytes = line.utf8.count + (rawLine.hasSuffix("\r") ? 1 : 0)
            defer { scalarOffset += lineBytes + 1 /* newline */ }

            let trimmed = line.drop(while: { $0 == " " })
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = trimmed.first!
                if inFence && marker == fenceMarker { inFence = false; fenceMarker = nil }
                else if !inFence { inFence = true; fenceMarker = marker }
                continue
            }
            if inFence { continue }

            // ATX heading: 1-6 leading '#' followed by space or end.
            if let atx = atxHeading(line) {
                let title = atx.title
                if let range = byteRange(of: title, in: line, lineStart: scalarOffset) {
                    items.append(OutlineItem(level: atx.level, title: title, byteRange: range))
                }
                continue
            }
            // Setext heading: a non-empty line underlined by ===/---.
            if index + 1 < lines.count, let next = lines[safe: index + 1] {
                let underline = next.trimmingCharacters(in: .whitespaces)
                if !line.isEmpty, underline.allSatisfy({ $0 == "=" }) && !underline.isEmpty {
                    if let range = byteRange(of: line.trimmingCharacters(in: .whitespaces), in: line, lineStart: scalarOffset) {
                        items.append(OutlineItem(level: 1, title: line.trimmingCharacters(in: .whitespaces), byteRange: range))
                    }
                } else if !line.isEmpty, underline.allSatisfy({ $0 == "-" }) && !underline.isEmpty {
                    if let range = byteRange(of: line.trimmingCharacters(in: .whitespaces), in: line, lineStart: scalarOffset) {
                        items.append(OutlineItem(level: 2, title: line.trimmingCharacters(in: .whitespaces), byteRange: range))
                    }
                }
            }
        }
        return items
    }

    private static func atxHeading(_ line: String) -> (level: Int, title: String)? {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", level < 6 {
            level += 1
            index = line.index(after: index)
        }
        guard level > 0 else { return nil }
        if index < line.endIndex, line[index] != " " { return nil }
        var title = String(line[index...]).trimmingCharacters(in: .whitespaces)
        // Strip an optional closing run of '#'.
        while title.hasSuffix("#") { title.removeLast() }
        title = title.trimmingCharacters(in: .whitespaces)
        return (level, title)
    }

    private static func byteRange(of substring: String, in line: String, lineStart: Int) -> ByteRange? {
        guard let range = line.range(of: substring) else { return nil }
        let leading = line.distance(from: line.startIndex, to: range.lowerBound)
        let lower = lineStart + line.prefix(leading).utf8.count
        let upper = lower + substring.utf8.count
        return try? ByteRange(lowerBound: lower, upperBound: upper)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
