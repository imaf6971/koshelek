import XCTest
import SwiftData
@testable import Koshelek

private let cal = Calendar.app
private func date(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

/// Reads entries of a stored (uncompressed) ZIP archive.
private func unzip(_ data: Data) -> [String: String] {
    var result: [String: String] = [:]
    var i = 0
    func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
    func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
    while i + 30 <= data.count, u32(i) == 0x04034B50 {
        let size = u32(i + 18), nameLen = u16(i + 26), extra = u16(i + 28)
        let name = String(decoding: data[(i + 30)..<(i + 30 + nameLen)], as: UTF8.self)
        let start = i + 30 + nameLen + extra
        result[name] = String(decoding: data[start..<(start + size)], as: UTF8.self)
        i = start + size
    }
    return result
}

final class XLSXTests: XCTestCase {
    func testCRC32() {
        XCTAssertEqual(ZipWriter.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    func testColumnNames() {
        XCTAssertEqual(XLSXWriter.columnName(0), "A")
        XCTAssertEqual(XLSXWriter.columnName(25), "Z")
        XCTAssertEqual(XLSXWriter.columnName(26), "AA")
    }

    func testSerialDate() {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        let d = c.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        XCTAssertEqual(XLSXWriter.serial(d, calendar: c), 46023.5, accuracy: 1e-6)   // 2026-01-01 12:00
    }

    func testWorkbookStructureAndCells() {
        let sheet = XLSXSheet(
            name: "Операции",
            columns: [.init(title: "Дата", width: 12, style: .date), .init(title: "Сумма", width: 12, style: .amount), .init(title: "Заметка", width: 20, style: .general)],
            rows: [[.date(date(2026, 3, 5)), .number(Decimal(string: "-1234.5")!), .text("Кофе & <булочка>")]])
        let files = unzip(XLSXWriter.data(for: sheet))
        XCTAssertEqual(Set(files.keys), ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/styles.xml", "xl/worksheets/sheet1.xml"])
        let xml = files["xl/worksheets/sheet1.xml"]!
        XCTAssertTrue(xml.contains("<t>Дата</t>"))
        XCTAssertTrue(xml.contains(#"<c r="B2" s="3"><v>-1234.5</v></c>"#))
        XCTAssertTrue(xml.contains(#"<c r="A2" s="2">"#))
        XCTAssertTrue(xml.contains("Кофе &amp; &lt;булочка&gt;"))
        XCTAssertTrue(xml.contains(#"state="frozen""#))
        XCTAssertTrue(files["xl/styles.xml"]!.contains(#"formatCode="dd\.mm\.yyyy""#))
        XCTAssertTrue(files["xl/workbook.xml"]!.contains(#"name="Операции""#))
        // Every XML part must be well-formed
        for (name, text) in files {
            let p = XMLParser(data: Data(text.utf8))
            XCTAssertTrue(p.parse(), "\(name) is not well-formed: \(String(describing: p.parserError))")
        }
    }
}

final class StoreTests: XCTestCase {
    func makeContext() throws -> ModelContext { ModelContext(try AppSchema.makeContainer(inMemory: true)) }

    func testRecurringGenerationHasNoDuplicates() throws {
        let ctx = try makeContext()
        let acc = Account(name: "Карта"); ctx.insert(acc)
        let rule = RecurringRule(amount: 100, note: "Подписка", frequency: .monthly, startDate: date(2026, 1, 15), account: acc, category: nil)
        ctx.insert(rule)
        let now = date(2026, 4, 20)
        XCTAssertEqual(RecurringService.generateDue(in: ctx, now: now), 4)
        XCTAssertEqual(RecurringService.generateDue(in: ctx, now: now), 0)
        XCTAssertEqual(RecurringService.generateDue(in: ctx, now: date(2026, 5, 16)), 1)
        // A deleted generated transaction is not recreated
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        ctx.delete(all[0]); try ctx.save()
        XCTAssertEqual(RecurringService.generateDue(in: ctx, now: date(2026, 5, 16)), 0)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Transaction>()), 4)
    }

    func testDeleteAccountMovesOrDeletesTransactions() throws {
        let ctx = try makeContext()
        let a = Account(name: "A"), b = Account(name: "B"), c = Account(name: "C")
        [a, b, c].forEach(ctx.insert)
        ctx.insert(Transaction(kind: .expense, amount: 10, date: date(2026, 1, 1), account: a))
        ctx.insert(Transaction(kind: .transfer, amount: 5, date: date(2026, 1, 2), account: a, toAccount: b))
        ctx.insert(Transaction(kind: .transfer, amount: 7, date: date(2026, 1, 3), account: c, toAccount: a))
        try ctx.save()
        Store.deleteAccount(a, moveTransactionsTo: b, in: ctx)
        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(txs.count, 2)                          // the A->B transfer became a self-transfer and was removed
        XCTAssertTrue(txs.allSatisfy { $0.account?.id != nil })
        Store.deleteAccount(b, moveTransactionsTo: nil, in: ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Transaction>()), 0)
    }

    func testDeleteCategoryReassigns() throws {
        let ctx = try makeContext()
        let acc = Account(name: "A"); ctx.insert(acc)
        let food = Koshelek.Category(name: "Еда", icon: "x", colorKey: "clay", kind: .expense)
        let cafe = Koshelek.Category(name: "Кафе", icon: "x", colorKey: "clay", kind: .expense, parent: food)
        let other = Koshelek.Category(name: "Прочее", icon: "x", colorKey: "clay", kind: .expense)
        [food, cafe, other].forEach(ctx.insert)
        ctx.insert(Transaction(kind: .expense, amount: 1, date: date(2026, 1, 1), account: acc, category: cafe))
        try ctx.save()
        Store.deleteCategory(food, moveTransactionsTo: other, deleteTransactions: false, in: ctx)
        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(txs.first?.category?.name, "Прочее")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Koshelek.Category>()), 1)
    }

    func testBackupRoundTrip() throws {
        let ctx = try makeContext()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        settings.currency = Currency(code: "XXX", symbol: "֏")
        DefaultCategories.ensure(in: ctx)
        let a = Account(name: "Карта", initialBalance: Decimal(string: "100.55")!), b = Account(name: "Нал")
        [a, b].forEach(ctx.insert)
        let cat = try ctx.fetch(FetchDescriptor<Koshelek.Category>()).first { $0.parent != nil }!
        ctx.insert(Transaction(kind: .expense, amount: Decimal(string: "12.34")!, date: date(2026, 2, 3), note: "Кофе", tags: ["a", "b"], account: a, category: cat))
        ctx.insert(Transaction(kind: .transfer, amount: 50, date: date(2026, 2, 4), account: a, toAccount: b))
        ctx.insert(RecurringRule(amount: 99, note: "Аренда", frequency: .weekly, startDate: date(2026, 1, 1), endDate: date(2026, 12, 1), account: a, category: cat))
        ctx.insert(Budget(monthlyLimit: 5000, category: cat))
        let goal = SavingsGoal(name: "Цель", targetAmount: 1000, deadline: date(2027, 1, 1)); ctx.insert(goal)
        ctx.insert(GoalContribution(amount: 250, date: date(2026, 2, 5), goal: goal))
        try ctx.save()

        let data = try BackupService.makeBackup(in: ctx, settings: settings)
        let file = try BackupService.validate(data)
        XCTAssertEqual(file.transactions.count, 2)

        let ctx2 = try makeContext()
        let settings2 = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        try BackupService.restore(file, in: ctx2, settings: settings2)
        XCTAssertEqual(settings2.currency.symbol, "֏")
        let txs = try ctx2.fetch(FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(txs.map(\.amount), [Decimal(string: "12.34")!, 50])
        XCTAssertEqual(txs[0].tags, ["a", "b"])
        XCTAssertEqual(txs[0].category?.parent != nil, true)
        XCTAssertEqual(txs[1].toAccount?.name, "Нал")
        XCTAssertEqual(try ctx2.fetch(FetchDescriptor<Account>()).first { $0.name == "Карта" }?.initialBalance, Decimal(string: "100.55")!)
        XCTAssertEqual(try ctx2.fetch(FetchDescriptor<SavingsGoal>()).first?.saved, 250)
        XCTAssertEqual(try ctx2.fetchCount(FetchDescriptor<Budget>()), 1)
        XCTAssertEqual(try ctx2.fetchCount(FetchDescriptor<Koshelek.Category>()), try ctx.fetchCount(FetchDescriptor<Koshelek.Category>()))
    }

    func testBackupValidationRejectsBadFiles() throws {
        XCTAssertThrowsError(try BackupService.validate(Data("не json".utf8)))
        let ctx = try makeContext()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let a = Account(name: "A"); ctx.insert(a)
        ctx.insert(Transaction(kind: .expense, amount: 1, date: date(2026, 1, 1), account: a))
        try ctx.save()
        var json = try JSONSerialization.jsonObject(with: BackupService.makeBackup(in: ctx, settings: settings)) as! [String: Any]
        var txs = json["transactions"] as! [[String: Any]]
        txs[0]["accountID"] = UUID().uuidString
        json["transactions"] = txs
        XCTAssertThrowsError(try BackupService.validate(JSONSerialization.data(withJSONObject: json)))
        json["transactions"] = (json["transactions"] as! [[String: Any]]).map { var t = $0; t["accountID"] = a.id.uuidString; return t }
        json["formatVersion"] = 99
        XCTAssertThrowsError(try BackupService.validate(JSONSerialization.data(withJSONObject: json)))
    }
}

final class WipeTests: XCTestCase {
    func testWipeAllRemovesEverything() throws {
        let ctx = ModelContext(try AppSchema.makeContainer(inMemory: true))
        DemoData.seed(in: ctx)
        XCTAssertGreaterThan(try ctx.fetchCount(FetchDescriptor<Transaction>()), 50)
        Store.wipeAll(in: ctx)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Transaction>()), 0, "transactions")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Account>()), 0, "accounts")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Koshelek.Category>()), 0, "categories")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<RecurringRule>()), 0, "rules")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Budget>()), 0, "budgets")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<SavingsGoal>()), 0, "goals")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<GoalContribution>()), 0, "contributions")
    }
}

