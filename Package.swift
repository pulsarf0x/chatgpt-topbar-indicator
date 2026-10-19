// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "QuotaCore", targets: ["QuotaCore"])],
    targets: [
        .target(name: "QuotaCore"),
        .target(name: "QuotaTransport", dependencies: ["QuotaCore"], path: "Sources/QuotaBar",
                exclude: ["UsageModel.swift", "QuotaStyle.swift", "QuotaBarApp.swift", "SnapshotStore.swift", "SettingsView.swift", "DashboardView.swift"],
                sources: ["CodexClient.swift"]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore", "QuotaTransport"])
    ]
)
