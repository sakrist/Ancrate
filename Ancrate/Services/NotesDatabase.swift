//
//  NotesDatabase.swift
//  NotesToDo
//
//  Created by Volodymyr Boichentsov on 23/10/2025.
//

import Foundation
import SQLite3
import Compression
import zlib

class NotesDatabase: ObservableObject {
    @Published var notes: [ANote] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var databasePath: String {
        // For testing, use the local copy in the project directory
        // Later, switch back to the actual Notes database location
        let projectPath = "/Users/boichentsovv/Developer/NotesToDo/NoteStore.sqlite"
        let realPath = "/Users/\(NSUserName())/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
        
        // Use local copy if it exists for testing, otherwise use real path
        let path = FileManager.default.fileExists(atPath: realPath) ? realPath : ""
        print("Database path: \(path)")
        return path
    }
    
    func loadNotes() {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .background).async {
            do {
                let notes = try self.fetchNotesFromDatabase()
                
                DispatchQueue.main.async {
                    self.notes = notes
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load notes: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func fetchNotesFromDatabase() throws -> [ANote] {
        var db: OpaquePointer?
        var notes: [ANote] = []
        
        print("Attempting to access database at: \(databasePath)")
        
        // Check if database file exists
        guard FileManager.default.fileExists(atPath: databasePath) else {
            print("Database file does not exist at path: \(databasePath)")
            throw NotesError.databaseNotFound
        }
        
        print("Database file exists, attempting to open...")
        
        // Open database
        if sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let error = sqlite3_errmsg(db)
            let errorString = error != nil ? String(cString: error!) : "Unknown error"
            print("Failed to open database: \(errorString)")
            throw NotesError.cannotOpenDatabase
        }
        
        print("Database opened successfully")
        
        defer {
            sqlite3_close(db)
        }
        
        // Query to get actual notes from ZICCLOUDSYNCINGOBJECT
        // Notes have titles in ZTITLE1, and actual content is in ZICNOTEDATA table
        let query = """
            SELECT 
                n.Z_PK as note_id,
                COALESCE(n.ZTITLE1, '') as title,
                COALESCE(n.ZSNIPPET, '') as snippet,
                COALESCE(n.ZCREATIONDATE, 0) as creation_date,
                COALESCE(n.ZMODIFICATIONDATE1, 0) as modification_date,
                COALESCE(f.ZTITLE2, '') as folder_name,
                nd.ZDATA as note_data,
                nd.ZCRYPTOINITIALIZATIONVECTOR as crypto_iv,
                nd.ZCRYPTOTAG as crypto_tag
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            LEFT JOIN ZICNOTEDATA nd ON n.ZNOTEDATA = nd.Z_PK
            WHERE n.ZTITLE1 IS NOT NULL 
            AND n.ZTITLE1 != ''
            AND COALESCE(n.ZMARKEDFORDELETION, 0) = 0
            ORDER BY COALESCE(n.ZMODIFICATIONDATE1, 0) DESC
            LIMIT 50
        """
        
        var statement: OpaquePointer?
        
        print("Preparing SQL query...")
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        
        if prepareResult == SQLITE_OK {
            print("Query prepared successfully, executing...")
            
            while sqlite3_step(statement) == SQLITE_ROW {
                // Use safe column access with type checking
                let noteIdPtr = sqlite3_column_text(statement, 0)
                let noteId = noteIdPtr != nil ? String(cString: noteIdPtr!) : UUID().uuidString
                
                let titlePtr = sqlite3_column_text(statement, 1)
                let title = titlePtr != nil ? String(cString: titlePtr!) : "Untitled"
                
                let snippetPtr = sqlite3_column_text(statement, 2)
                let snippet = snippetPtr != nil ? String(cString: snippetPtr!) : ""
                
                let creationTimestamp = sqlite3_column_double(statement, 3)
                let modificationTimestamp = sqlite3_column_double(statement, 4)
                
                // Apple's Core Data timestamps are seconds since 2001-01-01 00:00:00 UTC
                // Convert to standard Unix timestamp by adding the offset
                let coreDataEpochOffset: TimeInterval = 978307200 // Seconds between 1970 and 2001
                let creationDate = Date(timeIntervalSince1970: creationTimestamp + coreDataEpochOffset)
                let modificationDate = Date(timeIntervalSince1970: modificationTimestamp + coreDataEpochOffset)
                
                let folderPtr = sqlite3_column_text(statement, 5)
                let folderName = folderPtr != nil ? String(cString: folderPtr!) : nil
                
                // Extract note content from encrypted ZDATA in ZICNOTEDATA table
                var content = snippet // Use snippet as fallback
                var rawProtobufData: Data? = nil
                
                // Get encrypted note data and crypto information
                if let dataPointer = sqlite3_column_blob(statement, 6) {
                    let dataLength = sqlite3_column_bytes(statement, 6)
                    let encryptedData = Data(bytes: dataPointer, count: Int(dataLength))
                    
                    // Store raw data for protobuf parsing
                    rawProtobufData = encryptedData
                    
                    // Get crypto initialization vector
                    var cryptoIV: Data? = nil
                    if let ivPointer = sqlite3_column_blob(statement, 7) {
                        let ivLength = sqlite3_column_bytes(statement, 7)
                        cryptoIV = Data(bytes: ivPointer, count: Int(ivLength))
                    }
                    
                    // Get crypto tag
                    var cryptoTag: Data? = nil
                    if let tagPointer = sqlite3_column_blob(statement, 8) {
                        let tagLength = sqlite3_column_bytes(statement, 8)
                        cryptoTag = Data(bytes: tagPointer, count: Int(tagLength))
                    }
                    
                    // Try to decrypt or extract readable content
//                    print("Processing note data - ID: \(noteId), Title: \(title), Data length: \(encryptedData.count)")
//                    print("First 20 bytes: \(encryptedData.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))")
                    
                    // Try extracting content using our new SwiftProtobuf parser
                    if let decompressedData = tryDecompressData(encryptedData) {
//                        print("Successfully decompressed data: \(decompressedData.count) bytes")
                        
                        // Use our SwiftProtobuf-based parser
                        let parsedDocument = SwiftProtobufNotesParser.parseDocument(from: decompressedData)
                        if let document = parsedDocument, document.hasNote, document.note.hasNoteText, !document.note.noteText.isEmpty {
                            let noteText = document.note.noteText
//                            print("SwiftProtobuf parser extracted: \(noteText.prefix(100))...")
                            content = noteText
                        }
                        
                        // Store the decompressed protobuf data
                        rawProtobufData = decompressedData
                    } else if let extractedContent = extractContentFromNoteData(encryptedData) {
                        print("Successfully extracted content from note \(noteId): \(extractedContent.prefix(100))...")
                        content = extractedContent
                    } else if let basicContent = extractTextFromNoteData(encryptedData) {
                        print("Basic extraction successful for note \(noteId): \(basicContent.prefix(100))...")
                        content = basicContent
                    } else {
                        // Note is encrypted and we can't decrypt it without password
                        // Use snippet as content and indicate it's encrypted
                        content = snippet.isEmpty ? "[Encrypted Note - Cannot decrypt without password]" : snippet
                    }
                }
                
                let note = ANote(
                    id: noteId,
                    title: title.isEmpty ? "Untitled" : title,
                    content: content,
                    creationDate: creationDate,
                    modificationDate: modificationDate,
                    folder: folderName?.isEmpty == false ? folderName : nil,
                    rawProtobufData: rawProtobufData
                )
                
                notes.append(note)
                print("Added note: \(title) (ID: \(noteId))")
            }
            
            print("Successfully loaded \(notes.count) notes")
        
        } else {
            let error = sqlite3_errmsg(db)
            let errorString = error != nil ? String(cString: error!) : "Unknown error"
            print("Failed to prepare query. Error: \(errorString)")
            print("SQL Query was: \(query)")
            throw NotesError.queryFailed
        }
        
        // If we didn't get any notes, try a simpler query to see if there's data
        if notes.isEmpty {
            print("No notes found with main query, trying simpler query...")
            try attemptSimpleQuery(db: db!, notes: &notes)
        }
        
        sqlite3_finalize(statement)
        return notes
    }
    
    private func attemptSimpleQuery(db: OpaquePointer, notes: inout [ANote]) throws {
        let simpleQuery = """
            SELECT Z_PK, ZTITLE1, ZSNIPPET 
            FROM ZICCLOUDSYNCINGOBJECT 
            WHERE ZTITLE1 IS NOT NULL 
            AND ZTITLE1 != ''
            ORDER BY ZMODIFICATIONDATE DESC
            LIMIT 10
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, simpleQuery, -1, &statement, nil) == SQLITE_OK {
            print("Simple query prepared successfully")
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let noteIdPtr = sqlite3_column_text(statement, 0)
                let noteId = noteIdPtr != nil ? String(cString: noteIdPtr!) : UUID().uuidString
                
                let titlePtr = sqlite3_column_text(statement, 1)
                let title = titlePtr != nil ? String(cString: titlePtr!) : "Untitled"
                
                let snippetPtr = sqlite3_column_text(statement, 2)
                let snippet = snippetPtr != nil ? String(cString: snippetPtr!) : ""
                
                let note = ANote(
                    id: noteId,
                    title: title,
                    content: snippet,
                    creationDate: Date(),
                    modificationDate: Date(),
                    folder: nil,
                    rawProtobufData: nil
                )
                
                notes.append(note)
                print("Added note from simple query: \(title)")
            }
            
            sqlite3_finalize(statement)
        } else {
            let error = sqlite3_errmsg(db)
            let errorString = error != nil ? String(cString: error!) : "Unknown error"
            print("Simple query also failed: \(errorString)")
        }
    }
    
    // MARK: - Advanced Content Extraction
    
    /// Try to decompress data if it's gzipped
    private func tryDecompressData(_ data: Data) -> Data? {
        // Check if data is gzipped
        if data.count > 3 && data[0] == 0x1f && data[1] == 0x8b {
            return decompressGzip(data)
        }
        return nil
    }
    
    private func extractContentFromNoteData(_ data: Data) -> String? {
        print("extractContentFromNoteData called with \(data.count) bytes")
        print("First 10 bytes: \(data.prefix(10).map { String(format: "%02x", $0) }.joined(separator: " "))")
        
        // First, check if data is gzipped (common format for Apple Notes)
        if data.count > 3 && data[0] == 0x1f && data[1] == 0x8b {
            print("Detected gzipped data")
            // This is gzipped data
            if let decompressed = decompressGzip(data) {
                print("Gzip decompression successful, decompressed size: \(decompressed.count)")
                return parseNoteContent(decompressed)
            } else {
                print("Gzip decompression failed")
            }
        } else {
            print("Not gzipped data (header: \(data.prefix(4).map { String(format: "%02x", $0) }.joined(separator: " ")))")
        }
        
        // If not gzipped, try to parse as-is
        print("Trying to parse as raw data")
        return parseNoteContent(data)
    }
    
    private func decompressGzip(_ compressedData: Data) -> Data? {
        print("decompressGzip called with \(compressedData.count) bytes")
        
        guard compressedData.count > 10 else {
            print("Data too small for gzip format")
            return nil
        }
        
        // iOS 13+/macOS 10.15+ - Use Foundation's NSData decompression
        if #available(iOS 13.0, macOS 10.15, *) {
            do {
                let decompressed = try (compressedData as NSData).decompressed(using: .zlib)
                print("Foundation decompression successful: \(compressedData.count) bytes to \(decompressed.count) bytes")
                
                if let text = String(data: Data(decompressed.prefix(100)), encoding: .utf8) {
                    print("First 100 chars of decompressed content: \(text)")
                } else {
                    print("Decompressed data is not valid UTF-8")
                    let hexString = decompressed.prefix(50).map { String(format: "%02x", $0) }.joined(separator: " ")
                    print("Decompressed data hex (first 50 bytes): \(hexString)")
                }
                
                return decompressed as Data
            } catch {
//                print("Foundation zlib decompression failed: \(error)")
            }
        }
        
        // Fallback: Manual zlib decompression
        if let result = decompressWithZlib(compressedData) {
            return result
        }
        
//        print("All decompression methods failed")
        return nil
    }
    
    private func decompressWithZlib(_ compressedData: Data) -> Data? {
//        print("Trying zlib decompression directly...")
        
        return compressedData.withUnsafeBytes { compressedBytes in
            var stream = z_stream()
            
            // Initialize for gzip decompression
            let windowBits: Int32 = 15 + 16 // 15 + 16 for gzip format
            if inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) != Z_OK {
                print("Failed to initialize zlib")
                return nil
            }
            
            defer {
                inflateEnd(&stream)
            }
            
            // Set input
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: compressedBytes.bindMemory(to: UInt8.self).baseAddress!)
            stream.avail_in = UInt32(compressedData.count)
            
            var decompressedData = Data()
            let bufferSize = 1024 * 16
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            
            repeat {
                stream.next_out = buffer
                stream.avail_out = UInt32(bufferSize)
                
                let result = inflate(&stream, Z_NO_FLUSH)
                
                if result == Z_STREAM_ERROR || result == Z_DATA_ERROR || result == Z_MEM_ERROR {
                    print("zlib decompression error: \(result)")
                    return nil
                }
                
                let bytesDecompressed = bufferSize - Int(stream.avail_out)
                if bytesDecompressed > 0 {
                    decompressedData.append(buffer, count: bytesDecompressed)
                }
                
                if result == Z_STREAM_END {
                    break
                }
            } while stream.avail_out == 0
            
//            print("zlib decompression successful: \(compressedData.count) bytes to \(decompressedData.count) bytes")
            
            // Check if result looks like valid text
            if let text = String(data: decompressedData.prefix(100), encoding: .utf8) {
                print("First 100 chars of decompressed content: \(text)")
            } else {
//                print("Decompressed data is not valid UTF-8")
                let hexString = decompressedData.prefix(50).map { String(format: "%02x", $0) }.joined(separator: " ")
//                print("Decompressed data hex (first 50 bytes): \(hexString)")
            }
            
            return decompressedData
        }
    }
    
    private func parseNoteContent(_ data: Data) -> String? {
//        print("parseNoteContent called with \(data.count) bytes")
        
        // Apple Notes content can be in various formats (protobuf, attributed text, etc.)
        // First try UTF-8 decoding
        if let content = String(data: data, encoding: .utf8) {
//            print("Successfully decoded as UTF-8, length: \(content.count)")
//            print("First 200 characters: \(content.prefix(200))")
            let cleaned = cleanNoteContent(content)
//            print("After cleaning: \(cleaned.prefix(200))")
            return cleaned
        } else {
            print("Failed to decode as UTF-8")
        }
        
        // Try to find text content within the data
//        print("Trying to extract readable text from binary data")
        let result = extractReadableText(from: data)
        if let result = result {
            print("Extracted readable text: \(result.prefix(200))")
        } else {
            print("Failed to extract readable text")
        }
        return result
    }
    
    private func extractReadableText(from data: Data) -> String? {
        var textChunks: [String] = []
        var currentText = ""
        
        for byte in data {
            if byte >= 32 && byte <= 126 || byte == 10 || byte == 13 { // Printable ASCII + newlines
                currentText.append(Character(UnicodeScalar(Int(byte))!))
            } else {
                if currentText.count > 3 {
                    textChunks.append(currentText)
                }
                currentText = ""
            }
        }
        
        if currentText.count > 3 {
            textChunks.append(currentText)
        }
        
        let combined = textChunks.joined(separator: " ")
        return combined.isEmpty ? nil : cleanNoteContent(combined)
    }
    
    // Helper method for extracting text from note data
    private func extractTextFromNoteData(_ data: Data) -> String? {
        // Try to extract readable text from encrypted note data
        // This is a best-effort approach for Apple Notes binary format
        
        // First try UTF-8 decoding
        if let utf8String = String(data: data, encoding: .utf8) {
            let cleaned = cleanNoteContent(utf8String)
            if !cleaned.isEmpty && cleaned != "?" {
                return cleaned
            }
        }
        
        // Try extracting text patterns from binary data
        return extractTextFromBinaryData(data)
    }
    
    private func cleanNoteContent(_ content: String) -> String {
        // Remove non-printable characters and clean up the content
        return content
            .components(separatedBy: .controlCharacters)
            .joined()
            .components(separatedBy: .illegalCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractTextFromBinaryData(_ data: Data) -> String? {
        var extractedText = ""
        let bytes = data.withUnsafeBytes { $0.bindMemory(to: UInt8.self) }
        
        var currentString = ""
        for byte in bytes {
            if byte >= 32 && byte <= 126 { // Printable ASCII range
                if let scalar = UnicodeScalar(Int(byte)) {
                    currentString += String(Character(scalar))
                }
            } else if byte == 10 || byte == 13 { // Newlines
                if currentString.count > 2 {
                    extractedText += currentString + "\n"
                }
                currentString = ""
            } else {
                if currentString.count > 2 { // Only keep strings longer than 2 chars
                    extractedText += currentString + " "
                }
                currentString = ""
            }
        }
        
        // Add the last string if it's long enough
        if currentString.count > 2 {
            extractedText += currentString
        }
        
        let cleaned = extractedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return cleaned.isEmpty ? nil : cleaned
    }
}

enum NotesError: LocalizedError {
    case databaseNotFound
    case cannotOpenDatabase
    case queryFailed
    
    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return """
            Apple Notes database not found. Please check:
            1. Make sure Apple Notes app is installed and has been used
            2. Create some notes in the Notes app first
            3. The app may need Full Disk Access permission in System Preferences > Security & Privacy > Privacy > Full Disk Access
            """
        case .cannotOpenDatabase:
            return """
            Cannot open Apple Notes database. This may be due to:
            1. Insufficient permissions - try granting Full Disk Access to this app
            2. The database may be locked by the Notes app
            3. Database corruption
            """
        case .queryFailed:
            return "Failed to query notes from database. The database structure may have changed."
        }
    }
}