final class RestoreReplaceTests: XCTestCase {
    func testRestoreOverExistingDataReplacesIt() throws {
        let ctx = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        DemoData.seed(in: ctx)
        let data = try BackupService.makeBackup(in: ctx, settings: settings)
        let file = try BackupService.validate(data)
        // Add extra data after the backup, then restore into the same store.
        ctx.insert(Account(name: "Лишний")); try ctx.save()
        try BackupService.restore(file, in: ctx, settings: settings)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Account>()), file.accounts.count)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Transaction>()), file.transactions.count)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Koshelek.Category>()), file.categories.count)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<SavingsGoal>()), file.goals.count)
    }
}

final class FirstLaunchResetTests: XCTestCase {
    func testResetToDefaultsReturnsToOnboarding() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        settings.currency = Currency(code: "USD", symbol: "$")
        settings.theme = .dark
        settings.budgetNotifications = true
        settings.hasOnboarded = true
        settings.resetToDefaults()
        XCTAssertEqual(settings.currency, .rub)
        XCTAssertEqual(settings.theme, .system)
        XCTAssertFalse(settings.budgetNotifications)
        XCTAssertFalse(settings.hasOnboarded)
    }
}

@MainActor
final class WatchSyncTests: XCTestCase {
    private func makeStore() throws -> (ModelContext, MoneyFormatter) {
        (ModelContext(try AppSchema.makeContainer(inMemory: true)), MoneyFormatter(symbol: "₽"))
    }

