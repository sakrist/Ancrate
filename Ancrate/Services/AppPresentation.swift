#if os(macOS)
import AppKit

enum AppPresentation {
    static let dockPreferenceKey = "showInDock"

    static func applyDockVisibility(_ visible: Bool) {
        guard !AncrateMCPServer.isMCPMode,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        NSApplication.shared.setActivationPolicy(visible ? .regular : .accessory)
    }
}
#endif
