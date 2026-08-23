import XCTest
@testable import DaddyCore

final class ProviderUsageTests: XCTestCase {
    func testWindowClampsUsageAndComputesRemaining() {
        XCTAssertEqual(
            ProviderUsageWindow(id: "low", label: "Low", usedPercent: -4, resetsAt: nil)
                .remainingPercent,
            100
        )
        XCTAssertEqual(
            ProviderUsageWindow(id: "high", label: "High", usedPercent: 140, resetsAt: nil)
                .remainingPercent,
            0
        )
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
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [28, 82])
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
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [98, 73, 52])
    }

    func testCursorMapsItsTwoModelPools() throws {
        let snapshot = try ProviderUsageParser.cursor(data("""
        {
          "billingCycleEnd":"1787941766000",
          "planUsage":{"autoPercentUsed":6.25,"apiPercentUsed":70.5}
        }
        """))

        XCTAssertEqual(snapshot.windows.map(\.label), ["Cursor models", "Other models"])
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [93.75, 29.5])
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
    }

    func testCodexUsesReportedWindowDurations() throws {
        let snapshot = try ProviderUsageParser.codex(data("""
        {"id":0,"result":{"userAgent":"daddy"}}
        {"id":1,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1787000000},"secondary":{"usedPercent":18,"windowDurationMins":10080,"resetsAt":1787600000}}}}
        """))

        XCTAssertEqual(snapshot.windows.map(\.label), ["5-hour", "Weekly"])
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [75, 82])
    }

    func testCodexDoesNotMislabelMonthlyFreePlanAsFiveHour() throws {
        let snapshot = try ProviderUsageParser.codex(data("""
        {"id":1,"result":{"rateLimits":{"primary":{"usedPercent":61,"windowDurationMins":43200,"resetsAt":1789539725},"secondary":null}}}
        """))

        XCTAssertEqual(snapshot.windows.first?.label, "Monthly")
    }

    private func data(_ string: String) -> Data {
        Data(string.utf8)
    }
}