    private func snapshot(_ ctx: ModelContext, _ money: MoneyFormatter) throws -> WatchSnapshot {
        WatchSnapshotBuilder.make(
            accounts: try ctx.fetch(FetchDescriptor<Account>()), categories: try ctx.fetch(FetchDescriptor<Koshelek.Category>()),
            transactions: try ctx.fetch(FetchDescriptor<Transaction>()), budgets: try ctx.fetch(FetchDescriptor<Budget>()),
            rules: try ctx.fetch(FetchDescriptor<RecurringRule>()), money: money,
            now: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)))   // the wire format keeps whole seconds
    }

    func testSnapshotFromDemoData() throws {
        let (ctx, money) = try makeStore()
        DemoData.seed(in: ctx)
        let s = try snapshot(ctx, money)
        XCTAssertEqual(s.accounts.count, 3)
        XCTAssertLessThanOrEqual(s.recent.count, 8)
        XCTAssertTrue(zip(s.recent, s.recent.dropFirst()).allSatisfy { $0.date >= $1.date })
        XCTAssertFalse(s.budgets.isEmpty)
        XCTAssertTrue(zip(s.budgets, s.budgets.dropFirst()).allSatisfy { $0.ratio >= $1.ratio })
        XCTAssertFalse(s.expenseCategories.isEmpty)
        XCTAssertFalse(s.incomeCategories.isEmpty)
        XCTAssertTrue(s.totalBalance.hasSuffix("\u{00A0}₽"))
        // Round trip through the wire format
        let data = try WatchChannel.encoder.encode(s)
        XCTAssertEqual(try WatchChannel.decoder.decode(WatchSnapshot.self, from: data), s)
    }

    func testEntryFromWatchIsStoredOnceAndAppearsInSnapshot() throws {
        let (ctx, money) = try makeStore()
        DefaultCategories.ensure(in: ctx)
        let account = Account(name: "Карта", initialBalance: 1000); ctx.insert(account)
        try ctx.save()
        let category = try ctx.fetch(FetchDescriptor<Koshelek.Category>()).first { $0.kind == .expense }!
        let entry = WatchEntry(id: UUID(), kind: .expense, amount: "250.5", accountID: account.id, categoryID: category.id, date: Date())

        XCTAssertEqual(WatchEntryHandler.apply(entry, in: ctx), .applied)
        XCTAssertEqual(WatchEntryHandler.apply(entry, in: ctx), .duplicate, "the same entry must not be stored twice")
        let txs = try ctx.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(txs.count, 1)
        XCTAssertEqual(txs[0].amount, Decimal(string: "250.5"))
        XCTAssertEqual(txs[0].category?.id, category.id)

        let s = try snapshot(ctx, money)
        XCTAssertEqual(s.recent.first?.id, entry.id)
        XCTAssertEqual(s.totalBalance, "749,50\u{00A0}₽")
    }

    func testInvalidEntriesAreRejected() throws {
        let (ctx, _) = try makeStore()
        let account = Account(name: "A"); ctx.insert(account); try ctx.save()
        XCTAssertFalse(WatchEntryHandler.apply(WatchEntry(id: UUID(), kind: .expense, amount: "0", accountID: account.id, categoryID: nil, date: Date()), in: ctx).isAccepted)
        XCTAssertFalse(WatchEntryHandler.apply(WatchEntry(id: UUID(), kind: .expense, amount: "abc", accountID: account.id, categoryID: nil, date: Date()), in: ctx).isAccepted)
        XCTAssertFalse(WatchEntryHandler.apply(WatchEntry(id: UUID(), kind: .transfer, amount: "5", accountID: account.id, categoryID: nil, date: Date()), in: ctx).isAccepted)
        XCTAssertFalse(WatchEntryHandler.apply(WatchEntry(id: UUID(), kind: .expense, amount: "5", accountID: UUID(), categoryID: nil, date: Date()), in: ctx).isAccepted, "unknown account")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Transaction>()), 0)
    }
}

