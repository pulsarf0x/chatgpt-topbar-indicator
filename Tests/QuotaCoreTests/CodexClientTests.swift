#if os(macOS)
import XCTest
@testable import QuotaTransport

@MainActor
final class CodexClientTests: XCTestCase {
    private func withServer(_ body: String, run: (String) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QuotaBar transport \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("fake codex")
        try Data(("#!/bin/sh\n" + body).utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        try await run(script.path)
    }

    func testInitializationAndNotificationFraming() async throws {
        try await withServer("""
        IFS= read -r init
        case "$init" in *initialize*) ;; *) exit 9 ;; esac
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r request
        case "$request" in *rateLimits*read*) ;; *) exit 9 ;; esac
        printf '%s\n' '{"method":"account/updated","params":{}}'
        printf '%s\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":42}}}}'
        """) { path in
            let snapshot = try await CodexClient(executable: path).fetch()
            XCTAssertEqual(snapshot.menuValue(preferredID: "codex", at: .now), "58 %")
        }
    }

    func testSilentChildExitDoesNotHangOnParentPipe() async throws {
        let start = Date.now
        try await withServer("exit 1\n") { path in
            do {
                _ = try await CodexClient(executable: path).fetch()
                XCTFail("Expected disconnect")
            } catch ClientError.disconnected {} catch { XCTFail("Unexpected: \(error)") }
        }
        XCTAssertLessThan(Date.now.timeIntervalSince(start), 3)
    }

    func testAccountErrorIsSurfaced() async throws {
        try await withServer("""
        IFS= read -r init
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r request
        printf '%s\n' '{"id":2,"error":{"code":-32000,"message":"ChatGPT authentication required"}}'
        """) { path in
            do {
                _ = try await CodexClient(executable: path).fetch()
                XCTFail("Expected account error")
            } catch ClientError.service(let message) {
                XCTAssertEqual(message, "ChatGPT authentication required")
            } catch { XCTFail("Unexpected: \(error)") }
        }
    }
}
#endif
