import Foundation

public extension AssetStore {
    /// loads and parses an AXB file, caching the parsed named-mesh asset
    func loadAXB(named name: String, subdirectory: String? = nil) throws -> AXBFile {
        let key = AssetKey(name, "axb", subdirectory)
        if let cached = axbCache.value(for: key) { return cached }

        let data = try loadData(named: name, withExtension: "axb", subdirectory: subdirectory)
        let file = try AXBParser.parse(data, resourceName: "\(name).axb")
        
        axbCache.insert(file, for: key)
        return file
    }
}
