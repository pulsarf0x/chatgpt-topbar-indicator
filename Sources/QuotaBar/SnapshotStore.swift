import Foundation
import WidgetKit
import OSLog

// Only quota values and timestamps are shared; credentials stay with the CLI.
enum SnapshotStore {
    static let groupID = "group.net.plumia.QuotaBar"
    static let key = "usageSnapshot.v1"
    private static let logger = Logger(subsystem: "net.plumia.QuotaBar", category: "widget-cache")
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }
    private static let bookmarkKey = "widgetContainerAccess.v1"
    private static var accessURL: URL? {
        #if os(macOS)
        if let data = UserDefaults.standard.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                  relativeTo: nil, bookmarkDataIsStale: &stale),
               url.standardizedFileURL == containerURL?.standardizedFileURL {
                return url
            }
        }
        #endif
        return containerURL
    }
    #if os(macOS)
    static func authorize(_ url: URL, snapshot: UsageSnapshot) throws {
        guard url.standardizedFileURL == containerURL?.standardizedFileURL else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try JSONEncoder().encode(snapshot)
        let file = url.appendingPathComponent("usageSnapshot.v1.json")
        try data.write(to: file, options: .atomic)
        guard try Data(contentsOf: file) == data else { throw CocoaError(.fileWriteUnknown) }
        let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                           includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        logger.notice("User-authorized widget snapshot written and read back")
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif

    static func load() -> UsageSnapshot? {
        let container = accessURL
        #if os(macOS)
        let scoped = container?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { container?.stopAccessingSecurityScopedResource() } }
        #endif
        if let url = container?.appendingPathComponent("usageSnapshot.v1.json"), let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) {
            return snapshot
        }
        // Migrate snapshots written before the shared-file transport was added.
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    @discardableResult
    static func save(_ snapshot: UsageSnapshot) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot), let container = accessURL else {
            logger.error("Shared widget container unavailable")
            return false
        }
        #if os(macOS)
        let scoped = container.startAccessingSecurityScopedResource()
        defer { if scoped { container.stopAccessingSecurityScopedResource() } }
        #endif
        let url = container.appendingPathComponent("usageSnapshot.v1.json")
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
        let container = accessURL
        #if os(macOS)
        let scoped = container?.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { container?.stopAccessingSecurityScopedResource() } }
        #endif
        if let url = container?.appendingPathComponent("usageSnapshot.v1.json"), FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) }
            catch { logger.error("Unable to clear shared widget snapshot") }
        }
        UserDefaults(suiteName: groupID)?.removeObject(forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
