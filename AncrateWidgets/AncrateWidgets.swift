import SwiftUI
import WidgetKit
import AppIntents

private enum WidgetPeriod: String, AppEnum {
    case month, quarter, all
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Time range")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .month: "Past month", .quarter: "Past 3 months", .all: "All to-dos"
    ]
}

private struct TasksConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Your to-dos"
    static var description = IntentDescription("Choose which Apple Notes checklists appear on your desktop.")
    @Parameter(title: "Time range", default: .month) var period: WidgetPeriod
}

private struct TasksEntry: TimelineEntry {
    let date: Date
    let configuration: TasksConfiguration
    let snapshot: TaskSnapshot?
    var period: TaskPeriod { TaskPeriod(rawValue: configuration.period.rawValue) ?? .month }
    var tasks: [TaskRecord] { snapshot?.tasks(in: period, now: date) ?? [] }
}

private struct TasksProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TasksEntry {
        let task = TaskRecord(id: "preview", text: "Make room for a good idea", isCompleted: false, noteID: "preview",
                              noteTitle: "A fresh start", folder: "Notes", createdAt: .now, modifiedAt: .now)
        return TasksEntry(date: .now, configuration: TasksConfiguration(),
                          snapshot: TaskSnapshot(updatedAt: .now, dateBasis: .modified, status: .ready, tasks: [task]))
    }
    func snapshot(for configuration: TasksConfiguration, in context: Context) async -> TasksEntry {
        if context.isPreview { return placeholder(in: context) }
        return TasksEntry(date: .now, configuration: configuration, snapshot: TaskSnapshotStore.load())
    }
    func timeline(for configuration: TasksConfiguration, in context: Context) async -> Timeline<TasksEntry> {
        let now = Date.now
        return Timeline(entries: [TasksEntry(date: now, configuration: configuration, snapshot: TaskSnapshotStore.load())],
                        policy: .after(now.addingTimeInterval(15 * 60)))
    }
}

private struct TasksWidgetView: View {
    let entry: TasksEntry
    @Environment(\.widgetFamily) private var family
    private var openTasks: [TaskRecord] { entry.tasks.filter { !$0.isCompleted } }
    private var ready: Bool { entry.snapshot?.status == .ready }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                Text("Ancrate").font(.subheadline).fontWeight(.semibold)
                Spacer()
                if family != .systemSmall { Text(entry.period.title).font(.caption).foregroundStyle(.secondary) }
            }
            if ready {
                if family == .systemMedium {
                    HStack(alignment: .top, spacing: 20) {
                        summary.frame(width: 80, alignment: .leading)
                        taskList(limit: 3)
                    }
                } else {
                    summary
                    taskList(limit: family == .systemSmall ? 2 : 7)
                }
                Spacer(minLength: 0)
                if family != .systemSmall, let updated = entry.snapshot?.updatedAt {
                    (Text("Updated ") + Text(updated, style: .relative)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                Spacer(minLength: 0)
                Image(systemName: entry.snapshot?.status == .disabled ? "eye.slash" : "note.text")
                    .font(.title2).foregroundStyle(.secondary)
                Text(entry.snapshot?.status == .disabled ? "Widget sharing is off" : "Your notes, at a glance")
                    .font(.headline)
                Text(entry.snapshot?.status == .disabled ? "Enable it in Ancrate's settings." : "Open Ancrate to refresh your Notes library.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .containerBackground(for: .widget) {
            Rectangle().fill(.background)
        }
        .widgetURL(URL(string: "ancrate://tasks/\(entry.period.rawValue)"))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(openTasks.count, format: .number).font(.system(size: family == .systemSmall ? 32 : 38, weight: .semibold)).foregroundStyle(.primary)
            Text(family == .systemSmall ? entry.period.title : "open to-dos").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func taskList(limit: Int) -> some View {
        if openTasks.isEmpty {
            Text("No open to-dos").font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 10) {
                ForEach(openTasks.prefix(limit)) { task in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.text).font(.system(size: 12, weight: .medium)).lineLimit(family == .systemLarge ? 2 : 1)
                            if family != .systemSmall { Text(task.noteTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }.privacySensitive()
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AncrateTasksWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: TaskSnapshotStore.widgetKind, intent: TasksConfiguration.self, provider: TasksProvider()) { entry in
            TasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Ancrate To-dos")
        .description("Your Apple Notes checklists, quietly at hand.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct AncrateWidgets: WidgetBundle {
    var body: some Widget { AncrateTasksWidget() }
}
