import Foundation
import Testing
import SQLite3
import SwiftProtobuf
@testable import Ancrate

struct LibraryAndWidgetTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))! }

    @Test func monthAndQuarterHaveInclusiveCalendarBoundaries() {
        let monthStart = calendar.date(byAdding: .month, value: -1, to: now)!
        let quarterStart = calendar.date(byAdding: .month, value: -3, to: now)!
        #expect(TaskPeriod.month.contains(monthStart, now: now, calendar: calendar))
        #expect(!TaskPeriod.month.contains(monthStart.addingTimeInterval(-1), now: now, calendar: calendar))
        #expect(TaskPeriod.quarter.contains(quarterStart, now: now, calendar: calendar))
        #expect(!TaskPeriod.quarter.contains(quarterStart.addingTimeInterval(-1), now: now, calendar: calendar))
        #expect(!TaskPeriod.month.contains(now.addingTimeInterval(1), now: now, calendar: calendar))
    }

    @Test func snapshotUsesChosenDateBasis() {
        let old = calendar.date(byAdding: .month, value: -5, to: now)!
        let task = TaskRecord(id: "one", text: "Read", isCompleted: false, noteID: "note", noteTitle: "Reading",
                              folder: nil, createdAt: old, modifiedAt: now)
        let modified = TaskSnapshot(updatedAt: now, dateBasis: .modified, status: .ready, tasks: [task])
        let created = TaskSnapshot(updatedAt: now, dateBasis: .created, status: .ready, tasks: [task])
        #expect(modified.tasks(in: .month, now: now, calendar: calendar).count == 1)
        #expect(created.tasks(in: .month, now: now, calendar: calendar).isEmpty)
        #expect(created.tasks(in: .all, now: now, calendar: calendar).count == 1)
    }

    @Test func widgetSnapshotRoundTripsAndClearsWhenDisabled() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshot = TaskSnapshot(updatedAt: now, dateBasis: .modified, status: .ready, tasks: DemoNotes.make(now: now).flatMap(\.tasks))
        try TaskSnapshotStore.save(snapshot, directory: directory)
        #expect(TaskSnapshotStore.load(directory: directory) == snapshot)
        let disabled = TaskSnapshot(updatedAt: now, dateBasis: .modified, status: .disabled, tasks: [])
        try TaskSnapshotStore.save(disabled, directory: directory)
        #expect(TaskSnapshotStore.load(directory: directory)?.tasks.isEmpty == true)
        #expect(TaskSnapshotStore.load(directory: directory)?.status == .disabled)
    }

    @Test func unicodeChecklistsKeepTextOrderingAndStableIDs() throws {
        var document = Document()
        document.version = 1
        document.note.noteText = "A heading\nMeet Zoë 👋 tomorrow\nAnother task\n"
        var heading = AttributeRun(); heading.length = 10
        var first = AttributeRun(); first.length = 21
        first.paragraphStyle.checklist.uuid = Data([1]); first.paragraphStyle.checklist.done = 1
        var second = AttributeRun(); second.length = 13
        second.paragraphStyle.checklist.uuid = Data([2]); second.paragraphStyle.checklist.done = 0
        document.note.attributeRun = [heading, first, second]
        let data = try document.serializedData()
        func note(_ id: String) -> ANote {
            ANote(id: id, title: "Unicode", content: document.note.noteText, creationDate: now,
                  modificationDate: now, folder: nil, rawProtobufData: data)
        }
        let firstNote = note("a")
        #expect(firstNote.checklists.map(\.text) == ["Meet Zoë 👋 tomorrow", "Another task"])
        #expect(firstNote.checklists.map(\.lineNumber) == [1, 2])
        #expect(firstNote.checklists.first?.isCompleted == true)
        #expect(firstNote.tasks.map(\.id) == note("a").tasks.map(\.id))
        #expect(Set(firstNote.tasks.map(\.id)).isDisjoint(with: note("b").tasks.map(\.id)))
        let markdown = MarkdownConverter.convertToMarkdown(note: firstNote)
        #expect(markdown.contains("- [x] Meet Zoë 👋 tomorrow"))
        #expect(markdown.contains("- [ ] Another task"))
    }

    @Test func malformedChecklistRangesAreRejected() throws {
        var document = Document(); document.version = 1; document.note.noteText = "short"
        var run = AttributeRun(); run.length = -1; run.paragraphStyle.checklist.uuid = Data([1]); run.paragraphStyle.checklist.done = 0
        document.note.attributeRun = [run]
        let note = ANote(id: "bad", title: "Malformed", content: "short", creationDate: now,
                         modificationDate: now, folder: nil, rawProtobufData: try document.serializedData())
        #expect(note.checklists.isEmpty)
        #expect(MarkdownConverter.convertToMarkdown(note: note).contains("short"))
    }

    @Test func markdownPreservesTextWithoutFormattingRuns() {
        var document = Document(); document.version = 1; document.note.noteText = "Hello 👋\nAn unstyled ending"
        var run = AttributeRun(); run.length = Int32("Hello 👋\n".utf16.count)
        document.note.attributeRun = [run]
        let markdown = MarkdownConverter.convertToMarkdown(document: document, title: "Unicode export")
        #expect(markdown.contains(document.note.noteText))
    }

    @Test func libraryLoadsBeyondOldCapAndLooksUpOlderNoteByID() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: file) }
        var db: OpaquePointer?
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let schema = """
        CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER PRIMARY KEY, ZTITLE1 TEXT, ZTITLE2 TEXT, ZSNIPPET TEXT,
          ZCREATIONDATE REAL, ZMODIFICATIONDATE1 REAL, ZFOLDER INTEGER, ZNOTEDATA INTEGER, ZMARKEDFORDELETION INTEGER);
        CREATE TABLE ZICNOTEDATA (Z_PK INTEGER PRIMARY KEY, ZDATA BLOB);
        """
        #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
        for index in 1...600 {
            #expect(sqlite3_exec(db, "INSERT INTO ZICCLOUDSYNCINGOBJECT VALUES (\(index), 'Note \(index)', '', 'Text', \(index), \(index), NULL, NULL, 0)", nil, nil, nil) == SQLITE_OK)
        }
        #expect(sqlite3_exec(db, "INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZTITLE2) VALUES (1001, 'Work'), (1002, 'Work')", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "UPDATE ZICCLOUDSYNCINGOBJECT SET ZFOLDER = 1001 WHERE Z_PK = 1", nil, nil, nil) == SQLITE_OK)
        let reader = NotesDatabase(databaseURL: file)
        #expect(try reader.fetchNotes(limit: nil).count == 600)
        #expect(try reader.fetchNote(id: "1")?.title == "Note 1")
        #expect(try reader.fetchNote(id: "1")?.folder == "Work")
        #expect(try reader.fetchNote(id: "1")?.folderID == "1001")
        #expect(try reader.fetchNote(id: "1 OR 1=1") == nil)
        #expect(try reader.fetchNote(id: "601") == nil)
        #expect(sqlite3_total_changes(db) == 603)
    }
}
