//
//  NotesToDoApp.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 20/10/2025.
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct NotesToDoApp: App {
    @StateObject private var notesDatabase = NotesDatabase(
        previewNotes: CommandLine.arguments.contains("--demo") ? DemoNotes.make() : nil
    )
    @StateObject private var toDoPreferences = ToDoPreferences()

    #if os(macOS)
    @StateObject private var permissions = AncratePermissionCoordinator()
    @StateObject private var slashCommands = NotesSlashCommandController()
    #endif

    init() {
        #if os(macOS)
        if AncrateMCPServer.isMCPMode {
            NSApplication.shared.setActivationPolicy(.prohibited)
            Task {
                await AncrateMCPServer.run()
                await MainActor.run {
                    NSApplication.shared.terminate(nil)
                }
            }
        } else {
            AppPresentation.applyDockVisibility(UserDefaults.standard.bool(forKey: AppPresentation.dockPreferenceKey))
        }
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "library") {
            #if os(macOS)
            ContentView(
                notesDatabase: notesDatabase,
                permissions: permissions,
                slashCommands: slashCommands,
                checkPermissions: !AncrateMCPServer.isMCPMode && !CommandLine.arguments.contains("--demo")
            )
            .environmentObject(toDoPreferences)
            #else
            ContentView(notesDatabase: notesDatabase)
                .environmentObject(toDoPreferences)
            #endif
        }
        .defaultSize(width: 1120, height: 780)

        #if os(macOS)
        MenuBarExtra("Ancrate", systemImage: "note.text", isInserted: .constant(!AncrateMCPServer.isMCPMode)) {
            AncrateMenuBarView(slashCommands: slashCommands)
        }
        #endif
    }
}
