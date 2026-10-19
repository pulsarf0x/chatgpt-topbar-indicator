import XCTest
@testable import QuotaCore

final class UsageSnapshotTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func decode(_ json: String) throws -> UsageSnapshot {
        try UsageSnapshot.decodeResponse(Data(json.utf8), at: now)
    }
    func testMultipleBucketsPreferMapAndPreserveKey() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":1}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":35,"windowDurationMins":300}},"other":{"limitName":"Autre","secondary":{"usedPercent":80}}}}"#)
        XCTAssertEqual(snapshot.buckets.count, 2)
        XCTAssertEqual(snapshot.menuValue(preferredID: "codex", at: now), "65 %")
        XCTAssertEqual(snapshot.menuValue(preferredID: "other", at: now), "20 %")
    }
    func testMissingWindowsAreUnavailableRatherThanFull() throws {
        let snapshot = try decode(#"{"rateLimits":{"limitId":"codex","primary":null,"secondary":null}}"#)
        XCTAssertEqual(snapshot.menuValue(preferredID: "codex", at: now), "—")
        XCTAssertTrue(snapshot.buckets[0].windows.isEmpty)
    }
    func testLimitingWindowDoesNotDependOnPrimaryPosition() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":80,"windowDurationMins":10080},"secondary":{"usedPercent":20,"windowDurationMins":300}}}"#)
        XCTAssertEqual(snapshot.bucket(preferredID: "codex")?.windows.first?.title, "5 heures")
        XCTAssertEqual(snapshot.menuValue(preferredID: "codex", at: now), "20 %")
    }
    func testExpiredWindowNeverInventsReset() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":99,"resetsAt":1799999999}}}"#)
        XCTAssertEqual(snapshot.menuValue(preferredID: "codex", at: now), "—")
        XCTAssertEqual(snapshot.buckets[0].primary?.remaining, 1)
    }
    func testStaleAndFutureSnapshotsAreNotAdvertisedAsLive() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":40}}}"#)
        XCTAssertEqual(snapshot.menuValue(preferredID: "codex", at: now.addingTimeInterval(901)), "—")
        XCTAssertTrue(snapshot.isStale(at: now.addingTimeInterval(-61)))
    }
    func testBoundsAndFractionalPercentAreConservative() throws {
        let snapshot = try decode(#"{"rateLimitsByLimitId":{"a":{"primary":{"usedPercent":103}},"b":{"primary":{"usedPercent":-3}},"c":{"primary":{"usedPercent":24.6}}}}"#)
        XCTAssertEqual(snapshot.menuValue(preferredID: "a", at: now), "0 %")
        XCTAssertEqual(snapshot.menuValue(preferredID: "b", at: now), "100 %")
        XCTAssertEqual(snapshot.menuValue(preferredID: "c", at: now), "75 %")
    }
    func testLegacyFallbackAndCodableRoundTrip() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":10},"planType":"pro"},"rateLimitsByLimitId":{}}"#)
        let reloaded = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(snapshot, reloaded)
        XCTAssertEqual(reloaded.buckets[0].planType, "pro")
    }
    func testMalformedPercentageFailsRatherThanBecomingZero() {
        XCTAssertThrowsError(try decode(#"{"rateLimits":{"primary":{"usedPercent":"unknown"}}}"#))
    }
    func testNullResponseMeansNoQuota() throws {
        let snapshot = try decode(#"{"rateLimits":null,"rateLimitsByLimitId":null}"#)
        XCTAssertTrue(snapshot.buckets.isEmpty)
    }
    func testMenuSummaryShowsEachWindowWithItsDuration() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080},"secondary":{"usedPercent":35.2,"windowDurationMins":300}}}"#)
        XCTAssertEqual(snapshot.menuSummary(preferredID: "codex", at: now), "5 h 64 % · 7 j 80 %")
    }
    func testMenuSummaryKeepsLiveWindowsWhenAnotherHasExpired() throws {
        let snapshot = try decode(#"{"rateLimits":{"primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":1799999999},"secondary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":1800010000}}}"#)
        XCTAssertEqual(snapshot.menuSummary(preferredID: "codex", at: now), "5 h — · 7 j 75 %")
        XCTAssertEqual(snapshot.menuSummary(preferredID: "codex", at: now.addingTimeInterval(901)), "5 h — · 7 j —")
    }

}
