import Foundation

struct EnvSecretResolver: Sendable {
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func openAIAdminKey(for account: AccountConfig) -> String? {
        value(
            baseName: "LIMITBAR_OPENAI_ADMIN_KEY",
            account: account,
            fallbackNames: ["OPENAI_API_KEY"]
        )
    }

    func anthropicAdminKey(for account: AccountConfig) -> String? {
        value(
            baseName: "LIMITBAR_ANTHROPIC_ADMIN_KEY",
            account: account,
            fallbackNames: ["ANTHROPIC_API_KEY"]
        )
    }

    func googleOAuthToken(for account: AccountConfig) -> String? {
        value(
            baseName: "LIMITBAR_GOOGLE_OAUTH_TOKEN",
            account: account,
            fallbackNames: ["GOOGLE_OAUTH_ACCESS_TOKEN"]
        )
    }

    func googleProject(for account: AccountConfig) -> String? {
        if let project = account.settings["gcpProject"], !project.isEmpty {
            return project
        }
        return value(
            baseName: "LIMITBAR_GCP_PROJECT",
            account: account,
            fallbackNames: ["GCP_PROJECT", "GOOGLE_CLOUD_PROJECT"]
        )
    }

    func configValue(for key: String, account: AccountConfig) -> String? {
        if let explicit = account.settings[key], !explicit.isEmpty {
            return explicit
        }
        return value(baseName: key, account: account, fallbackNames: [])
    }

    private func value(baseName: String, account: AccountConfig, fallbackNames: [String]) -> String? {
        let scoped = "\(baseName)_\(normalizedAccountSuffix(account.id))"
        if let scopedValue = environment[scoped], !scopedValue.isEmpty {
            return scopedValue
        }

        if let baseValue = environment[baseName], !baseValue.isEmpty {
            return baseValue
        }

        for fallback in fallbackNames {
            if let value = environment[fallback], !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private func normalizedAccountSuffix(_ accountID: String) -> String {
        let upper = accountID.uppercased()
        let mapped = upper.map { char -> Character in
            if char.isLetter || char.isNumber {
                return char
            }
            return "_"
        }
        return String(mapped)
    }
}
