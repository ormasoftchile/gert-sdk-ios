import Foundation

/// KitLoader handles loading and validating kit bundles.
public struct KitLoader {
    
    /// Loads a kit from a local directory URL.
    /// - Parameter url: URL to the .kit directory
    /// - Returns: A fully loaded kit with all dependencies resolved
    /// - Throws: KitLoadError if manifest is missing, invalid, or dependencies cannot be resolved
    public static func load(from url: URL) async throws -> LoadedKit {
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
        try await checkCapabilities(tools: tools)
        
        // 7. Resolve dependencies eagerly
        // TODO: Implement dependency resolution
        
        return LoadedKit(
            manifest: manifest,
            runbooks: runbooks,
            tools: tools
        )
    }
    
    private static func loadRunbooks(from url: URL) throws -> [RunbookEntry] {
        fatalError("Not yet implemented")
    }
    
    private static func loadTools(from url: URL) throws -> [ToolDefinition] {
        fatalError("Not yet implemented")
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
