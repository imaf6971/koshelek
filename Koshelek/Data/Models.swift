import Foundation
import SwiftData

@Model final class Account {
    var id: UUID = UUID()
    var name: String
    var icon: String
    var colorKey: String
    var initialBalance: Decimal
    var sortOrder: Int
    var isArchived: Bool = false
    @Relationship(deleteRule: .nullify, inverse: \Transaction.account) var transactions: [Transaction] = []
    @Relationship(deleteRule: .nullify, inverse: \Transaction.toAccount) var incomingTransfers: [Transaction] = []
    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.account) var rules: [RecurringRule] = []

    init(id: UUID = UUID(), name: String, icon: String = "creditcard", colorKey: String = "slate", initialBalance: Decimal = 0, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.icon = icon; self.colorKey = colorKey
        self.initialBalance = initialBalance; self.sortOrder = sortOrder
    }
}

@Model final class Category {
    var id: UUID = UUID()
    var name: String
    var icon: String
    var colorKey: String
    var kind: CategoryKind
    var sortOrder: Int
    var isArchived: Bool = false
    var parent: Category?
    @Relationship(deleteRule: .nullify, inverse: \Category.parent) var children: [Category] = []
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category) var transactions: [Transaction] = []
    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.category) var rules: [RecurringRule] = []
    @Relationship(deleteRule: .nullify, inverse: \Budget.category) var budgets: [Budget] = []

    init(id: UUID = UUID(), name: String, icon: String, colorKey: String, kind: CategoryKind, sortOrder: Int = 0, parent: Category? = nil) {
        self.id = id; self.name = name; self.icon = icon; self.colorKey = colorKey
        self.kind = kind; self.sortOrder = sortOrder; self.parent = parent
    }

    var info: CategoryInfo { CategoryInfo(id: id, name: name, parentID: parent?.id, kind: kind) }

    /// Name including the parent, e.g. "Еда → Кафе".
    var fullName: String { parent.map { "\($0.name) → \(name)" } ?? name }
}

@Model final class Transaction {
    var id: UUID = UUID()
    var kind: TxKind
    var amount: Decimal
    var date: Date
    var note: String = ""
    var tags: [String] = []
    var account: Account?
    var toAccount: Account?
    var category: Category?
    /// Set for transactions generated from a recurring rule.
    var ruleID: UUID?
    var occurrenceDate: Date?

    init(id: UUID = UUID(), kind: TxKind, amount: Decimal, date: Date, note: String = "", tags: [String] = [],
         account: Account?, toAccount: Account? = nil, category: Category? = nil, ruleID: UUID? = nil, occurrenceDate: Date? = nil) {
        self.id = id; self.kind = kind; self.amount = amount; self.date = date; self.note = note; self.tags = tags
        self.account = account; self.toAccount = toAccount; self.category = category
        self.ruleID = ruleID; self.occurrenceDate = occurrenceDate
    }

    /// Row title: category path, or "From → To" for transfers.
    var displayTitle: String {
        if kind == .transfer { return LF("%@ → %@", account?.name ?? "?", toAccount?.name ?? "?") }
        return category?.fullName ?? L("Без категории")
    }

    /// Row subtitle: account, note and tags.
    var displaySubtitle: String {
        var parts: [String] = []
        if kind != .transfer, let a = account { parts.append(a.name) }
        if !note.isEmpty { parts.append(note) }
        if !tags.isEmpty { parts.append(tags.map { "#" + $0 }.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }

    var record: TxRecord {
        TxRecord(id: id, kind: kind, amount: amount, date: date, accountID: account?.id, toAccountID: toAccount?.id,
                 categoryID: category?.id, tags: tags, note: note)
    }
}

@Model final class RecurringRule {
    var id: UUID = UUID()
    var kind: TxKind
    var amount: Decimal
    var note: String
    var frequency: Frequency
    var startDate: Date
    var endDate: Date?
    var lastGeneratedDate: Date?
    var isActive: Bool = true
    var account: Account?
    var category: Category?

    init(id: UUID = UUID(), kind: TxKind = .expense, amount: Decimal, note: String, frequency: Frequency, startDate: Date,
         endDate: Date? = nil, account: Account?, category: Category?) {
        self.id = id; self.kind = kind; self.amount = amount; self.note = note; self.frequency = frequency
        self.startDate = startDate; self.endDate = endDate; self.account = account; self.category = category
    }

    var schedule: RuleSchedule { RuleSchedule(frequency: frequency, startDate: startDate, endDate: endDate) }
}

@Model final class Budget {
    var id: UUID = UUID()
    var monthlyLimit: Decimal
    var category: Category?

    init(id: UUID = UUID(), monthlyLimit: Decimal, category: Category?) {
        self.id = id; self.monthlyLimit = monthlyLimit; self.category = category
    }
}

@Model final class SavingsGoal {
    var id: UUID = UUID()
    var name: String
    var icon: String
    var colorKey: String
    var targetAmount: Decimal
    var deadline: Date?
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \GoalContribution.goal) var contributions: [GoalContribution] = []

    init(id: UUID = UUID(), name: String, icon: String = "star", colorKey: String = "olive", targetAmount: Decimal, deadline: Date? = nil) {
        self.id = id; self.name = name; self.icon = icon; self.colorKey = colorKey
        self.targetAmount = targetAmount; self.deadline = deadline
    }

    var saved: Decimal { contributions.reduce(0) { $0 + $1.amount } }
    var progress: Double { targetAmount == 0 ? 0 : max(min((saved / targetAmount).doubleValue, 1), 0) }
}

@Model final class GoalContribution {
    var id: UUID = UUID()
    var amount: Decimal
    var date: Date
    var note: String = ""
    var goal: SavingsGoal?

    init(id: UUID = UUID(), amount: Decimal, date: Date = Date(), note: String = "", goal: SavingsGoal?) {
        self.id = id; self.amount = amount; self.date = date; self.note = note; self.goal = goal
    }
}

/// Version 1 of the stored data. When a model changes, add a new `VersionedSchema` (V2, ...) and a migration stage to
/// `AppMigrationPlan`; never edit V1 once it has shipped. Additive changes (a new optional property or one with a default value)
/// can use a lightweight stage.
enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Account.self, Category.self, Transaction.self, RecurringRule.self, Budget.self, SavingsGoal.self, GoalContribution.self]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AppSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = AppSchemaV1.models

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(for: Schema(versionedSchema: AppSchemaV1.self), migrationPlan: AppMigrationPlan.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
    }
}
