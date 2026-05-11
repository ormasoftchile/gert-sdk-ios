//
//  RoutineStoreTests.swift
//

import XCTest
@testable import GertSDK

final class RoutineStoreTests: XCTestCase {

    private func makeStore() throws -> (FileRoutineStore, URL) {
        let base = URL(fileURLWithPath: "/Volumes/Projects/gert-tui/tmp")
            .appendingPathComponent("ios-routinestore-\(UUID().uuidString.prefix(8))")
        let s = try FileRoutineStore(directory: base)
        return (s, base)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func testListEmpty() throws {
        let (s, dir) = try makeStore()
        defer { cleanup(dir) }
        XCTAssertEqual(try s.list(), [])
    }

    func testPutGetList() throws {
        let (s, dir) = try makeStore()
        defer { cleanup(dir) }
        try s.put(.init(id: "alpha", bytes: "id: alpha\n"))
        try s.put(.init(id: "beta",  bytes: "id: beta\n"))
        XCTAssertEqual(try s.list(), ["alpha", "beta"])
        let got = try s.get(id: "alpha")
        XCTAssertEqual(got?.bytes, "id: alpha\n")
    }

    func testGetMissingReturnsNil() throws {
        let (s, dir) = try makeStore()
        defer { cleanup(dir) }
        XCTAssertNil(try s.get(id: "nope"))
    }

    func testDelete() throws {
        let (s, dir) = try makeStore()
        defer { cleanup(dir) }
        try s.put(.init(id: "alpha", bytes: "x"))
        try s.delete(id: "alpha")
        XCTAssertNil(try s.get(id: "alpha"))
        // Idempotent.
        try s.delete(id: "alpha")
    }

    func testInvalidID() throws {
        let (s, dir) = try makeStore()
        defer { cleanup(dir) }
        XCTAssertThrowsError(try s.put(.init(id: "Bad ID", bytes: "x")))
        XCTAssertThrowsError(try s.put(.init(id: "../escape", bytes: "x")))
        XCTAssertThrowsError(try s.put(.init(id: "", bytes: "x")))
        XCTAssertThrowsError(try s.get(id: "Bad ID"))
    }

    func testRoundTripWithComposedRoutine() throws {
        let (s, dir) = try makeStore()
        defer { cleanup(dir) }

        let templatesDir = TestPaths.domainHomeTemplatesDir
        let (kit, _) = TemplateKit.load(directory: templatesDir,
                                         context: TestCtx(zones: ["pool"], assets: []))
        let composed = try kit.compose(
            templateID: "gutter_clean",
            routineID: "clean_pool_gutter",
            bindings: ["zone": "pool", "cadence": "30d"],
            toggles: [:]
        )
        try s.put(.init(id: "clean_pool_gutter", bytes: composed.bytes))
        let read = try XCTUnwrap(s.get(id: "clean_pool_gutter"))
        XCTAssertEqual(read.bytes, composed.bytes)
    }
}

private struct TestCtx: SlotContext {
    let zones: Set<String>
    let assets: Set<String>
    func hasZone(_ id: String) -> Bool { zones.contains(id) }
    func hasAsset(_ id: String) -> Bool { assets.contains(id) }
}
