import Foundation

/// failures encountered while locating or loading a bundled asset
public enum AssetError: Error, LocalizedError {
    case notFound(name: String, fileExtension: String?, subdirectory: String?)
    case unreadable(name: String, underlying: Error)
    case malformed(name: String, offset: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .notFound(name, fileExtension, subdirectory):
            let filename = fileExtension.map { "\(name).\($0)" } ?? name
            let folder = subdirectory.map { " in '\($0)'" } ?? ""
            return "Asset '\(filename)' was not found\(folder)."
        case let .unreadable(name, underlying):
            return "Asset '\(name)' could not be read: \(underlying.localizedDescription)"
        case let .malformed(name, offset, reason):
            return "Asset '\(name)' is malformed at byte offset 0x\(String(offset, radix: 16).uppercased()): \(reason)"
        }
    }
}