@MainActor
final class SafeRestoreTests: XCTestCase {
    func testRestoreSafelyKeepsASafetyCopyOfTheCurrentData() throws {
        let ctx = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        DemoData.seed(in: ctx)
        let file = try BackupService.validate(BackupService.makeBackup(in: ctx, settings: settings))

        // The current data changes after the backup was taken; restoring must bring the backup state back
        ctx.insert(Account(name: "Появился позже")); try ctx.save()
        let before = (try? FileManager.default.contentsOfDirectory(at: BackupService.safetyDirectory, includingPropertiesForKeys: nil))?.count ?? 0

        try BackupService.restoreSafely(file, in: ctx, settings: settings)

        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Account>()), file.accounts.count)
        let after = (try? FileManager.default.contentsOfDirectory(at: BackupService.safetyDirectory, includingPropertiesForKeys: nil))?.count ?? 0
        XCTAssertGreaterThanOrEqual(after, min(before + 1, 5), "a safety copy must be written before the data is replaced")
    }
}

final class SchemaTests: XCTestCase {
    func testVersionedSchemaOpensAnInMemoryStore() throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        XCTAssertEqual(container.schema.entities.count, AppSchemaV1.models.count)
    }
}

@MainActor
final class SafetyBackupRetentionTests: XCTestCase {
    /// Older copies made for another reason must not push out the copy that was just written.
    func testNewestCopyIsKeptWhateverTheReason() throws {
        let fm = FileManager.default
        let dir = BackupService.safetyDirectory
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: url) }
        for i in 0..<6 {
            let url = dir.appending(path: "Koshelek-before-wipe-old-\(i).json")
            try Data("{}".utf8).write(to: url)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -Double(1000 + i))], ofItemAtPath: url.path)
        }
        let ctx = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        XCTAssertNotNil(BackupService.writeSafetyBackup(in: ctx, settings: settings, reason: "before-restore"))
        let names = try fm.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(names.count, 5)
        XCTAssertTrue(names.contains { $0.hasPrefix("Koshelek-before-restore-") }, "the copy just written must survive")
        XCTAssertFalse(names.contains("Koshelek-before-wipe-old-5.json"), "the oldest copy is removed")
    }
}

