//
//  Note.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 23/10/2025.
//

import Foundation
import SwiftProtobuf

struct ANote: Identifiable, Hashable {
    let id: String
    let title: String
    let content: String
    let creationDate: Date
    let modificationDate: Date
    let folder: String?
    let rawProtobufData: Data?
    
    var checklists: [ChecklistItem] {
        extractChecklistItems()
    }
    
    var hasProtobufData: Bool {
        rawProtobufData != nil
    }
    
    /// Parse the raw protobuf data if available
    var parsedDocument: Document? {
        guard let protobufData = self.rawProtobufData else { return nil }
        return SwiftProtobufNotesParser.parseDocument(from: protobufData)
    }
    
    private func extractChecklistItems() -> [ChecklistItem] {
        // Extract checklist items directly from Document/Note structure
        guard let document = parsedDocument, document.hasNote else { return [] }
        
        let note = document.note
        let noteText = note.hasNoteText ? note.noteText : ""
        var currentOffset = 0
        
        // Dictionary to group attribute runs by checklist UUID
        var checklistRunsByUuid: [Data: [(range: Range<Int>, isCompleted: Bool)]] = [:]
        
        // Parse attribute runs to find checklist items and group by UUID
        for attributeRun in note.attributeRun {
            let length = Int(attributeRun.length)
            let startIndex = currentOffset
            let endIndex = currentOffset + length
            
            // Check if this attribute run has checklist information
            if attributeRun.hasParagraphStyle && attributeRun.paragraphStyle.hasChecklist {
                let checklist = attributeRun.paragraphStyle.checklist
                
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
        var checklistItems: [ChecklistItem] = []
        
        for (uuid, runs) in checklistRunsByUuid {
            // Sort runs by their start position to maintain order
            let sortedRuns = runs.sorted { $0.range.lowerBound < $1.range.lowerBound }
            
            // Combine text from all runs for this checklist item
            var combinedText = ""
            var overallRange: Range<Int>?
            var isCompleted = false
            
            for run in sortedRuns {
                let range = run.range
                if range.lowerBound < noteText.count && range.upperBound <= noteText.count {
                    let startIdx = noteText.index(noteText.startIndex, offsetBy: range.lowerBound)
                    let endIdx = noteText.index(noteText.startIndex, offsetBy: range.upperBound)
                    let segmentText = String(noteText[startIdx..<endIdx])
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
                    lineNumber: checklistItems.count,
                    range: overallRange
                )
                checklistItems.append(checklistItem)
            }
        }
        
        // Sort checklist items by their position in the note to maintain order
        return checklistItems.sorted { 
            guard let range1 = $0.range, let range2 = $1.range else { return false }
            return range1.lowerBound < range2.lowerBound
        }
    }

}

struct ChecklistItem: Identifiable, Hashable {
    let id: String
    let text: String
    let isCompleted: Bool
    let uuid: Data?
    let lineNumber: Int
    let range: Range<Int>?
}
