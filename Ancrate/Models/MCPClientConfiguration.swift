import Foundation

struct MCPClientConfiguration: Encodable {
    private struct Server: Encodable {
        let command: String
        let args: [String]
    }

    private let mcpServers: [String: Server]

    init(executablePath: String) {
        mcpServers = ["ancrate": Server(command: executablePath, args: ["--mcp-stdio"])]
    }

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
