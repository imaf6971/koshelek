import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var allQuery: [Category]
    private var all: [Category] { allQuery.live }
    @State private var kind = CategoryKind.expense
    @State private var editing: ItemID?
    @State private var adding = false
    @State private var deleting: ItemID?

    private struct CategoryRow: Identifiable { var id: UUID; var name: String; var fullName: String; var icon: String; var colorKey: String; var childCount: Int }

    private func row(_ c: Category) -> CategoryRow {
        CategoryRow(id: c.id, name: c.name, fullName: c.fullName, icon: c.icon, colorKey: c.colorKey, childCount: c.children.live.count)
    }

    private var parents: [Category] { all.filter { $0.kind == kind && $0.parent == nil && !$0.isArchived } }
    private var archived: [Category] { all.filter { $0.kind == kind && $0.isArchived } }
    private func category(_ id: UUID) -> Category? { all.first { $0.id == id } }

    var body: some View {
        let parentRows = parents.map(row)
        let archivedRows = archived.map(row)
        List {
            Section {
                Picker("Тип", selection: $kind) { ForEach(CategoryKind.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }.listRowBackground(Theme.Colors.card)
            Section {
                ForEach(parentRows) { p in
                    NavigationLink {
                        SubcategoriesView(parentID: p.id)
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            IconBadge(icon: p.icon, colorKey: p.colorKey)
                            Text(p.name)
                            Spacer()
                            if p.childCount > 0 { Text("\(p.childCount)").foregroundStyle(Theme.Colors.textSecondary) }
                        }
                    }
                    .listRowBackground(Theme.Colors.card)
                    .swipeActions { actions(p.id, archived: false) }
                }
                .onMove { from, to in
                    var list = parents
                    list.move(fromOffsets: from, toOffset: to)
                    for (i, c) in list.enumerated() { c.sortOrder = i }
                    context.saveOrReport()
                }
            }.listRowBackground(Theme.Colors.card)
            if !archivedRows.isEmpty {
                Section("Архив") {
                    ForEach(archivedRows) { c in
                        Button { editing = ItemID(id: c.id) } label: { HStack { IconBadge(icon: c.icon, colorKey: c.colorKey, size: 30); Text(c.fullName).foregroundStyle(Theme.Colors.textPrimary) } }
                            .listRowBackground(Theme.Colors.card)
                            .swipeActions { actions(c.id, archived: true) }
                    }
                }.listRowBackground(Theme.Colors.card)
            }
        }
        .listStyleWarm()
        .navigationTitle("Категории")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel(Text("Добавить категорию")) }
        }
        .sheet(isPresented: $adding) { CategoryEditView(category: nil, kind: kind, parent: nil) }
        .sheet(item: $editing) { item in
            if let c = category(item.id) { CategoryEditView(category: c, kind: c.kind, parent: c.parent) }
        }
        .sheet(item: $deleting) { item in CategoryDeleteSheet(categoryID: item.id) }
    }

    @ViewBuilder private func actions(_ id: UUID, archived: Bool) -> some View {
        Button("Удалить") { if let c = category(id) { requestDelete(c, context: context) { deleting = ItemID(id: $0.id) } } }.tint(Theme.Colors.expense)
        Button(archived ? "Вернуть" : "В архив") { if let c = category(id) { c.isArchived.toggle(); context.saveOrReport() } }.tint(Theme.Colors.textSecondary)
        Button("Изменить") { editing = ItemID(id: id) }.tint(Theme.Colors.accent)
    }
}

/// Deletes right away when nothing references the category, otherwise asks via `ask`.
func requestDelete(_ c: Category, context: ModelContext, ask: (Category) -> Void) {
    let used = !c.transactions.isEmpty || c.children.contains { !$0.transactions.isEmpty } || !c.rules.isEmpty
    if used { ask(c) } else { Store.deleteCategory(c, moveTransactionsTo: nil, deleteTransactions: false, in: context) }
}

struct CategoryDeleteSheet: View {
    let categoryID: UUID
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var allQuery: [Category]
    private var all: [Category] { allQuery.live }

    var body: some View {
        if let category = all.first(where: { $0.id == categoryID }) {
            let family = Set([category.id] + category.children.live.map(\.id))
            let targets = all.filter { $0.kind == category.kind && !family.contains($0.id) && !$0.isArchived }.map { ($0.id, $0.fullName) }
            DeleteReassignSheet(
                title: LF("Удалить «%@»?", category.name),
                message: L("У категории есть операции. Перенесите их в другую категорию, оставьте без категории или удалите вместе с ними."),
                targets: targets, allowNoTarget: true,
                onMove: { id in Store.deleteCategory(category, moveTransactionsTo: all.first { $0.id == id }, deleteTransactions: false, in: context) },
                onDeleteAll: { Store.deleteCategory(category, moveTransactionsTo: nil, deleteTransactions: true, in: context) })
        }
    }
}

