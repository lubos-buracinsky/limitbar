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
                        ForEach(WindowSection.allCases) { section in
                            let providerGroups = providerGroups(for: section)
                            if !providerGroups.isEmpty {
                                WindowSectionView(
                                    state: state,
                                    section: section,
                                    providerGroups: providerGroups,
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

        let allIDs = Set(
            WindowSection.allCases.flatMap { section in
                providerGroups(for: section).flatMap { group in
                    group.snapshots.map(\.id)
                }
            }
        )
        if force || expandedAccountIDs != allIDs {
            expandedAccountIDs = allIDs
        }
    }

    private func providerGroups(for section: WindowSection) -> [WindowProviderGroup] {
        let grouped = Dictionary(grouping: state.snapshots.map { snapshot in
            let metrics = snapshot.metrics.filter { section.windows.contains($0.window) }
            return WindowGroupedSnapshot(section: section, snapshot: snapshot, metrics: metrics)
        }, by: { $0.snapshot.provider })

        return Provider.allCases.compactMap { provider in
            guard let snapshots = grouped[provider], !snapshots.isEmpty else {
                return nil
            }
            let sortedSnapshots = snapshots.sorted { lhs, rhs in
                let lhsTag = state.accountTag(for: lhs.snapshot.id, fallbackKind: lhs.snapshot.accountKind)
                let rhsTag = state.accountTag(for: rhs.snapshot.id, fallbackKind: rhs.snapshot.accountKind)
                return lhsTag.localizedCaseInsensitiveCompare(rhsTag) == .orderedAscending
            }
            return WindowProviderGroup(section: section, provider: provider, snapshots: sortedSnapshots)
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

private enum WindowSection: String, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var windows: Set<WindowKind> {
        switch self {
        case .daily:
            return [.daily, .rpd]
        case .weekly:
            return [.weekly]
        }
    }
}

private struct WindowGroupedSnapshot: Identifiable {
    let section: WindowSection
    let snapshot: AccountSnapshot
    let metrics: [LimitMetric]

    var id: String {
        "\(snapshot.id)-\(section.rawValue)"
    }

    var status: OverallStatus {
        StatusComputation.overallStatus(metrics: metrics, fallback: .unknown)
    }

    var emptyMessage: String {
        "No \(section.title.lowercased()) limits available for this account."
    }
}

private struct WindowProviderGroup: Identifiable {
    let section: WindowSection
    let provider: Provider
    let snapshots: [WindowGroupedSnapshot]

    var id: String {
        "\(section.rawValue)-\(provider.rawValue)"
    }
}

private struct WindowSectionView: View {
    @ObservedObject var state: AppState
    let section: WindowSection
    let providerGroups: [WindowProviderGroup]
    @Binding var expandedAccountIDs: Set<String>
    let rowConfig: RowUIConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(providerGroups) { providerGroup in
                VStack(alignment: .leading, spacing: 4) {
                    Text(providerGroup.provider.displayName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    ForEach(providerGroup.snapshots) { grouped in
                        DisclosureGroup(
                            isExpanded: binding(for: grouped.id)
                        ) {
                            AccountDetailView(
                                snapshot: grouped.snapshot,
                                metrics: grouped.metrics,
                                emptyMessage: grouped.emptyMessage
                            )
                                .padding(.top, 6)
                        } label: {
                            CompactAccountRow(
                                snapshot: grouped.snapshot,
                                metrics: grouped.metrics,
                                status: grouped.status,
                                iconText: state.accountIcon(for: grouped.snapshot.id, provider: grouped.snapshot.provider),
                                iconURL: state.accountIconURL(for: grouped.snapshot.id, provider: grouped.snapshot.provider),
                                tag: state.accountTag(for: grouped.snapshot.id, fallbackKind: grouped.snapshot.accountKind),
                                rowConfig: rowConfig
                            )
                        }
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
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
    let metrics: [LimitMetric]
    let status: OverallStatus
    let iconText: String
    let iconURL: URL?
    let tag: String
    let rowConfig: RowUIConfig

    var body: some View {
        HStack(spacing: 8) {
            FaviconBadge(provider: snapshot.provider, iconText: iconText, iconURL: iconURL)

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
                tint: statusColor(status)
            )
        }
    }

    private var utilizationRatio: Double? {
        StatusComputation.utilizationRatio(metrics: metrics)
    }

    private var percentText: String {
        guard let percent = StatusComputation.utilizationPercent(metrics: metrics) else {
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
    let metrics: [LimitMetric]
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if metrics.isEmpty {
                Text(emptyMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(metrics) { metric in
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
    let iconURL: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor.opacity(0.18))
                .frame(width: 18, height: 18)

            iconContent
                .frame(width: 14, height: 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var iconContent: some View {
        if let iconURL {
            AsyncImage(url: iconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    fallbackText
                }
            }
        } else {
            fallbackText
        }
    }

    private var fallbackText: some View {
        Text(String(iconText.prefix(2)))
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(backgroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
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
