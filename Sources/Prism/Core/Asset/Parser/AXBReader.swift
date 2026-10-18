import Foundation

/// bounds-checked little-endian reader used by the AXB decoder
internal struct AXBReader {
    private let bytes: [UInt8]
    private let baseOffset: Int
    private(set) var offset = 0

    init(data: Data, baseOffset: Int = 0) {
        self.bytes = Array(data)
        self.baseOffset = baseOffset
    }

    var absoluteOffset: Int { baseOffset + offset }
    var remaining: Int { bytes.count - offset }
    var hasMore: Bool { offset < bytes.count }
    func peekUInt8() -> UInt8? { hasMore ? bytes[offset] : nil }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, count <= remaining else {
            throw failure("need \(count) bytes, only \(remaining) remain")
        }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    mutating func readUInt8() throws -> UInt8 { try readBytes(1)[0] }
    mutating func readInt8() throws -> Int8 { Int8(bitPattern: try readUInt8()) }

    mutating func readUInt16() throws -> UInt16 {
        let b = try readBytes(2)
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }

    mutating func readInt16() throws -> Int16 { Int16(bitPattern: try readUInt16()) }

    mutating func readUInt32() throws -> UInt32 {
        let b = try readBytes(4)
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    mutating func readInt32() throws -> Int32 { Int32(bitPattern: try readUInt32()) }
    mutating func readFloat() throws -> Float { Float(bitPattern: try readUInt32()) }

    mutating func readDouble() throws -> Double {
        let low = UInt64(try readUInt32())
        let high = UInt64(try readUInt32())
        return Double(bitPattern: low | high << 32)
    }

    mutating func readString(lengthBytes: Int) throws -> String {
        let length: Int
        switch lengthBytes {
        case 1: length = Int(try readUInt8())
        case 2: length = Int(try readUInt16())
        default: throw failure("unsupported string length prefix: \(lengthBytes)")
        }
        let stringOffset = absoluteOffset
        let raw = try readBytes(length)
        guard let value = String(bytes: raw, encoding: .utf8) else {
            throw AssetError.malformed(name: "AXB", offset: stringOffset, reason: "invalid UTF-8 string")
        }
        return value
    }

    func failure(_ reason: String) -> AssetError {
        .malformed(name: "AXB", offset: absoluteOffset, reason: reason)
    }
}
