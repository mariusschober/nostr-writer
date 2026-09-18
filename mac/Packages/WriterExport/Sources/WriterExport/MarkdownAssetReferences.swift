import Foundation
import Markdown
import WriterFoundation

/// Actual Markdown image destinations only. Code examples, ordinary links and
/// remote URLs are not file-operation authority.
public enum MarkdownAssetReferences {
    public static func relativeImagePaths(in source: SourceSnapshot) throws -> Set<String> {
        let document = Document(parsing: source.string)
        var pending: [any Markup] = [document], result: Set<String> = [], visited = 0
        while let node = pending.popLast() {
            guard visited < 200_000 else { throw ContractError.unsupported("The image-reference scan exceeded its bound.") }
            visited += 1
            if let image = node as? Image, let destination = image.source,
               let path = destination.removingPercentEncoding,
               !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
               URLComponents(string: path)?.scheme == nil,
               !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
                result.insert(path)
            }
            pending.append(contentsOf: node.children)
        }
        return result
    }
}
