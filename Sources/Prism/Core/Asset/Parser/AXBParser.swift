import Foundation

/// decodes the AXB binary polygon format into an 'AXBFile'
///
/// every failure is re-thrown as 'AssetError.malformed' carrying the byte
/// offset it came from, so a corrupt file points at what broke it
internal enum AXBParser {
    static func parse(_ data: Data, resourceName: String) throws -> AXBFile {
        do {
            return try parseContents(data, resourceName: resourceName)
        } catch let error as AssetError {
            throw relabeled(error, resourceName: resourceName)
        }
    }

    private static func parseContents(_ data: Data, resourceName: String) throws -> AXBFile {
        guard data.count >= 32 else {
            throw malformed(resourceName, 0, "file is shorter than the 32-byte header")
        }

        var reader = AXBReader(data: data)
        let magic = try reader.readBytes(4)
        guard magic == Array("AXIS".utf8) else {
            throw malformed(resourceName, 0, "expected AXIS magic")
        }

        let major = try reader.readUInt16()
        let minor = try reader.readUInt16()
        let flags = try reader.readUInt32()
        let metadataOffset = try reader.readUInt32()
        let metadataSize = try reader.readUInt32()
        let polygonOffset = try reader.readUInt32()
        let polygonSize = try reader.readUInt32()
        let polygonCount = try reader.readUInt32()
        let header = AXBHeader(
            version: AXBVersion(major: major, minor: minor),
            flags: flags,
            metadataOffset: metadataOffset,
            metadataSize: metadataSize,
            polygonOffset: polygonOffset,
            polygonSize: polygonSize,
            polygonCount: polygonCount
        )

        let metadataRange = try sectionRange(offset: metadataOffset, size: metadataSize, fileSize: data.count, name: resourceName, label: "metadata")
        let polygonRange = try sectionRange(offset: polygonOffset, size: polygonSize, fileSize: data.count, name: resourceName, label: "polygon")

        let metadataData = data.subdata(in: metadataRange)
        let metadataBlocks = try parseMetadata(metadataData, baseOffset: metadataRange.lowerBound, resourceName: resourceName)
        let polygonData = data.subdata(in: polygonRange)
        let polygons = try parsePolygons(
            polygonData,
            baseOffset: polygonRange.lowerBound,
            count: polygonCount,
            metadataBlocks: metadataBlocks,
            resourceName: resourceName
        )
        return AXBFile(header: header, metadataBlocks: metadataBlocks, polygons: polygons)
    }

    private static func sectionRange(offset: UInt32, size: UInt32, fileSize: Int, name: String, label: String) throws -> Range<Int> {
        let start = UInt64(offset)
        let end = start + UInt64(size)
        guard end <= UInt64(fileSize), start <= UInt64(Int.max) else {
            throw malformed(name, Int(min(start, UInt64(Int.max))), "\(label) section extends past end of file")
        }
        return Int(start)..<Int(end)
    }

    private static func parseMetadata(_ data: Data, baseOffset: Int, resourceName: String) throws -> [AXBMetadata] {
        guard !data.isEmpty else { return [] }
        var reader = AXBReader(data: data, baseOffset: baseOffset)
        var blocks: [AXBMetadata] = []
        var values: [String: AXBValue] = [:]

        while reader.hasMore {
            if reader.peekUInt8() == 0xFF {
                _ = try reader.readUInt8()
                blocks.append(AXBMetadata(values))
                values.removeAll(keepingCapacity: true)
                continue
            }
            let keyOffset = reader.absoluteOffset
            do {
                let key = try reader.readString(lengthBytes: 1)
                let tag = try reader.readUInt8()
                values[key] = try readValue(tag: tag, from: &reader)
            } catch let error as AssetError {
                throw relabeled(error, resourceName: resourceName)
            } catch {
                throw malformed(resourceName, keyOffset, error.localizedDescription)
            }
        }
        blocks.append(AXBMetadata(values))
        return blocks
    }

