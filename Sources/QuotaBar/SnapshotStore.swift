import Foundation
import WidgetKit

// No credentials or account identifiers are stored in either container.
enum SnapshotStore {
    static let groupID = "group.net.plumia.QuotaBar"
    static let key = "usageSnapshot.v1"
    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }
    static func load() -> UsageSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
    static func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let previous = load()
        let lastReload = defaults.object(forKey: "lastWidgetReload") as? Date ?? .distantPast
        defaults.set(data, forKey: key)
        // Frequent menu reads should not request a widget timeline every 30 s.
        if previous?.buckets != snapshot.buckets || Date.now.timeIntervalSince(lastReload) >= 300 {
            defaults.set(Date.now, forKey: "lastWidgetReload")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    static func clear() {
        defaults.removeObject(forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
