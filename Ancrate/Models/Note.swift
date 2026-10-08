import Foundation
import SwiftProtobuf

struct ANote: Identifiable, Hashable {
    let id: String
    let title: String
    let content: String
    let creationDate: Date
    let modificationDate: Date
    let folder: String?
    let folderID: String?
    let rawProtobufData: Data?
    let checklists: [ChecklistItem]

    init(id: String, title: String, content: String, creationDate: Date, modificationDate: Date,
         folder: String?, rawProtobufData: Data?, folderID: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.folder = folder
        self.folderID = folderID
        self.rawProtobufData = rawProtobufData
        checklists = Self.extractChecklists(from: rawProtobufData)
    }

    var hasProtobufData: Bool { rawProtobufData != nil }
    var parsedDocument: Document? { rawProtobufData.flatMap(SwiftProtobufNotesParser.parseDocument) }

    var tasks: [TaskRecord] {
        checklists.map { item in
            TaskRecord(id: "\(id):\(item.id)", text: item.text, isCompleted: item.isCompleted,
                       noteID: id, noteTitle: title, folder: folder,
                       createdAt: creationDate, modifiedAt: modificationDate)
        }
    }

    private static func extractChecklists(from data: Data?) -> [ChecklistItem] {
        guard let data, let document = SwiftProtobufNotesParser.parseDocument(from: data), document.hasNote else { return [] }
        let text = document.note.noteText as NSString
        let units = Array(document.note.noteText.utf16)
        var offset = 0
        var groups: [Data: [(NSRange, Bool)]] = [:]
        for run in document.note.attributeRun {
            let length = Int(run.length)
            guard length >= 0, offset <= text.length, length <= text.length - offset else { return [] }
            let range = NSRange(location: offset, length: length)
            offset += length
            guard NSMaxRange(range) <= text.length,
                  run.hasParagraphStyle, run.paragraphStyle.hasChecklist,
                  run.paragraphStyle.checklist.hasUuid else { continue }
            let checklist = run.paragraphStyle.checklist
            groups[checklist.uuid, default: []].append((range, checklist.done != 0))
        }
        return groups.compactMap { uuid, runs -> ChecklistItem? in
            let sorted = runs.sorted { $0.0.location < $1.0.location }
            guard let first = sorted.first, let last = sorted.last else { return nil }
            let combinedUnits = sorted.flatMap { Array(units[$0.0.location..<NSMaxRange($0.0)]) }
            let combined = String(decoding: combinedUnits, as: UTF16.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !combined.isEmpty else { return nil }
            let line = text.substring(to: first.0.location).components(separatedBy: "\n").count - 1
            return ChecklistItem(id: uuid.map { String(format: "%02x", $0) }.joined(), text: combined,
                                 isCompleted: first.1, uuid: uuid, lineNumber: line,
                                 range: first.0.location..<NSMaxRange(last.0))
        }.sorted { ($0.range?.lowerBound ?? 0) < ($1.range?.lowerBound ?? 0) }
    }
}

struct ChecklistItem: Identifiable, Hashable {
    let id: String
    let text: String
    let isCompleted: Bool
    let uuid: Data?
    let lineNumber: Int
    let range: Range<Int>?
}
