import XCTest
@testable import GertSDK

final class UserDefaultsCompletionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let key = "test.completions.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "")
        super.tearDown()
    }

    func testEmptyOnFirstLoad() async {
        let store = UserDefaultsCompletionStore(defaults: defaults, key: key)
        let date = await store.lastCompletion(routineID: "x")
        XCTAssertNil(date)
    }

    func testRoundTripPersistence() async {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let s1 = UserDefaultsCompletionStore(defaults: defaults, key: key)
        await s1.recordCompletion(routineID: "trash_day", at: when)

        // A fresh instance reads from the same UserDefaults — values
        // must survive being dropped from memory.
        let s2 = UserDefaultsCompletionStore(defaults: defaults, key: key)
        let read = await s2.lastCompletion(routineID: "trash_day")
        // ISO-8601 round-trip is at second granularity.
        XCTAssertNotNil(read)
        XCTAssertEqual(Int(read!.timeIntervalSince1970), Int(when.timeIntervalSince1970))
    }

    func testMonotonic() async {
        let store = UserDefaultsCompletionStore(defaults: defaults, key: key)
        let earlier = Date(timeIntervalSince1970: 100)
        let later   = Date(timeIntervalSince1970: 200)
        await store.recordCompletion(routineID: "r", at: later)
        await store.recordCompletion(routineID: "r", at: earlier)
        let read = await store.lastCompletion(routineID: "r")
        XCTAssertEqual(Int(read!.timeIntervalSince1970), Int(later.timeIntervalSince1970))
    }
}
