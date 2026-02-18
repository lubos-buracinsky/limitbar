import Foundation
import Testing
@testable import limitbar

@Test
func loadAccountsFromConfiguredPath() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let configURL = tempDir.appendingPathComponent("accounts.json")
    let json = """
    {
      "accounts": [
        {
          "id": "codex_api",
          "displayName": "Codex API",
          "provider": "codex",
          "accountKind": "api",
          "enabled": true,
          "settings": {"dailyBudgetUSD": "20"}
        },
        {
          "id": "claude_disabled",
          "displayName": "Claude Disabled",
          "provider": "claude",
          "accountKind": "api",
          "enabled": false,
          "settings": {}
        }
      ]
    }
    """

    try json.data(using: .utf8)?.write(to: configURL)

    let loader = ConfigLoader(
        fileManager: .default,
        environment: [ConfigLoader.configPathEnv: configURL.path]
    )

    let accounts = try loader.loadAccounts()
    #expect(accounts.count == 1)
    #expect(accounts.first?.id == "codex_api")
}

@Test
func loadReturnsEmptyWhenFileMissing() throws {
    let loader = ConfigLoader(
        fileManager: .default,
        environment: [ConfigLoader.configPathEnv: "/tmp/definitely-missing-limitbar-config.json"]
    )

    let accounts = try loader.loadAccounts()
    #expect(accounts.isEmpty)
}

@Test
func loadConfigurationIncludesUIOverrides() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let configURL = tempDir.appendingPathComponent("accounts.json")
    let json = """
    {
      "ui": {
        "menuBar": {
          "showPercentage": true,
          "showMiniBar": true,
          "showWarningCount": false,
          "aggregation": "average"
        },
        "row": {
          "progressWidth": 180,
          "showPercentage": false,
          "detailsCollapsedByDefault": false
        }
      },
      "accounts": [
        {
          "id": "gemini_api",
          "displayName": "Gemini",
          "provider": "gemini",
          "accountKind": "api",
          "enabled": true,
          "settings": {"tag": "API"}
        }
      ]
    }
    """

    try json.data(using: .utf8)?.write(to: configURL)

    let loader = ConfigLoader(
        fileManager: .default,
        environment: [ConfigLoader.configPathEnv: configURL.path]
    )

    let configuration = try loader.loadConfiguration()
    #expect(configuration.accounts.count == 1)
    #expect(configuration.ui.menuBar.aggregation == .average)
    #expect(configuration.ui.menuBar.showWarningCount == false)
    #expect(configuration.ui.row.progressWidth == 180)
    #expect(configuration.ui.row.showPercentage == false)
    #expect(configuration.ui.row.detailsCollapsedByDefault == false)
}
