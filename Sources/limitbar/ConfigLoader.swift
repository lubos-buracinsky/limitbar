import Foundation

struct ConfigLoader {
    static let configPathEnv = "LIMITBAR_CONFIG_PATH"
    static let defaultConfigPath = "~/.config/limitbar/accounts.json"

    private let fileManager: FileManager
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func configURL() -> URL {
        let configuredPath = environment[Self.configPathEnv] ?? Self.defaultConfigPath
        let expanded = NSString(string: configuredPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    func loadConfiguration() throws -> AppConfiguration {
        let path = configURL()
        guard fileManager.fileExists(atPath: path.path) else {
            return AppConfiguration(accounts: [], ui: .default)
        }

        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()

        do {
            let config = try decoder.decode(AccountsConfigFile.self, from: data)
            return AppConfiguration(
                accounts: config.accounts.filter { $0.enabled },
                ui: config.ui ?? .default
            )
        } catch {
            throw LimitbarError.invalidConfig("Failed to decode \(path.path): \(error.localizedDescription)")
        }
    }

    func loadAccounts() throws -> [AccountConfig] {
        try loadConfiguration().accounts
    }
}
