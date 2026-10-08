import Foundation
import Testing
@testable import Ancrate

struct MCPClientConfigurationTests {
    @Test(arguments: [
        "/Applications/Ancrate.app/Contents/MacOS/Ancrate",
        "/Users/test/Apps with spaces/Notes \"日記\".app/Contents/MacOS/Ancrate",
        "/Users/test/Apps\\Archive/Ancrate.app/Contents/MacOS/Ancrate"
    ])
    func configurationPreservesExecutablePaths(executablePath: String) throws {
        let json = try MCPClientConfiguration(executablePath: executablePath).json()
        let root = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let servers = try #require(root["mcpServers"] as? [String: [String: Any]])
        let ancrate = try #require(servers["ancrate"])
        #expect(servers.count == 1)
        #expect(ancrate["command"] as? String == executablePath)
        #expect(ancrate["args"] as? [String] == ["--mcp-stdio"])
    }
}
