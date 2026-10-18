import Foundation

/// a small synchronized memory cache. loads happen outside the lock so a slow
/// bundle read or decode cannot block unrelated cache lookups
///
/// 'AssetCache' is '@unchecked Sendable' because every read and write is
/// guarded by 'lock'
internal final class AssetCache<Key: Hashable, Value>: @unchecked Sendable {
    private let lock: NSLock = NSLock()
    private var values: [Key: Value] = [:]

    func value(for key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }

        return values[key]
    }

    func insert(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }

        values[key] = value
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        
        values.removeAll(keepingCapacity: false)
    }
}

internal struct AssetKey: Hashable, Sendable {
    let name: String
    let fileExtension: String?
    let subdirectory: String?

    init(_ name: String, _ fileExtension: String?, _ subdirectory: String?) {
        self.name = name
        self.fileExtension = fileExtension
        self.subdirectory = subdirectory
    }
}
