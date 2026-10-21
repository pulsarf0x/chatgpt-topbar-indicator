import SwiftUI
import WidgetKit
import OSLog

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    var isPreview = false
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { preview }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(context.isPreview ? preview : UsageEntry(date: .now, snapshot: SnapshotStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date.now
        let snapshot = SnapshotStore.load()
        Logger(subsystem: "net.plumia.QuotaBar", category: "widget-provider")
            .notice("Widget timeline has shared quota snapshot: \(snapshot != nil, privacy: .public)")
        var dates = [now, now.addingTimeInterval(16 * 60)]
        if let snapshot {
            dates.append(snapshot.fetchedAt.addingTimeInterval(15 * 60 + 1))
            dates += snapshot.buckets.flatMap(\.windows).compactMap(\.resetDate).map { $0.addingTimeInterval(1) }
        }
        let entries = Set(dates.filter { $0 >= now }).sorted().map { UsageEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
    private var preview: UsageEntry {
        let data = Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":28,"windowDurationMins":300},"secondary":{"usedPercent":46,"windowDurationMins":10080}}}"#.utf8)
        return UsageEntry(date: .now, snapshot: try? UsageSnapshot.decodeResponse(data), isPreview: true)
    }
}

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let bucket = entry.snapshot?.bucket(preferredID: "codex")
        let stale = entry.snapshot?.isStale(at: entry.date) ?? false
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(Color.quotaAccent)
                Text("QuotaBar").fontWeight(.semibold)
                Spacer()
                if entry.isPreview { Text("Aperçu").foregroundStyle(.secondary) }
            }.font(.caption)
            HStack(spacing: 26) {
                QuotaRing(remaining: bucket?.limitingWindow(at: entry.date)?.remaining, size: family == .systemSmall ? 82 : 98, muted: stale)
                if family == .systemMedium {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array((bucket?.windows ?? []).enumerated()), id: \.offset) { _, window in
                            HStack {
                                Text(window.title).foregroundStyle(.secondary)
                                Spacer()
                                Text(window.isExpired(at: entry.date) ? "—" : "\(Int(window.remaining.rounded(.down))) %")
                                    .monospacedDigit().fontWeight(.semibold)
                            }.font(.caption)
                        }
                        if bucket == nil {
                            Text("Ouvre QuotaBar pour lire tes quotas.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if let snapshot = entry.snapshot {
                    Image(systemName: stale ? "clock.badge.exclamationmark" : "arrow.clockwise")
                    Text(stale ? "Ancien ·" : "Lecture")
                    Text(snapshot.fetchedAt, style: .time)
                } else { Text("Ouvre QuotaBar pour commencer") }
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) { Color.quotaAccent.opacity(0.055) }
        .widgetURL(URL(string: "quotabar://dashboard"))
    }
}

@main
struct QuotaWidget: Widget {
    let kind = "QuotaBarUsage"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in UsageWidgetView(entry: entry) }
            .configurationDisplayName("Quotas Codex")
            .description("Tes quotas restants et la dernière lecture de QuotaBar.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
