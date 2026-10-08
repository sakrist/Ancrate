import Foundation
import Testing
@testable import Ancrate

struct ToDoScopeTests {
    @Test func exclusionsApplyToEveryRangeAndWidgetSnapshot() {
        let now = Date.now
        let library = DemoNotes.make(now: now)
        let excluded = library[0]
        var scope = ToDoScope()
        #expect(scope.notes(from: library) == library)
        scope.setExcluded(true, noteID: excluded.id)
        let visible = scope.notes(from: library)
        #expect(visible.count == library.count - 1)
        #expect(!visible.contains(where: { $0.id == excluded.id }))
        let snapshot = scope.snapshot(notes: library, basis: .modified, status: .ready, now: now)
        #expect(snapshot.tasks == visible.flatMap(\.tasks))
        for period in TaskPeriod.allCases {
            let boardTasks = visible.filter { period.contains($0.modificationDate, now: now) }.flatMap(\.tasks)
            #expect(snapshot.tasks(in: period, now: now) == boardTasks)
            #expect(!boardTasks.contains(where: { $0.noteID == excluded.id }))
        }
        // Exclusion only filters the projection; the source note and its checklist remain intact.
        #expect(library[0] == excluded)
        scope.setExcluded(false, noteID: excluded.id)
        #expect(scope.notes(from: library) == library)
    }

    @Test func selectedFoldersAndNoteExclusionsCombine() {
        let library = DemoNotes.make()
        var scope = ToDoScope(restrictToSelectedFolders: true)
        #expect(scope.notes(from: library).isEmpty)
        #expect(scope.snapshot(notes: library, basis: .modified, status: .ready).tasks.isEmpty)
        let personal = library.filter { $0.folder == "Personal" }
        scope.setFolderSelected(true, folderID: personal[0].toDoFolderID)
        #expect(scope.notes(from: library) == personal)
        scope.setExcluded(true, noteID: personal[0].id)
        #expect(scope.notes(from: library) == [personal[1]])
        scope.restrictToSelectedFolders = false
        #expect(scope.notes(from: library).count == library.count - 1)
        scope.restrictToSelectedFolders = true
        #expect(scope.notes(from: library) == [personal[1]])
    }

    @Test func folderIdentitySurvivesRenameAndSeparatesDuplicateNames() {
        func note(_ id: String, folder: String?, folderID: String?) -> ANote {
            ANote(id: id, title: "Note \(id)", content: "", creationDate: .now, modificationDate: .now,
                  folder: folder, rawProtobufData: nil, folderID: folderID)
        }
        let first = note("1", folder: "Work", folderID: "10")
        let second = note("2", folder: "Work", folderID: "20")
        var scope = ToDoScope(restrictToSelectedFolders: true, selectedFolderIDs: [first.toDoFolderID])
        #expect(scope.notes(from: [first, second]) == [first])
        #expect(scope.includes(note("1", folder: "Renamed", folderID: "10")))
        #expect(!scope.includes(note("1", folder: "Work", folderID: "20")))
        #expect(ToDoFolder.all(in: [first, second]).count == 2)
        let unfiled = note("3", folder: nil, folderID: nil)
        scope.setFolderSelected(true, folderID: unfiled.toDoFolderID)
        #expect(scope.includes(unfiled))
        scope.setExcluded(true, noteID: first.id)
        #expect(!scope.includes(note("1", folder: "Renamed", folderID: "10")))
    }

    @Test @MainActor func preferencesSurviveRelaunchAndCanBeRestored() throws {
        let suite = "ToDoScopeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ToDoPreferences(defaults: defaults)
        #expect(store.scope == ToDoScope())
        var scope = store.scope
        scope.setExcluded(true, noteID: "old-note")
        scope.restrictToSelectedFolders = true
        scope.setFolderSelected(true, folderID: "id:42")
        store.update(scope)
        let reloaded = ToDoPreferences(defaults: defaults)
        #expect(reloaded.scope == scope)
        reloaded.update(ToDoScope())
        #expect(ToDoPreferences(defaults: defaults).scope == ToDoScope())
    }

    @Test func disabledAndUnavailableSnapshotsContainNoTasksEvenWithSelectedSources() {
        let library = DemoNotes.make()
        let scope = ToDoScope()
        for status in [TaskSnapshot.Status.disabled, .unavailable] {
            let snapshot = scope.snapshot(notes: library, basis: .created, status: status)
            #expect(snapshot.status == status)
            #expect(snapshot.tasks.isEmpty)
        }
    }
}
