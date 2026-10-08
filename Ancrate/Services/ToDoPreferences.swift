import Foundation
import Combine

@MainActor
final class ToDoPreferences: ObservableObject {
    @Published private(set) var scope: ToDoScope
    private let defaults: UserDefaults
    private let key = "toDoScope.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scope = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ToDoScope.self, from: $0) } ?? ToDoScope()
    }

    func update(_ scope: ToDoScope) {
        guard self.scope != scope, let data = try? JSONEncoder().encode(scope) else { return }
        defaults.set(data, forKey: key)
        self.scope = scope
    }
}
