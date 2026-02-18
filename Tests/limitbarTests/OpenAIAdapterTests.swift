import Foundation
import Testing
@testable import limitbar

@Test
func fetchBuildsMetricsFromPublicEndpoints() async {
    let transport = MockTransport { request in
        let url = request.url!.absoluteString
        if url.contains("/v1/organization/costs") {
            let data = """
            {"data":[{"amount":{"value":1.5}},{"amount":{"value":2.0}}]}
            """.data(using: .utf8)!
            return result(url: request.url!, status: 200, headers: [:], data: data)
        }

        if url.contains("/v1/organization/usage/completions") {
            let data = """
            {"data":[{"num_model_requests":12,"input_tokens":1200,"output_tokens":500}]}
            """.data(using: .utf8)!
            return result(url: request.url!, status: 200, headers: [:], data: data)
        }

        if url.contains("/v1/models") {
            let data = "{}".data(using: .utf8)!
            let headers = [
                "x-ratelimit-limit-requests": "100",
                "x-ratelimit-remaining-requests": "10",
                "x-ratelimit-reset-requests": "30s"
            ]
            return result(url: request.url!, status: 200, headers: headers, data: data)
        }

        Issue.record("Unexpected URL: \(url)")
        return result(url: request.url!, status: 404, headers: [:], data: Data())
    }

    let resolver = EnvSecretResolver(environment: [
        "LIMITBAR_OPENAI_ADMIN_KEY_TEST_OPENAI": "test-key"
    ])

    let adapter = OpenAIAdapter(
        transport: transport,
        secrets: resolver,
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    let snapshot = await adapter.fetch(account: AccountConfig(
        id: "test-openai",
        displayName: "Test OpenAI",
        provider: .codex,
        accountKind: .api,
        enabled: true,
        settings: ["dailyBudgetUSD": "10"]
    ))

    #expect(snapshot.overallStatus == .warning)
    #expect(snapshot.metrics.count >= 4)

    let costMetric = snapshot.metrics.first(where: { $0.name == "Cost (24h)" })
    #expect(costMetric?.used == 3.5)
    #expect(costMetric?.limit == 10)

    let rateMetric = snapshot.metrics.first(where: { $0.window == .rpm })
    #expect(rateMetric?.status == .warning)
    #expect(rateMetric?.remaining == 10)
}

@Test
func subscriptionReturnsNotAvailable() async {
    let adapter = OpenAIAdapter(
        transport: MockTransport { request in
            Issue.record("No network expected for subscription account: \(request)")
            return result(url: request.url!, status: 500, headers: [:], data: Data())
        },
        secrets: EnvSecretResolver(environment: [:])
    )

    let snapshot = await adapter.fetch(account: AccountConfig(
        id: "sub",
        displayName: "Sub",
        provider: .codex,
        accountKind: .subscription,
        enabled: true,
        settings: [:]
    ))

    #expect(snapshot.overallStatus == .unknown)
    #expect(snapshot.metrics.isEmpty)
    #expect(snapshot.sourceInfo.summary == "Not available")
}

private func result(url: URL, status: Int, headers: [String: String], data: Data) -> HTTPResult {
    let response = HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
    )!
    return HTTPResult(data: data, response: response)
}

private struct MockTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) throws -> HTTPResult

    init(handler: @escaping @Sendable (URLRequest) throws -> HTTPResult) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        try handler(request)
    }
}
