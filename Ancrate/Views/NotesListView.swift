//
//  NotesListView.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 23/10/2025.
//

import SwiftUI

struct NotesListView: View {
    @ObservedObject var notesDatabase: NotesDatabase
    @Binding var selectedNotes: Set<ANote>
    @State private var searchText = ""
    
    var filteredNotes: [ANote] {
        if searchText.isEmpty {
            return notesDatabase.notes
        } else {
            return notesDatabase.notes.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText) ||
                note.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            VStack {
                // Header
//                HStack {
//                    Text("Notes List")
//                        .font(.title2)
//                        .fontWeight(.semibold)
//                    
//                    Spacer()
//                    
//                    Button("Refresh") {
//                        notesDatabase.loadNotes()
//                    }
//                    .disabled(notesDatabase.isLoading)
//                }
//                .padding()
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search notes...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom)
                
                // Notes list
                if notesDatabase.isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading notes...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = notesDatabase.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundColor(.orange)
                        
                        Text("Database Access Issue")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("To fix this issue:")
                                .fontWeight(.semibold)
                            
                            Text("1. Open System Preferences → Security & Privacy → Privacy")
                            Text("2. Select 'Full Disk Access' from the left sidebar")
                            Text("3. Click the lock icon and enter your password")
                            Text("4. Click '+' and add this NotesToDo app")
                            Text("5. Restart the app")
                        }
                        .font(.caption)
                        .padding()
//                        .background(Color(.blue).opacity(0.1))
                        .cornerRadius(8)
                        
                        Button("Retry") {
                            notesDatabase.loadNotes()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Open System Preferences") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    SwiftUI.List(selection: $selectedNotes) {
                        ForEach(filteredNotes, id: \.id) { note in
                            NoteRowView(note: note, isSelected: selectedNotes.contains(note))
                                .tag(note)
                        }
                    }
                   .listStyle(.sidebar)
                }
                
                // Selection info
                if !selectedNotes.isEmpty {
                    HStack {
                        Text("\(selectedNotes.count) note(s) selected")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear Selection") {
                            selectedNotes.removeAll()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 350)
        } detail: {
            if selectedNotes.isEmpty {
                VStack {
                    Image(systemName: "note.text")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select notes to extract checklists")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Choose one or more notes from the list to find all checklist items")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ChecklistsListView(selectedNotes: Array(selectedNotes))
            }
        }
        .onAppear {
            if notesDatabase.notes.isEmpty && notesDatabase.errorMessage == nil {
                notesDatabase.loadNotes()
            }
        }
    }
}

struct NoteRowView: View {
    let note: ANote
    let isSelected: Bool
    @State private var showingProtobufDebug = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                // Protobuf indicator
                if note.hasProtobufData {
                    Button(action: {
                        showingProtobufDebug = true
                    }) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("View protobuf data")
                }
                
                if note.checklists.count > 0 {
                    Text("\(note.checklists.count) checklist\(note.checklists.count == 1 ? "" : "s")")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
            }
            
            if let folder = note.folder, !folder.isEmpty {
                Text(folder)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Show enhanced content if available from protobuf data
            Text({
                if note.hasProtobufData, let document = note.parsedDocument, document.hasNote, document.note.hasNoteText {
                    return document.note.noteText
                } else {
                    return note.content
                }
            }().prefix(100))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                Text(note.modificationDate, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
//        .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
        .sheet(isPresented: $showingProtobufDebug) {
            ProtobufDebugView(note: note)
                .frame(minWidth: 1000, minHeight: 700)
        }
    }
}

#Preview {
    NotesListView(notesDatabase: NotesDatabase(), selectedNotes: .constant(Set<ANote>()))
}