    private static func parsePolygons(
        _ data: Data,
        baseOffset: Int,
        count: UInt32,
        metadataBlocks: [AXBMetadata],
        resourceName: String
    ) throws -> [String: AXBPolygon] {
        var reader = AXBReader(data: data, baseOffset: baseOffset)
        var polygons: [String: AXBPolygon] = [:]

        for index in 0..<count {
            let start = reader.absoluteOffset
            do {
                let name = try reader.readString(lengthBytes: 1)
                let templateLength = Int(try reader.readUInt8())
                let template: String?
                if templateLength == 0 {
                    template = nil
                } else {
                    let templateOffset = reader.absoluteOffset
                    let raw = try reader.readBytes(templateLength)
                    guard let decoded = String(bytes: raw, encoding: .utf8) else {
                        throw malformed(resourceName, templateOffset, "invalid UTF-8 template name")
                    }
                    template = decoded
                }

                let fieldCount = try reader.readUInt16()
                var fields: [String: AXBField] = [:]
                for _ in 0..<fieldCount {
                    let fieldName = try reader.readString(lengthBytes: 1)
                    let tag = try reader.readUInt8()
                    if tag == 0x30 {
                        let elementTag = try reader.readUInt8()
                        let parameter = try reader.readUInt16()
                        let hasDefault = try reader.readUInt8() != 0
                        let value = hasDefault ? try readArray(elementTag: elementTag, from: &reader) : nil
                        fields[fieldName] = AXBField(typeTag: tag, arrayParameter: parameter, value: value)
                    } else {
                        let hasDefault = try reader.readUInt8() != 0
                        let value = hasDefault ? try readValue(tag: tag, from: &reader) : nil
                        fields[fieldName] = AXBField(typeTag: tag, arrayParameter: nil, value: value)
                    }
                }
                guard polygons[name] == nil else {
                    throw malformed(resourceName, start, "duplicate polygon name '\(name)'")
                }
                let metadata = Int(index) < metadataBlocks.count ? metadataBlocks[Int(index)] : AXBMetadata()
                polygons[name] = AXBPolygon(name: name, template: template, fields: fields, metadata: metadata)
            } catch let error as AssetError {
                throw relabeled(error, resourceName: resourceName)
            } catch {
                throw malformed(resourceName, start, error.localizedDescription)
            }
        }
        return polygons
    }

    private static func readArray(elementTag: UInt8, from reader: inout AXBReader) throws -> AXBValue {
        let count = Int(try reader.readUInt8())
        var values: [AXBValue] = []
        values.reserveCapacity(count)
        for _ in 0..<count { values.append(try readValue(tag: elementTag, from: &reader)) }
        return .array(values)
    }

    private static func readValue(tag: UInt8, from reader: inout AXBReader) throws -> AXBValue {
        switch tag {
        case 0x00: return .unknown
        case 0x01: return .bool(try reader.readUInt8() != 0)
        case 0x02: return .byte(try reader.readInt8())
        case 0x03: return .unsignedByte(try reader.readUInt8())
        case 0x04: return .short(try reader.readInt16())
        case 0x05: return .unsignedShort(try reader.readUInt16())
        case 0x06: return .integer(try reader.readInt32())
        case 0x07: return .unsignedInteger(try reader.readUInt32())
        case 0x08: return .float(try reader.readFloat())
        case 0x09: return .double(try reader.readDouble())
        case 0x10:
            let count = Int(try reader.readUInt8())
            var components: [Float] = []
            components.reserveCapacity(count)
            for _ in 0..<count { components.append(try reader.readFloat()) }
            return .vector(components)
        case 0x20: return .color4(try reader.readUInt32())
        case 0x50: return .string(try reader.readString(lengthBytes: 2))
        default:
            throw reader.failure(String(format: "unsupported value type tag 0x%02X", tag))
        }
    }

    private static func relabeled(_ error: AssetError, resourceName: String) -> AssetError {
        guard case let .malformed(_, offset, reason) = error else { return error }
        return malformed(resourceName, offset, reason)
    }

    private static func malformed(_ name: String, _ offset: Int, _ reason: String) -> AssetError {
        .malformed(name: name, offset: offset, reason: reason)
    }
}
