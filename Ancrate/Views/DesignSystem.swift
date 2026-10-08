import SwiftUI

enum AncrateStyle {
    static let accent = SwiftUI.Color.accentColor
    #if os(macOS)
    static let canvas = SwiftUI.Color(nsColor: .windowBackgroundColor)
    static let surface = SwiftUI.Color(nsColor: .textBackgroundColor)
    #else
    static let canvas = SwiftUI.Color(uiColor: .systemGroupedBackground)
    static let surface = SwiftUI.Color(uiColor: .systemBackground)
    #endif
}

struct AncrateMark: View {
    var size: CGFloat = 36
    var body: some View {
        Image("AncrateIcon").resizable().scaledToFit()
        .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2).fontWeight(.semibold)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 36)).foregroundStyle(.secondary)
            Text(title).font(.title3).fontWeight(.semibold)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MetricSummary: View {
    let value: Int
    let title: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .number).font(.title2).fontWeight(.semibold).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
