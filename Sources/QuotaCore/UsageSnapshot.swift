import Foundation

public struct QuotaWindow: Codable, Equatable, Sendable, Identifiable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Double?
    public var id: String { "\(windowDurationMins ?? -1)-\(resetsAt ?? -1)" }
    public var remaining: Double { min(100, max(0, 100 - usedPercent)) }
    public var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
    public func isExpired(at date: Date) -> Bool { resetDate.map { $0 <= date } ?? false }
    public var shortTitle: String {
        guard let minutes = windowDurationMins, minutes > 0 else { return "Quota" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) j" }
        if minutes % 60 == 0 { return "\(minutes / 60) h" }
        return "\(minutes) min"
    }
    public var title: String {
        guard let minutes = windowDurationMins else { return "Fenêtre de quota" }
        if minutes == 10080 { return "Semaine" }
        if minutes == 1440 { return "24 heures" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) jours" }
        if minutes % 60 == 0 { return "\(minutes / 60) heures" }
        return "\(minutes) minutes"
    }
}

public struct QuotaBucket: Codable, Equatable, Sendable, Identifiable {
    public let limitId: String?
    public let limitName: String?
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public let planType: String?
    public var id: String { limitId ?? "codex" }
    public var title: String { limitName ?? (id == "codex" ? "Codex" : id) }
    public var windows: [QuotaWindow] {
        [primary, secondary].compactMap { $0 }.sorted {
            ($0.windowDurationMins ?? Int.max) < ($1.windowDurationMins ?? Int.max)
        }
    }
    public func limitingWindow(at date: Date) -> QuotaWindow? {
        windows.filter { !$0.isExpired(at: date) }.min { $0.remaining < $1.remaining }
    }
}

public struct RateLimitsResponse: Decodable, Sendable {
    public let rateLimits: QuotaBucket?
    public let rateLimitsByLimitId: [String: QuotaBucket]?
    public var buckets: [QuotaBucket] {
        if let map = rateLimitsByLimitId, !map.isEmpty {
            // The map key remains authoritative when older servers omit limitId.
            return map.map { key, value in
                QuotaBucket(limitId: key, limitName: value.limitName, primary: value.primary,
                            secondary: value.secondary, planType: value.planType)
            }.sorted { $0.id < $1.id }
        }
        return rateLimits.map { [$0] } ?? []
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let fetchedAt: Date
    public let buckets: [QuotaBucket]
    public init(fetchedAt: Date = .now, buckets: [QuotaBucket]) {
        self.fetchedAt = fetchedAt
        self.buckets = buckets
    }
    public func bucket(preferredID: String) -> QuotaBucket? {
        buckets.first { $0.id == preferredID } ?? buckets.first { $0.id == "codex" } ?? buckets.first
    }
    public func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) > 15 * 60 || fetchedAt.timeIntervalSince(date) > 60
    }
    public func menuValue(preferredID: String, at date: Date) -> String {
        guard !isStale(at: date), let window = bucket(preferredID: preferredID)?.limitingWindow(at: date) else {
            return "—"
        }
        return "\(Int(window.remaining.rounded(.down))) %"
    }
    public func menuSummary(preferredID: String, at date: Date) -> String {
        guard let bucket = bucket(preferredID: preferredID), !bucket.windows.isEmpty else { return "Codex —" }
        let stale = isStale(at: date)
        return bucket.windows.map { window in
            let value = stale || window.isExpired(at: date) ? "—" : "\(Int(window.remaining.rounded(.down))) %"
            return "\(window.shortTitle) \(value)"
        }.joined(separator: " · ")
    }
    public static func decodeResponse(_ data: Data, at date: Date = .now) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        return UsageSnapshot(fetchedAt: date, buckets: response.buckets)
    }
}
