//
//  ComposeViewModelTests.swift
//

import XCTest
@testable import GertSDK

@available(iOS 16.0, macOS 13.0, *)
final class ComposeViewModelTests: XCTestCase {

    private func gutterTemplate() throws -> Template {
        let dir = TestPaths.domainHomeTemplatesDir
        let (kit, errs) = TemplateKit.load(directory: dir)
        XCTAssertEqual(errs.count, 0)
        return try XCTUnwrap(kit.template(id: "gutter_clean"))
    }

    func testInitSeedsToggleDefaults() throws {
        let m = ComposeViewModel(template: try gutterTemplate())
        XCTAssertFalse(m.toggleValues.isEmpty)
        XCTAssertEqual(m.toggleValues["needs_ladder"], false)
        XCTAssertEqual(m.toggleValues["photo_evidence"], true)
    }

    func testMakeBindingProducesCompilableEntry() throws {
        let m = ComposeViewModel(template: try gutterTemplate())
        m.routineID = "clean_pool_gutter"
        m.stringValues["zone"] = "pool"
        m.stringValues["cadence"] = "30d"
        m.toggleValues["needs_ladder"] = false

        let b = m.makeBinding()
        XCTAssertEqual(b.id, "clean_pool_gutter")
        XCTAssertEqual(b.templateID, "gutter_clean")
        XCTAssertEqual(b.bindings["zone"] as? String, "pool")
        XCTAssertEqual(b.bindings["cadence"] as? String, "30d")
        XCTAssertEqual(b.toggles["needs_ladder"], false)
        XCTAssertEqual(b.toggles["photo_evidence"], true)

        // Spot-check encoded form is shaped right.
        let yaml = RoutineBindingEncoder.encode(b)
        XCTAssertTrue(yaml.contains("template: gutter_clean"))
        XCTAssertTrue(yaml.contains("needs_ladder: false"))
        XCTAssertTrue(yaml.contains("zone: pool"))
    }

    func testMakeBindingDropsEmptyOptionalFields() throws {
        let m = ComposeViewModel(template: try gutterTemplate())
        m.routineID = "x"
        // Clear seeded defaults so we can verify drop behavior.
        m.stringValues = [:]
        m.intValues = [:]
        m.enumValues = [:]
        let b = m.makeBinding()
        XCTAssertTrue(b.bindings.isEmpty)
    }
}
