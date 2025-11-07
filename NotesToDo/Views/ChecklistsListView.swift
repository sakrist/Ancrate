//
//  ChecklistsListView.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 23/10/2025.
//

import SwiftUI

struct ChecklistsListView: View {
    let selectedNotes: [ANote]
    @State private var searchText = ""
    @State private var showCompletedChecklists = true
    @State private var selectedChecklistItems: Set<ChecklistItem> = []
    
    var allChecklists: [ChecklistWithSource] {
        var checklists: [ChecklistWithSource] = []
        
        for note in selectedNotes {
            for checklist in note.checklists {
                checklists.append(ChecklistWithSource(checklist: checklist, sourceNote: note))
            }
        }
        
        return checklists
    }
    
    var filteredChecklists: [ChecklistWithSource] {
        let checklistsToShow = showCompletedChecklists ? allChecklists : allChecklists.filter { !$0.checklist.isCompleted }
        
        if searchText.isEmpty {
            return checklistsToShow
        } else {
            return checklistsToShow.filter { checklistWithSource in
                checklistWithSource.checklist.text.localizedCaseInsensitiveContains(searchText) ||
                checklistWithSource.sourceNote.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var completedCount: Int {
        allChecklists.filter { $0.checklist.isCompleted }.count
    }
    
    var totalCount: Int {
        allChecklists.count
    }
    
    var body: some View {
        VStack {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Extracted Checklists")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(totalCount - completedCount) remaining • \(completedCount) completed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Menu {
                    Button(action: { copyChecklistsToClipboard() }) {
                        Label("Copy All Checklists", systemImage: "doc.on.clipboard")
                    }
                    
                    Button(action: { exportChecklists() }) {
                        Label("Export Checklists", systemImage: "square.and.arrow.up")
                    }
                    
                    Button(action: { exportAsMarkdown() }) {
                        Label("Export as Markdown", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
            }
            .padding()
            
            // Search and filters
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search checklists...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                
                Toggle("Show completed", isOn: $showCompletedChecklists)
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal)
            
            if filteredChecklists.isEmpty {
                VStack {
                    Image(systemName: allChecklists.isEmpty ? "checklist" : "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text(allChecklists.isEmpty ? "No checklists found" : "No matching checklists")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text(allChecklists.isEmpty ? 
                         "The selected notes don't contain any recognizable checklist items" :
                         "Try adjusting your search terms or filters")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Checklists list
                SwiftUI.List(selection: $selectedChecklistItems) {
                    ForEach(filteredChecklists, id: \.id) { checklistWithSource in
                        ChecklistRowView(checklistWithSource: checklistWithSource)
                            .tag(checklistWithSource.checklist)
                    }
                }
                .listStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !selectedChecklistItems.isEmpty {
                    Button("Copy Selected (\(selectedChecklistItems.count))") {
                        copySelectedChecklistsToClipboard()
                    }
                }
            }
        }
    }
    
    private func copyChecklistsToClipboard() {
        let checklistText = filteredChecklists.map { checklistWithSource in
            let checkbox = checklistWithSource.checklist.isCompleted ? "☑" : "☐"
            return "\(checkbox) \(checklistWithSource.checklist.text) (from: \(checklistWithSource.sourceNote.title))"
        }.joined(separator: "\n")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(checklistText, forType: .string)
    }
    
    private func copySelectedChecklistsToClipboard() {
        let selectedChecklistTexts = filteredChecklists
            .filter { selectedChecklistItems.contains($0.checklist) }
            .map { checklistWithSource in
                let checkbox = checklistWithSource.checklist.isCompleted ? "☑" : "☐"
                return "\(checkbox) \(checklistWithSource.checklist.text) (from: \(checklistWithSource.sourceNote.title))"
            }
            .joined(separator: "\n")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedChecklistTexts, forType: .string)
        
        selectedChecklistItems.removeAll()
    }
    
    private func exportChecklists() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Checklists"
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "checklists.txt"
        
        if savePanel.runModal() == .OK {
            guard let url = savePanel.url else { return }
            
            let checklistText = filteredChecklists.map { checklistWithSource in
                let checkbox = checklistWithSource.checklist.isCompleted ? "[x]" : "[ ]"
                return "- \(checkbox) \(checklistWithSource.checklist.text)\n  Source: \(checklistWithSource.sourceNote.title)"
            }.joined(separator: "\n\n")
            
            do {
                try checklistText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Handle error - could show an alert here
                print("Failed to export checklists: \(error)")
            }
        }
    }
    
    private func exportAsMarkdown() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Notes as Markdown"
        savePanel.allowedContentTypes = [.init(filenameExtension: "md")!]
        savePanel.nameFieldStringValue = "notes.md"
        
        if savePanel.runModal() == .OK {
            guard let url = savePanel.url else { return }
            
            let markdownContent = MarkdownConverter.convertToMarkdown(notes: selectedNotes)
            
            do {
                try markdownContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Handle error - could show an alert here
                print("Failed to export markdown: \(error)")
            }
        }
    }
}

struct ChecklistRowView: View {
    let checklistWithSource: ChecklistWithSource
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: checklistWithSource.checklist.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundColor(checklistWithSource.checklist.isCompleted ? .green : .secondary)
                    .font(.title3)
                
                Text(checklistWithSource.checklist.text)
                    .strikethrough(checklistWithSource.checklist.isCompleted)
                    .foregroundColor(checklistWithSource.checklist.isCompleted ? .secondary : .primary)
                
                Spacer()
            }
            
            HStack {
                Text("from: \(checklistWithSource.sourceNote.title)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("line \(checklistWithSource.checklist.lineNumber + 1)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ChecklistWithSource: Identifiable {
    let id = UUID()
    let checklist: ChecklistItem
    let sourceNote: ANote
}

#Preview {
    ChecklistsListView(selectedNotes: [])
}