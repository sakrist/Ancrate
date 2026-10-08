#if os(macOS)
import SwiftUI
import AppKit

struct MCPSetupView: View {
    private let configuration: String?
    @State private var copyStatus: String?

    init(bundle: Bundle = .main) {
        if let executablePath = bundle.executableURL?.path {
            configuration = try? MCPClientConfiguration(executablePath: executablePath).json()
        } else {
            configuration = nil
        }
    }

    var body: some View {
        Section("MCP setup") {
            Label("Read-only access to Apple Notes", systemImage: "lock.shield")
            Text("Your MCP client starts its own Ancrate process. The Ancrate window can stay closed; no server runs automatically when you open the app.")
                .font(.caption).foregroundStyle(.secondary)
            if let configuration {
                Text("Add this to your client's MCP configuration. If it already has an mcpServers object, add the ancrate entry inside it.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(configuration)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("mcpConfiguration")
                Button("Copy configuration", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    copyStatus = NSPasteboard.general.setString(configuration, forType: .string)
                        ? "Copied. Paste this into your MCP client's configuration."
                        : "Could not copy. Select the configuration above to copy it manually."
                }
                .accessibilityIdentifier("copyMCPConfiguration")
                if let copyStatus {
                    Text(copyStatus).font(.caption).foregroundStyle(.secondary)
                }
                Text("This uses Ancrate's current location. If you move the app, copy the configuration again. Full Disk Access for Ancrate is required to read your notes.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Ancrate's executable could not be located. Relaunch the installed app to generate its configuration.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
#endif
