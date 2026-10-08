import Foundation

/// Local presentation preferences. These never change the Apple Notes store or MCP results.
struct ToDoScope: Codable, Equatable {
    var excludedNoteIDs: Set<String> = []
    var restrictToSelectedFolders = false
    var selectedFolderIDs: Set<String> = []

    func includesFolder(of note: ANote) -> Bool {
        !restrictToSelectedFolders || selectedFolderIDs.contains(note.toDoFolderID)
    }

    func includes(_ note: ANote) -> Bool {
        !excludedNoteIDs.contains(note.id) && includesFolder(of: note)
    }

    func notes(from library: [ANote]) -> [ANote] { library.filter(includes) }

    func snapshot(notes: [ANote], basis: TaskDateBasis, status: TaskSnapshot.Status, now: Date = .now) -> TaskSnapshot {
        TaskSnapshot(updatedAt: now, dateBasis: basis, status: status,
                     tasks: status == .ready ? self.notes(from: notes).flatMap(\.tasks) : [])
    }

    mutating func setExcluded(_ excluded: Bool, noteID: String) {
        if excluded { excludedNoteIDs.insert(noteID) } else { excludedNoteIDs.remove(noteID) }
    }

    mutating func setFolderSelected(_ selected: Bool, folderID: String) {
        if selected { selectedFolderIDs.insert(folderID) } else { selectedFolderIDs.remove(folderID) }
    }
}

extension ANote {
    var toDoFolderID: String {
        if let folderID { return "id:\(folderID)" }
        if let folder, !folder.isEmpty { return "name:\(folder)" }
        return "unfiled"
    }
}

struct ToDoFolder: Identifiable {
    let id: String
    let title: String
    let noteCount: Int
    let exampleTitle: String

    static func all(in notes: [ANote]) -> [ToDoFolder] {
        Swift.Dictionary(grouping: notes, by: \.toDoFolderID).map { id, notes in
            let sorted = notes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            let first = sorted[0]
            let title = first.folder.flatMap { $0.isEmpty ? nil : $0 } ?? "No folder"
            return ToDoFolder(id: id, title: title,
                             noteCount: notes.count, exampleTitle: first.title)
        }.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
