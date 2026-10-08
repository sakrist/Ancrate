import Foundation
import Testing
@testable import Ancrate

struct NotesSlashCommandTests {
    @Test func detectsSlashAtLineStart() {
        #expect(NotesSlashToken.parse(text: "/", caret: 1)?.query == "")
        #expect(NotesSlashToken.parse(text: "Title\n  /H2", caret: 11)
            == NotesSlashToken(query: "h2", range: NSRange(location: 8, length: 3)))
        #expect(NotesSlashToken.parse(text: "Title\r\n/code", caret: 12)?.query == "code")
    }

    @Test func leavesOrdinaryTypingAlone() {
        for text in ["https://example.com", "and/or", "hello /title", "//", "/code text", "/🚀", "/foo-bar"] {
            #expect(NotesSlashToken.parse(text: text, caret: text.utf16.count) == nil)
        }
        #expect(NotesSlashToken.parse(text: "/heading", caret: 3) == nil)
        #expect(NotesSlashToken.parse(text: "/heading rest", caret: 8)?.query == "heading")
        #expect(NotesSlashToken.parse(text: "/" + String(repeating: "a", count: 33), caret: 34) == nil)
        #expect(NotesSlashToken.parse(text: "/h1", caret: -1) == nil)
        #expect(NotesSlashToken.parse(text: "/h1", caret: 4) == nil)
    }

    @Test func usesUTF16AndWindowOffsets() {
        let text = "😀 café\n/h3"
        #expect(NotesSlashToken.parse(text: text, caret: text.utf16.count)?.range
            == NSRange(location: 8, length: 3))
        #expect(NotesSlashToken.parse(text: "\n/h1", caret: 4, origin: 127)?.range
            == NSRange(location: 128, length: 3))
        #expect(NotesSlashToken.parse(text: "/h1", caret: 3, origin: 127) == nil)
    }

    @Test func resolvesAliasesAndUnknownCommands() {
        #expect(NotesSlashCommand.matching("h1").first?.id == "title")
        #expect(NotesSlashCommand.matching("h2").first?.id == "heading")
        #expect(NotesSlashCommand.matching("h3").first?.id == "subheading")
        #expect(NotesSlashCommand.matching("CODE").first?.id == "monostyled")
        #expect(NotesSlashCommand.matching("blockquote").first?.id == "quote")
        #expect(NotesSlashCommand.matching("unknown").isEmpty)
        #expect(NotesSlashCommand.matching("").count == 11)
    }
}
