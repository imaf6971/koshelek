import Foundation
import Observation
import SwiftData

/// Collects failures that must not stay silent (a failed save, a failed restore); the root view shows them in an alert.
@Observable
final class AppErrors {
    static let shared = AppErrors()
    var message: String?

    func report(_ text: String) {
        DispatchQueue.main.async { self.message = text }
    }
}

extension ModelContext {
    /// Saves, and tells the user when that fails instead of silently losing the change. The unsaved changes are discarded
    /// so the screen and the store stay consistent.
    func saveOrReport() {
        do { try save() } catch {
            rollback()
            AppErrors.shared.report(LF("Не удалось сохранить изменения: %@", error.localizedDescription))
        }
    }
}
