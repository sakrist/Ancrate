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
    private var previewNotes: [ANote]?
    @Published private(set) var isDemoData = false
    private let databaseURL: URL?

    init(previewNotes: [ANote]? = nil, databaseURL: URL? = nil) {
        self.previewNotes = previewNotes
        self.databaseURL = databaseURL
        self.notes = previewNotes ?? []
        self.isDemoData = previewNotes != nil
    }

    func showSampleNotes() {
        guard !isLoading else { return }
        previewNotes = DemoNotes.make()
        isDemoData = true
        notes = previewNotes ?? []
        errorMessage = nil
    }

    func connectRealNotes() {
        previewNotes = nil
        isDemoData = false
        notes = []
        loadNotes()
    }
    
    private var databasePath: String {
        if let databaseURL { return databaseURL.path }
        let realPath = "/Users/\(NSUserName())/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
        let path = FileManager.default.fileExists(atPath: realPath) ? realPath : ""
        return path
    }

    /// Fetch notes for both the SwiftUI client and the MCP server.
    ///
    /// This reads the Notes store without touching the published UI state so
    /// MCP requests can use an isolated NotesDatabase instance and receive a
    /// fresh snapshot.
    func fetchNotes(limit: Int? = 100) throws -> [ANote] {
        try fetchNotesFromDatabase(limit: limit)
    }

    func fetchNote(id: String) throws -> ANote? {
        guard let numericID = Int64(id), numericID > 0 else { return nil }
        return try fetchNotesFromDatabase(limit: 1, noteID: numericID).first
    }

    /// Check the read permission without parsing any note contents.
    func canReadNotesDatabase() -> Bool {
        let path = databasePath
        guard FileManager.default.fileExists(atPath: path) else { return false }

        var db: OpaquePointer?
        let result = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        if let db {
            sqlite3_close(db)
        }
        return result == SQLITE_OK
    }

    func loadNotes() {
        guard !isLoading else { return }
        if let previewNotes { notes = previewNotes; errorMessage = nil; return }
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .background).async {
            do {
                let notes = try self.fetchNotesFromDatabase(limit: nil)
                
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
    
    private func fetchNotesFromDatabase(limit: Int? = 100, noteID: Int64? = nil) throws -> [ANote] {
        var db: OpaquePointer?
        var notes: [ANote] = []
        
        // Check if database file exists
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw NotesError.databaseNotFound
        }
        
        defer { if let db { sqlite3_close(db) } }
        // Open database
        if sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let error = sqlite3_errmsg(db)
            let errorString = error != nil ? String(cString: error!) : "Unknown error"
            diagnostic("Failed to open database: \(errorString)")
            throw NotesError.cannotOpenDatabase
        }
        
        // Query to get actual notes from ZICCLOUDSYNCINGOBJECT
        // Notes have titles in ZTITLE1, and actual content is in ZICNOTEDATA table
        let limitClause = limit.map { "LIMIT \(max(1, min($0, 500)))" } ?? ""
        let idClause = noteID == nil ? "" : "AND n.Z_PK = ?"
        let query = """
            SELECT 
                n.Z_PK as note_id,
                COALESCE(n.ZTITLE1, '') as title,
                COALESCE(n.ZSNIPPET, '') as snippet,
                COALESCE(n.ZCREATIONDATE, 0) as creation_date,
                COALESCE(n.ZMODIFICATIONDATE1, 0) as modification_date,
                COALESCE(f.ZTITLE2, '') as folder_name,
                nd.ZDATA as note_data,
                n.ZFOLDER as folder_id
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON n.ZFOLDER = f.Z_PK
            LEFT JOIN ZICNOTEDATA nd ON n.ZNOTEDATA = nd.Z_PK
            WHERE n.ZTITLE1 IS NOT NULL 
            AND n.ZTITLE1 != ''
            AND COALESCE(n.ZMARKEDFORDELETION, 0) = 0
            \(idClause)
            ORDER BY COALESCE(n.ZMODIFICATIONDATE1, 0) DESC
            \(limitClause)
        """
        
        var statement: OpaquePointer?
        
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        
        if prepareResult == SQLITE_OK {
            if let noteID { sqlite3_bind_int64(statement, 1, noteID) }
            
            var stepResult = sqlite3_step(statement)
            while stepResult == SQLITE_ROW {
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
                let folderID = sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil
                    : String(sqlite3_column_int64(statement, 7))
                
                // Extract note content from encrypted ZDATA in ZICNOTEDATA table
                var content = snippet // Use snippet as fallback
                var rawProtobufData: Data? = nil
                
                // Get encrypted note data and crypto information
                if let dataPointer = sqlite3_column_blob(statement, 6) {
                    let dataLength = sqlite3_column_bytes(statement, 6)
                    let encryptedData = Data(bytes: dataPointer, count: Int(dataLength))
                    
                    // Store raw data for protobuf parsing
                    rawProtobufData = encryptedData
                    
                    // Try extracting content using our new SwiftProtobuf parser
                    if let decompressedData = tryDecompressData(encryptedData) {
                        
                        // Use our SwiftProtobuf-based parser
                        let parsedDocument = SwiftProtobufNotesParser.parseDocument(from: decompressedData)
                        if let document = parsedDocument, document.hasNote, document.note.hasNoteText, !document.note.noteText.isEmpty {
                            let noteText = document.note.noteText
                            content = noteText
                        }
                        
                        // Store the decompressed protobuf data
                        rawProtobufData = decompressedData
                    } else if let extractedContent = extractContentFromNoteData(encryptedData) {
                        content = extractedContent
                    } else if let basicContent = extractTextFromNoteData(encryptedData) {
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
                    rawProtobufData: rawProtobufData,
                    folderID: folderID
                )
                
                notes.append(note)
                stepResult = sqlite3_step(statement)
            }
            
            guard stepResult == SQLITE_DONE else { throw NotesError.queryFailed }
        
        } else {
            let error = sqlite3_errmsg(db)
            let errorString = error != nil ? String(cString: error!) : "Unknown error"
            diagnostic("Failed to prepare query. Error: \(errorString)")
            throw NotesError.queryFailed
        }
        
        return notes
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
        
        // First, check if data is gzipped (common format for Apple Notes)
        if data.count > 3 && data[0] == 0x1f && data[1] == 0x8b {
            // This is gzipped data
            if let decompressed = decompressGzip(data) {
                return parseNoteContent(decompressed)
            } else {
            }
        } else {
        }
        
        // If not gzipped, try to parse as-is
        return parseNoteContent(data)
    }
    
    private func decompressGzip(_ compressedData: Data) -> Data? {
        
        guard compressedData.count > 10 else {
            return nil
        }
        
        // iOS 13+/macOS 10.15+ - Use Foundation's NSData decompression
        if #available(iOS 13.0, macOS 10.15, *) {
            do {
                let decompressed = try (compressedData as NSData).decompressed(using: .zlib)
                
                return decompressed as Data
            } catch {
            }
        }
        
        // Fallback: Manual zlib decompression
        if let result = decompressWithZlib(compressedData) {
            return result
        }
        
        return nil
    }
    
    private func decompressWithZlib(_ compressedData: Data) -> Data? {
        
        return compressedData.withUnsafeBytes { compressedBytes in
            var stream = z_stream()
            
            // Initialize for gzip decompression
            let windowBits: Int32 = 15 + 16 // 15 + 16 for gzip format
            if inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) != Z_OK {
                diagnostic("Failed to initialize zlib")
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
            
            
            return decompressedData
        }
    }
    
    private func parseNoteContent(_ data: Data) -> String? {
        
        // Apple Notes content can be in various formats (protobuf, attributed text, etc.)
        // First try UTF-8 decoding
        if let content = String(data: data, encoding: .utf8) {
            let cleaned = cleanNoteContent(content)
            return cleaned
        } else {
            diagnostic("Failed to decode as UTF-8")
        }
        
        // Try to find text content within the data
        let result = extractReadableText(from: data)
        if result == nil {
            diagnostic("Failed to extract readable text")
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
    private func diagnostic(_ message: @autoclosure () -> String) {
        let data = Data((message() + "\n").utf8)
        FileHandle.standardError.write(data)
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
