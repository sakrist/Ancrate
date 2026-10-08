import Foundation

/// Native Notes menu shortcuts, documented by Apple. Command is implicit in
/// AXMenuItemCmdModifiers; Shift = 1 and Option = 2.
struct NotesSlashCommand: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let aliases: [String]
    let menuCharacter: String
    let menuModifiers: Int

    static let all: [Self] = [
        .init(id: "title", title: "Title", symbol: "textformat.size.larger", aliases: ["h1"], menuCharacter: "t", menuModifiers: 1),
        .init(id: "heading", title: "Heading", symbol: "textformat", aliases: ["h2"], menuCharacter: "h", menuModifiers: 1),
        .init(id: "subheading", title: "Subheading", symbol: "textformat.size.smaller", aliases: ["h3"], menuCharacter: "j", menuModifiers: 1),
        .init(id: "body", title: "Body", symbol: "text.alignleft", aliases: [], menuCharacter: "b", menuModifiers: 1),
        .init(id: "monostyled", title: "Monostyled", symbol: "chevron.left.forwardslash.chevron.right", aliases: ["code"], menuCharacter: "m", menuModifiers: 1),
        .init(id: "checklist", title: "Checklist", symbol: "checklist", aliases: ["todo"], menuCharacter: "l", menuModifiers: 1),
        .init(id: "bulletedlist", title: "Bulleted list", symbol: "list.bullet", aliases: ["bullet"], menuCharacter: "7", menuModifiers: 1),
        .init(id: "dashedlist", title: "Dashed list", symbol: "list.dash", aliases: ["dash"], menuCharacter: "8", menuModifiers: 1),
        .init(id: "numberedlist", title: "Numbered list", symbol: "list.number", aliases: ["numbered"], menuCharacter: "9", menuModifiers: 1),
        .init(id: "quote", title: "Block quote", symbol: "text.quote", aliases: ["blockquote"], menuCharacter: "'", menuModifiers: 0),
        .init(id: "table", title: "Table", symbol: "tablecells", aliases: [], menuCharacter: "t", menuModifiers: 2)
    ]

    static func matching(_ query: String) -> [Self] {
        let query = query.lowercased()
        let matches = all.filter { command in
            ([command.id] + command.aliases).contains { $0.hasPrefix(query) }
        }
        // An exact alias such as /h3 must win over partial matches.
        return matches.filter { ([$0.id] + $0.aliases).contains(query) }
            + matches.filter { !([$0.id] + $0.aliases).contains(query) }
    }
}

struct NotesSlashToken: Equatable {
    let query: String
    let range: NSRange

    /// Accessibility ranges use UTF-16, not Swift Character offsets. `text`
    /// can be a small window around the caret; a truncated line is rejected.
    static func parse(text: String, caret: Int, origin: Int = 0) -> Self? {
        let text = text as NSString
        guard caret >= 0, caret <= text.length, origin >= 0 else { return nil }
        let prefix = text.substring(to: caret) as NSString
        let newline = prefix.rangeOfCharacter(from: .newlines, options: .backwards)
        guard origin == 0 || newline.location != NSNotFound else { return nil }
        let start = newline.location == NSNotFound ? 0 : NSMaxRange(newline)
        let line = prefix.substring(from: start) as NSString
        var slash = 0
        while slash < line.length && (line.character(at: slash) == 32 || line.character(at: slash) == 9) {
            slash += 1
        }
        guard slash < line.length, line.character(at: slash) == 47 else { return nil }
        let query = line.substring(from: slash + 1)
        guard query.utf16.count <= 32,
              query.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) }) else {
            return nil
        }
        // Do not accept a command in the middle of a word when the caret moves.
        if caret < text.length {
            let suffix = text.substring(with: NSRange(location: caret, length: 1))
            guard suffix.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else { return nil }
        }
        return .init(query: query.lowercased(), range: NSRange(location: origin + start + slash, length: line.length - slash))
    }
}
