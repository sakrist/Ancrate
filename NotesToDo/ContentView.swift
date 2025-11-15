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
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

#Preview {
    ContentView(notesDatabase: NotesDatabase())
}
