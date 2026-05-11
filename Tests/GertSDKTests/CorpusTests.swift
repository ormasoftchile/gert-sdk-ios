//
//  CorpusTests.swift
//  Cross-platform determinism harness.
//
//  Reads the same testdata/golden/templates/*/ triples used by Go's
//  pkg/materialize/corpus_test.go and asserts byte-equal output.
//

import XCTest
import Yams
@testable import GertSDK

private struct CorpusInput: Decodable {
    let routine_id: String
    let bindings: [String: AnyCodable]?
    let toggles: [String: Bool]?
    let ctx: Ctx?

    struct Ctx: Decodable {
        let zones: [String]?
        let assets: [String]?
    }
}

private struct CorpusCtx: SlotContext {
    let zones: Set<String>
    let assets: Set<String>
    func hasZone(_ id: String) -> Bool { zones.contains(id) }
    func hasAsset(_ id: String) -> Bool { assets.contains(id) }
}

/// Permissive Codable wrapper for arbitrary YAML scalars in input.yaml.
private struct AnyCodable: Decodable {
    let value: Any
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let i = try? c.decode(Int.self)    { value = i;       return }
        if let b = try? c.decode(Bool.self)   { value = b;       return }
        if let dbl = try? c.decode(Double.self) { value = dbl;   return }
        if let s = try? c.decode(String.self) { value = s;       return }
        value = ""
    }
}

final class CorpusTests: XCTestCase {

    private func corpusDir() -> URL {
        TestPaths.domainHomeCorpus
    }

    func testCorpus() throws {
        let dir = corpusDir()
        let fm = FileManager.default
        guard let cases = try? fm.contentsOfDirectory(atPath: dir.path) else {
            XCTFail("corpus dir missing: \(dir.path)")
            return
        }
        let sorted = cases.filter { !$0.hasPrefix(".") && $0 != "README.md" }.sorted()
        XCTAssertGreaterThan(sorted.count, 0, "no corpus cases found")

        var failures: [String] = []

        for name in sorted {
            let caseDir = dir.appendingPathComponent(name)
            let templatePath = caseDir.appendingPathComponent("template.yaml").path
            let inputPath    = caseDir.appendingPathComponent("input.yaml").path
            let expectedPath = caseDir.appendingPathComponent("expected.yaml").path

            do {
                let tpl = try TemplateParser.parseFile(templatePath)

                let inputBody = try String(contentsOfFile: inputPath, encoding: .utf8)
                let decoder = YAMLDecoder()
                let input = try decoder.decode(CorpusInput.self, from: inputBody)

                var bindings: [String: Any] = [:]
                for (k, v) in input.bindings ?? [:] { bindings[k] = v.value }

                let ctx = CorpusCtx(
                    zones: Set(input.ctx?.zones ?? []),
                    assets: Set(input.ctx?.assets ?? [])
                )

                let result = try Materializer.materialize(.init(
                    template: tpl,
                    routineID: input.routine_id,
                    bindings: bindings,
                    toggles: input.toggles ?? [:],
                    context: ctx
                ))

                let expected = try String(contentsOfFile: expectedPath, encoding: .utf8)
                if result.bytes != expected {
                    failures.append("\n=== \(name) DIFF ===\n--- got ---\n\(result.bytes)\n--- want ---\n\(expected)")
                }
            } catch {
                failures.append("\n=== \(name) ERROR ===\n\(error)")
            }
        }

        if !failures.isEmpty {
            XCTFail(failures.joined(separator: "\n"))
        }
    }
}
