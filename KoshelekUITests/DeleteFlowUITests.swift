import XCTest

/// Deletes one object of every kind through the real UI and checks that the app survives. Run these in an optimized build
/// (SWIFT_OPTIMIZATION_LEVEL=-O): the crash this guards against showed up only there.
final class DeleteFlowUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-seedDemo", "-resetData"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Общий баланс"].waitForExistence(timeout: 20), "demo data did not load")
    }

    // MARK: helpers

    private func row(_ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func scrollTo(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "element not found: \(element)", file: file, line: line)
    }

    private func openTab(_ name: String) {
        let tab = app.buttons[name].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "tab \(name)")
        tab.tap()
    }

    private func confirmDeleteDialog() {
        let confirm = app.buttons["Удалить"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }

    private func assertAlive(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "app crashed: \(message)", file: file, line: line)
    }

    // MARK: transactions

    func testDeleteTransactionFromOverviewSheet() {
        let r = row("Здоровье")
        scrollTo(r)
        r.tap()
        let delete = app.buttons["Удалить операцию"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        confirmDeleteDialog()
        assertAlive("deleting a transaction from the edit sheet")
    }

    func testSwipeDeleteTransactionInOperations() {
        openTab("Операции")
        let r = row("Продукты")
        XCTAssertTrue(r.waitForExistence(timeout: 5))
        r.swipeLeft()
        let del = app.buttons["Удалить"].firstMatch
        XCTAssertTrue(del.waitForExistence(timeout: 5))
        del.tap()
        assertAlive("swipe-deleting a transaction")
    }

    // MARK: plans

    func testDeleteGoalContribution() {
        openTab("Планы")
        app.buttons["Цели"].firstMatch.tap()
        let goal = row("Отпуск")
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        goal.tap()
        let trash = app.buttons["Удалить взнос"].firstMatch
        scrollTo(trash)
        trash.tap()
        assertAlive("deleting a goal contribution")
        trash.tap()   // a second one right after the first
        assertAlive("deleting a second goal contribution")
    }

    func testDeleteGoal() {
        openTab("Планы")
        app.buttons["Цели"].firstMatch.tap()
        let goal = row("Подушка")
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        goal.tap()
        let menu = app.buttons["Действия с целью"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["Удалить цель"].firstMatch.tap()
        confirmDeleteDialog()
        assertAlive("deleting a goal")
    }

    func testDeleteBudget() {
        openTab("Планы")
        let budget = row("Транспорт")
        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        budget.tap()
        let delete = app.buttons["Удалить бюджет"]
        scrollTo(delete)
        delete.tap()
        assertAlive("deleting a budget")
    }

    func testDeleteRecurringRule() {
        openTab("Планы")
        app.buttons["Регулярные"].firstMatch.tap()
        let rule = row("Аренда")
        XCTAssertTrue(rule.waitForExistence(timeout: 5))
        rule.tap()
        let delete = app.buttons["Удалить правило"]
        scrollTo(delete)
        delete.tap()
        assertAlive("deleting a recurring rule")
    }

    // MARK: accounts and categories

    func testDeleteAccountAndMoveItsTransactions() {
        openTab("Настройки")
        app.buttons["Счета"].firstMatch.tap()
        let account = row("Наличные")
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.swipeLeft()
        app.buttons["Удалить"].firstMatch.tap()
        let move = app.buttons["Перенести и удалить"]
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        move.tap()
        assertAlive("deleting an account and moving its transactions")
        XCTAssertFalse(row("Наличные").exists, "the account should be gone")
    }

    func testDeleteCategoryAndMoveItsTransactions() {
        openTab("Настройки")
        app.buttons["Категории"].firstMatch.tap()
        let category = row("Одежда")
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.swipeLeft()
        app.buttons["Удалить"].firstMatch.tap()
        let move = app.buttons["Перенести и удалить"]
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        move.tap()
        assertAlive("deleting a category and moving its transactions")
    }
}
