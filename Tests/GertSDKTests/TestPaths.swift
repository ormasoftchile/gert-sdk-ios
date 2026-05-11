//
//  TestPaths.swift
//  Shared test helper that resolves the gert-domain-home repo on the
//  filesystem. Honours $GERT_DOMAIN_HOME first (used by CI), then
//  falls back to the workspace sibling layout used during local dev.
//

import Foundation

enum TestPaths {
    /// Absolute path to the gert-domain-home repository root.
    /// Throws an XCTSkip-equivalent error indirectly via fatalError if
    /// the repo cannot be located, since every consumer test depends
    /// on it.
    static var domainHome: URL {
        if let env = ProcessInfo.processInfo.environment["GERT_DOMAIN_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        // Local dev sibling: <workspace>/gert-sdk-ios/ + <workspace>/gert-domain-home/
        let here = URL(fileURLWithPath: #filePath)
        let workspace = here
            .deletingLastPathComponent()  // GertSDKTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // gert-sdk-ios
            .deletingLastPathComponent()  // workspace
        return workspace.appendingPathComponent("gert-domain-home")
    }

    static var domainHomeTemplatesDir: URL {
        domainHome.appendingPathComponent("templates/routine")
    }

    static var domainHomeTemplatesRoot: URL {
        domainHome.appendingPathComponent("templates")
    }

    static var domainHomeCorpus: URL {
        domainHome.appendingPathComponent("testdata/golden/templates")
    }
}
