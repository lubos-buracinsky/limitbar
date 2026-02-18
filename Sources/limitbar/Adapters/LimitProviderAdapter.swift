import Foundation

protocol LimitProviderAdapter: Sendable {
    var provider: Provider { get }
    func fetch(account: AccountConfig) async -> AccountSnapshot
}
