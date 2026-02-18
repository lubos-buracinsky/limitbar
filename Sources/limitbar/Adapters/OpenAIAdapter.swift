import Foundation

struct OpenAIAdapter: LimitProviderAdapter {
    let provider: Provider = .codex

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
                reason: "Public API does not expose remaining limits for subscription Codex usage.",
                now: currentDate
            )
        }

        guard let apiKey = secrets.openAIAdminKey(for: account) else {
            return AccountSnapshot.error(
                for: account,
                message: "Missing secret: LIMITBAR_OPENAI_ADMIN_KEY_\(account.id.uppercased())",
                now: currentDate
            )
        }

        let start = currentDate.addingTimeInterval(-86_400)
        var metrics: [LimitMetric] = []
        var details: [String] = []

        do {
            let costUSD = try await fetchCostUSD(apiKey: apiKey, start: start, end: currentDate)
            let budget = numberSetting(keys: ["dailyBudgetUSD", "budgetUSD"], from: account)
            let remainingBudget = budget.map { $0 - costUSD }
            metrics.append(
                LimitMetric(
                    name: "Cost (24h)",
                    window: .daily,
                    limit: budget,
                    used: costUSD,
                    remaining: remainingBudget,
                    resetAt: nil,
                    unit: "usd",
                    status: StatusComputation.metricStatus(limit: budget, used: costUSD)
                )
            )
        } catch {
            details.append("Cost endpoint failed: \(error.localizedDescription)")
        }

        do {
            let usage = try await fetchUsage(apiKey: apiKey, start: start, end: currentDate)
            metrics.append(
                LimitMetric(
                    name: "Model Requests (24h)",
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
            let rate = try await probeRateLimit(apiKey: apiKey, now: currentDate)
            if rate.requestLimit != nil || rate.requestRemaining != nil {
                metrics.append(
                    LimitMetric(
                        name: "Requests",
                        window: .rpm,
                        limit: rate.requestLimit,
                        used: rate.requestUsed,
                        remaining: rate.requestRemaining,
                        resetAt: rate.requestReset,
                        unit: "requests/min",
                        status: StatusComputation.metricStatus(limit: rate.requestLimit, remaining: rate.requestRemaining)
                    )
                )
            }

            if rate.tokenLimit != nil || rate.tokenRemaining != nil {
                metrics.append(
                    LimitMetric(
                        name: "Tokens",
                        window: .tpm,
                        limit: rate.tokenLimit,
                        used: rate.tokenUsed,
                        remaining: rate.tokenRemaining,
                        resetAt: rate.tokenReset,
                        unit: "tokens/min",
                        status: StatusComputation.metricStatus(limit: rate.tokenLimit, remaining: rate.tokenRemaining)
                    )
                )
            }
        } catch {
            details.append("Rate-limit probe failed: \(error.localizedDescription)")
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
                summary: "OpenAI public APIs",
                details: details.isEmpty ? ["Usage + costs + rate-limit headers"] : details
            )
        )
    }

    private func fetchCostUSD(apiKey: String, start: Date, end: Date) async throws -> Double {
        let startTimestamp = Int(start.timeIntervalSince1970)
        let endTimestamp = Int(end.timeIntervalSince1970)
        guard let url = URL(string: "https://api.openai.com/v1/organization/costs?start_time=\(startTimestamp)&end_time=\(endTimestamp)") else {
            throw LimitbarError.invalidResponse("Invalid OpenAI costs URL")
        }

        let response = try await transport.send(makeRequest(url: url, apiKey: apiKey))
        let object = try HTTPHelpers.jsonObject(from: response.data)
        return sumCostUSD(in: object)
    }

    private func fetchUsage(apiKey: String, start: Date, end: Date) async throws -> (requests: Double?, inputTokens: Double?, outputTokens: Double?) {
        let startTimestamp = Int(start.timeIntervalSince1970)
        let endTimestamp = Int(end.timeIntervalSince1970)

        guard let url = URL(string: "https://api.openai.com/v1/organization/usage/completions?start_time=\(startTimestamp)&end_time=\(endTimestamp)") else {
            throw LimitbarError.invalidResponse("Invalid OpenAI usage URL")
        }

        let response = try await transport.send(makeRequest(url: url, apiKey: apiKey))
        let object = try HTTPHelpers.jsonObject(from: response.data)

        let requests = sumNumeric(keys: ["num_model_requests", "request_count"], in: object)
        let inputTokens = sumNumeric(keys: ["input_tokens"], in: object)
        let outputTokens = sumNumeric(keys: ["output_tokens"], in: object)

        return (
            requests: requests > 0 ? requests : nil,
            inputTokens: inputTokens > 0 ? inputTokens : nil,
            outputTokens: outputTokens > 0 ? outputTokens : nil
        )
    }

    private func probeRateLimit(apiKey: String, now: Date) async throws -> RateLimitProbe {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            throw LimitbarError.invalidResponse("Invalid OpenAI probe URL")
        }

        let response = try await transport.send(makeRequest(url: url, apiKey: apiKey))
        let headers = response.response

        let requestLimit = HTTPHelpers.parseDouble(HTTPHelpers.stringHeader(headers, key: "x-ratelimit-limit-requests"))
        let requestRemaining = HTTPHelpers.parseDouble(HTTPHelpers.stringHeader(headers, key: "x-ratelimit-remaining-requests"))
        let requestReset = HTTPHelpers.parseRateResetHeader(
            HTTPHelpers.stringHeader(headers, key: "x-ratelimit-reset-requests"),
            now: now
        )

        let tokenLimit = HTTPHelpers.parseDouble(HTTPHelpers.stringHeader(headers, key: "x-ratelimit-limit-tokens"))
        let tokenRemaining = HTTPHelpers.parseDouble(HTTPHelpers.stringHeader(headers, key: "x-ratelimit-remaining-tokens"))
        let tokenReset = HTTPHelpers.parseRateResetHeader(
            HTTPHelpers.stringHeader(headers, key: "x-ratelimit-reset-tokens"),
            now: now
        )

        return RateLimitProbe(
            requestLimit: requestLimit,
            requestRemaining: requestRemaining,
            requestReset: requestReset,
            tokenLimit: tokenLimit,
            tokenRemaining: tokenRemaining,
            tokenReset: tokenReset
        )
    }

    private func makeRequest(url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

            if let amount = dictionary["amount"] as? [String: Any], let value = HTTPHelpers.parseDouble(amount["value"]) {
                total += value
            }

            if let value = HTTPHelpers.parseDouble(dictionary["cost_usd"]) {
                total += value
            }

            if let value = HTTPHelpers.parseDouble(dictionary["total_cost_usd"]) {
                total += value
            }

            for (key, value) in dictionary where key != "amount" {
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

private struct RateLimitProbe: Sendable {
    let requestLimit: Double?
    let requestRemaining: Double?
    let requestReset: Date?

    let tokenLimit: Double?
    let tokenRemaining: Double?
    let tokenReset: Date?

    var requestUsed: Double? {
        guard let requestLimit, let requestRemaining else {
            return nil
        }
        return max(0, requestLimit - requestRemaining)
    }

    var tokenUsed: Double? {
        guard let tokenLimit, let tokenRemaining else {
            return nil
        }
        return max(0, tokenLimit - tokenRemaining)
    }
}
