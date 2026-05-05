import XCTest
@testable import GertSDK

final class DelegationTests: XCTestCase {

    // MARK: - isActive

    func testIsActive_WithinWindow() {
        let d = makeDelegation(from: "2026-05-01", to: "2026-05-10")
        XCTAssertTrue(d.isActive(on: makeDate("2026-05-05")))
    }

    func testIsActive_OnFromBoundary() {
        let d = makeDelegation(from: "2026-05-01", to: "2026-05-10")
        XCTAssertTrue(d.isActive(on: makeDate("2026-05-01")))
    }

    func testIsActive_OnToBoundary() {
        let d = makeDelegation(from: "2026-05-01", to: "2026-05-10")
        XCTAssertTrue(d.isActive(on: makeDate("2026-05-10")))
    }

    func testIsActive_BeforeWindow() {
        let d = makeDelegation(from: "2026-05-01", to: "2026-05-10")
        XCTAssertFalse(d.isActive(on: makeDate("2026-04-30")))
    }

    func testIsActive_AfterWindow() {
        let d = makeDelegation(from: "2026-05-01", to: "2026-05-10")
        XCTAssertFalse(d.isActive(on: makeDate("2026-05-11")))
    }

    // MARK: - covers

    func testCovers_BareRoutineID() {
        let d = makeDelegation(routines: ["water_plants"])
        XCTAssertTrue(d.covers(routineID: "water_plants", zone: nil))
    }

    func testCovers_KitScopedRoutineID() {
        let d = makeDelegation(routines: ["water_plants"])
        XCTAssertTrue(d.covers(routineID: "casa-santiago.routine.water_plants", zone: nil))
    }

    func testCovers_ZoneMatch() {
        let d = makeDelegation(zones: ["pool"])
        XCTAssertTrue(d.covers(routineID: "casa-santiago.routine.pool_clean", zone: "pool"))
    }

    func testCovers_NoMatch() {
        let d = makeDelegation(routines: ["water_plants"])
        XCTAssertFalse(d.covers(routineID: "trash_day", zone: nil))
    }

    // MARK: - helpers

    private func makeDate(_ iso: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = .current
        f.timeZone = .current
        return f.date(from: iso)!
    }

    private func makeDelegation(from: String = "2026-01-01",
                                to: String = "2026-12-31",
                                routines: [String] = [],
                                zones: [String] = []) -> Delegation {
        let assigns = routines.map { Delegation.Assignment(routine: $0, zone: "") }
                    + zones.map    { Delegation.Assignment(routine: "", zone: $0) }
        return Delegation(
            delegate: .init(name: "Test", contact: nil, email: nil),
            active: .init(from: from, to: to),
            assigns: assigns,
            permissions: .init(canReportIncidents: true,
                               canModifyRoutines: false,
                               canViewHistory: true),
            notifications: nil
        )
    }
}
