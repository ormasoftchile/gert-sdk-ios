import XCTest
@testable import GertSDK

final class CadenceTests: XCTestCase {
    func testParseDays()   throws { XCTAssertEqual(try Cadence.parse("7d"),  Cadence(value: 7, unit: .day)) }
    func testParseWeeks()  throws { XCTAssertEqual(try Cadence.parse("2w"),  Cadence(value: 2, unit: .week)) }
    func testParseMonths() throws { XCTAssertEqual(try Cadence.parse("3M"),  Cadence(value: 3, unit: .month)) }
    func testParseYears()  throws { XCTAssertEqual(try Cadence.parse("1y"),  Cadence(value: 1, unit: .year)) }

    func testInvalid() {
        XCTAssertThrowsError(try Cadence.parse(""))
        XCTAssertThrowsError(try Cadence.parse("d"))
        XCTAssertThrowsError(try Cadence.parse("7"))
        XCTAssertThrowsError(try Cadence.parse("7x"))
        XCTAssertThrowsError(try Cadence.parse("7D")) // case sensitive (matches Go side)
    }

    func testApproximateInterval() {
        XCTAssertEqual(Cadence(value: 1, unit: .day).approximateInterval,   86_400)
        XCTAssertEqual(Cadence(value: 1, unit: .week).approximateInterval,  86_400 * 7)
        XCTAssertEqual(Cadence(value: 1, unit: .month).approximateInterval, 86_400 * 30)
        XCTAssertEqual(Cadence(value: 1, unit: .year).approximateInterval,  86_400 * 365)
    }
}

final class SchedulerTests: XCTestCase {
    private func kitURL() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let workspace = here
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let kit = workspace
            .appendingPathComponent("gert-domain-home/examples/casa-santiago.home.kit")
        if !FileManager.default.fileExists(atPath: kit.path) {
            throw XCTSkip("casa-santiago kit not found at \(kit.path)")
        }
        return kit
    }

    func testNeverCompleted() async throws {
        let kit = try KitLoader.load(from: try kitURL())
        let store = InMemoryCompletionStore()
        let schedule = await Scheduler().schedule(kit: kit, completions: store)
        XCTAssertEqual(schedule.count, kit.routines.count)
        for item in schedule {
            XCTAssertEqual(item.status, .neverCompleted)
            XCTAssertNil(item.lastCompleted)
        }
    }

    func testOverdueAndUpcoming() async throws {
        let kit = try KitLoader.load(from: try kitURL())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // pool_clean cadence is 7d; mark completed 30 days ago (overdue).
        // water_plants cadence is 3d; mark completed 1 hour ago (upcoming).
        let store = InMemoryCompletionStore(seed: [
            "casa-santiago.routine.pool_clean":   now.addingTimeInterval(-30 * 86_400),
            "casa-santiago.routine.water_plants": now.addingTimeInterval(-3600),
        ])
        let schedule = await Scheduler().schedule(kit: kit, completions: store, now: now)
        let byID = Dictionary(uniqueKeysWithValues: schedule.map { ($0.entry.id, $0) })

        if case .overdue(let by) = byID["casa-santiago.routine.pool_clean"]?.status {
            XCTAssertGreaterThan(by, 22 * 86_400) // 30d - 7d
        } else {
            XCTFail("pool_clean should be overdue, got \(String(describing: byID["casa-santiago.routine.pool_clean"]?.status))")
        }

        if case .upcoming(let inSec) = byID["casa-santiago.routine.water_plants"]?.status {
            XCTAssertGreaterThan(inSec, 2 * 86_400)
        } else {
            XCTFail("water_plants should be upcoming, got \(String(describing: byID["casa-santiago.routine.water_plants"]?.status))")
        }

        // Sort: overdue routines come before upcoming ones.
        let firstOverdue = schedule.firstIndex { if case .overdue = $0.status { return true } else { return false } }
        let firstUpcoming = schedule.firstIndex { if case .upcoming = $0.status { return true } else { return false } }
        if let o = firstOverdue, let u = firstUpcoming {
            XCTAssertLessThan(o, u)
        }
    }

    func testDueWindow() async throws {
        let kit = try KitLoader.load(from: try kitURL())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Exactly 7d ago → due now (within default 1h window).
        let store = InMemoryCompletionStore(seed: [
            "casa-santiago.routine.pool_clean": now.addingTimeInterval(-7 * 86_400),
        ])
        let schedule = await Scheduler().schedule(kit: kit, completions: store, now: now)
        let pool = schedule.first { $0.entry.id == "casa-santiago.routine.pool_clean" }
        XCTAssertEqual(pool?.status, .dueNow)
    }

    func testActionableFiltersUpcoming() async throws {
        let kit = try KitLoader.load(from: try kitURL())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = InMemoryCompletionStore(seed: [
            "casa-santiago.routine.water_plants": now.addingTimeInterval(-3600),
        ])
        let actionable = await Scheduler().actionable(kit: kit, completions: store, now: now)
        XCTAssertFalse(actionable.contains { $0.entry.id == "casa-santiago.routine.water_plants" })
        // The other 4 routines were never completed → all in actionable list.
        XCTAssertEqual(actionable.count, kit.routines.count - 1)
    }
}
