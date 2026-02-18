import Foundation
import Combine
import OSLog

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var accounts: [AccountConfig] = []
    @Published private(set) var snapshots: [AccountSnapshot] = []
    @Published private(set) var uiConfig: UIConfig = .default
    @Published private(set) var warningCount: Int = 0
    @Published private(set) var overallStatus: OverallStatus = .unknown
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var configPath: String = ""
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var globalErrorMessage: String?

    private let logger = Logger(subsystem: "com.limitbar.app", category: "refresh")
    private let configLoader: ConfigLoader
    private let refreshCoordinator: RefreshCoordinator
    private let refreshIntervalSeconds: TimeInterval

    private var hasStarted = false
    private var timerTask: Task<Void, Never>?

    init(
        configLoader: ConfigLoader = ConfigLoader(),
        refreshCoordinator: RefreshCoordinator = RefreshCoordinator(
            transport: URLSessionHTTPTransport(),
            secrets: EnvSecretResolver()
        ),
        refreshIntervalSeconds: TimeInterval = 60
    ) {
        self.configLoader = configLoader
        self.refreshCoordinator = refreshCoordinator
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.configPath = configLoader.configURL().path
    }

    deinit {
        timerTask?.cancel()
    }

    var menuBarLabel: String {
        var parts: [String] = ["AI"]

        let progressPercent = StatusComputation.aggregateUtilizationPercent(
            snapshots: snapshots,
            mode: uiConfig.menuBar.aggregation
        )

        if uiConfig.menuBar.showMiniBar, let progressPercent {
            parts.append(Self.miniBar(percent: progressPercent))
        }

        if uiConfig.menuBar.showPercentage, let progressPercent {
            parts.append("\(progressPercent)%")
        }

        if uiConfig.menuBar.showWarningCount, warningCount > 0 {
            parts.append("!\(warningCount)")
        }

        return parts.joined(separator: " ")
    }

    func startIfNeeded() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        loadConfig()
        startPolling()
        Task {
            await refresh()
        }
    }

    func reloadConfig() {
        loadConfig()
        Task {
            await refresh()
        }
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    func accountConfig(for accountID: String) -> AccountConfig? {
        accounts.first(where: { $0.id == accountID })
    }

    func accountIcon(for accountID: String, provider: Provider) -> String {
        if let custom = accountConfig(for: accountID)?.iconText, !custom.isEmpty {
            return custom
        }
        return provider.shortLabel
    }

    func accountTag(for accountID: String, fallbackKind: AccountKind) -> String {
        if let config = accountConfig(for: accountID) {
            return config.compactTag
        }
        return fallbackKind.displayName
    }

    private func loadConfig() {
        do {
            let configuration = try configLoader.loadConfiguration()
            accounts = configuration.accounts
            uiConfig = configuration.ui
            configPath = configLoader.configURL().path
            globalErrorMessage = nil
            logger.info("Loaded \(self.accounts.count) account(s) from config")
        } catch {
            accounts = []
            snapshots = []
            uiConfig = .default
            warningCount = 0
            overallStatus = .error
            globalErrorMessage = error.localizedDescription
            logger.error("Failed loading config: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startPolling() {
        timerTask?.cancel()

        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(refreshIntervalSeconds))
                if Task.isCancelled {
                    break
                }
                await refresh()
            }
        }
    }

    private func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        guard !accounts.isEmpty else {
            snapshots = []
            warningCount = 0
            overallStatus = globalErrorMessage == nil ? .unknown : .error
            lastUpdated = Date()
            return
        }

        let result = await refreshCoordinator.refresh(accounts: accounts)
        snapshots = result
        warningCount = StatusComputation.warningCount(snapshots: result)
        overallStatus = StatusComputation.overallAppStatus(snapshots: result)
        lastUpdated = Date()
        logger.info("Refresh complete for \(result.count) account(s)")
    }

    private static func miniBar(percent: Int) -> String {
        let clamped = max(0, min(100, percent))
        let slots = 5
        let filled = Int((Double(clamped) / 100 * Double(slots)).rounded(.toNearestOrAwayFromZero))
        return String(repeating: "▰", count: filled) + String(repeating: "▱", count: max(0, slots - filled))
    }
}
