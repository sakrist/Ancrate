#if os(macOS)
import SwiftUI

struct NotesSlashPalette: View {
    @ObservedObject var controller: NotesSlashCommandController

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Format in Notes").fontWeight(.medium)
                Spacer()
                Text("↑↓  ↵  esc").foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .frame(height: 40)
            ForEach(controller.commands) { command in
                Button {
                    controller.choose(command)
                } label: {
                    NotesSlashRow(command: command, selected: controller.commands.firstIndex(of: command) == controller.selectedIndex)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(command.title), slash \(command.id)")
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.12)))
    }
}

private struct NotesSlashRow: View {
    let command: NotesSlashCommand
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.symbol).frame(width: 20)
            Text(command.title)
            Spacer()
            Text("/\(command.id)").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .contentShape(Rectangle())
        .background(selected ? SwiftUI.Color.accentColor.opacity(0.18) : SwiftUI.Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }
}

struct NotesSlashSettings: View {
    @ObservedObject var controller: NotesSlashCommandController

    var body: some View {
        Section("Slash commands in Apple Notes") {
            Text("Keep Ancrate running and type / at the start of a line in the original Notes app. Use ↑ and ↓ to choose, Return or Tab to apply, and Escape to dismiss.")
            Toggle("Enable slash commands", isOn: Binding(get: { controller.isEnabled }, set: controller.setEnabled))
            Label(controller.status, systemImage: controller.isRunning ? "checkmark.circle" : "info.circle")
                .font(.callout).foregroundStyle(.secondary)
            if controller.isEnabled && !controller.isRunning {
                HStack {
                    Button("Open Accessibility Settings", action: controller.openAccessibilitySettings)
                    Button("Check Again", action: controller.startIfEnabled)
                }
            }
            Text("Accessibility permission lets Ancrate read the text around your cursor and invoke Notes’ formatting menus. Slash commands don't need Full Disk Access.")
                .font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                ForEach(NotesSlashCommand.all) { command in
                    Label("/\(command.id)", systemImage: command.symbol).font(.callout)
                }
            }
        }
    }
}
#endif
