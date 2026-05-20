import Foundation
import SwiftData

/// v1.67 — Scheduled auto-backup. Run en arrière-plan : check au launch + toutes les 24h
/// si > 24h depuis le dernier backup, déclenche BackupService.exportAll vers dir configuré.
///
/// Persiste : isEnabled, lastBackupAt, backupDir (UserDefaults).
public actor BackupScheduler {
    public static let shared = BackupScheduler()

    private var loopTask: Task<Void, Never>?
    private weak var modelContainer: ModelContainer?
    private let checkIntervalSeconds: UInt64 = 3600  // 1h ticks

    private static let enabledKey = "iris.backup.autoEnabled"
    private static let lastBackupAtKey = "iris.backup.lastAt"
    private static let backupDirKey = "iris.backup.dir"

    private init() {}

    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    public static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    public static var lastBackupAt: Date? {
        UserDefaults.standard.object(forKey: lastBackupAtKey) as? Date
    }

    public static var backupDir: URL {
        if let raw = UserDefaults.standard.string(forKey: backupDirKey),
           !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: ("~/Documents/IRIS-Backups" as NSString).expandingTildeInPath)
    }

    public static func setBackupDir(_ path: String) {
        UserDefaults.standard.set(path, forKey: backupDirKey)
    }

    public func start(modelContainer: ModelContainer) async {
        self.modelContainer = modelContainer
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            // Premier check 60s après bootstrap (laisse le reste démarrer)
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            while !Task.isCancelled {
                await self?.tickIfDue()
                try? await Task.sleep(nanoseconds: (self?.checkIntervalSeconds ?? 3600) * 1_000_000_000)
            }
        }
        irisLog(.info, "BackupScheduler started — auto=\(Self.isEnabled) interval=1h check", category: IRISLogger.store)
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// Déclenche backup manuel (depuis Settings). Retourne URL backup créé.
    @discardableResult
    public func backupNow() async -> URL? {
        guard let container = modelContainer else { return nil }
        return await Self.runBackup(container: container)
    }

    private func tickIfDue() async {
        guard Self.isEnabled, let container = modelContainer else { return }
        let now = Date()
        let last = Self.lastBackupAt ?? .distantPast
        let elapsed = now.timeIntervalSince(last)
        guard elapsed > 86400 else { return }  // 24h
        _ = await Self.runBackup(container: container)
    }

    @MainActor
    private static func runBackup(container: ModelContainer) async -> URL? {
        let dir = backupDir
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            let url = try BackupService.exportAll(container: container, to: dir)
            UserDefaults.standard.set(Date(), forKey: lastBackupAtKey)
            irisLog(.notice, "BackupScheduler: backup written to \(url.lastPathComponent)", category: IRISLogger.store)
            return url
        } catch {
            irisLog(.error, "BackupScheduler: backup failed — \(error.localizedDescription)", category: IRISLogger.store)
            return nil
        }
    }
}
