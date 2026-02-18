import AppKit
import SwiftUI

struct LimitbarMenuView: View {
    @ObservedObject var state: AppState
    @State private var expandedAccountIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let globalErrorMessage = state.globalErrorMessage {
                        ErrorCardView(message: globalErrorMessage)
                    }

                    if state.accounts.isEmpty {
                        EmptyConfigView(configPath: state.configPath)
                    } else {
                        ForEach(Provider.allCases) { provider in
                            let providerSnapshots = state.snapshots.filter { $0.provider == provider }
                            if !providerSnapshots.isEmpty {
                                ProviderSectionView(
                                    state: state,
                                    provider: provider,
                                    snapshots: providerSnapshots,
                                    expandedAccountIDs: $expandedAccountIDs,
                                    rowConfig: state.uiConfig.row
                                )
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 420)

            Divider()
            footer
        }
        .padding(12)
        .onAppear {
            state.startIfNeeded()
            applyDefaultExpansionIfNeeded()
        }
        .onChange(of: state.snapshots) { _, _ in
            applyDefaultExpansionIfNeeded()
        }
        .onChange(of: state.uiConfig.row.detailsCollapsedByDefault) { _, _ in
            applyDefaultExpansionIfNeeded(force: true)
        }
    }

    private var header: some View {
        HStack {
            Text("Limitbar")
                .font(.headline)
            Spacer()

            if let progress = StatusComputation.aggregateUtilizationPercent(
                snapshots: state.snapshots,
                mode: state.uiConfig.menuBar.aggregation
            ) {
                CompactProgressBar(
                    ratio: Double(progress) / 100,
                    width: 78,
                    tint: statusColor(state.overallStatus)
                )
            }

            Text(state.overallStatus.label)
                .font(.caption)
                .foregroundStyle(statusColor(state.overallStatus))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(state.isRefreshing ? "Refreshing..." : "Refresh") {
                    state.refreshNow()
                }
                .disabled(state.isRefreshing)

                Button("Reload config") {
                    state.reloadConfig()
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }

            if let lastUpdated = state.lastUpdated {
                Text("Updated: \(lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applyDefaultExpansionIfNeeded(force: Bool = false) {
        guard !state.uiConfig.row.detailsCollapsedByDefault else {
            if force {
                expandedAccountIDs = []
            }
            return
        }

        let allIDs = Set(state.snapshots.map(\.id))
        if force || expandedAccountIDs != allIDs {
            expandedAccountIDs = allIDs
        }
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

private struct ProviderSectionView: View {
    @ObservedObject var state: AppState
    let provider: Provider
    let snapshots: [AccountSnapshot]
    @Binding var expandedAccountIDs: Set<String>
    let rowConfig: RowUIConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(snapshots) { snapshot in
                DisclosureGroup(
                    isExpanded: binding(for: snapshot.id)
                ) {
                    AccountDetailView(snapshot: snapshot)
                        .padding(.top, 6)
                } label: {
                    CompactAccountRow(
                        snapshot: snapshot,
                        icon: state.accountIcon(for: snapshot.id, provider: snapshot.provider),
                        tag: state.accountTag(for: snapshot.id, fallbackKind: snapshot.accountKind),
                        rowConfig: rowConfig
                    )
                }
                .padding(8)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func binding(for accountID: String) -> Binding<Bool> {
        Binding(
            get: { expandedAccountIDs.contains(accountID) },
            set: { expanded in
                if expanded {
                    expandedAccountIDs.insert(accountID)
                } else {
                    expandedAccountIDs.remove(accountID)
                }
            }
        )
    }
}

private struct CompactAccountRow: View {
    let snapshot: AccountSnapshot
    let icon: String
    let tag: String
    let rowConfig: RowUIConfig

    var body: some View {
        HStack(spacing: 8) {
            FaviconBadge(provider: snapshot.provider, iconText: icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(tag)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if rowConfig.showPercentage {
                Text(percentText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            CompactProgressBar(
                ratio: utilizationRatio,
                width: CGFloat(max(56, min(rowConfig.progressWidth, 220))),
                tint: statusColor(snapshot.overallStatus)
            )
        }
    }

    private var utilizationRatio: Double? {
        StatusComputation.snapshotUtilizationRatio(snapshot: snapshot)
    }

    private var percentText: String {
        guard let percent = StatusComputation.snapshotUtilizationPercent(snapshot: snapshot) else {
            return "--"
        }
        return "\(percent)%"
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

private struct AccountDetailView: View {
    let snapshot: AccountSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if snapshot.metrics.isEmpty {
                Text(snapshot.sourceInfo.details.first ?? "No metrics available")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.metrics) { metric in
                    MetricDetailRow(metric: metric)
                }
            }

            Text(snapshot.sourceInfo.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(snapshot.sourceInfo.details, id: \.self) { detail in
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.leading, 4)
    }
}

private struct MetricDetailRow: View {
    let metric: LimitMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(metric.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(metric.window.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(metricValueText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            CompactProgressBar(
                ratio: StatusComputation.utilizationRatio(metric: metric),
                width: 180,
                tint: color(for: metric.status)
            )
        }
    }

    private var metricValueText: String {
        let usedText = formatNumber(metric.used)
        let limitText = formatNumber(metric.limit)

        if let usedText, let limitText {
            return "\(usedText)/\(limitText)"
        }

        if let remaining = metric.remaining {
            let remainingText = formatNumber(remaining) ?? "-"
            return "left \(remainingText)"
        }

        if let usedText {
            return usedText
        }

        if let limitText {
            return "limit \(limitText)"
        }

        return "--"
    }

    private func formatNumber(_ value: Double?) -> String? {
        guard let value else {
            return nil
        }
        if abs(value.rounded() - value) < 0.0001 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private func color(for status: MetricStatus) -> Color {
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

private struct CompactProgressBar: View {
    let ratio: Double?
    let width: CGFloat
    let tint: Color

    var body: some View {
        let clamped = max(0, min(1, ratio ?? 0))

        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: width, height: 7)

            Capsule()
                .fill(tint.opacity(ratio == nil ? 0.28 : 0.9))
                .frame(width: width * clamped, height: 7)

            if ratio == nil {
                Text("--")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: width, alignment: .center)
            }
        }
    }
}

private struct FaviconBadge: View {
    let provider: Provider
    let iconText: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
                .frame(width: 18, height: 18)
            Text(iconText.prefix(2))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private var backgroundColor: Color {
        switch provider {
        case .claude:
            return Color.orange
        case .codex:
            return Color.green
        case .gemini:
            return Color.blue
        }
    }
}

private struct EmptyConfigView: View {
    let configPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No accounts configured")
                .font(.callout.weight(.semibold))
            Text("Create this file and add your account definitions:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(configPath)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .padding(8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ErrorCardView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Config error")
                .font(.callout.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.red.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
