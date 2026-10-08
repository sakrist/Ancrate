import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct ChecklistsListView: View {
    let selectedNotes: [ANote]
    @Binding var toDoScope: ToDoScope
    let manageSources: () -> Void
    var title = "To-dos"
    var subtitle = "Your checklists, gathered from Apple Notes."
    @State private var searchText = ""
    @State private var filter: TaskFilter = .open
    @State private var selectedIDs: Set<String> = []
    @State private var exportError: String?
    @State private var copied = false

    private enum TaskFilter: String, CaseIterable, Identifiable {
        case open = "Open", all = "All", completed = "Completed"
        var id: String { rawValue }
    }
    private var allTasks: [TaskRecord] { selectedNotes.flatMap(\.tasks) }
    private var tasks: [TaskRecord] {
        allTasks.filter { task in
            (filter == .all || (filter == .completed ? task.isCompleted : !task.isCompleted)) &&
            (searchText.isEmpty || task.text.localizedCaseInsensitiveContains(searchText) || task.noteTitle.localizedCaseInsensitiveContains(searchText))
        }
    }
    private var groupedNotes: [ANote] {
        let ids = Set(tasks.map(\.noteID))
        return selectedNotes.filter { ids.contains($0.id) }.sorted { $0.modificationDate > $1.modificationDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                PageHeading(title: title, subtitle: subtitle)
                Spacer()
                Button(action: manageSources) {
                    Label("Sources", systemImage: "line.3.horizontal.decrease")
                }.fixedSize()
                Menu {
                    Button("Copy visible to-dos", action: copyVisible)
                    Button("Export to-dos as Markdown", action: exportTasks)
                    Button("Export source notes", action: exportNotes)
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .fixedSize()
                .disabled(tasks.isEmpty)
            }
            HStack(spacing: 14) {
                MetricSummary(value: allTasks.filter { !$0.isCompleted }.count, title: "Open to-dos", symbol: "circle.dashed")
                Divider().frame(height: 40)
                MetricSummary(value: allTasks.filter(\.isCompleted).count, title: "Completed", symbol: "checkmark.circle")
                Divider().frame(height: 40)
                MetricSummary(value: Set(allTasks.map(\.noteID)).count, title: "Source notes", symbol: "note.text")
            }.padding(.vertical, 4)
            Divider()
            HStack(spacing: 20) {
                Picker("Show to-dos", selection: $filter) {
                    ForEach(TaskFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 250)
                Spacer()
            }
            if toDoScope.restrictToSelectedFolders || !toDoScope.excludedNoteIDs.isEmpty {
                Button(action: manageSources) {
                    Label("To-do sources filtered · Manage", systemImage: "line.3.horizontal.decrease")
                }.buttonStyle(.borderless).font(.caption)
            }
            if tasks.isEmpty {
                EmptyState(symbol: searchText.isEmpty ? "checkmark.circle" : "magnifyingglass",
                           title: searchText.isEmpty ? "No to-dos to show" : "No matching to-dos",
                           detail: allTasks.isEmpty ? "Choose another time range, review your Sources, or refresh your notes."
                               : "Try another filter or search to see more of your checklists.")
            } else {
                SwiftUI.List {
                    ForEach(groupedNotes) { note in taskGroup(note) }
                }.listStyle(.inset)
            }
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.right.square")
                Text("Check off items in Apple Notes. Ancrate reflects your changes.")
                Spacer()
                if copied { Text("Copied") }
                if !selectedIDs.isEmpty {
                    Button("Copy selected (\(selectedIDs.count))") { copy(tasks.filter { selectedIDs.contains($0.id) }) }
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).background(AncrateStyle.surface)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search to-dos")
        .onChange(of: tasks.map(\.id)) { _, ids in selectedIDs.formIntersection(ids) }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copied = false }
        }
        .alert("Couldn't export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private func taskGroup(_ note: ANote) -> some View {
        Section {
            ForEach(tasks.filter { $0.noteID == note.id }) { task in
                TaskRow(task: task, selected: selectedIDs.contains(task.id)) {
                    if !selectedIDs.insert(task.id).inserted { selectedIDs.remove(task.id) }
                }
                .contextMenu { ToDoNoteMenu(note: note, scope: $toDoScope) }
            }
        } header: {
            HStack(spacing: 8) {
                Image(systemName: "note.text").foregroundStyle(.secondary)
                Text(note.title).font(.headline)
                if let folder = note.folder { Text(folder).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text(note.modificationDate, style: .date).font(.caption).foregroundStyle(.secondary)
            }
                .contentShape(Rectangle())
                .contextMenu { ToDoNoteMenu(note: note, scope: $toDoScope) }
        }
    }

    private func markdown(_ items: [TaskRecord]) -> String {
        items.map { "- [\($0.isCompleted ? "x" : " ")] \($0.text)\n  Source: \($0.noteTitle)" }.joined(separator: "\n\n")
    }
    private func copyVisible() { copy(tasks) }
    private func copy(_ items: [TaskRecord]) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown(items), forType: .string)
        copied = true
        #endif
    }
    private func exportTasks() { save(markdown(tasks), filename: "ancrate-to-dos.md") }
    private func exportNotes() { save(MarkdownConverter.convertToMarkdown(notes: selectedNotes), filename: "ancrate-notes.md") }
    private func save(_ text: String, filename: String) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { exportError = error.localizedDescription }
        #endif
    }
}

private struct TaskRow: View {
    let task: TaskRecord
    let selected: Bool
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(task.isCompleted ? AncrateStyle.accent : SwiftUI.Color.secondary)
                    .accessibilityLabel(task.isCompleted ? "Completed in Notes" : "Open in Notes")
                Text(task.text).font(.body).lineSpacing(3)
                    .strikethrough(task.isCompleted).foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected { Image(systemName: "doc.on.doc").foregroundStyle(AncrateStyle.accent) }
            }
            .padding(.horizontal, 6).padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(selected ? AncrateStyle.accent.opacity(0.12) : SwiftUI.Color.clear,
                        in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Select for copying. Completion is changed in Apple Notes.")
    }
}
