import Foundation
import Testing
@testable import limitbar

@Test
func metricStatusWarningWhenRemainingBelow20Percent() {
    let status = StatusComputation.metricStatus(limit: 100, remaining: 15)
    #expect(status == .warning)
}

@Test
func metricStatusExhaustedWhenRemainingZero() {
    let status = StatusComputation.metricStatus(limit: 100, remaining: 0)
    #expect(status == .exhausted)
}

@Test
func metricStatusUnknownWhenLimitMissing() {
    let status = StatusComputation.metricStatus(limit: nil, remaining: 40)
    #expect(status == .unknown)
}

@Test
func overallStatusUsesHighestSeverity() {
    let metrics = [
        LimitMetric(name: "A", window: .daily, limit: 100, used: 20, remaining: 80, resetAt: nil, unit: "requests", status: .ok),
        LimitMetric(name: "B", window: .daily, limit: 100, used: 90, remaining: 10, resetAt: nil, unit: "requests", status: .warning),
        LimitMetric(name: "C", window: .daily, limit: 100, used: 100, remaining: 0, resetAt: nil, unit: "requests", status: .exhausted)
    ]

    #expect(StatusComputation.overallStatus(metrics: metrics) == .exhausted)
}

@Test
func warningCountIncludesWarningExhaustedAndError() {
    let snapshots = [
        AccountSnapshot(
            id: "1",
            displayName: "One",
            provider: .codex,
            accountKind: .api,
            metrics: [],
            overallStatus: .ok,
            lastUpdated: Date(),
            sourceInfo: SourceInfo(summary: "", details: [])
        ),
        AccountSnapshot(
            id: "2",
            displayName: "Two",
            provider: .claude,
            accountKind: .api,
            metrics: [],
            overallStatus: .warning,
            lastUpdated: Date(),
            sourceInfo: SourceInfo(summary: "", details: [])
        ),
        AccountSnapshot(
            id: "3",
            displayName: "Three",
            provider: .gemini,
            accountKind: .api,
            metrics: [],
            overallStatus: .error,
            lastUpdated: Date(),
            sourceInfo: SourceInfo(summary: "", details: [])
        )
    ]

    #expect(StatusComputation.warningCount(snapshots: snapshots) == 2)
}
