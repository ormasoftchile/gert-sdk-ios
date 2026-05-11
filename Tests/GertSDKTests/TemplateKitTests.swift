//
//  TemplateKitTests.swift
//

import XCTest
@testable import GertSDK

private struct TestCtx: SlotContext {
    let zones: Set<String>
    let assets: Set<String>
    func hasZone(_ id: String) -> Bool { zones.contains(id) }
    func hasAsset(_ id: String) -> Bool { assets.contains(id) }
}

final class TemplateKitTests: XCTestCase {

    private func templatesDir() -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let sdkRoot = here
            .deletingLastPathComponent()  // GertSDKTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // gert-sdk-ios
            .deletingLastPathComponent()  // workspace root
        return sdkRoot.appendingPathComponent("gert-domain-home/templates/routine")
    }

    func testLoadStarterLibrary() {
        let (kit, errors) = TemplateKit.load(directory: templatesDir())
        XCTAssertEqual(errors.count, 0, "load errors: \(errors)")
        XCTAssertGreaterThanOrEqual(kit.templates.count, 3)
        let ids = kit.templates.map(\.id)
        XCTAssertTrue(ids.contains("gutter_clean"), "ids=\(ids)")
        XCTAssertTrue(ids.contains("asset_maintenance"), "ids=\(ids)")
        XCTAssertTrue(ids.contains("zone_inspection"), "ids=\(ids)")
        // Sorted by id.
        XCTAssertEqual(ids, ids.sorted())
    }

    func testFormDescriptorForGutterClean() throws {
        let (kit, _) = TemplateKit.load(directory: templatesDir())
        let tpl = try XCTUnwrap(kit.template(id: "gutter_clean"))
        let form = tpl.formDescriptor()

        XCTAssertEqual(form.templateID, "gutter_clean")
        XCTAssertEqual(form.templateVersion, 1)
        let fieldIDs = form.fields.map(\.id)
        XCTAssertEqual(fieldIDs, ["zone", "cadence"])

        guard case .zoneRef = form.fields[0].kind else {
            return XCTFail("expected zoneRef, got \(form.fields[0].kind)")
        }
        guard case .cadence = form.fields[1].kind else {
            return XCTFail("expected cadence, got \(form.fields[1].kind)")
        }

        let toggleIDs = form.toggles.map(\.id)
        XCTAssertEqual(toggleIDs, ["needs_ladder", "photo_evidence"])
    }

    func testFormDescriptorForAssetMaintenance_carriesIntMinMax() throws {
        let (kit, _) = TemplateKit.load(directory: templatesDir())
        let tpl = try XCTUnwrap(kit.template(id: "asset_maintenance"))
        let form = tpl.formDescriptor()
        // The third slot should be the runtime int.
        XCTAssertEqual(form.fields.count, 3)
        let intField = form.fields[2]
        guard case let .int(mn, mx) = intField.kind else {
            return XCTFail("expected int field, got \(intField.kind)")
        }
        XCTAssertNotNil(mn)
        XCTAssertGreaterThanOrEqual(mn ?? -1, 0)
        _ = mx
    }

    func testFormDescriptorForZoneInspection_carriesEnumOptions() throws {
        let (kit, _) = TemplateKit.load(directory: templatesDir())
        let tpl = try XCTUnwrap(kit.template(id: "zone_inspection"))
        let form = tpl.formDescriptor()
        let priority = form.fields.first { $0.id == "priority" }
        XCTAssertNotNil(priority)
        guard case let .enumeration(opts) = priority!.kind else {
            return XCTFail("expected enum, got \(priority!.kind)")
        }
        XCTAssertEqual(opts, ["low", "medium", "high"])
    }

    func testCompose_endToEnd() throws {
        let ctx = TestCtx(
            zones: ["pool", "front_lawn"],
            assets: []
        )
        let (kit, errors) = TemplateKit.load(directory: templatesDir(), context: ctx)
        XCTAssertEqual(errors.count, 0)

        let result = try kit.compose(
            templateID: "gutter_clean",
            routineID: "clean_front_gutter",
            bindings: ["zone": "front_lawn", "cadence": "90d"],
            toggles: ["needs_ladder": true, "photo_evidence": true]
        )
        XCTAssertTrue(result.bytes.contains("id: clean_front_gutter"))
        XCTAssertTrue(result.bytes.contains("template_id: gutter_clean"))
    }

    func testCompose_unknownTemplate() {
        let (kit, _) = TemplateKit.load(directory: templatesDir())
        XCTAssertThrowsError(try kit.compose(templateID: "no_such",
                                             routineID: "x")) { e in
            guard case ComposeError.unknownTemplate = e else {
                return XCTFail("wrong error: \(e)")
            }
        }
    }
}
