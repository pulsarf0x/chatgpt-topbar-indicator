import Foundation
import Observation
import WidgetKit
import OSLog
#if os(macOS)
import AppKit
#endif

@MainActor @Observable
final class UsageModel {
    static let shared = UsageModel()
    var displayDate = Date.now
    var snapshot = SnapshotStore.load()
    var cloudSyncAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "QuotaBarLocalBuild") as? Bool != true
    }
    var isRefreshing = false
    var isLoggingIn = false
    var error: String?
    var selectedBucketID: String {
        didSet { UserDefaults.standard.set(selectedBucketID, forKey: "selectedBucket") }
    }
    var executablePath: String {
        didSet { UserDefaults.standard.set(executablePath, forKey: "executablePath") }
    }
    var syncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(syncEnabled, forKey: "cloudSync")
            if syncEnabled { synchronize() }
        }
    }
    private var syncObserver: NSObjectProtocol?
    private var running = false
    private var refreshTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "net.plumia.QuotaBar", category: "refresh")

    init() {
        selectedBucketID = UserDefaults.standard.string(forKey: "selectedBucket") ?? "codex"
        syncEnabled = UserDefaults.standard.bool(forKey: "cloudSync")
            && (Bundle.main.object(forInfoDictionaryKey: "QuotaBarLocalBuild") as? Bool != true)
        #if os(macOS)
        executablePath = UserDefaults.standard.string(forKey: "executablePath") ?? CodexClient.detectedExecutable
        #else
        executablePath = ""
        #endif
        syncObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.receiveCloudSnapshot() }
        }
        logger.notice("Usage model initialized")
    }

    var menuBarTitle: String {
        let title = snapshot?.menuSummary(preferredID: selectedBucketID, at: displayDate) ?? "Codex —"
        return error == nil ? title : title + " ⚠︎"
    }

    var bucket: QuotaBucket? { snapshot?.bucket(preferredID: selectedBucketID) }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        guard !running else { return }
        running = true
        defer { running = false }
        if syncEnabled { synchronize() }
        while !Task.isCancelled {
            displayDate = .now
            await refresh()
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
        }
    }

    func refresh() async {
        guard !isRefreshing, !isLoggingIn else { return }
        logger.notice("Starting quota read")
        #if os(macOS)
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                            reason: "Actualisation des quotas Codex")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        #endif
        isRefreshing = true
        defer { isRefreshing = false }
        #if os(macOS)
        do {
            let value = try await CodexClient(executable: executablePath).fetch()
            logger.notice("Quota read succeeded")
            displayDate = .now
            snapshot = value
            error = nil
            if !SnapshotStore.save(value) {
                error = "Quotas lus, mais le stockage partagé avec le widget est indisponible."
            }
            if syncEnabled { publish(value) }
        } catch {
            logger.error("Account operation failed: \(error.localizedDescription, privacy: .private)")
            self.error = error.localizedDescription
        }
        #else
        if syncEnabled {
            NSUbiquitousKeyValueStore.default.synchronize()
            receiveCloudSnapshot()
        } else {
            error = "Active iCloud sur les deux appareils, puis actualise QuotaBar sur ton Mac."
        }
        #endif
    }

    #if os(macOS)
    func login() async {
        guard !isLoggingIn, !isRefreshing else { return }
        isLoggingIn = true
        error = nil
        do {
            try await CodexClient(executable: executablePath).login { url in
                Task { @MainActor in NSWorkspace.shared.open(url) }
            }
            // The existing snapshot may belong to another account.
            snapshot = nil
            SnapshotStore.clear()
        } catch {
            logger.error("Account operation failed: \(error.localizedDescription, privacy: .private)")
            self.error = error.localizedDescription
        }
        isLoggingIn = false
        if error == nil { await refresh() }
    }
    #endif

    func synchronize() {
        guard syncEnabled, cloudSyncAvailable else { return }
        NSUbiquitousKeyValueStore.default.synchronize()
        #if os(macOS)
        if let snapshot { publish(snapshot) }
        #else
        receiveCloudSnapshot()
        #endif
    }

    private func publish(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        NSUbiquitousKeyValueStore.default.set(data, forKey: SnapshotStore.key)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func receiveCloudSnapshot() {
        #if os(iOS)
        guard syncEnabled, let data = NSUbiquitousKeyValueStore.default.data(forKey: SnapshotStore.key),
              let incoming = try? JSONDecoder().decode(UsageSnapshot.self, from: data),
              incoming.fetchedAt <= Date.now.addingTimeInterval(60),
              snapshot == nil || incoming.fetchedAt > snapshot!.fetchedAt else { return }
        snapshot = incoming
        error = nil
        SnapshotStore.save(incoming)
        #endif
    }
}
