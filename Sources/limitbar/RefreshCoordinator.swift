import Foundation

@MainActor
struct RefreshCoordinator {
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

    func refresh(accounts: [AccountConfig]) async -> [AccountSnapshot] {
        var snapshots: [AccountSnapshot] = []

        for account in accounts {
            let adapter = adapter(for: account)
            let snapshot = await adapter.fetch(account: account)
            snapshots.append(snapshot)
        }

        return snapshots.sorted { lhs, rhs in
            if lhs.provider == rhs.provider {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return lhs.provider.rawValue < rhs.provider.rawValue
        }
    }

    private func adapter(for account: AccountConfig) -> any LimitProviderAdapter {
        if account.settings["demo"]?.lowercased() == "true" {
            return DemoDataAdapter(provider: account.provider, now: now)
        }

        if account.accountKind == .subscription {
            return UnsupportedSubscriptionAdapter(provider: account.provider, now: now)
        }

        switch account.provider {
        case .codex:
            return OpenAIAdapter(transport: transport, secrets: secrets, now: now)
        case .claude:
            return AnthropicAdapter(transport: transport, secrets: secrets, now: now)
        case .gemini:
            return GeminiAdapter(transport: transport, secrets: secrets, now: now)
        }
    }
}
