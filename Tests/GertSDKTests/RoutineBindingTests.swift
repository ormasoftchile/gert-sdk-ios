//
//  RoutineBindingTests.swift
//
//  Includes a round-trip test that hands a Swift-emitted binding to
//  the real Go home-compile binary and asserts it compiles cleanly.
//  Skipped when `go` is not on PATH.
//

import XCTest
@testable import GertSDK

final class RoutineBindingTests: XCTestCase {

    func testEncodeBasic() {
        let b = RoutineBinding(
            id: "clean_front_gutter",
            templateID: "gutter_clean",
            templateVersion: 1,
            bindings: ["zone": "front_lawn", "cadence": "90d"],
            toggles: ["needs_ladder": true, "photo_evidence": true]
        )
        let out = RoutineBindingEncoder.encode(b)
        let expected = """
        id: clean_front_gutter
        template: gutter_clean
        template_version: 1
        bindings:
          cadence: 90d
          zone: front_lawn
        toggles:
          needs_ladder: true
          photo_evidence: true

        """
        XCTAssertEqual(out, expected)
    }

    func testEncodeQuotesAmbiguousStrings() {
        let b = RoutineBinding(
            id: "x", templateID: "t", templateVersion: 1,
            bindings: ["a": "true", "b": "42"]
        )
        let out = RoutineBindingEncoder.encode(b)
        XCTAssertTrue(out.contains(#"a: "true""#), out)
        XCTAssertTrue(out.contains(#"b: "42""#), out)
    }

    func testEncodeListOmitsEmptySections() {
        let b = RoutineBinding(
            id: "x", templateID: "t", templateVersion: 1
        )
        let out = RoutineBindingEncoder.encodeList([b])
        XCTAssertFalse(out.contains("bindings"), out)
        XCTAssertFalse(out.contains("toggles"), out)
        XCTAssertTrue(out.contains("- id: x"), out)
    }

    /// Round-trip: write a property file with a Swift-encoded binding,
    /// run gert-domain-home/cmd/home-compile against it, assert the
    /// expected routine appears in the compiled index.
    func testRoundTripThroughGoCompiler() throws {
        let goExec = goPath()
        guard goExec != nil else {
            throw XCTSkip("go not on PATH; skipping cross-language round-trip")
        }

        let tmp = URL(fileURLWithPath: "/Volumes/Projects/gert-tui/tmp")
            .appendingPathComponent("ios-rt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1. Materials: link templates dir from gert-domain-home.
        let templatesSrc = TestPaths.domainHomeTemplatesRoot.path
        let templatesLink = tmp.appendingPathComponent("templates")
        try FileManager.default.createSymbolicLink(at: templatesLink,
                                                    withDestinationURL: URL(fileURLWithPath: templatesSrc))

        // 2. Build a property file with one Swift-encoded routine.
        let binding = RoutineBinding(
            id: "clean_pool_gutter",
            templateID: "gutter_clean",
            templateVersion: 1,
            bindings: ["zone": "pool", "cadence": "30d"],
            toggles: [:]
        )
        let routineYAML = RoutineBindingEncoder.encodeList([binding])
            .split(separator: "\n").map { "  " + $0 }.joined(separator: "\n")

        let prop = """
        property:
          id: casa
          name: Casa Test
          zones:
            - id: pool
              name: Pool
        assets: []
        routines:
        \(routineYAML)
        """
        let propFile = tmp.appendingPathComponent("casa.home.yaml")
        try prop.write(to: propFile, atomically: true, encoding: .utf8)

        // 3. Run home-compile.
        let outDir = tmp.appendingPathComponent("out")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: goExec!)
        process.arguments = ["run", "./cmd/home-compile",
                             "-o", outDir.path, propFile.path]
        process.currentDirectoryURL = TestPaths.domainHome
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()

        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0,
                       "compile failed:\nstderr: \(stderr)\nstdout: \(stdout)")

        // 4. Verify the compiled routine appears in the index.
        let indexPath = outDir.appendingPathComponent("index.json")
        let idx = try String(contentsOf: indexPath, encoding: .utf8)
        XCTAssertTrue(idx.contains("clean_pool_gutter"),
                      "routine missing from index: \(idx.prefix(500))")
    }

    private func goPath() -> String? {
        for p in ["/usr/local/go/bin/go", "/opt/homebrew/bin/go",
                  "/Users/cormazab/.asdf/shims/go", "/usr/bin/go"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}
