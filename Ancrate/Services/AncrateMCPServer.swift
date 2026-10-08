//
//  AncrateMCPServer.swift
//  Ancrate
//
//  Local stdio MCP server used by desktop LLM clients. Launch the app
//  executable with --mcp-stdio to start this mode.
//

#if os(macOS)
import Foundation
import MCP

enum AncrateMCPServer {
    static let isMCPMode = CommandLine.arguments.contains("--mcp-stdio")

    static func makeServer() async -> Server {
        let noteService = NotesMCPService()
        let server = Server(
            name: "ancrate",
            version: "1.0.0",
            title: "Ancrate Notes",
            instructions: "Ancrate provides read-only access to the user's Apple Notes. List and search notes, read their contents, and extract checklists. This server cannot create, edit, append to, or delete notes.",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: toolDefinitions)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let result: String
                switch params.name {
                case "list_notes":
                    result = try await noteService.listNotes(
                        query: params.arguments?["query"]?.stringValue,
                        folder: params.arguments?["folder"]?.stringValue,
                        limit: params.arguments?["limit"]?.intValue ?? 25
                    )
                case "search_notes":
                    guard let query = params.arguments?["query"]?.stringValue,
                          !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw AncrateMCPError.missingArgument("query")
                    }
                    result = try await noteService.listNotes(
                        query: query,
                        folder: nil,
                        limit: params.arguments?["limit"]?.intValue ?? 25
                    )
                case "get_note":
                    result = try await noteService.getNote(id: requiredString("id", from: params))
                case "get_checklists":
                    result = try await noteService.getChecklists(id: requiredString("id", from: params))
                default:
                    throw AncrateMCPError.unknownTool(params.name)
                }

                return .init(content: [.text(text: result, annotations: nil, _meta: nil)], isError: false)
            } catch {
                return .init(
                    content: [.text(text: "Ancrate error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
        }

        return server
    }

    static func run() async {
        let server = await makeServer()
        do {
            let transport = StdioTransport()
            try await server.start(transport: transport)
            await server.waitUntilCompleted()
        } catch {
            writeToStandardError("Ancrate MCP server stopped: \(error.localizedDescription)")
        }
    }

    private static func requiredString(_ name: String, from params: CallTool.Parameters) throws -> String {
        guard let value = params.arguments?[name]?.stringValue,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AncrateMCPError.missingArgument(name)
        }
        return value
    }

    private static func writeToStandardError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static let toolDefinitions: [Tool] = [
        Tool(
            name: "list_notes",
            description: "List recent Apple Notes with stable Ancrate IDs, titles, folders, dates, and short content previews. Use get_note for the complete body.",
            inputSchema: objectSchema(
                properties: [
                    "query": stringField("Optional text to match in the title or note body."),
                    "folder": stringField("Optional Apple Notes folder name."),
                    "limit": integerField("Optional maximum number of results, from 1 to 100.")
                ]
            ),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "search_notes",
            description: "Search Apple Notes by title or body text and return matching note IDs and previews.",
            inputSchema: objectSchema(
                properties: [
                    "query": stringField("Text to search for."),
                    "limit": integerField("Optional maximum number of results, from 1 to 100.")
                ],
                required: ["query"]
            ),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "get_note",
            description: "Read one Apple Note by the id returned by list_notes or search_notes. Returns the complete readable body and metadata.",
            inputSchema: objectSchema(
                properties: ["id": stringField("Ancrate note ID.")],
                required: ["id"]
            ),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        ),
        Tool(
            name: "get_checklists",
            description: "Extract checklist items from one Apple Note by Ancrate note ID, including completion state and line order.",
            inputSchema: objectSchema(
                properties: ["id": stringField("Ancrate note ID.")],
                required: ["id"]
            ),
            annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false)
        )
    ]

    private static func objectSchema(properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }

    private static func stringField(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description)
        ])
    }

    private static func integerField(_ description: String) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string(description),
            "minimum": .int(1),
            "maximum": .int(100)
        ])
    }
}

private enum AncrateMCPError: LocalizedError {
    case missingArgument(String)
    case unknownTool(String)
    case noteNotFound(String)
    case invalidLimit

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            return "Missing required argument '\(name)'."
        case .unknownTool(let name):
            return "Unknown Ancrate tool '\(name)'."
        case .noteNotFound(let id):
            return "No note was found for Ancrate ID '\(id)'. Refresh the list and try again."
        case .invalidLimit:
            return "limit must be between 1 and 100."
        }
    }
}

private actor NotesMCPService {
    private let database = NotesDatabase()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    func listNotes(query: String?, folder: String?, limit: Int) throws -> String {
        let boundedLimit = try validatedLimit(limit)
        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFolder = folder?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = try database.fetchNotes(limit: nil).filter { note in
            let matchesQuery = normalizedQuery.map { query in
                note.title.localizedCaseInsensitiveContains(query)
                    || note.content.localizedCaseInsensitiveContains(query)
            } ?? true
            let matchesFolder = normalizedFolder.map { folder in
                note.folder?.localizedCaseInsensitiveCompare(folder) == .orderedSame
            } ?? true
            return matchesQuery && matchesFolder
        }

        let payload = notes.prefix(boundedLimit).map(NotePreview.init)
        return try encode(payload)
    }

    func getNote(id: String) throws -> String {
        let note = try findNote(id: id)
        return try encode(NoteDetails(note: note))
    }

    func getChecklists(id: String) throws -> String {
        let note = try findNote(id: id)
        let payload = NoteChecklists(
            id: note.id,
            title: note.title,
            items: note.checklists.map(ChecklistPayload.init)
        )
        return try encode(payload)
    }

    private func findNote(id: String) throws -> ANote {
        guard let note = try database.fetchNote(id: id) else {
            throw AncrateMCPError.noteNotFound(id)
        }
        return note
    }

    private func validatedLimit(_ limit: Int) throws -> Int {
        guard (1...100).contains(limit) else {
            throw AncrateMCPError.invalidLimit
        }
        return limit
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

private struct NotePreview: Encodable {
    let id: String
    let title: String
    let folder: String?
    let creationDate: Date
    let modificationDate: Date
    let contentPreview: String
    let checklistCount: Int

    init(note: ANote) {
        id = note.id
        title = note.title
        folder = note.folder
        creationDate = note.creationDate
        modificationDate = note.modificationDate
        contentPreview = String(note.content.prefix(500))
        checklistCount = note.checklists.count
    }
}

private struct NoteDetails: Encodable {
    let id: String
    let title: String
    let folder: String?
    let creationDate: Date
    let modificationDate: Date
    let content: String
    let checklists: [ChecklistPayload]

    init(note: ANote) {
        id = note.id
        title = note.title
        folder = note.folder
        creationDate = note.creationDate
        modificationDate = note.modificationDate
        content = note.content
        checklists = note.checklists.map(ChecklistPayload.init)
    }
}

private struct ChecklistPayload: Encodable {
    let id: String
    let text: String
    let isCompleted: Bool
    let lineNumber: Int

    init(item: ChecklistItem) {
        id = item.id
        text = item.text
        isCompleted = item.isCompleted
        lineNumber = item.lineNumber
    }
}

private struct NoteChecklists: Encodable {
    let id: String
    let title: String
    let items: [ChecklistPayload]
}

#endif
