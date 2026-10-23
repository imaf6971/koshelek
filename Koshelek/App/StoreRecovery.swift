import SwiftUI
import SwiftData

/// What to do when the data store cannot be opened (for example after a faulty update), instead of crashing at launch.
enum StoreRecovery {
    /// Files that make up the default SwiftData store.
    private static var storeFiles: [URL] {
        let base = URL.applicationSupportDirectory
        return ["default.store", "default.store-shm", "default.store-wal"].map { base.appending(path: $0) }
    }

    /// Moves the store files into a timestamped folder next to them; nothing is deleted, so the data can still be recovered.
    @discardableResult
    static func setAsideStore() -> URL? {
        let fm = FileManager.default
        let folder = URL.applicationSupportDirectory.appending(path: "StoreBackup-\(FileStamp.string("yyyy-MM-dd-HHmmss"))", directoryHint: .isDirectory)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var moved = false
        for file in storeFiles where fm.fileExists(atPath: file.path) {
            if (try? fm.moveItem(at: file, to: folder.appending(path: file.lastPathComponent))) != nil { moved = true }
        }
        return moved ? folder : nil
    }
}

struct StoreRecoveryView: View {
    let message: String
    var retry: () -> Void
    var startFresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "exclamationmark.triangle").font(.system(size: 36, weight: .light)).foregroundStyle(Theme.Colors.accent)
            Text("Не удалось открыть данные").font(Theme.Fonts.display)
            Text("Данные на устройстве целы, но приложение не смогло их прочитать. Попробуйте ещё раз. Если не помогает, можно отложить старые данные в сторону и начать с чистого листа: старые файлы останутся на устройстве в папке приложения.")
                .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
            Text(message).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary).lineLimit(4)
            Spacer()
            Button("Попробовать снова", action: retry).buttonStyle(PrimaryButtonStyle())
            Button("Отложить старые данные и начать заново", role: .destructive, action: startFresh)
                .frame(maxWidth: .infinity)
        }
        .padding(Theme.Spacing.l)
        .screenBackground()
    }
}
