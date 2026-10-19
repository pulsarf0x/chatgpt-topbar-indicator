import Foundation

@main
struct Probe {
    static func main() async {
        do {
            let snapshot = try await CodexClient(executable: CodexClient.detectedExecutable).fetch()
            print("Live Codex account read: \(snapshot.buckets.count) quota groups")
            for bucket in snapshot.buckets {
                print("\(bucket.id): \(snapshot.menuValue(preferredID: bucket.id, at: .now)) remaining; \(bucket.windows.count) windows")
            }
        } catch {
            print("Live read failed: \(error.localizedDescription)")
            exit(1)
        }
    }
}
