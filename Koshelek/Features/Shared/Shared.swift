import SwiftUI
import SwiftData

/// Renders its content only while `model` is still in the store. SwiftUI may re-run a row's body for an object that was
/// just deleted, and reading any attribute of such an object crashes, so rows that take a model must read it inside this guard.
struct LiveGuard<Model: PersistentModel, Content: View>: View {
    let model: Model
    @ViewBuilder var content: () -> Content
    var body: some View {
        if model.modelContext != nil { content() } else { EmptyView() }
    }
}

/// Identity of a model object for `.sheet(item:)` and navigation. A plain value, so SwiftUI never reads an object that was just deleted.
struct ItemID: Identifiable, Hashable { let id: UUID }

struct TransactionRow: View {
    let row: TxRowData
    @Environment(\.dynamicTypeSize) private var typeSize

    private var amountColor: Color {
        switch row.kind {
        case .income: Theme.Colors.income
        case .expense: Theme.Colors.textPrimary
        case .transfer: Theme.Colors.textSecondary
        }
    }

    private var icon: some View { IconBadge(icon: row.icon, colorKey: row.colorKey) }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            if !row.subtitle.isEmpty {
                Text(row.subtitle).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            }
        }
    }

    private var amountLabel: some View {
        Text(row.amountText).font(Theme.Fonts.amount).foregroundStyle(amountColor).lineLimit(1).minimumScaleFactor(0.7)
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .top, spacing: Theme.Spacing.m) { icon; texts }
                    amountLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Theme.Spacing.m) {
                    icon
                    texts
                    Spacer(minLength: Theme.Spacing.s)
                    amountLabel
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hierarchical category selection (parents with indented subcategories).
struct CategoryPicker: View {
    let kind: CategoryKind
    @Binding var selection: Category?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allQuery: [Category]
    private var all: [Category] { allQuery.live }
    private var parents: [Category] { all.filter { $0.kind == kind && $0.parent == nil && !$0.isArchived } }

    var body: some View {
        NavigationStack {
            List {
                if selection != nil {
                    Button("Без категории") { selection = nil; dismiss() }
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .listRowBackground(Theme.Colors.card)
                }
                ForEach(parents) { p in
                    row(p, indent: false)
                    ForEach(p.children.live.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }) { row($0, indent: true) }
                }
            }
            .listStyleWarm()
            .navigationTitle("Категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }

    private func row(_ c: Category, indent: Bool) -> some View {
        Button { selection = c; dismiss() } label: {
            HStack {
                IconBadge(icon: c.icon, colorKey: c.colorKey, size: 30)
                Text(c.name).foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if selection?.id == c.id { Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent) }
            }
            .padding(.leading, indent ? Theme.Spacing.xl : 0)
        }
        .listRowBackground(Theme.Colors.card)
    }
}

/// Date labels for the UI. Formatters are created once (they are used for every list row) and only from the main thread.
enum DateText {
    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.calendar = .app
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    private static let dayFormatter = formatter("d MMMM, EEEE")
    private static let shortFormatter = formatter("d MMM yyyy")
    private static let monthFormatter = formatter("LLL")

    static func day(_ d: Date) -> String { dayFormatter.string(from: d).capitalizedFirst }
    static func short(_ d: Date) -> String { shortFormatter.string(from: d) }
    static func monthShort(_ d: Date) -> String { monthFormatter.string(from: d) }
}

/// Timestamps for file names: always Gregorian digits, whatever the device's region and calendar are.
enum FileStamp {
    static func string(_ format: String, _ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f.string(from: date)
    }
}
