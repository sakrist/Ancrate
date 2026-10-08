import Foundation

enum TaskPeriod: String, Codable, CaseIterable, Identifiable {
    case all, month, quarter
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All to-dos"
        case .month: return "Past month"
        case .quarter: return "Past 3 months"
        }
    }
    var symbol: String {
        switch self {
        case .all: return "checklist"
        case .month: return "calendar"
        case .quarter: return "calendar.badge.clock"
        }
    }
    func contains(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard self != .all else { return true }
        guard let start = calendar.date(byAdding: .month, value: self == .month ? -1 : -3, to: now) else { return false }
        return date >= start && date <= now
    }
}

enum TaskDateBasis: String, Codable, CaseIterable, Identifiable {
    case modified, created
    var id: String { rawValue }
    var title: String { self == .modified ? "Last edited" : "Created" }
    func date(created: Date, modified: Date) -> Date { self == .modified ? modified : created }
}

struct TaskRecord: Codable, Identifiable, Hashable {
    let id: String
    let text: String
    let isCompleted: Bool
    let noteID: String
    let noteTitle: String
    let folder: String?
    let createdAt: Date
    let modifiedAt: Date
}

struct TaskSnapshot: Codable, Equatable {
    enum Status: String, Codable { case ready, unavailable, disabled }
    let updatedAt: Date
    let dateBasis: TaskDateBasis
    let status: Status
    let tasks: [TaskRecord]

    func tasks(in period: TaskPeriod, now: Date = .now, calendar: Calendar = .current) -> [TaskRecord] {
        tasks.filter { period.contains(dateBasis.date(created: $0.createdAt, modified: $0.modifiedAt), now: now, calendar: calendar) }
    }
}

enum TaskSnapshotStore {
    static let appGroupID = "group.com.sakrist.Ancrate"
    static let widgetKind = "AncrateTasks"
    private static let filename = "tasks-v1.json"
    enum StoreError: LocalizedError {
        case containerUnavailable
        var errorDescription: String? { "The shared widget container is unavailable. Install and reopen the signed Ancrate app." }
    }
    static func directory() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            throw StoreError.containerUnavailable
        }
        return url
    }
    static func save(_ snapshot: TaskSnapshot, directory: URL? = nil) throws {
        let directory = try directory ?? self.directory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent(filename), options: .atomic)
    }
    static func load(directory: URL? = nil) -> TaskSnapshot? {
        guard let directory = try? directory ?? self.directory(),
              let data = try? Data(contentsOf: directory.appendingPathComponent(filename)) else { return nil }
        return try? JSONDecoder().decode(TaskSnapshot.self, from: data)
    }
}
