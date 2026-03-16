import SwiftUI
import AppKit

struct ExtensionStudioView: View {
    @ObservedObject var notesDatabase: NotesDatabase
    @ObservedObject var hotkeyService: NotesHotkeyService

    @State private var selectedTemplateName = "Meeting Notes"
    @State private var liveStatusMessage = ""
    @State private var isRunningLiveAction = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Apple Notes Companion")
                .font(.title2)
                .fontWeight(.semibold)

            Text("All actions are executed on selected text in Apple Notes. This app only triggers them.")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Slash suggestions may briefly activate Ancrate to show the command menu, then insert into Notes.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("1) Open Apple Notes and select text")
                Text("2) Ensure Accessibility is enabled for this app")
                Text("3) Run an action below")
            }
            .font(.subheadline)

            HStack {
                Circle()
                    .fill(AppleNotesCompanionBridge.isNotesFrontmost() ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(AppleNotesCompanionBridge.isNotesFrontmost() ? "Apple Notes is active" : "Apple Notes is not active (actions will auto-switch)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Circle()
                    .fill(AppleNotesCompanionBridge.isAccessibilityTrusted() ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(AppleNotesCompanionBridge.isAccessibilityTrusted() ? "Accessibility is enabled" : "Accessibility is not enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Open Accessibility Settings") {
                    openAccessibilitySettings()
                }

                Button("Open Automation Settings") {
                    openAutomationSettings()
                }

                Button("Request Accessibility Permission") {
                    AppleNotesCompanionBridge.requestAccessibilityPermission()
                    liveStatusMessage = "Requested Accessibility permission."
                }

                Button("Request Automation Permission") {
                    let result = AppleNotesCompanionBridge.requestAutomationPermission()
                    liveStatusMessage = result.granted
                    ? result.details
                    : "Automation probe failed: \(result.details)"
                }

                Button("Run Diagnostics") {
                    let accessibility = AppleNotesCompanionBridge.isAccessibilityTrusted() ? "Accessibility: OK" : "Accessibility: Missing"
                    let automation = AppleNotesCompanionBridge.requestAutomationPermission()
                    let automationText = automation.granted ? "Automation: OK" : "Automation: \(automation.details)"
                    let notesState = AppleNotesCompanionBridge.isNotesFrontmost() ? "Notes: Active" : "Notes: Not active"
                    let hotkeys = hotkeyService.isEnabled ? "Hotkeys: Enabled" : "Hotkeys: Disabled"
                    liveStatusMessage = "\(accessibility) | \(automationText) | \(notesState) | \(hotkeys)"
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Global Hotkeys")
                    .font(.headline)

                Text("Use these anywhere, including while Apple Notes is focused.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Cmd+Opt+Return: Run All transforms on selected text")
                    .font(.caption)
                Text("Cmd+Opt+/: Apply Slash Commands on selected text")
                    .font(.caption)

                HStack {
                    Button(hotkeyService.isEnabled ? "Disable Hotkeys" : "Enable Hotkeys") {
                        hotkeyService.toggle()
                    }

                    Text(hotkeyService.isEnabled ? "Enabled" : "Disabled")
                        .font(.caption)
                        .foregroundColor(hotkeyService.isEnabled ? .green : .secondary)
                }

                Text(hotkeyService.lastStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Run All On Notes Selection") {
                    runLiveAction { text in
                        ProNotesExtensionEngine.runAllTransforms(on: text)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunningLiveAction)

                Button("Slash Commands On Selection") {
                    runLiveAction { text in
                        ProNotesExtensionEngine.applySlashCommands(to: text)
                    }
                }
                .disabled(isRunningLiveAction)
            }

            HStack {
                Picker("Template", selection: $selectedTemplateName) {
                    ForEach(Array(ProNotesExtensionEngine.templates.keys.sorted()), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(maxWidth: 220)

                Button("Insert Template In Selection") {
                    guard let template = ProNotesExtensionEngine.templates[selectedTemplateName] else { return }
                    runLiveAction { _ in template }
                }
                .disabled(isRunningLiveAction)
            }

            if !liveStatusMessage.isEmpty {
                Text(liveStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            if notesDatabase.notes.isEmpty {
                notesDatabase.loadNotes()
            }
        }
    }

    private func runLiveAction(_ transform: @escaping (String) -> String) {
        isRunningLiveAction = true
        defer { isRunningLiveAction = false }

        do {
            _ = try AppleNotesCompanionBridge.transformSelectedTextInNotes(using: transform)
            liveStatusMessage = "Updated selection in Apple Notes."
        } catch {
            liveStatusMessage = error.localizedDescription
        }
    }

    private func openAccessibilitySettings() {
        let deepLink = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        let fallback = "x-apple.systempreferences:com.apple.preference.security"

        if let url = URL(string: deepLink), NSWorkspace.shared.open(url) {
            liveStatusMessage = "Opened Accessibility settings. Enable access for Ancrate."
            return
        }

        if let url = URL(string: fallback), NSWorkspace.shared.open(url) {
            liveStatusMessage = "Opened Security & Privacy settings. Go to Accessibility."
            return
        }

        liveStatusMessage = "Could not open System Settings automatically."
    }

    private func openAutomationSettings() {
        let deepLink = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        let fallback = "x-apple.systempreferences:com.apple.preference.security"

        if let url = URL(string: deepLink), NSWorkspace.shared.open(url) {
            liveStatusMessage = "Opened Automation settings. Enable Notes and System Events for Ancrate."
            return
        }

        if let url = URL(string: fallback), NSWorkspace.shared.open(url) {
            liveStatusMessage = "Opened Security & Privacy settings. Go to Automation."
            return
        }

        liveStatusMessage = "Could not open System Settings automatically."
    }
}

#Preview {
    ExtensionStudioView(notesDatabase: NotesDatabase(), hotkeyService: NotesHotkeyService())
}
