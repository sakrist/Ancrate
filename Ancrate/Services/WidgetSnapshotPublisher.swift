#if os(macOS)
import Foundation
import WidgetKit

@MainActor
final class WidgetSnapshotPublisher: ObservableObject {
    @Published private(set) var errorMessage: String?

    func publish(notes: [ANote], scope: ToDoScope, basis: TaskDateBasis, enabled: Bool, unavailable: Bool = false) {
        guard !AncrateMCPServer.isMCPMode, !CommandLine.arguments.contains("--demo"),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let status: TaskSnapshot.Status = !enabled ? .disabled : unavailable ? .unavailable : .ready
        let snapshot = scope.snapshot(notes: notes, basis: basis, status: status)
        do {
            try TaskSnapshotStore.save(snapshot)
            errorMessage = nil
            WidgetCenter.shared.reloadTimelines(ofKind: TaskSnapshotStore.widgetKind)
        } catch { errorMessage = error.localizedDescription }
    }
}
#endif
