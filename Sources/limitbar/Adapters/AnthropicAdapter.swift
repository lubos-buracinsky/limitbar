import Foundation

struct AnthropicAdapter: LimitProviderAdapter {
    let provider: Provider = .claude

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
                reason: "Public API does not expose remaining limits for Claude subscription sessions.",
                now: currentDate
            )
        }

        guard let apiKey = secrets.anthropicAdminKey(for: account) else {
            return AccountSnapshot.error(
                for: account,
                message: "Missing secret: LIMITBAR_ANTHROPIC_ADMIN_KEY_\(account.id.uppercased())",
                now: currentDate
            )
        }

        let start = currentDate.addingTimeInterval(-86_400)
        var metrics: [LimitMetric] = []
        var details: [String] = []

        do {
            let usage = try await fetchUsage(apiKey: apiKey, start: start, end: currentDate)
            metrics.append(
                LimitMetric(
                    name: "Requests (24h)",
                    window: .daily,
                    limit: nil,
                    used: usage.requests,
                    remaining: nil,
                    resetAt: nil,
                    unit: "requests",
                    status: .unknown
                )
            )
            metrics.append(
                LimitMetric(
                    name: "Input Tokens (24h)",
                    window: .daily,
                    limit: nil,
                    used: usage.inputTokens,
                    remaining: nil,
                    resetAt: nil,
                    unit: "tokens",
                    status: .unknown
                )
            )
            metrics.append(
                LimitMetric(
                    name: "Output Tokens (24h)",
                    window: .daily,
                    limit: nil,
                    used: usage.outputTokens,
                    remaining: nil,
                    resetAt: nil,
                    unit: "tokens",
                    status: .unknown
                )
            )
        } catch {
            details.append("Usage endpoint failed: \(error.localizedDescription)")
        }

        do {
            let cost = try await fetchCostUSD(apiKey: apiKey, start: start, end: currentDate)
            let budget = numberSetting(keys: ["dailyBudgetUSD", "budgetUSD"], from: account)
            metrics.append(
                LimitMetric(
                    name: "Cost (24h)",
                    window: .daily,
                    limit: budget,
                    used: cost,
                    remaining: budget.map { $0 - cost },
                    resetAt: nil,
                    unit: "usd",
                    status: StatusComputation.metricStatus(limit: budget, used: cost)
                )
            )
        } catch {
            details.append("Cost endpoint failed: \(error.localizedDescription)")
        }

        let fallback: OverallStatus = details.isEmpty ? .unknown : .error
        var overallStatus = StatusComputation.overallStatus(metrics: metrics, fallback: fallback)
        if !details.isEmpty && overallStatus == .ok {
            overallStatus = .warning
        }

        return AccountSnapshot(
            id: account.id,
            displayName: account.displayName,
            provider: account.provider,
            accountKind: account.accountKind,
            metrics: metrics,
            overallStatus: overallStatus,
            lastUpdated: currentDate,
            sourceInfo: SourceInfo(
                summary: "Anthropic organization APIs",
                details: details.isEmpty ? ["Usage report + cost report"] : details
            )
        )
    }

    private func fetchUsage(apiKey: String, start: Date, end: Date) async throws -> (requests: Double?, inputTokens: Double?, outputTokens: Double?) {
        let formatter = ISO8601DateFormatter()
        let startText = formatter.string(from: start)
        let endText = formatter.string(from: end)

        guard let url = URL(string: "https://api.anthropic.com/v1/organizations/usage_report/messages?starting_at=\(startText)&ending_at=\(endText)") else {
            throw LimitbarError.invalidResponse("Invalid Anthropic usage URL")
        }

        let response = try await transport.send(makeRequest(url: url, apiKey: apiKey))
        let object = try HTTPHelpers.jsonObject(from: response.data)

        let requests = sumNumeric(keys: ["request_count", "requests"], in: object)
        let inputTokens = sumNumeric(keys: ["input_tokens"], in: object)
        let outputTokens = sumNumeric(keys: ["output_tokens"], in: object)

        return (
            requests: requests > 0 ? requests : nil,
            inputTokens: inputTokens > 0 ? inputTokens : nil,
            outputTokens: outputTokens > 0 ? outputTokens : nil
        )
    }

    private func fetchCostUSD(apiKey: String, start: Date, end: Date) async throws -> Double {
        let formatter = ISO8601DateFormatter()
        let startText = formatter.string(from: start)
        let endText = formatter.string(from: end)

        guard let url = URL(string: "https://api.anthropic.com/v1/organizations/cost_report?starting_at=\(startText)&ending_at=\(endText)") else {
            throw LimitbarError.invalidResponse("Invalid Anthropic cost URL")
        }

        let response = try await transport.send(makeRequest(url: url, apiKey: apiKey))
        let object = try HTTPHelpers.jsonObject(from: response.data)

        return sumCostUSD(in: object)
    }

    private func makeRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func sumNumeric(keys: Set<String>, in object: Any) -> Double {
        switch object {
        case let dictionary as [String: Any]:
            var total = 0.0
            for (key, value) in dictionary {
                if keys.contains(key), let number = HTTPHelpers.parseDouble(value) {
                    total += number
                }
                total += sumNumeric(keys: keys, in: value)
            }
            return total
        case let array as [Any]:
            return array.reduce(0) { $0 + sumNumeric(keys: keys, in: $1) }
        default:
            return 0
        }
    }

    private func sumCostUSD(in object: Any) -> Double {
        switch object {
        case let dictionary as [String: Any]:
            var total = 0.0

            if let value = HTTPHelpers.parseDouble(dictionary["cost_usd"]) {
                total += value
            }

            if let value = HTTPHelpers.parseDouble(dictionary["amount_usd"]) {
                total += value
            }

            for (_, value) in dictionary {
                total += sumCostUSD(in: value)
            }

            return total
        case let array as [Any]:
            return array.reduce(0) { $0 + sumCostUSD(in: $1) }
        default:
            return 0
        }
    }

    private func numberSetting(keys: [String], from account: AccountConfig) -> Double? {
        for key in keys {
            if let value = account.settings[key], let parsed = Double(value) {
                return parsed
            }
        }
        return nil
    }
}
