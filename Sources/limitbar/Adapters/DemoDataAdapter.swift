import Foundation

struct DemoDataAdapter: LimitProviderAdapter {
    let provider: Provider
    private let now: @Sendable () -> Date

    init(provider: Provider, now: @escaping @Sendable () -> Date = Date.init) {
        self.provider = provider
        self.now = now
    }

    func fetch(account: AccountConfig) async -> AccountSnapshot {
        let timestamp = now()
        let metrics = demoMetrics(for: account, at: timestamp)
        let overall = StatusComputation.overallStatus(metrics: metrics, fallback: .unknown)

        return AccountSnapshot(
            id: account.id,
            displayName: account.displayName,
            provider: account.provider,
            accountKind: account.accountKind,
            metrics: metrics,
            overallStatus: overall,
            lastUpdated: timestamp,
            sourceInfo: SourceInfo(
                summary: "Demo data",
                details: ["Rendered from local demo mode (account.settings.demo=true)"]
            )
        )
    }

    private func demoMetrics(for account: AccountConfig, at now: Date) -> [LimitMetric] {
        let seed = abs(account.id.hashValue % 100)

        if account.accountKind == .subscription {
            let sessionLimit = 45.0
            let sessionUsed = Double((seed % 28) + 10)
            let weeklyLimit = 250.0
            let weeklyUsed = Double((seed % 160) + 30)

            return [
                metric(
                    name: "Session Messages",
                    window: .session,
                    limit: sessionLimit,
                    used: sessionUsed,
                    unit: "messages",
                    resetAt: now.addingTimeInterval(3_600)
                ),
                metric(
                    name: "Weekly Messages",
                    window: .weekly,
                    limit: weeklyLimit,
                    used: weeklyUsed,
                    unit: "messages",
                    resetAt: now.addingTimeInterval(5 * 24 * 3_600)
                )
            ]
        }

        let dailyBudget = Double((seed % 8) + 8)
        let dailyUsed = Double(seed % Int(dailyBudget * 100)) / 100
        let rpmLimit = 120.0
        let rpmUsed = Double((seed % 100) + 8)
        let tpmLimit = 120_000.0
        let tpmUsed = Double((seed % 95_000) + 18_000)

        return [
            metric(
                name: "Cost (24h)",
                window: .daily,
                limit: dailyBudget,
                used: dailyUsed,
                unit: "usd",
                resetAt: now.addingTimeInterval(24 * 3_600)
            ),
            metric(
                name: "Requests",
                window: .rpm,
                limit: rpmLimit,
                used: rpmUsed,
                unit: "requests/min",
                resetAt: now.addingTimeInterval(60)
            ),
            metric(
                name: "Tokens",
                window: .tpm,
                limit: tpmLimit,
                used: tpmUsed,
                unit: "tokens/min",
                resetAt: now.addingTimeInterval(60)
            )
        ]
    }

    private func metric(
        name: String,
        window: WindowKind,
        limit: Double,
        used: Double,
        unit: String,
        resetAt: Date?
    ) -> LimitMetric {
        let remaining = max(0, limit - used)
        return LimitMetric(
            name: name,
            window: window,
            limit: limit,
            used: used,
            remaining: remaining,
            resetAt: resetAt,
            unit: unit,
            status: StatusComputation.metricStatus(limit: limit, used: used)
        )
    }
}
