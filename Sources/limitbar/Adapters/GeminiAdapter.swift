import Foundation

struct GeminiAdapter: LimitProviderAdapter {
    let provider: Provider = .gemini

    private let transport: HTTPTransport
    private let secrets: EnvSecretResolver
    private let now: @Sendable () -> Date

    init(
        transport: HTTPTransport,
        secrets: EnvSecretResolver,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.secrets = secrets
        self.now = now
    }

    func fetch(account: AccountConfig) async -> AccountSnapshot {
        let currentDate = now()

        guard account.accountKind == .api else {
            return AccountSnapshot.notAvailable(
                for: account,
                reason: "Public API does not expose remaining limits for Gemini subscription accounts.",
                now: currentDate
            )
        }

        guard let project = secrets.googleProject(for: account), !project.isEmpty else {
            return AccountSnapshot.error(
                for: account,
                message: "Missing project: LIMITBAR_GCP_PROJECT_\(account.id.uppercased())",
                now: currentDate
            )
        }

        guard let token = secrets.googleOAuthToken(for: account), !token.isEmpty else {
            return AccountSnapshot.error(
                for: account,
                message: "Missing OAuth token: LIMITBAR_GOOGLE_OAUTH_TOKEN_\(account.id.uppercased())",
                now: currentDate
            )
        }

        do {
            let metrics = try await fetchQuotaMetrics(project: project, oauthToken: token)
            let overall = StatusComputation.overallStatus(metrics: metrics, fallback: .unknown)
            return AccountSnapshot(
                id: account.id,
                displayName: account.displayName,
                provider: account.provider,
                accountKind: account.accountKind,
                metrics: metrics,
                overallStatus: overall,
                lastUpdated: currentDate,
                sourceInfo: SourceInfo(
                    summary: "Google Service Usage API",
                    details: ["Quota limits for generativelanguage.googleapis.com"]
                )
            )
        } catch {
            return AccountSnapshot.error(
                for: account,
                message: error.localizedDescription,
                now: currentDate
            )
        }
    }

    private func fetchQuotaMetrics(project: String, oauthToken: String) async throws -> [LimitMetric] {
        guard let url = URL(string: "https://serviceusage.googleapis.com/v1/projects/\(project)/services/generativelanguage.googleapis.com/consumerQuotaMetrics?view=FULL") else {
            throw LimitbarError.invalidResponse("Invalid Google quota URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "GET"
        request.setValue("Bearer \(oauthToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let response = try await transport.send(request)
        let object = try HTTPHelpers.jsonObject(from: response.data)

        guard let root = object as? [String: Any] else {
            throw LimitbarError.parsing("Invalid Service Usage payload")
        }

        let rawMetrics = root["consumerQuotaMetrics"] as? [[String: Any]] ?? []
        var metrics: [LimitMetric] = []

        for rawMetric in rawMetrics {
            let metricName = (rawMetric["displayName"] as? String) ?? (rawMetric["metric"] as? String) ?? "Quota"
            let limits = rawMetric["consumerQuotaLimits"] as? [[String: Any]] ?? []

            for limit in limits {
                let limitName = (limit["displayName"] as? String) ?? (limit["name"] as? String) ?? "Limit"
                let unit = (limit["unit"] as? String) ?? "quota"
                let effectiveLimit = extractEffectiveLimit(from: limit)
                let window = inferWindow(from: unit)

                let metric = LimitMetric(
                    id: "\(metricName)-\(limitName)-\(unit)",
                    name: "\(metricName) / \(limitName)",
                    window: window,
                    limit: effectiveLimit,
                    used: nil,
                    remaining: nil,
                    resetAt: nil,
                    unit: unit,
                    status: .unknown
                )
                metrics.append(metric)
            }
        }

        if metrics.isEmpty {
            throw LimitbarError.parsing("No quota metrics returned for the configured project")
        }

        return Array(metrics.prefix(8))
    }

    private func extractEffectiveLimit(from limitEntry: [String: Any]) -> Double? {
        let buckets = limitEntry["quotaBuckets"] as? [[String: Any]] ?? []
        for bucket in buckets {
            if let effective = HTTPHelpers.parseDouble(bucket["effectiveLimit"]) {
                return effective
            }
            if let `default` = HTTPHelpers.parseDouble(bucket["defaultLimit"]) {
                return `default`
            }
        }
        return nil
    }

    private func inferWindow(from unit: String) -> WindowKind {
        let lower = unit.lowercased()
        if lower.contains("minute") {
            return .rpm
        }
        if lower.contains("day") {
            return .daily
        }
        if lower.contains("week") {
            return .weekly
        }
        return .custom
    }
}
