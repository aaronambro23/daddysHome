import XCTest
@testable import DaddyCore

// Assertions are on `usedPercent`, because that is what every provider
// dashboard reports and therefore the only number you can cross-reference
// against one. `remainingPercent` is still derived and still tested, but it is
// no longer what the battery shows.
final class ProviderUsageTests: XCTestCase {
    func testWindowClampsUsageAndComputesRemaining() {
        let low = ProviderUsageWindow(id: "low", label: "Low", usedPercent: -4, resetsAt: nil)
        XCTAssertEqual(low.usedPercent, 0)
        XCTAssertEqual(low.remainingPercent, 100)

        let high = ProviderUsageWindow(id: "high", label: "High", usedPercent: 140, resetsAt: nil)
        XCTAssertEqual(high.usedPercent, 100)
        XCTAssertEqual(high.remainingPercent, 0)
    }

    func testClaudeParsesStructuredWindows() throws {
        let snapshot = try ProviderUsageParser.claude(data("""
        {
          "limits": [
            {"kind":"session","percent":72,"resets_at":"2026-08-18T00:20:00.400332+00:00"},
            {"kind":"weekly_all","percent":18,"resets_at":"2026-08-23T21:00:00.400355+00:00"}
          ]
        }
        """))

        XCTAssertEqual(snapshot.windows.map(\.label), ["Current session", "All models"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [72, 18])
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
    }

    /// The pre-`limits[]` shape, which had no coverage at all. It uses
    /// `utilization` rather than `percent` and a different set of keys, so a
    /// regression here would be silent.
    func testClaudeFallsBackToLegacyUtilizationShape() throws {
        let snapshot = try ProviderUsageParser.claude(data("""
        {
          "five_hour":{"utilization":13,"resets_at":"2026-08-24T05:29:59.668735+00:00"},
          "seven_day":{"utilization":7,"resets_at":"2026-08-30T20:59:59.668755+00:00"}
        }
        """))

        XCTAssertEqual(snapshot.windows.map(\.label), ["Current session", "All models"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [13, 7])
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
    }

    func testOpenCodeParsesAllThreeWindows() throws {
        let snapshot = try ProviderUsageParser.openCode(data("""
        {
          "usage": {
            "rolling":{"status":"ok","percent":2,"resetsAt":"2026-08-18T02:41:49.197Z"},
            "weekly":{"status":"ok","percent":27,"resetsAt":"2026-08-24T00:00:00.197Z"},
            "monthly":{"status":"ok","percent":48,"resetsAt":"2026-09-09T04:57:15.197Z"}
          }
        }
        """))

        XCTAssertEqual(snapshot.windows.map(\.id), ["rolling", "weekly", "monthly"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [2, 27, 48])
    }

    /// The headline number must come first, because the battery shows
    /// `windows.first` until you click through. Reading `autoPercentUsed` here
    /// is what made Daddy say 9% while the Cursor dashboard said 21%.
    func testCursorLeadsWithTotalUsageNotTheAutoPool() throws {
        let snapshot = try ProviderUsageParser.cursor(data("""
        {
          "billingCycleEnd":"1787941766000",
          "planUsage":{
            "autoPercentUsed":9.313333333333333,
            "apiPercentUsed":100,
            "totalPercentUsed":21.240579710144928
          }
        }
        """))

        XCTAssertEqual(snapshot.windows.map(\.id), ["total", "cursor-models", "other-models"])
        XCTAssertEqual(snapshot.windows[0].label, "Included usage")
        XCTAssertEqual(snapshot.windows[0].usedPercent, 21.240579710144928, accuracy: 0.0001)
        XCTAssertEqual(snapshot.windows[1].usedPercent, 9.313333333333333, accuracy: 0.0001)
        XCTAssertEqual(snapshot.windows[2].usedPercent, 100)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
    }

    /// Losing a breakdown pool should cost you the breakdown, not the headline.
    func testCursorSurvivesAMissingBreakdownPool() throws {
        let snapshot = try ProviderUsageParser.cursor(data("""
        {"billingCycleEnd":"1787941766000","planUsage":{"totalPercentUsed":21}}
        """))

        XCTAssertEqual(snapshot.windows.map(\.id), ["total"])
        XCTAssertEqual(snapshot.windows[0].usedPercent, 21)
    }

    func testCursorWithoutTotalIsAFormatChange() {
        XCTAssertThrowsError(
            try ProviderUsageParser.cursor(data("""
            {"billingCycleEnd":"1787941766000","planUsage":{"autoPercentUsed":6.25}}
            """))
        )
    }

    func testCodexUsesReportedWindowDurations() throws {
        let snapshot = try ProviderUsageParser.codex(data("""
        {"id":0,"result":{"userAgent":"daddy"}}
        {"id":1,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1787000000},"secondary":{"usedPercent":18,"windowDurationMins":10080,"resetsAt":1787600000}}}}
        """))

        XCTAssertEqual(snapshot.windows.map(\.label), ["5-hour", "Weekly"])
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [25, 18])
    }

    func testCodexDoesNotMislabelMonthlyFreePlanAsFiveHour() throws {
        let snapshot = try ProviderUsageParser.codex(data("""
        {"id":1,"result":{"rateLimits":{"primary":{"usedPercent":61,"windowDurationMins":43200,"resetsAt":1789539725},"secondary":null}}}
        """))

        XCTAssertEqual(snapshot.windows.first?.label, "Monthly")
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 61)
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }
}
