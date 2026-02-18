import AppKit
import SwiftUI

final class LimitbarAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

@main
struct LimitbarApp: App {
    @NSApplicationDelegateAdaptor(LimitbarAppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            LimitbarMenuView(state: state)
                .frame(minWidth: 420)
        } label: {
            MenuBarWidgetLabel(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarWidgetLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: -2) {
                ForEach(visibleProviders.prefix(3)) { provider in
                    ProviderDot(provider: provider)
                }
            }

            if state.uiConfig.menuBar.showMiniBar {
                MiniWidgetProgressBar(
                    ratio: aggregateProgress.map { Double($0) / 100 },
                    tint: statusColor(state.overallStatus)
                )
            }

            if state.uiConfig.menuBar.showPercentage {
                Text(progressText)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }

            if state.uiConfig.menuBar.showWarningCount, state.warningCount > 0 {
                Text("\(state.warningCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(Color.red)
                    )
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.08))
        )
        .overlay(
            Capsule()
                .strokeBorder(statusColor(state.overallStatus).opacity(0.35), lineWidth: 0.9)
        )
    }

    private var aggregateProgress: Int? {
        StatusComputation.aggregateUtilizationPercent(
            snapshots: state.snapshots,
            mode: state.uiConfig.menuBar.aggregation
        )
    }

    private var progressText: String {
        guard let aggregateProgress else {
            return "--"
        }
        return "\(aggregateProgress)%"
    }

    private var visibleProviders: [Provider] {
        let snapshotProviders = Set(state.snapshots.map(\.provider))
        if !snapshotProviders.isEmpty {
            return Provider.allCases.filter { snapshotProviders.contains($0) }
        }

        let configuredProviders = Set(state.accounts.map(\.provider))
        if !configuredProviders.isEmpty {
            return Provider.allCases.filter { configuredProviders.contains($0) }
        }

        return Provider.allCases
    }

    private func statusColor(_ status: OverallStatus) -> Color {
        switch status {
        case .ok:
            return .green
        case .warning:
            return .orange
        case .exhausted, .error:
            return .red
        case .unknown:
            return .secondary
        }
    }
}

private struct ProviderDot: View {
    let provider: Provider

    var body: some View {
        Text(provider.shortLabel)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 12, height: 12)
            .background(
                Circle()
                    .fill(color(for: provider))
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
            )
    }

    private func color(for provider: Provider) -> Color {
        switch provider {
        case .claude:
            return .orange
        case .codex:
            return .green
        case .gemini:
            return .blue
        }
    }
}

private struct MiniWidgetProgressBar: View {
    let ratio: Double?
    let tint: Color

    var body: some View {
        let width: CGFloat = 26
        let clamped = max(0, min(1, ratio ?? 0))

        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.secondary.opacity(0.22))
                .frame(width: width, height: 6)

            Capsule()
                .fill(tint.opacity(ratio == nil ? 0.35 : 0.95))
                .frame(width: width * clamped, height: 6)
        }
    }
}
