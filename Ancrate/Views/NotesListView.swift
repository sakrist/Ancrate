import SwiftUI
#if os(macOS)
import AppKit
#endif

struct NotesListView: View {
    @ObservedObject var notesDatabase: NotesDatabase
    @Binding var selectedNotes: Set<ANote>
    @Binding var toDoScope: ToDoScope
    @State private var searchText = ""
    @State private var focusedID: String?
    private var filtered: [ANote] {
        notesDatabase.notes.filter {
            searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) || $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    private var focused: ANote? { notesDatabase.notes.first { $0.id == focusedID } }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeading(title: "Notes", subtitle: "Search and read your Apple Notes.")
                    .padding(.horizontal, 20).padding(.top, 24)
                if filtered.isEmpty {
                    EmptyState(symbol: "note.text", title: "No notes found", detail: "Refresh your library or try another search.")
                } else {
                    SwiftUI.List(selection: $focusedID) {
                        ForEach(filtered) { note in
                            NoteLibraryRow(note: note, scope: toDoScope).tag(note.id)
                                .padding(.vertical, 6).listRowSeparator(.hidden)
                                .contextMenu { ToDoNoteMenu(note: note, scope: $toDoScope) }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            }.frame(minWidth: 280, idealWidth: 310, maxWidth: 350)
            Divider()
            if let note = focused {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            Label(note.folder ?? "Notes", systemImage: "folder")
                            Spacer()
                            Text(note.modificationDate, style: .date)
                        }.font(.caption).foregroundStyle(.secondary)
                        Text(note.title).font(.title).fontWeight(.semibold)
                            .contextMenu { ToDoNoteMenu(note: note, scope: $toDoScope) }
                        if !note.checklists.isEmpty {
                            Label("\(note.checklists.filter { !$0.isCompleted }.count) open to-dos", systemImage: "checklist")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if !toDoScope.includes(note) {
                            Label(toDoScope.excludedNoteIDs.contains(note.id) ? "Excluded from to-dos" : "Folder not included in to-dos",
                                  systemImage: "eye.slash").font(.callout).foregroundStyle(.secondary)
                        }
                        Divider()
                        Text(note.content).font(.body).lineSpacing(5).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Copy as Markdown", systemImage: "doc.on.doc") {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(MarkdownConverter.convertToMarkdown(notes: [note]), forType: .string)
                            #endif
                        }
                        .buttonStyle(.borderless).padding(.top, 8)
                        let excluded = toDoScope.excludedNoteIDs.contains(note.id)
                        Button(excluded ? "Include in to-dos" : "Exclude from to-dos", systemImage: excluded ? "checklist" : "eye.slash") {
                            toDoScope.setExcluded(!excluded, noteID: note.id)
                        }.buttonStyle(.borderless)
                    }.padding(32)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(AncrateStyle.surface)
            } else {
                EmptyState(symbol: "doc.text.magnifyingglass", title: "Select a note", detail: "Choose a note to read its text and view its to-dos.")
            }
        }
        .background(AncrateStyle.canvas)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search notes")
        .onChange(of: focusedID) { _, id in
            selectedNotes = Set(notesDatabase.notes.filter { $0.id == id })
        }
    }
}

private struct NoteLibraryRow: View {
    let note: ANote
    let scope: ToDoScope
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(note.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text(note.content.replacingOccurrences(of: "\n", with: " ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Text(note.folder ?? "Notes")
                Spacer()
                if !note.checklists.isEmpty { Label("\(note.checklists.count)", systemImage: "checklist") }
            }.font(.caption2).foregroundStyle(.secondary)
            if !scope.includes(note) {
                Label(scope.excludedNoteIDs.contains(note.id) ? "Excluded from to-dos" : "Folder not included",
                      systemImage: "eye.slash").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
