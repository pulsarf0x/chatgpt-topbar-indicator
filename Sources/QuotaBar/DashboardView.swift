import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DashboardView: View {
    @Bindable var model: UsageModel
    var compact = false
    @State private var showingSettings = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let snapshot = model.snapshot
            let stale = snapshot?.isStale(at: context.date) ?? false
            let bucket = model.bucket
            let limiting = bucket?.limitingWindow(at: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.hexagongrid.fill")
                            .font(.title2).foregroundStyle(Color.quotaAccent)
                            .padding(9).background(Color.quotaAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("QuotaBar").font(.headline)
                            Text("CHATGPT · CODEX").font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(1.5).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { showingSettings = true } label: {
                            Image(systemName: "gearshape").frame(width: 28, height: 28)
                        }
                            .quotaButton().buttonBorderShape(.circle)
                            .accessibilityLabel("Réglages")
                    }

                    if let snapshot, let bucket {
                        VStack(spacing: 17) {
                            HStack {
                                Text("Ta marge de création").font(.title3.weight(.semibold))
                                Spacer()
                                if let plan = bucket.planType {
                                    Text(plan.capitalized).font(.caption.weight(.medium))
                                        .padding(.horizontal, 9).padding(.vertical, 4)
                                        .background(.primary.opacity(0.05), in: Capsule())
                                }
                            }
                            QuotaRing(remaining: limiting?.remaining, size: compact ? 126 : 156, muted: stale)
                                .padding(.vertical, 6)
                            Text(limiting.map { "Fenêtre la plus contrainte · \($0.title.lowercased())" } ?? "Quota à actualiser")
                                .font(.caption).foregroundStyle(.secondary)
                            if snapshot.buckets.count > 1 {
                                Picker("Quota", selection: $model.selectedBucketID) {
                                    ForEach(snapshot.buckets) { Text($0.title).tag($0.id) }
                                }
                                .labelsHidden()
                            } else {
                                Text(bucket.title).font(.caption.weight(.medium))
                            }
                        }
                        .frame(maxWidth: .infinity).padding(20)
                        .background(Color.quotaAccent.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24)
                                .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
                        }

                        VStack(spacing: 20) {
                            ForEach(Array(bucket.windows.enumerated()), id: \.offset) { _, window in
                                WindowRow(window: window, now: context.date, stale: stale)
                            }
                            if bucket.windows.isEmpty {
                                Text("Aucune fenêtre de quota communiquée par le service.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 6) {
                            Circle().fill(stale ? .orange : .green).frame(width: 5, height: 5)
                            Text(stale ? "Données anciennes" : "Dernière lecture")
                            Text(snapshot.fetchedAt, style: .time)
                            Spacer()
                        }.font(.caption).foregroundStyle(.secondary)
                    } else {
                        emptyState
                    }

                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.isLoggingIn {
                        Label("Termine la connexion dans ton navigateur…", systemImage: "safari")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    #if os(macOS)
                    if compact {
                        Button("Ouvrir la fenêtre") { openWindow(id: "dashboard") }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                    #endif
                    Text("Pourcentages de l’abonnement Codex. Ils ne représentent pas un solde exact de tokens ni tous les usages de ChatGPT.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(compact ? 22 : 28)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            QuotaGlassGroup {
                HStack(spacing: 12) {
                    Button { Task { await model.refresh() } } label: {
                        HStack(spacing: 7) {
                            if model.isRefreshing { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.clockwise") }
                            Text("Actualiser")
                        }
                        .frame(maxWidth: .infinity, minHeight: 26)
                    }
                    .quotaButton(prominent: true).tint(.quotaAccent)
                    .buttonBorderShape(.capsule)
                    .disabled(model.isRefreshing || model.isLoggingIn)
                    #if os(macOS)
                    if compact {
                        Button { NSApplication.shared.terminate(nil) } label: {
                            Image(systemName: "power").frame(width: 26, height: 26)
                        }
                        .quotaButton().buttonBorderShape(.circle)
                        .help("Quitter QuotaBar").accessibilityLabel("Quitter QuotaBar")
                    }
                    #endif
                }
                .controlSize(.large)
            }
            .padding(.horizontal, compact ? 22 : 28)
            .padding(.top, 12).padding(.bottom, compact ? 18 : 22)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .quotaWindowBackground(enabled: !compact)
        .onAppear { model.start() }
        .sheet(isPresented: $showingSettings) { SettingsView(model: model) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            QuotaRing(remaining: nil)
            Text("Chaque idée mérite sa place.").font(.title3.weight(.semibold))
            #if os(macOS)
            Text("Connecte ton compte ChatGPT pour garder un œil sur les quotas de Codex, directement dans la barre de menus.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Se connecter avec ChatGPT") { Task { await model.login() } }
                .quotaButton().buttonBorderShape(.capsule)
                .disabled(model.isLoggingIn || model.isRefreshing)
            #else
            Text("Ouvre QuotaBar sur ton Mac et active la synchronisation iCloud sur les deux appareils avec le même compte Apple.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            #endif
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
    }
}
