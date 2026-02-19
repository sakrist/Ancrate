//
//  ProtobufDebugView.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 04/11/2025.
//

import SwiftUI
import SwiftProtobuf

struct ProtobufDebugView: View {
    let note: ANote
    @State private var parsedDocument: Document?
    @State private var markdownOutput: String = ""
    
    var body: some View {
        HSplitView {
            /*
            // Left side - Debug info
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if note.hasProtobufData {
                        protobufInfoSection
                        
                        if let document = parsedDocument {
                            swiftProtobufContentSection(document: document)
                        }
                    } else {
                        Text("No protobuf data available for this note")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .frame(minWidth: 400)
            */
            // Right side - Markdown output
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Markdown Output")
                        .font(.headline)
                    Spacer()
                    Button("Copy Markdown") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(markdownOutput, forType: .string)
                    }
                    .disabled(markdownOutput.isEmpty)
                }
                
                ScrollView {
                    Text(markdownOutput.isEmpty ? "No markdown output available" : markdownOutput)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                        .background(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            .padding()
            .frame(minWidth: 400)
        }
        .navigationTitle("Protobuf Debug & Markdown")
        .onAppear {
            parseProtobufData()
        }
    }
    
    private var protobufInfoSection: some View {
        GroupBox("Protobuf Info") {
            VStack(alignment: .leading, spacing: 8) {
                if let data = note.rawProtobufData {
                    Text("Data size: \(data.count) bytes")
                    Text("First 20 bytes: \(data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }
    

    
    private func swiftProtobufContentSection(document: Document) -> some View {
        GroupBox("SwiftProtobuf Parser Results") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Parser: SwiftProtobuf")
                    .font(.headline)
                    .foregroundColor(.green)
                
                Text("Document Version: \(document.version)")
                
                if document.hasNote {
                    let note = document.note
                    
                    if note.hasNoteText {
                        Text("Note Text Length: \(note.noteText.count) characters")
                    }
                    
                    Text("Attribute Runs: \(note.attributeRun.count)")
                    
                    // Extract and display checklist items using the same logic as the Note model
                    let checklistItems = extractChecklistItems(from: document)
                    Text("Checklists Found: \(checklistItems.count)")
                    
                    if note.hasNoteText && !note.noteText.isEmpty {
                        Text("Content:")
                            .font(.headline)
                        Text(note.noteText.prefix(500))
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    if !checklistItems.isEmpty {
                        Text("Checklists (\(checklistItems.count)):")
                            .font(.headline)
                        ForEach(Array(checklistItems.enumerated()), id: \.offset) { index, item in
                            HStack {
                                Image(systemName: item.isCompleted ? "checkmark.square" : "square")
                                Text(item.text)
                            }
                            .font(.caption)
                        }
                    }
                    
                    if !note.attributeRun.isEmpty {
                        Text("Attribute Runs:")
                            .font(.headline)
                        ForEach(Array(note.attributeRun.prefix(5).enumerated()), id: \.offset) { index, run in
                            VStack(alignment: .leading) {
                                Text("Run \(index + 1): Length \(run.length)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                
                                if run.hasParagraphStyle {
                                    Text("• Has paragraph style")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        
                        if note.attributeRun.count > 5 {
                            Text("... and \(note.attributeRun.count - 5) more runs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("No note data available")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func extractChecklistItems(from document: Document) -> [ChecklistItem] {
        guard document.hasNote else { return [] }
        
        let note = document.note
        guard note.hasNoteText && !note.attributeRun.isEmpty else { return [] }
        
        let text = note.noteText
        var currentOffset = 0
        
        // Dictionary to group attribute runs by checklist UUID
        var checklistRunsByUuid: [Data: [(range: Range<Int>, isCompleted: Bool)]] = [:]
        
        // Parse attribute runs to find checklist items and group by UUID
        for run in note.attributeRun {
            let length = Int(run.length)
            let startIndex = currentOffset
            let endIndex = currentOffset + length
            
            // Check if this attribute run has checklist information
            if run.hasParagraphStyle && run.paragraphStyle.hasChecklist {
                let checklist = run.paragraphStyle.checklist
                
                if checklist.hasUuid {
                    let uuid = checklist.uuid
                    let isCompleted = checklist.hasDone ? checklist.done != 0 : false
                    let range = startIndex..<endIndex
                    
                    if checklistRunsByUuid[uuid] == nil {
                        checklistRunsByUuid[uuid] = []
                    }
                    checklistRunsByUuid[uuid]?.append((range: range, isCompleted: isCompleted))
                }
            }
            
            currentOffset += length
        }
        
        // Convert grouped runs into checklist items
        var items: [ChecklistItem] = []
        
        for (uuid, runs) in checklistRunsByUuid {
            // Sort runs by their start position to maintain order
            let sortedRuns = runs.sorted { $0.range.lowerBound < $1.range.lowerBound }
            
            // Combine text from all runs for this checklist item
            var combinedText = ""
            var overallRange: Range<Int>?
            var isCompleted = false
            
            for run in sortedRuns {
                let range = run.range
                if range.lowerBound < text.count && range.upperBound <= text.count {
                    let startIdx = text.index(text.startIndex, offsetBy: range.lowerBound)
                    let endIdx = text.index(text.startIndex, offsetBy: range.upperBound)
                    let segmentText = String(text[startIdx..<endIdx])
                    combinedText += segmentText
                    
                    // Track the overall range (from first to last segment)
                    if overallRange == nil {
                        overallRange = range
                    } else {
                        overallRange = overallRange!.lowerBound..<range.upperBound
                    }
                    
                    // Use completion status from any of the runs (they should be consistent)
                    isCompleted = run.isCompleted
                }
            }
            
            // Create checklist item if we have valid text
            let trimmedText = combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                let checklistId = uuid.map { String(format: "%02x", $0) }.joined()
                
                let checklistItem = ChecklistItem(
                    id: checklistId,
                    text: trimmedText,
                    isCompleted: isCompleted,
                    uuid: uuid,
                    lineNumber: items.count,
                    range: overallRange
                )
                items.append(checklistItem)
            }
        }
        
        // Sort checklist items by their position in the note to maintain order
        return items.sorted { 
            guard let range1 = $0.range, let range2 = $1.range else { return false }
            return range1.lowerBound < range2.lowerBound
        }
    }
    

    
    private func parseProtobufData() {
        guard let data = note.rawProtobufData else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let document = SwiftProtobufNotesParser.parseDocument(from: data)
            
            DispatchQueue.main.async {
                self.parsedDocument = document
                
                // Generate markdown output if we have a document
                if let document = document {
                    self.markdownOutput = MarkdownConverter.convertToMarkdown(document: document, title: note.title)
                } else {
                    self.markdownOutput = "Failed to parse document"
                }
            }
        }
    }
}

#Preview {
    ProtobufDebugView(note: ANote(
        id: "1",
        title: "Test Note",
        content: "Sample content",
        creationDate: Date(),
        modificationDate: Date(),
        folder: nil,
        rawProtobufData: Data("test data".utf8)
    ))
}