struct SubcategoriesView: View {
    let parentID: UUID
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var allQuery: [Category]
    private var all: [Category] { allQuery.live }
    @State private var adding = false
    @State private var editing: ItemID?
    @State private var deleting: ItemID?

    private var parent: Category? { all.first { $0.id == parentID } }
    private func category(_ id: UUID) -> Category? { all.first { $0.id == id } }

    private struct ChildRow: Identifiable { var id: UUID; var name: String; var icon: String; var colorKey: String }

    var body: some View {
        if let parent {
            content(parent)
        } else {
            Color.clear.screenBackground()
        }
    }

    private func content(_ parent: Category) -> some View {
        let children = parent.children.live.filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
        let rows = children.map { ChildRow(id: $0.id, name: $0.name, icon: $0.icon, colorKey: $0.colorKey) }
        let parentName = parent.name, parentKind = parent.kind
        return List {
            Section {
                Button { editing = ItemID(id: parentID) } label: { Label(LF("Изменить «%@»", parentName), systemImage: "pencil") }
                    .listRowBackground(Theme.Colors.card)
            }.listRowBackground(Theme.Colors.card)
            Section("Подкатегории") {
                if rows.isEmpty {
                    Text("Подкатегорий нет. Добавьте, например, «Кафе» или «Продукты».").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(rows) { c in
                    Button { editing = ItemID(id: c.id) } label: { HStack(spacing: Theme.Spacing.m) { IconBadge(icon: c.icon, colorKey: c.colorKey, size: 30); Text(c.name).foregroundStyle(Theme.Colors.textPrimary) } }
                        .listRowBackground(Theme.Colors.card)
                        .swipeActions {
                            Button("Удалить") { if let cat = category(c.id) { requestDelete(cat, context: context) { deleting = ItemID(id: $0.id) } } }.tint(Theme.Colors.expense)
                            Button("В архив") { if let cat = category(c.id) { cat.isArchived = true; context.saveOrReport() } }.tint(Theme.Colors.textSecondary)
                        }
                }
                .onMove { from, to in
                    var list = children
                    list.move(fromOffsets: from, toOffset: to)
                    for (i, c) in list.enumerated() { c.sortOrder = i }
                    context.saveOrReport()
                }
            }.listRowBackground(Theme.Colors.card)
        }
        .listStyleWarm()
        .navigationTitle(parentName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel(Text("Добавить подкатегорию")) }
        }
        .sheet(isPresented: $adding) { CategoryEditView(category: nil, kind: parentKind, parent: parent) }
        .sheet(item: $editing) { item in
            if let c = category(item.id) { CategoryEditView(category: c, kind: c.kind, parent: c.parent) }
        }
        .sheet(item: $deleting) { item in CategoryDeleteSheet(categoryID: item.id) }
    }
}

struct CategoryEditView: View {
    let category: Category?
    let kind: CategoryKind
    @State var parent: Category?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allQuery: [Category]
    private var all: [Category] { allQuery.live }
    @State private var name = ""
    @State private var icon = "ellipsis.circle"
    @State private var colorKey = "clay"

    init(category: Category?, kind: CategoryKind, parent: Category?) {
        self.category = category; self.kind = kind; _parent = State(initialValue: parent)
    }

    private var canHaveParent: Bool { category == nil ? parent != nil : (category?.children.isEmpty ?? true) }
    private var parentOptions: [Category] { all.filter { $0.kind == kind && $0.parent == nil && $0.id != category?.id && !$0.isArchived } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $name)
                    if canHaveParent {
                        Picker("Родитель", selection: $parent) {
                            Text("Нет (основная категория)").tag(Category?.none)
                            ForEach(parentOptions) { Text($0.name).tag(Optional($0)) }
                        }
                    }
                }.listRowBackground(Theme.Colors.card)
                Section("Значок и цвет") { IconColorPicker(icon: $icon, colorKey: $colorKey) }.listRowBackground(Theme.Colors.card)
            }
            .scrollContentBackground(.hidden).background(Theme.Colors.background)
            .navigationTitle(category == nil ? "Новая категория" : "Категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear {
                if let c = category { name = c.name; icon = c.icon; colorKey = c.colorKey }
                else if let p = parent { icon = p.icon; colorKey = p.colorKey }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if let c = category {
            c.name = n; c.icon = icon; c.colorKey = colorKey; c.parent = parent
        } else {
            let siblings = all.filter { $0.kind == kind && $0.parent?.id == parent?.id }
            context.insert(Category(name: n, icon: icon, colorKey: colorKey, kind: kind, sortOrder: (siblings.map(\.sortOrder).max() ?? -1) + 1, parent: parent))
        }
        context.saveOrReport()
        dismiss()
    }
}
