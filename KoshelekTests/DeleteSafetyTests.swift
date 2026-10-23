import XCTest
import SwiftData
@testable import Koshelek

final class DeleteSafetyTests: XCTestCase {
    func testDeletedObjectLosesItsContext() throws {
        let ctx = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let account = Account(name: "A"); ctx.insert(account)
        let tx = Transaction(kind: .expense, amount: 5, date: Date(), account: account); ctx.insert(tx)
        try ctx.save()
        XCTAssertNotNil(tx.modelContext)
        ctx.delete(tx)
        try ctx.save()
        // Views keep such references in their @Query arrays for a moment; the live filter must recognise them without reading attributes.
        XCTAssertNil(tx.modelContext, "deleted transaction should be detached after save")
        XCTAssertEqual([tx].live.count, 0)
        XCTAssertEqual([account].live.count, 1)
    }
}
