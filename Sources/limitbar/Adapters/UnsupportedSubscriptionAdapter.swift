import Foundation

struct UnsupportedSubscriptionAdapter: LimitProviderAdapter {
    let provider: Provider
    private let now: @Sendable () -> Date

    init(provider: Provider, now: @escaping @Sendable () -> Date = Date.init) {
        self.provider = provider
        self.now = now
    }

    func fetch(account: AccountConfig) async -> AccountSnapshot {
        AccountSnapshot.notAvailable(
            for: account,
            reason: "Public API does not expose remaining limits for subscription accounts.",
            now: now()
        )
    }
}
