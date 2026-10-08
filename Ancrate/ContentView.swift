import SwiftUI

struct ContentView: View {
    @ObservedObject var notesDatabase: NotesDatabase
    @EnvironmentObject private var toDoPreferences: ToDoPreferences
    @State private var sampleScope = ToDoScope()
    @State private var selectedNotes: Set<ANote> = []
    @State private var destination: String? = TaskPeriod.month.rawValue
    @AppStorage("taskDateBasis") private var dateBasis: TaskDateBasis = .modified
    @AppStorage("widgetSharingEnabled") private var widgetSharing = true
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @AppStorage(AppPresentation.dockPreferenceKey) private var showInDock = false
    @ObservedObject var permissions: AncratePermissionCoordinator
    @ObservedObject var slashCommands: NotesSlashCommandController
    @StateObject private var widgets = WidgetSnapshotPublisher()
    let checkPermissions: Bool
    init(notesDatabase: NotesDatabase, permissions: AncratePermissionCoordinator,
         slashCommands: NotesSlashCommandController, checkPermissions: Bool = true) {
        self.notesDatabase = notesDatabase
        self.permissions = permissions
        self.slashCommands = slashCommands
        self.checkPermissions = checkPermissions
    }
    #endif

    private var period: TaskPeriod { TaskPeriod(rawValue: destination ?? "month") ?? .month }
    private var toDoScope: ToDoScope { notesDatabase.isDemoData ? sampleScope : toDoPreferences.scope }
    private var scopeBinding: Binding<ToDoScope> {
        Binding(get: { toDoScope }, set: { scope in
            if notesDatabase.isDemoData { sampleScope = scope } else { toDoPreferences.update(scope) }
        })
    }
    private func notes(in period: TaskPeriod) -> [ANote] {
        toDoScope.notes(from: notesDatabase.notes).filter {
            period.contains(dateBasis.date(created: $0.creationDate, modified: $0.modificationDate))
        }
    }
    private func openCount(_ period: TaskPeriod) -> Int {
        notes(in: period).reduce(0) { $0 + $1.checklists.filter { !$0.isCompleted }.count }
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    AncrateMark(size: 24)
                    Text("Ancrate").font(.headline)
                }.padding(.horizontal, 16).padding(.vertical, 12)
                SwiftUI.List(selection: $destination) {
                    Section("Library") {
                        Label("All notes", systemImage: "note.text").badge(notesDatabase.notes.count).tag("notes")
                    }
                    Section("To-dos") {
                        ForEach(TaskPeriod.allCases) { period in
                            Label(period.title, systemImage: period.symbol).badge(openCount(period)).tag(period.rawValue)
                        }
                    }
                    #if os(macOS)
                    Section("Ancrate") {
                        Label("Settings", systemImage: "slider.horizontal.3").tag("settings")
                    }
                    #endif
                }.listStyle(.sidebar)
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 7) {
                    Label(notesDatabase.isDemoData ? "Exploring sample notes" : "Local Notes library", systemImage: "leaf")
                        .foregroundStyle(.secondary)
                    Text(notesDatabase.isDemoData ? "Sample library" : "Your notes stay on this Mac.").foregroundStyle(.secondary)
                }.font(.caption).padding(14)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            content
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Label("Apple Notes · Read-only library", systemImage: "lock")
                            .labelStyle(.titleAndIcon).fixedSize()
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { notesDatabase.loadNotes() } label: {
                            Label("Refresh notes", systemImage: "arrow.clockwise")
                        }
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(notesDatabase.isLoading)
                    }
                }
        }
        .navigationTitle(destination == "settings" ? "Settings" : destination == "notes" ? "Notes" : period.title)
        .frame(minWidth: 920, minHeight: 640)
        #if os(macOS)
        .sheet(isPresented: $permissions.isPresented) {
            PermissionSetupView(permissions: permissions, exploreSamples: notesDatabase.showSampleNotes)
        }
        .onChange(of: notesDatabase.isLoading) { _, loading in if !loading { publishWidget() } }
        .onChange(of: dateBasis) { _, _ in publishWidget() }
        .onChange(of: widgetSharing) { _, _ in publishWidget() }
        .onChange(of: toDoScope) { _, _ in publishWidget() }
        .onChange(of: showInDock) { _, visible in
            AppPresentation.applyDockVisibility(visible)
        }
        #endif
        .onOpenURL { url in
            if url.scheme == "ancrate", url.host == "tasks" {
                destination = TaskPeriod(rawValue: url.lastPathComponent)?.rawValue ?? TaskPeriod.month.rawValue
            }
        }
        .onChange(of: scenePhase) { _, phase in
            #if os(macOS)
            if AncrateMCPServer.isMCPMode || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
            #endif
            if phase == .active && notesDatabase.notes.isEmpty { notesDatabase.loadNotes() }
        }
        .task {
            #if os(macOS)
            if AncrateMCPServer.isMCPMode || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
            if checkPermissions {
                permissions.check()
                slashCommands.startIfEnabled()
            }
            #endif
            if notesDatabase.notes.isEmpty { notesDatabase.loadNotes() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { return }
                notesDatabase.loadNotes()
            }
        }
    }

    @ViewBuilder private var content: some View {
        #if os(macOS)
        if destination == "settings" {
            settings
        } else {
            libraryContent
        }
        #else
        libraryContent
        #endif
    }

    @ViewBuilder private var libraryContent: some View {
        if notesDatabase.isLoading && notesDatabase.notes.isEmpty {
            VStack(spacing: 16) { ProgressView(); Text("Gathering your notes…").foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(AncrateStyle.canvas)
        } else if let error = notesDatabase.errorMessage {
            VStack(spacing: 18) {
                EmptyState(symbol: "lock.shield", title: "Let's connect your notes", detail: error)
                #if os(macOS)
                Button("Open Full Disk Access", action: permissions.openFullDiskAccessSettings).buttonStyle(.borderedProminent)
                #endif
                Button("Try Again") { notesDatabase.loadNotes() }
                Button("Explore with sample notes", action: notesDatabase.showSampleNotes)
            }.padding(.bottom, 50).frame(maxWidth: .infinity, maxHeight: .infinity).background(AncrateStyle.canvas)
        } else if destination == "notes" {
            NotesListView(notesDatabase: notesDatabase, selectedNotes: $selectedNotes, toDoScope: scopeBinding)
        } else {
            ChecklistsListView(selectedNotes: notes(in: period), toDoScope: scopeBinding,
                               manageSources: { destination = "settings" }, title: period.title,
                               subtitle: period == .all ? "Checklists from your Apple Notes."
                                   : "From notes \(dateBasis == .modified ? "edited" : "created") in the last \(period == .month ? "month" : "three months").")
        }
    }

    #if os(macOS)
    private var settings: some View {
        Form {
            Section("Application") {
                Toggle("Show in Dock", isOn: $showInDock)
                Text("When hidden from the Dock, use the menu-bar icon to open Ancrate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Library") {
                Picker("Group recent to-dos by note date", selection: $dateBasis) {
                    ForEach(TaskDateBasis.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 400)
                Text("Apple Notes provides dates for notes, rather than individual checklist items.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Manage Full Disk Access", action: permissions.openFullDiskAccessSettings)
                if notesDatabase.isDemoData {
                    Button("Connect my Apple Notes") { notesDatabase.connectRealNotes(); permissions.check() }
                } else {
                    Button("Explore with sample notes", action: notesDatabase.showSampleNotes)
                        .disabled(notesDatabase.isLoading)
                }
            }
            ToDoSourcesView(notes: notesDatabase.notes, scope: scopeBinding, isSample: notesDatabase.isDemoData)
            Section("Desktop widget") {
                Toggle("Show my to-dos in the Ancrate widget", isOn: $widgetSharing)
                Text("Right-click your desktop, choose Edit Widgets, then find Ancrate. Choose a time range by editing the widget. Keep Ancrate running to refresh its local snapshot every minute.")
                    .font(.caption).foregroundStyle(.secondary)
                if !notesDatabase.isDemoData, let error = widgets.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
            NotesSlashSettings(controller: slashCommands)
            MCPSetupView()
        }
        .formStyle(.grouped)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AncrateStyle.canvas)
    }
    private func publishWidget() {
        guard !notesDatabase.isDemoData || !widgetSharing else { return }
        widgets.publish(notes: notesDatabase.notes, scope: toDoScope, basis: dateBasis, enabled: widgetSharing,
                        unavailable: notesDatabase.errorMessage != nil)
    }
    #endif
}
