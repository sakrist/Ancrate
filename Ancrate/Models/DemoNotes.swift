import Foundation
import SwiftProtobuf

/// Fictional data for UI previews and the explicit --demo launch argument.
/// It never reads Notes or publishes a widget snapshot.
enum DemoNotes {
    static func make(now: Date = .now) -> [ANote] {
        return [note("A little space for good ideas", folder: "Personal", daysAgo: 1, rows: [
            ("Take a long walk without a podcast", false), ("Write down three things worth remembering", false), ("Find a book for the weekend", true)]),
         note("The next chapter of Ancrate", folder: "Projects", daysAgo: 3, rows: [
            ("Sketch a calmer place for all my to-dos", true), ("Give the desktop widget a home", false), ("Try the new slash commands in Notes", false), ("Share the first version with a friend", false)]),
         note("Weekend, thoughtfully", folder: "Personal", daysAgo: 12, rows: [
            ("Pick up coffee from the little shop on the corner", false), ("Book a table for Saturday", false), ("Send the photos from our trip", true)]),
         note("Studio housekeeping", folder: "Work", daysAgo: 52, rows: [
            ("Archive last season's project notes", false), ("Organize the reference library", false), ("Clean up the shared folders", true)])
        ].sorted { $0.modificationDate > $1.modificationDate }
        func note(_ title: String, folder: String, daysAgo: Int, rows: [(String, Bool)]) -> ANote {
            var document = Document()
            document.version = 1
            document.note.noteText = rows.map(\.0).joined(separator: "\n") + "\n"
            document.note.attributeRun = rows.enumerated().map { index, row in
                var run = AttributeRun()
                run.length = Int32((row.0 + "\n").utf16.count)
                run.paragraphStyle.checklist.uuid = Data("\(title)-\(index)".utf8)
                run.paragraphStyle.checklist.done = row.1 ? 1 : 0
                return run
            }
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return ANote(id: title, title: title, content: document.note.noteText,
                         creationDate: date.addingTimeInterval(-86400), modificationDate: date,
                         folder: folder, rawProtobufData: try? document.serializedData())
        }
    }
}
