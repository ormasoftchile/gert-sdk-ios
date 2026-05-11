//
//  SlotTests.swift
//  GertSDKTests
//
//  Mirror of pkg/slot/slot_test.go.
//

import XCTest
@testable import GertSDK

private struct FakeCtx: SlotContext {
    let zones: Set<String>
    let assets: Set<String>
    func hasZone(_ id: String) -> Bool { zones.contains(id) }
    func hasAsset(_ id: String) -> Bool { assets.contains(id) }

    static let casa = FakeCtx(
        zones: ["pool", "front_lawn", "garage", "driveway", "backyard"],
        assets: ["pool_pump", "riding_mower", "front_gate"]
    )
}

final class SlotTests: XCTestCase {
    func testDefaultRegistryHasAllCatalogTypes() {
        let r = SlotRegistry.default
        for name in ["zone_ref", "asset_ref", "cadence", "duration", "string_short", "int", "enum"] {
            XCTAssertNotNil(r.lookup(name), "missing \(name)")
        }
    }

    func testUnknownType() {
        XCTAssertNil(SlotRegistry.default.lookup("frobnicate"))
    }

    func testZoneRef() throws {
        let t = SlotRegistry.default.lookup("zone_ref")!
        try t.validate(.string("pool"), params: [:], context: FakeCtx.casa)
        XCTAssertThrowsError(try t.validate(.string("kitchen"), params: [:], context: FakeCtx.casa))
        XCTAssertThrowsError(try t.validate(.string(""), params: [:], context: FakeCtx.casa))
        XCTAssertThrowsError(try t.validate(.int(42), params: [:], context: FakeCtx.casa))
        XCTAssertThrowsError(try t.validate(.string("pool"), params: [:], context: nil))
        XCTAssertEqual(t.marshal(.string("pool")), "pool")
    }

    func testAssetRef() throws {
        let t = SlotRegistry.default.lookup("asset_ref")!
        try t.validate(.string("pool_pump"), params: [:], context: FakeCtx.casa)
        XCTAssertThrowsError(try t.validate(.string("hovercraft"), params: [:], context: FakeCtx.casa))
        XCTAssertThrowsError(try t.validate(.string(""), params: [:], context: FakeCtx.casa))
    }

    func testCadence() throws {
        let t = SlotRegistry.default.lookup("cadence")!
        for s in ["1m", "30m", "1h", "12h", "1d", "90d", "1w", "52w"] {
            try t.validate(.string(s), params: [:], context: nil)
        }
        for s in ["", "1", "1s", "1y", "d1", "1.5d", "1d ", " 1d", "1d2h", "abc"] {
            XCTAssertThrowsError(try t.validate(.string(s), params: [:], context: nil), "should reject \(s)")
        }
        XCTAssertEqual(t.marshal(.string("90d")), "90d")
    }

    func testDuration() throws {
        let t = SlotRegistry.default.lookup("duration")!
        try t.validate(.string("4h"), params: [:], context: nil)
        XCTAssertThrowsError(try t.validate(.string("4hours"), params: [:], context: nil))
    }

    func testStringShort() throws {
        let t = SlotRegistry.default.lookup("string_short")!
        try t.validate(.string("hello"), params: [:], context: nil)
        XCTAssertThrowsError(try t.validate(.string(""), params: [:], context: nil))
        XCTAssertThrowsError(try t.validate(.string(String(repeating: "x", count: 81)), params: [:], context: nil))
        try t.validate(.string(String(repeating: "x", count: 80)), params: [:], context: nil)
        XCTAssertThrowsError(try t.validate(.string("line1\nline2"), params: [:], context: nil))
        XCTAssertThrowsError(try t.validate(.int(42), params: [:], context: nil))
    }

    func testInt() throws {
        let t = SlotRegistry.default.lookup("int")!
        try t.validate(.int(5), params: [:], context: nil)
        XCTAssertThrowsError(try t.validate(.string("5"), params: [:], context: nil))
        XCTAssertThrowsError(try t.validate(.int(3), params: ["min": 5, "max": 10], context: nil))
        XCTAssertThrowsError(try t.validate(.int(11), params: ["min": 5, "max": 10], context: nil))
        try t.validate(.int(7), params: ["min": 5, "max": 10], context: nil)
        XCTAssertEqual(t.marshal(.int(42)), "42")
    }

    func testEnum() throws {
        let t = SlotRegistry.default.lookup("enum")!
        let params: [String: Any] = ["options": ["low", "medium", "high"]]
        try t.validate(.string("medium"), params: params, context: nil)
        XCTAssertThrowsError(try t.validate(.string("ultra"), params: params, context: nil))
        XCTAssertThrowsError(try t.validate(.string("medium"), params: [:], context: nil))
        XCTAssertThrowsError(try t.validate(.string("medium"), params: ["options": [String]()], context: nil))
        XCTAssertEqual(t.marshal(.string("medium")), "medium")
    }
}
