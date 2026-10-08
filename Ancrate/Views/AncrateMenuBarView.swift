#if os(macOS)
import SwiftUI
import AppKit

struct AncrateMenuBarView: View {
    @ObservedObject var slashCommands: NotesSlashCommandController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Ancrate", systemImage: "macwindow") {
            if let window = NSApplication.shared.windows.first(where: {
                $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized)
            }) {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: "library")
            }
            NSApplication.shared.activate()
        }
        Divider()
        Toggle("Slash Commands in Apple Notes", isOn: Binding(
            get: { slashCommands.isEnabled }, set: slashCommands.setEnabled
        ))
        Text(slashCommands.status)
        if slashCommands.isEnabled && !slashCommands.isRunning {
            Button("Open Accessibility Settings", action: slashCommands.openAccessibilitySettings)
            Button("Check Again", action: slashCommands.startIfEnabled)
        }
        Divider()
        Button("Quit Ancrate") { NSApplication.shared.terminate(nil) }
    }
}
#endif
