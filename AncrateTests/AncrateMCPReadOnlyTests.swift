#if os(macOS)
import MCP
import Testing
@testable import Ancrate

struct AncrateMCPReadOnlyTests {
    @Test(.timeLimit(.minutes(1)))
    func advertisesOnlyReadToolsAndRejectsWrites() async throws {
        let server = await AncrateMCPServer.makeServer()
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "read-only-regression-test", version: "1.0")
        try await server.start(transport: serverTransport)

        do {
            _ = try await client.connect(transport: clientTransport)
            let result = try await client.listTools()
            #expect(Set(result.tools.map(\.name)) == Set([
                "list_notes", "search_notes", "get_note", "get_checklists"
            ]))
            #expect(result.tools.allSatisfy { $0.annotations.readOnlyHint == true })
            #expect(result.tools.allSatisfy { $0.annotations.destructiveHint == false })

            // Exercise actual MCP dispatch. These requests must be rejected
            // before accessing Notes, regardless of the supplied arguments.
            for name in ["create_note", "update_note", "append_to_note", "delete_note"] {
                let response = try await client.callTool(name: name, arguments: [
                    "id": .string("not-a-real-note"),
                    "title": .string("Must not be created"),
                    "content": .string("Must not be written"),
                    "text": .string("Must not be appended")
                ])
                #expect(response.isError == true)
                #expect(response.content.contains { content in
                    if case .text(let text, _, _) = content {
                        return text.contains("Unknown Ancrate tool '\(name)'")
                    }
                    return false
                })
            }
        } catch {
            await client.disconnect()
            await server.stop()
            throw error
        }
        await client.disconnect()
        await server.stop()
    }
}
#endif
