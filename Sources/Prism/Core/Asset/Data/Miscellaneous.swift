import Foundation

public extension AssetStore {
    /// reads a bundle file once and returns the cached bytes on later requests
    func loadData(
        named name: String,
        withExtension fileExtension: String? = nil,
        subdirectory: String? = nil
    ) throws -> Data {
        let key = AssetKey(name, fileExtension, subdirectory)
        if let cached = dataCache.value(for: key) { return cached }

        let assetURL = try url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        )
        let data: Data
        do {
            data = try Data(contentsOf: assetURL, options: .mappedIfSafe)
        } catch {
            throw AssetError.unreadable(name: assetURL.lastPathComponent, underlying: error)
        }
        dataCache.insert(data, for: key)
        return data
    }
}
