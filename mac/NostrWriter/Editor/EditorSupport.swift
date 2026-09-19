import AppKit
import WriterFoundation

/// Pure decision for one typewriter-scroll step.
///
/// Splitting the decision from the scroll view makes the Reduce Motion branch
/// verifiable without a system accessibility toggle: the plan depends only on
/// the caret rectangle, the visible rectangle, the font padding and the
/// system's Reduce Motion flag. It never touches text storage, so the exact
/// source bytes and the text position are identical either way — only the
/// amount of on-screen motion differs.
struct TypewriterScrollPlan: Equatable {
    /// New clip-view origin, or `nil` when the caret is already well placed.
    let origin: NSPoint?

    static func plan(caret: NSRect, visible: NSRect, reduceMotion: Bool, padding: CGFloat) -> TypewriterScrollPlan {
        if reduceMotion {
            // Keep the caret visible with the smallest jump rather than
            // continuously recentering the page.
            if caret.minY < visible.minY + padding * 0.5 {
                return TypewriterScrollPlan(origin: NSPoint(x: visible.minX, y: max(0, caret.minY - padding)))
            }
            if caret.maxY > visible.maxY - padding * 0.5 {
                return TypewriterScrollPlan(origin: NSPoint(x: visible.minX, y: caret.maxY - visible.height + padding))
            }
            return TypewriterScrollPlan(origin: nil)
        }
        let delta = caret.origin.y - (visible.minY + visible.height * 0.45)
        guard abs(delta) > 8 else { return TypewriterScrollPlan(origin: nil) }
        return TypewriterScrollPlan(origin: NSPoint(x: visible.origin.x, y: max(0, visible.minY + delta)))
    }
}

/// Syntax emphasis and focus presentation for the live editor.
///
/// Everything here is *presentation only*. It uses TextKit 2 rendering
/// attributes, never source-string rewrites and never the legacy layout
/// manager, so exact UTF-8 source bytes are untouched by display state.
@MainActor
enum EditorPresentation {
    /// Applies restrained Markdown source emphasis for the EXPORT grammar.
    /// Unsupported or malformed content is simply left unemphasised.
    static func applySyntaxEmphasis(to editor: NSTextView) {
        guard let layout = editor.textLayoutManager, let content = layout.textContentManager else { return }
        layout.removeRenderingAttribute(.foregroundColor, for: layout.documentRange)
        let text = editor.string as NSString
        guard text.length > 0 else { return }

        func emphasise(_ range: NSRange, _ color: NSColor) {
            guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= text.length else { return }
            guard let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end) else { return }
            layout.addRenderingAttribute(.foregroundColor, value: color, for: textRange)
        }

        let heading = NSColor.controlAccentColor
        let quote = NSColor.systemTeal
        let code = NSColor.systemPink

        // Line-leading heading and blockquote markers.
        var lineStart = 0
        while lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = text.substring(with: lineRange)
            let trimmed = line.drop(while: { $0 == " " })
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" }).count
                emphasise(NSRange(location: lineRange.location, length: hashes), heading)
            } else if trimmed.hasPrefix(">") {
                let indent = line.count - trimmed.count
                emphasise(NSRange(location: lineRange.location + indent, length: 1), quote)
            }
            lineStart = NSMaxRange(lineRange)
        }

        // Inline code spans.
        var index = 0
        while index < text.length {
            let tick = text.range(of: "`", options: [], range: NSRange(location: index, length: text.length - index))
            guard tick.location != NSNotFound else { break }
            let close = text.range(of: "`", options: [],
                                   range: NSRange(location: NSMaxRange(tick), length: text.length - NSMaxRange(tick)))
            guard close.location != NSNotFound else { break }
            emphasise(NSRange(location: NSMaxRange(tick), length: close.location - NSMaxRange(tick)), code)
            index = NSMaxRange(close)
        }
    }

    /// Highlights the active sentence or paragraph without reducing text
    /// contrast. A background tint never dims the writing itself.
    static func applyFocusHighlight(to editor: NSTextView, mode: EditorFocusMode) {
        guard let layout = editor.textLayoutManager, let content = layout.textContentManager else { return }
        layout.removeRenderingAttribute(.backgroundColor, for: layout.documentRange)
        guard mode != .off else { return }
        let text = editor.string as NSString
        guard text.length > 0 else { return }
        let selection = editor.selectedRange()
        let range = mode == .paragraph
            ? text.paragraphRange(for: NSRange(location: min(selection.location, max(0, text.length - 1)), length: 0))
            : sentenceRange(in: text, around: selection)
        guard range.length > 0,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return }
        let tint = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.12)
        layout.addRenderingAttribute(.backgroundColor, value: tint, for: textRange)
    }

    private static func sentenceRange(in text: NSString, around selection: NSRange) -> NSRange {
        let location = min(selection.location, max(0, text.length - 1))
        var start = location
        while start > 0 {
            let previous = text.character(at: start - 1)
            if previous == 0x2E || previous == 0x21 || previous == 0x3F || previous == 0x0A { break }
            start -= 1
        }
        var end = location
        while end < text.length {
            let current = text.character(at: end)
            if current == 0x2E || current == 0x21 || current == 0x3F || current == 0x0A { end += 1; break }
            end += 1
        }
        return NSRange(location: start, length: max(0, end - start))
    }
}

/// Inserts visible Markdown syntax for a selection through the mutation
/// gateway, so the change is recorded with a formatting cause rather than
/// direct physical typing. Only the inserted syntax characters are added; the
/// rest of the source stays exact.
@MainActor
enum EditorCommands {
    enum Formatting: String, CaseIterable {
        case bold, italic, inlineCode, heading, blockquote, bulletList, link

        var title: String {
            switch self {
            case .bold: "Bold"
            case .italic: "Italic"
            case .inlineCode: "Inline Code"
            case .heading: "Heading"
            case .blockquote: "Block Quote"
            case .bulletList: "Bulleted List"
            case .link: "Link"
            }
        }
    }

    /// Wraps or prefixes the current selection with visible Markdown syntax.
    static func apply(_ formatting: Formatting, to editor: MarkdownTextView, gateway: EditorMutationGateway) {
        let selection = editor.selectedRange()
        let text = editor.string as NSString
        let selected = selection.length > 0 ? text.substring(with: selection) : ""
        let insertion: String
        switch formatting {
        case .bold: insertion = "**\(selected.isEmpty ? "bold text" : selected)**"
        case .italic: insertion = "_\(selected.isEmpty ? "italic text" : selected)_"
        case .inlineCode: insertion = "`\(selected.isEmpty ? "code" : selected)`"
        case .heading: insertion = "## \(selected.isEmpty ? "Heading" : selected)"
        case .blockquote: insertion = "> \(selected.isEmpty ? "Quote" : selected)"
        case .bulletList: insertion = "- \(selected.isEmpty ? "Item" : selected)"
        case .link: insertion = "[\(selected.isEmpty ? "link text" : selected)](https://)"
        }
        let range = selection.length > 0 ? selection : NSRange(location: selection.location, length: 0)
        gateway.performProgrammatic(origin: .formatting) {
            editor.insertText(insertion, replacementRange: range)
        }
    }
}
