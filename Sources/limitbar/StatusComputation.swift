import Foundation

enum StatusComputation {
    static func metricStatus(limit: Double?, remaining: Double?) -> MetricStatus {
        guard let limit, limit > 0 else {
            return .unknown
        }
        guard let remaining else {
            return .unknown
        }
        if remaining <= 0 {
            return .exhausted
        }
        let ratio = remaining / limit
        if ratio <= 0.20 {
            return .warning
        }
        return .ok
    }

    static func metricStatus(limit: Double?, used: Double?) -> MetricStatus {
        guard let limit, limit > 0 else {
            return .unknown
        }
        guard let used else {
            return .unknown
        }
        let remaining = limit - used
        return metricStatus(limit: limit, remaining: remaining)
    }

    static func overallStatus(metrics: [LimitMetric], fallback: OverallStatus = .unknown) -> OverallStatus {
        guard !metrics.isEmpty else {
            return fallback
        }

        let maxStatus = metrics.reduce(MetricStatus.ok) { current, metric in
            max(current, metric.status)
        }

        switch maxStatus {
        case .ok:
            return .ok
        case .warning:
            return .warning
        case .exhausted:
            return .exhausted
        case .unknown:
            return .unknown
        case .error:
            return .error
        }
    }

    static func warningCount(snapshots: [AccountSnapshot]) -> Int {
        snapshots.filter { snapshot in
            snapshot.overallStatus == .warning || snapshot.overallStatus == .exhausted || snapshot.overallStatus == .error
        }.count
    }

    static func overallAppStatus(snapshots: [AccountSnapshot]) -> OverallStatus {
        guard !snapshots.isEmpty else {
            return .unknown
        }
        return snapshots.reduce(OverallStatus.ok) { partial, snapshot in
            max(partial, snapshot.overallStatus)
        }
    }

    static func utilizationRatio(metric: LimitMetric) -> Double? {
        if let limit = metric.limit, limit > 0 {
            if let used = metric.used {
                return clampedRatio(used / limit)
            }
            if let remaining = metric.remaining {
                return clampedRatio(1 - (remaining / limit))
            }
        }
        return nil
    }

    static func utilizationRatio(metrics: [LimitMetric]) -> Double? {
        let ratios = metrics.compactMap(utilizationRatio(metric:))
        guard !ratios.isEmpty else {
            return nil
        }
        return ratios.max()
    }

    static func utilizationPercent(metrics: [LimitMetric]) -> Int? {
        guard let ratio = utilizationRatio(metrics: metrics) else {
            return nil
        }
        return Int((ratio * 100).rounded())
    }

    static func snapshotUtilizationRatio(snapshot: AccountSnapshot) -> Double? {
        utilizationRatio(metrics: snapshot.metrics)
    }

    static func snapshotUtilizationPercent(snapshot: AccountSnapshot) -> Int? {
        utilizationPercent(metrics: snapshot.metrics)
    }

    static func aggregateUtilizationPercent(snapshots: [AccountSnapshot], mode: ProgressAggregation) -> Int? {
        let ratios = snapshots.compactMap(snapshotUtilizationRatio(snapshot:))
        guard !ratios.isEmpty else {
            return nil
        }

        let ratio: Double
        switch mode {
        case .worst:
            ratio = ratios.max() ?? 0
        case .average:
            ratio = ratios.reduce(0, +) / Double(ratios.count)
        }

        return Int((ratio * 100).rounded())
    }

    private static func clampedRatio(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}
