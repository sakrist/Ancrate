//
//  SwiftProtobufNotesParser.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 04/11/2025.
//

import Foundation
import SwiftProtobuf

/// Simplified parser that works directly with Apple Notes protobuf types
class SwiftProtobufNotesParser {
    
    /// Parse Apple Notes protobuf data and return the Document directly
    static func parseDocument(from data: Data) -> Document? {
        // Try parsing as NoteStoreProto first
        if let document = parseAsNoteStore(data) {
            return document
        }
        
        // Try parsing as Document directly
        if let document = parseAsDocument(data) {
            return document
        }
        
        // Try parsing as Note and wrap in Document
        if let note = parseAsNote(data) {
            var document = Document()
            document.note = note
            return document
        }
        
        return nil
    }
    
    /// Try parsing as NoteStoreProto and extract Document
    private static func parseAsNoteStore(_ data: Data) -> Document? {
        do {
            let noteStore = try NoteStoreProto(serializedBytes: data)
            if noteStore.hasDocument {
                return noteStore.document
            }
        } catch {
            // Not a valid NoteStoreProto, continue to next attempt
        }
        return nil
    }
    
    /// Try parsing as Document directly
    private static func parseAsDocument(_ data: Data) -> Document? {
        do {
            return try Document(serializedBytes: data)
        } catch {
            // Not a valid Document, continue to next attempt
        }
        return nil
    }
    
    /// Try parsing as Note directly
    private static func parseAsNote(_ data: Data) -> Note? {
        do {
            return try Note(serializedBytes: data)
        } catch {
            // Not a valid Note, continue to next attempt
        }
        return nil
    }
}
