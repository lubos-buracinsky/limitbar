import Foundation

enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .gemini:
            return "Gemini"
        }
    }

    var shortLabel: String {
        switch self {
        case .claude:
            return "A"
        case .codex:
            return "C"
        case .gemini:
            return "G"
        }
    }
}

enum AccountKind: String, Codable, Sendable {
    case api
    case subscription

    var displayName: String {
        switch self {
        case .api:
            return "API"
        case .subscription:
            return "Subscription"
        }
    }
}

enum WindowKind: String, Codable, Sendable {
    case session
    case daily
    case weekly
    case rpm
    case tpm
    case rpd
    case custom

    var displayName: String {
        switch self {
        case .session:
            return "Session"
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .rpm:
            return "RPM"
        case .tpm:
            return "TPM"
        case .rpd:
            return "RPD"
        case .custom:
            return "Custom"
        }
    }
}

enum MetricStatus: String, Codable, Comparable, Sendable {
    case ok
    case warning
    case exhausted
    case unknown
    case error

    private var severity: Int {
        switch self {
        case .ok:
            return 0
        case .unknown:
            return 1
        case .warning:
            return 2
        case .exhausted:
            return 3
        case .error:
            return 4
        }
    }

    static func < (lhs: MetricStatus, rhs: MetricStatus) -> Bool {
        lhs.severity < rhs.severity
    }

    var label: String {
        switch self {
        case .ok:
            return "OK"
        case .warning:
            return "Warning"
        case .exhausted:
            return "Exhausted"
        case .unknown:
            return "Unknown"
        case .error:
            return "Error"
        }
    }
}

enum OverallStatus: String, Comparable, Sendable {
    case ok
    case warning
    case exhausted
    case unknown
    case error

    private var severity: Int {
        switch self {
        case .ok:
            return 0
        case .unknown:
            return 1
        case .warning:
            return 2
        case .exhausted:
            return 3
        case .error:
            return 4
        }
    }

    static func < (lhs: OverallStatus, rhs: OverallStatus) -> Bool {
        lhs.severity < rhs.severity
    }

    var label: String {
        switch self {
        case .ok:
            return "OK"
        case .warning:
            return "Warning"
        case .exhausted:
            return "Exhausted"
        case .unknown:
            return "Unknown"
        case .error:
            return "Error"
        }
    }
}

enum ProgressAggregation: String, Codable, Sendable {
    case worst
    case average
}

struct MenuBarUIConfig: Codable, Sendable, Equatable {
    var showPercentage: Bool
    var showMiniBar: Bool
    var showWarningCount: Bool
    var aggregation: ProgressAggregation

    init(
        showPercentage: Bool = true,
        showMiniBar: Bool = true,
        showWarningCount: Bool = true,
        aggregation: ProgressAggregation = .worst
    ) {
        self.showPercentage = showPercentage
        self.showMiniBar = showMiniBar
        self.showWarningCount = showWarningCount
        self.aggregation = aggregation
    }

    enum CodingKeys: String, CodingKey {
        case showPercentage
        case showMiniBar
        case showWarningCount
        case aggregation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.showPercentage = try container.decodeIfPresent(Bool.self, forKey: .showPercentage) ?? true
        self.showMiniBar = try container.decodeIfPresent(Bool.self, forKey: .showMiniBar) ?? true
        self.showWarningCount = try container.decodeIfPresent(Bool.self, forKey: .showWarningCount) ?? true
        self.aggregation = try container.decodeIfPresent(ProgressAggregation.self, forKey: .aggregation) ?? .worst
    }
}

struct RowUIConfig: Codable, Sendable, Equatable {
    var progressWidth: Int
    var showPercentage: Bool
    var detailsCollapsedByDefault: Bool

    init(
        progressWidth: Int = 120,
        showPercentage: Bool = true,
        detailsCollapsedByDefault: Bool = true
    ) {
        self.progressWidth = progressWidth
        self.showPercentage = showPercentage
        self.detailsCollapsedByDefault = detailsCollapsedByDefault
    }

