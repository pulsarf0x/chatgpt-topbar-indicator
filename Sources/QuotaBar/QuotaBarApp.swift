import SwiftUI
#if os(macOS)
import AppKit

@MainActor
final class QuotaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UsageModel.shared.start()
    }
}
#endif

@main
struct QuotaBarApp: App {
    @State private var model = UsageModel.shared
    #if os(macOS)
    @NSApplicationDelegateAdaptor(QuotaAppDelegate.self) private var delegate
    #endif
    #if os(macOS)
    var body: some Scene {
        MenuBarExtra(model.menuBarTitle,
                     systemImage: "circle.hexagongrid.fill") {
            DashboardView(model: model, compact: true).frame(width: 360, height: 650)
        }
        .menuBarExtraStyle(.window)
        Window("QuotaBar", id: "dashboard") {
            DashboardView(model: model).frame(minWidth: 400, minHeight: 680)
                .onOpenURL { _ in NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 440, height: 740)
    }
    #else
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            DashboardView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.synchronize() }
                }
        }
    }
    #endif
}