final class BackupHierarchyTests: XCTestCase {
    func testNestedCategoriesAreRejected() throws {
        let ctx = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let settings = AppSettings(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
        let a = Koshelek.Category(name: "A", icon: "x", colorKey: "clay", kind: .expense)
        let b = Koshelek.Category(name: "B", icon: "x", colorKey: "clay", kind: .expense, parent: a)
        let c = Koshelek.Category(name: "C", icon: "x", colorKey: "clay", kind: .expense)
        [a, b, c].forEach(ctx.insert)
        try ctx.save()
        let data = try BackupService.makeBackup(in: ctx, settings: settings)
        XCTAssertNoThrow(try BackupService.validate(data))
        // Make C a child of B, which is itself a subcategory: three levels are not supported.
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["categories"] = (json["categories"] as! [[String: Any]]).map { var x = $0; if x["name"] as? String == "C" { x["parentID"] = b.id.uuidString }; return x }
        XCTAssertThrowsError(try BackupService.validate(JSONSerialization.data(withJSONObject: json)))
    }
}

final class ForecastRulesTests: XCTestCase {
    func testRulesWithoutAccountAreNotForecast() throws {
        let ctx = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let acc = Account(name: "A"); ctx.insert(acc)
        let now = date(2026, 3, 10)
        let withAccount = RecurringRule(amount: 100, note: "", frequency: .monthly, startDate: date(2026, 1, 20), account: acc, category: nil)
        let orphan = RecurringRule(amount: 500, note: "", frequency: .monthly, startDate: date(2026, 1, 20), account: nil, category: nil)
        [withAccount, orphan].forEach(ctx.insert)
        try ctx.save()
        let f = OverviewMetrics.forecast(balance: 1000, records: [], rules: [withAccount, orphan], now: now)
        XCTAssertEqual(f.scheduledNet, -100)
    }
}
