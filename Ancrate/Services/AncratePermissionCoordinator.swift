//
//  AncratePermissionCoordinator.swift
//  Ancrate
//

#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class AncratePermissionCoordinator: ObservableObject {
    @Published private(set) var fullDiskAccessGranted = false
    @Published private(set) var isChecking = false
    @Published var isPresented = false

    func check() {
        guard !isChecking else { return }
        isChecking = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let hasFullDiskAccess = NotesDatabase().canReadNotesDatabase()

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.fullDiskAccessGranted = hasFullDiskAccess
                self.isChecking = false
                self.isPresented = !hasFullDiskAccess
            }
        }
    }

    func openFullDiskAccessSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    private func openSettings(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct PermissionSetupView: View {
    @ObservedObject var permissions: AncratePermissionCoordinator
    var exploreSamples: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ancrate needs permission")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Full Disk Access lets Ancrate read Apple Notes for search and checklists. Slash commands only need Accessibility permission.")
                        .foregroundStyle(.secondary)
                }
            }

            PermissionRow(
                title: "Read Apple Notes",
                detail: "Full Disk Access lets Ancrate read your local Notes database for search and checklist extraction.",
                granted: permissions.fullDiskAccessGranted,
                actionTitle: "Open Full Disk Access",
                action: permissions.openFullDiskAccessSettings
            )

            if permissions.isChecking {
                ProgressView("Checking permissions…")
                    .controlSize(.small)
            }

            HStack {
                if let exploreSamples {
                    Button("Explore with sample notes") { exploreSamples(); dismiss() }
                }
                Button("Check Again") {
                    permissions.check()
                }
                .disabled(permissions.isChecking)

                Spacer()

                Button("Continue") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(26)
        .frame(width: 560)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                Text(title)
                    .fontWeight(.medium)
                Spacer()
                Text(granted ? "Granted" : "Needed")
                    .font(.caption)
                    .foregroundStyle(granted ? .green : .secondary)
            }

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !granted {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
#endif
