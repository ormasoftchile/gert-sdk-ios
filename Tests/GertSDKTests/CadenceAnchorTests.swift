import XCTest
@testable import GertSDK

final class CadenceAnchorTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Santiago")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        return calendar.date(from: c)!
    }

    // MARK: - Decoding

    func testFromMetadataMissing() {
        XCTAssertNil(CadenceAnchor.from(metadata: nil))
        XCTAssertNil(CadenceAnchor.from(metadata: [:]))
        XCTAssertNil(CadenceAnchor.from(metadata: ["interval": "7d"]))
    }

    func testFromMetadataWeekday() {
        let a = CadenceAnchor.from(metadata: [
            "anchor_weekday": "monday",
            "anchor_time": "07:00",
        ])
        XCTAssertEqual(a?.rule, .weekday(1))
        XCTAssertEqual(a?.timeOfDay?.hour, 7)
        XCTAssertEqual(a?.timeOfDay?.minute, 0)
    }

    func testFromMetadataDayOfMonth() {
        let a = CadenceAnchor.from(metadata: ["anchor_day_of_month": "15"])
        XCTAssertEqual(a?.rule, .dayOfMonth(15))
        XCTAssertNil(a?.timeOfDay)
    }

    func testFromMetadataFixedDate() {
        let a = CadenceAnchor.from(metadata: ["anchor_date": "2026-10-15"])
        XCTAssertEqual(a?.rule, .fixedDate(year: 2026, month: 10, day: 15))
    }

    func testFromMetadataIgnoresGarbage() {
        XCTAssertNil(CadenceAnchor.from(metadata: ["anchor_weekday": "funday"]))
        XCTAssertNil(CadenceAnchor.from(metadata: ["anchor_day_of_month": "32"]))
        XCTAssertNil(CadenceAnchor.from(metadata: ["anchor_date": "garbage"]))
    }

    // MARK: - nextOccurrence (weekday)

    func testWeekdayNextFromBefore() {
        // Monday Jan 5 2026 was a Monday. Use Sunday Jan 4 → next Monday is Jan 5.
        let a = CadenceAnchor(rule: .weekday(1), timeOfDay: (7, 0))
        let next = a.nextOccurrence(
            onOrAfter: date(2026, 1, 4, 12, 0),
            cadenceInterval: 7 * 86_400,
            inclusive: true,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 1, 5, 7, 0))
    }

    func testWeekdayNextStrictlyAfter() {
        // Same Monday 07:00 → strict means next Monday a week later.
        let a = CadenceAnchor(rule: .weekday(1), timeOfDay: (7, 0))
        let next = a.nextOccurrence(
            onOrAfter: date(2026, 1, 5, 7, 0),
            cadenceInterval: 7 * 86_400,
            inclusive: false,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 1, 12, 7, 0))
    }

    // MARK: - nextOccurrence (day_of_month)

    func testDayOfMonthClampsToMonthEnd() {
        // Anchor day 31 in February → clamps to 28 (or 29 leap).
        let a = CadenceAnchor(rule: .dayOfMonth(31))
        let next = a.nextOccurrence(
            onOrAfter: date(2026, 2, 1),
            cadenceInterval: 30 * 86_400,
            inclusive: true,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 2, 28))
    }

    func testDayOfMonthSkipsToNextMonth() {
        // After the 15th, anchor 15 should land on the next month's 15th.
        let a = CadenceAnchor(rule: .dayOfMonth(15))
        let next = a.nextOccurrence(
            onOrAfter: date(2026, 1, 20),
            cadenceInterval: 30 * 86_400,
            inclusive: true,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 2, 15))
    }

    // MARK: - nextOccurrence (fixed date)

    func testFixedDateBeforeAnchor() {
        // Reference is well before the anchor → first occurrence is the anchor itself.
        let a = CadenceAnchor(rule: .fixedDate(year: 2026, month: 10, day: 15))
        let next = a.nextOccurrence(
            onOrAfter: date(2026, 1, 1),
            cadenceInterval: 365 * 86_400,
            inclusive: true,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 10, 15))
    }

    func testFixedDateAfterAnchor() {
        // Reference is past the anchor → next yearly cycle.
        let a = CadenceAnchor(rule: .fixedDate(year: 2024, month: 10, day: 15))
        let next = a.nextOccurrence(
            onOrAfter: date(2026, 1, 1),
            cadenceInterval: 365 * 86_400,
            inclusive: true,
            calendar: calendar
        )
        // Two cycles forward of 2024-10-15 lands roughly on 2026-10-15.
        // Allow a small tolerance because approximateInterval drifts.
        let expected = date(2026, 10, 15)
        XCTAssertLessThan(abs(next.timeIntervalSince(expected)), 86_400 * 2)
    }

    // MARK: - Time-only (daily) anchor

    func testFromMetadataTimeOnly() {
        let a = CadenceAnchor.from(metadata: ["anchor_time": "07:30"])
        XCTAssertEqual(a?.rule, .timeOfDay)
        XCTAssertEqual(a?.timeOfDay?.hour, 7)
        XCTAssertEqual(a?.timeOfDay?.minute, 30)
    }

    func testTimeOnlyTodayBeforeFireTime() {
        // Reference is 2026-05-05 06:00. Anchor 07:30 fires today at
        // 07:30, well before any cadence step.
        let a = CadenceAnchor(rule: .timeOfDay, timeOfDay: (7, 30))
        let next = a.nextOccurrence(
            onOrAfter: date(2026, 5, 5, 6, 0),
            cadenceInterval: 86_400,
            inclusive: true,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 5, 5, 7, 30))
    }

    func testTimeOnlyTodayAfterFireTime() {
        // Reference is 2026-05-05 08:00. Anchor 07:30 already passed
        // today → tomorrow at 07:30.
        let a = CadenceAnchor(rule: .timeOfDay, timeOfDay: (7, 30))
        let next = a.nextOccurrence(
            onOrAfter: date(2026, 5, 5, 8, 0),
            cadenceInterval: 86_400,
            inclusive: true,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 5, 6, 7, 30))
    }

    func testTimeOnlyEveningWalk() {
        // Reference 2026-05-05 18:00, anchor 19:30 → today 19:30.
        let a = CadenceAnchor(rule: .timeOfDay, timeOfDay: (19, 30))
        let next = a.nextOccurrence(
            onOrAfter: date(2026, 5, 5, 18, 0),
            cadenceInterval: 86_400,
            inclusive: true,
            calendar: calendar
        )
        XCTAssertEqual(next, date(2026, 5, 5, 19, 30))
    }
}
