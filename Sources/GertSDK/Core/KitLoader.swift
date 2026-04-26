import Foundation
import Yams

/// KitLoader handles loading and validating kit bundles.
public struct KitLoader {
    
    /// Loads a kit from a local directory URL.
    /// - Parameters:
    ///   - url: URL to the .kit directory
    ///   - skipCapabilityCheck: If true, skip platform capability checks (for testing)
    /// - Returns: A fully loaded kit with all dependencies resolved
    /// - Throws: KitLoadError if manifest is missing, invalid, or dependencies cannot be resolved
    public static func load(from url: URL, skipCapabilityCheck: Bool = false) async throws -> LoadedKit {
        // 1. Read manifest.json
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw KitLoadError.manifestMissing
        }
        
        // 2. Parse manifest
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        
        // 3. Load runbooks from runbooks/
        let runbooks = try loadRunbooks(from: url.appendingPathComponent("runbooks"))
        
        // 4. Load tools from tools/
        let tools = try loadTools(from: url.appendingPathComponent("tools"))
        
        // 5. Validate all tools have iOS impl
        try validatePlatformImpls(tools: tools)
        
        // 6. Check capabilities
        if !skipCapabilityCheck {
            try await checkCapabilities(tools: tools)
        }
        
        // 7. Resolve dependencies eagerly
        // TODO: Implement dependency resolution
        
        return LoadedKit(
            manifest: manifest,
            runbooks: runbooks,
            tools: tools
        )
    }
    
    private static func loadRunbooks(from url: URL) throws -> [RunbookEntry] {
        let fileManager = FileManager.default
        
        // Check if directory exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }
        
        // Enumerate *.runbook.yaml files
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return []
        }
        
        var runbooks: [RunbookEntry] = []
        
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "yaml" && fileURL.lastPathComponent.hasSuffix(".runbook.yaml") else {
                continue
            }
            
            // Read and parse YAML
            let yamlString = try String(contentsOf: fileURL, encoding: .utf8)
            let decoder = YAMLDecoder()
            let runbook = try decoder.decode(RunbookEntry.self, from: yamlString)
            runbooks.append(runbook)
        }
        
        return runbooks
    }
    
    private static func loadTools(from url: URL) throws -> [ToolDefinition] {
        let fileManager = FileManager.default
        
        // Check if directory exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw KitLoadError.manifestInvalid("tools/ directory missing")
        }
        
        // Enumerate *.tool.yaml files
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) else {
            throw KitLoadError.manifestInvalid("Cannot enumerate tools/ directory")
        }
        
        var tools: [ToolDefinition] = []
        
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "yaml" && fileURL.lastPathComponent.hasSuffix(".tool.yaml") else {
                continue
            }
            
            // Read and parse YAML
            let yamlString = try String(contentsOf: fileURL, encoding: .utf8)
            let decoder = YAMLDecoder()
            let tool = try decoder.decode(ToolDefinition.self, from: yamlString)
            tools.append(tool)
        }
        
        return tools
    }
    
    private static func validatePlatformImpls(tools: [ToolDefinition]) throws {
        for tool in tools {
            if !tool.hasIOSImpl {
                throw KitLoadError.missingPlatformImpl(toolName: tool.name, platform: "ios")
            }
        }
    }
    
    private static func checkCapabilities(tools: [ToolDefinition]) async throws {
        let handlers = PlatformHandlerRegistry.shared.allHandlers
        
        for tool in tools {
            for capability in tool.requiredCapabilities {
                guard let handler = handlers.first(where: { $0.capability == capability }) else {
                    throw KitLoadError.missingCapability(capability: capability)
                }
                
                let available = await handler.checkAvailability()
                if !available {
                    throw KitLoadError.missingCapability(capability: capability)
                }
            }
        }
    }
}
