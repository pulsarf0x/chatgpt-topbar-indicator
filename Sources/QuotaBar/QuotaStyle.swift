import SwiftUI

extension Color {
    static let quotaAccent = Color(red: 0.49, green: 0.40, blue: 0.95)
    static func quotaLevel(_ remaining: Double) -> Color {
        remaining <= 10 ? .red : remaining <= 25 ? .orange : .quotaAccent
    }
}

struct QuotaRing: View {
    let remaining: Double?
    var size: CGFloat = 132
    var muted = false
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.07), lineWidth: 10)
            Circle().trim(from: 0, to: (remaining ?? 0) / 100)
                .stroke(muted ? .secondary : Color.quotaLevel(remaining ?? 0), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(remaining.map { "\(Int($0.rounded(.down)))" } ?? "—")
                    .font(.system(size: size * 0.30, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(remaining == nil ? "indisponible" : "% restant")
                    .font(.system(size: size * 0.09, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining.map { "\(Int($0)) pour cent restants" } ?? "Quota indisponible")
    }
}

struct WindowRow: View {
    let window: QuotaWindow
    let now: Date
    var stale = false
    var body: some View {
        let expired = window.isExpired(at: now)
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(window.title).font(.subheadline.weight(.medium))
                Spacer()
                Text(expired ? "À actualiser" : "\(Int(window.remaining.rounded(.down))) %")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(expired || stale ? .secondary : Color.quotaLevel(window.remaining))
            }
            ProgressView(value: expired ? 0 : window.remaining, total: 100)
                .tint(stale ? .secondary : Color.quotaLevel(window.remaining))
            if let reset = window.resetDate {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").font(.caption2)
                    if expired {
                        Text("Échéance passée · actualise les quotas")
                    } else {
                        Text("Réinitialisation")
                        Text(reset, style: .relative)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .help(reset.formatted(date: .complete, time: .shortened))
            } else {
                Text("Date de réinitialisation indisponible").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