    enum CodingKeys: String, CodingKey {
        case progressWidth
        case showPercentage
        case detailsCollapsedByDefault
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.progressWidth = try container.decodeIfPresent(Int.self, forKey: .progressWidth) ?? 120
        self.showPercentage = try container.decodeIfPresent(Bool.self, forKey: .showPercentage) ?? true
        self.detailsCollapsedByDefault = try container.decodeIfPresent(Bool.self, forKey: .detailsCollapsedByDefault) ?? true
    }
}

struct UIConfig: Codable, Sendable, Equatable {
    var menuBar: MenuBarUIConfig
    var row: RowUIConfig

    static let `default` = UIConfig()

    init(menuBar: MenuBarUIConfig = MenuBarUIConfig(), row: RowUIConfig = RowUIConfig()) {
        self.menuBar = menuBar
        self.row = row
    }

    enum CodingKeys: String, CodingKey {
        case menuBar
        case row
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.menuBar = try container.decodeIfPresent(MenuBarUIConfig.self, forKey: .menuBar) ?? MenuBarUIConfig()
        self.row = try container.decodeIfPresent(RowUIConfig.self, forKey: .row) ?? RowUIConfig()
    }
}

struct LimitMetric: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let window: WindowKind
    let limit: Double?
    let used: Double?
    let remaining: Double?
    let resetAt: Date?
    let unit: String
    let status: MetricStatus

    init(
        id: String? = nil,
        name: String,
        window: WindowKind,
        limit: Double?,
        used: Double?,
        remaining: Double?,
        resetAt: Date?,
        unit: String,
        status: MetricStatus
    ) {
        self.id = id ?? "\(window.rawValue)-\(name)-\(unit)"
        self.name = name
        self.window = window
        self.limit = limit
        self.used = used
        self.remaining = remaining
        self.resetAt = resetAt
        self.unit = unit
        self.status = status
    }
}

struct SourceInfo: Equatable, Sendable {
    let summary: String
    let details: [String]
}

struct AccountSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let provider: Provider
    let accountKind: AccountKind
    let metrics: [LimitMetric]
    let overallStatus: OverallStatus
    let lastUpdated: Date
    let sourceInfo: SourceInfo
}

struct AccountConfig: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let provider: Provider
    let accountKind: AccountKind
    let enabled: Bool
    let settings: [String: String]

    init(
        id: String,
        displayName: String,
        provider: Provider,
        accountKind: AccountKind,
        enabled: Bool = true,
        settings: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.accountKind = accountKind
        self.enabled = enabled
        self.settings = settings
    }

    var iconText: String? {
        settings["icon"]
    }

    var compactTag: String {
        if let tag = settings["tag"], !tag.isEmpty {
            return tag
        }
        return accountKind.displayName
    }
}

struct AccountsConfigFile: Codable, Sendable {
    let accounts: [AccountConfig]
    let ui: UIConfig?
}

struct AppConfiguration: Sendable {
    let accounts: [AccountConfig]
    let ui: UIConfig
}

extension AccountSnapshot {
    static func notAvailable(for account: AccountConfig, reason: String, now: Date = Date()) -> AccountSnapshot {
        AccountSnapshot(
            id: account.id,
            displayName: account.displayName,
            provider: account.provider,
            accountKind: account.accountKind,
            metrics: [],
            overallStatus: .unknown,
            lastUpdated: now,
            sourceInfo: SourceInfo(
                summary: "Not available",
                details: [reason]
            )
        )
    }

    static func error(for account: AccountConfig, message: String, now: Date = Date()) -> AccountSnapshot {
        AccountSnapshot(
            id: account.id,
            displayName: account.displayName,
            provider: account.provider,
            accountKind: account.accountKind,
            metrics: [
                LimitMetric(
                    name: "Provider API",
                    window: .custom,
                    limit: nil,
                    used: nil,
                    remaining: nil,
                    resetAt: nil,
                    unit: "status",
                    status: .error
                )
            ],
            overallStatus: .error,
            lastUpdated: now,
            sourceInfo: SourceInfo(summary: "Request failed", details: [message])
        )
    }
}
