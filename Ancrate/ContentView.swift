//
//  ContentView.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 20/10/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @ObservedObject var notesDatabase: NotesDatabase
    @ObservedObject var hotkeyService: NotesHotkeyService
    @State private var selectedNotes: Set<ANote> = []
    
    var body: some View {
        VStack {
            
            TabView {
                NotesListView(notesDatabase: notesDatabase, selectedNotes: $selectedNotes)
                    .tabItem {
                        Label("Notes", systemImage: "note.text")
                    }
                
                ChecklistsListView(selectedNotes: Array(selectedNotes))
                    .tabItem {
                        Label("Checklists", systemImage: "checklist")
                    }

                ExtensionStudioView(notesDatabase: notesDatabase, hotkeyService: hotkeyService)
                    .tabItem {
                        Label("Extension", systemImage: "wand.and.stars")
                    }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    ContentView(notesDatabase: NotesDatabase(), hotkeyService: NotesHotkeyService())
}
