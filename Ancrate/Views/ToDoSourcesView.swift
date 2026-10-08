import SwiftUI

struct ToDoNoteMenu: View {
    let note: ANote
    @Binding var scope: ToDoScope

    var body: some View {
        let excluded = scope.excludedNoteIDs.contains(note.id)
        Button(excluded ? "Include in to-dos" : "Exclude from to-dos",
               systemImage: excluded ? "checklist" : "eye.slash") {
            scope.setExcluded(!excluded, noteID: note.id)
        }
        if !scope.includesFolder(of: note) {
            Text("This folder isn't selected for to-dos")
        }
    }
}

struct ToDoSourcesView: View {
    let notes: [ANote]
    @Binding var scope: ToDoScope
    var isSample = false
    private var folders: [ToDoFolder] { ToDoFolder.all(in: notes) }
    private var excludedNotes: [ANote] {
        notes.filter { scope.excludedNoteIDs.contains($0.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Section("To-do sources") {
            Picker("Folders", selection: $scope.restrictToSelectedFolders) {
                Text("All folders").tag(false)
                Text("Selected folders").tag(true)
            }.pickerStyle(.segmented).frame(maxWidth: 400)
            Text("These choices apply to every to-do list, its counts, and the desktop widget. All notes remain in your library.")
                .font(.callout).foregroundStyle(.secondary)
            if isSample {
                Text("Sample choices won't change your saved library preferences.").font(.caption).foregroundStyle(.secondary)
            }
            if scope.restrictToSelectedFolders {
                if folders.isEmpty {
                    Text("Connect your Notes library to choose folders.").font(.callout).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("Select all") { scope.selectedFolderIDs = Set(folders.map(\.id)) }
                        Button("Clear selection") { scope.selectedFolderIDs.removeAll() }
                        Spacer()
                    }.buttonStyle(.borderless).font(.callout)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(folders) { folder in
                                Toggle(isOn: Binding(
                                    get: { scope.selectedFolderIDs.contains(folder.id) },
                                    set: { scope.setFolderSelected($0, folderID: folder.id) }
                                )) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(folder.title)
                                        Text("\(folder.noteCount) \(folder.noteCount == 1 ? "note" : "notes") · \(folder.exampleTitle)")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }.padding(.trailing, 8)
                    }.frame(maxHeight: 220)
                    if !folders.contains(where: { scope.selectedFolderIDs.contains($0.id) }) {
                        Text("Select at least one folder to see to-dos.").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Right-click a note or a to-do to exclude its source note. Restore it from the note's menu or here.")
                .font(.callout).foregroundStyle(.secondary)
            if !scope.excludedNoteIDs.isEmpty {
                DisclosureGroup("Excluded notes (\(scope.excludedNoteIDs.count))") {
                    VStack(alignment: .leading, spacing: 12) {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(excludedNotes) { note in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(note.title).lineLimit(1)
                                            Text(note.folder ?? "No folder").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Include") { scope.setExcluded(false, noteID: note.id) }
                                            .accessibilityLabel("Include \(note.title) in to-dos")
                                    }
                                }
                            }
                        }.frame(maxHeight: 180)
                        Button("Include all excluded notes") { scope.excludedNoteIDs.removeAll() }
                            .buttonStyle(.borderless)
                    }.padding(.top, 12)
                }
            }
        }
    }
}
