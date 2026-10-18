import Foundation
import Audio

/// resolves and caches local content from one bundle
///
/// create one store per game or content bundle. cached resources remain alive
/// until 'removeAllCachedAssets()' is called or the store is released
///
/// 'AssetStore' is '@unchecked Sendable' because its bundle is immutable
/// and each of its caches is guarded by its own lock
public final class AssetStore: @unchecked Sendable {
    public let bundle: Bundle

    internal let dataCache = AssetCache<AssetKey, Data>()
    internal let audioCache = AssetCache<AssetKey, AudioClip>()
    internal let axbCache = AssetCache<AssetKey, AXBFile>()

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// resolves a resource URL without reading its contents
    public func url(
        forResource name: String,
        withExtension fileExtension: String? = nil,
        subdirectory: String? = nil
    ) throws -> URL {
        guard let url = bundle.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) else {
            throw AssetError.notFound(
                name: name,
                fileExtension: fileExtension,
                subdirectory: subdirectory
            )
        }
        return url
    }

    /// clears cached CPU-side bytes and decoded resources
    public func removeAllCachedAssets() {
        dataCache.removeAll()
        audioCache.removeAll()
        axbCache.removeAll()
    }
}
