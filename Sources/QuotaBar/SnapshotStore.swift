import Foundation
import WidgetKit
import OSLog

// Only quota values and timestamps are shared; credentials stay with the CLI.
enum SnapshotStore {
    static let groupID = "group.net.plumia.QuotaBar"
    static let key = "usageSnapshot.v1"
    private static let logger = Logger(subsystem: "net.plumia.QuotaBar", category: "widget-cache")
    private static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("usageSnapshot.v1.json")
    }

    static func load() -> UsageSnapshot? {
        if let url = snapshotURL, let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) {
            return snapshot
        }
        // Migrate snapshots written before the shared-file transport was added.
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    @discardableResult
    static func save(_ snapshot: UsageSnapshot) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot), let url = snapshotURL else {
            logger.error("Shared widget container unavailable")
            return false
        }
        let previous = load()
        do {
            // Atomic replacement keeps the extension from reading a partial file.
            try data.write(to: url, options: .atomic)
            guard try Data(contentsOf: url) == data else { return false }
            logger.notice("Shared widget snapshot written and read back")
        } catch {
            logger.error("Shared widget snapshot write failed: domain=\((error as NSError).domain, privacy: .public), code=\((error as NSError).code, privacy: .public)")
            return false
        }
        // Refresh bookkeeping belongs to the writer, not the shared preferences
        // domain, which can reject writes from a non-sandboxed macOS host app.
        let defaults = UserDefaults.standard
        let lastReload = defaults.object(forKey: "lastWidgetReload") as? Date ?? .distantPast
        if previous?.buckets != snapshot.buckets || Date.now.timeIntervalSince(lastReload) >= 300 {
            defaults.set(Date.now, forKey: "lastWidgetReload")
            WidgetCenter.shared.reloadAllTimelines()
        }
        return true
    }

    static func clear() {
        if let url = snapshotURL, FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) }
            catch { logger.error("Unable to clear shared widget snapshot") }
        }
        UserDefaults(suiteName: groupID)?.removeObject(forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
