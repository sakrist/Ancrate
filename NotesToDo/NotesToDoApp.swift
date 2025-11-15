//
//  NotesToDoApp.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 20/10/2025.
//

import SwiftUI
import SwiftData

@main
struct NotesToDoApp: App {
    @StateObject private var notesDatabase = NotesDatabase()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(notesDatabase: notesDatabase)
        }
        .modelContainer(sharedModelContainer)
    }
}
