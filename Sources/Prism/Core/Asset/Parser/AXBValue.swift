import Foundation
import Math

/// a value stored in AXB metadata or a polygon field
public indirect enum AXBValue: Equatable, Sendable {
    case unknown
    case bool(Bool)
    case byte(Int8)
    case unsignedByte(UInt8)
    case short(Int16)
    case unsignedShort(UInt16)
    case integer(Int32)
    case unsignedInteger(UInt32)
    case float(Float)
    case double(Double)
    case vector([Float])
    case color4(UInt32)
    case string(String)
    case array([AXBValue])

    public var string: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
    public var float: Float? {
        guard case let .float(value) = self else { return nil }
        return value
    }
    public var vector2D: Vector2D? {
        guard case let .vector(values) = self, values.count >= 2 else { return nil }
        return Vector2D(values[0], values[1])
    }
    public var vectors2D: [Vector2D]? {
        guard case let .array(values) = self else { return nil }
        let points = values.compactMap(\.vector2D)
        return points.count == values.count ? points : nil
    }
}

/// a dynamic metadata map. unknown keys return 'nil'
@dynamicMemberLookup
public struct AXBMetadata: Sendable {
    private let values: [String: AXBValue]

    public init(_ values: [String: AXBValue] = [:]) { self.values = values }

    public subscript(dynamicMember key: String) -> AXBValue? { values[key] }
    public subscript(_ key: String) -> AXBValue? { values[key] }
    public var keys: [String] { Array(values.keys).sorted() }
    public var isEmpty: Bool { values.isEmpty }
}

public struct AXBVersion: Equatable, Sendable, CustomStringConvertible {
    public let major: UInt16
    public let minor: UInt16
    public var description: String { "\(major).\(minor)" }
}

public struct AXBHeader: Equatable, Sendable {
    public let version: AXBVersion
    public let flags: UInt32
    public let metadataOffset: UInt32
    public let metadataSize: UInt32
    public let polygonOffset: UInt32
    public let polygonSize: UInt32
    public let polygonCount: UInt32
}

public struct AXBField: Equatable, Sendable {
    public let typeTag: UInt8
    /// present for array fields; this is the format's array parameter,
    /// not its element count
    public let arrayParameter: UInt16?
    /// 'nil' means the field was declared without a default value
    public let value: AXBValue?
}

public struct AXBPolygon: Sendable {
    public let name: String
    public let isPresent: Bool
    public let template: String?
    public let fields: [String: AXBField]
    public let metadata: AXBMetadata

    public subscript(_ field: String) -> AXBField? { fields[field] }

    /// the 'vertices' array when it contains 2D vector values,
    /// otherwise an empty array
    public var vertices: [Vector2D] {
        fields["vertices"]?.value?.vectors2D ?? []
    }

    internal init(
        name: String,
        template: String?,
        fields: [String: AXBField],
        metadata: AXBMetadata = AXBMetadata(),
        isPresent: Bool = true
    ) {
        self.name = name
        self.isPresent = isPresent
        self.template = template
        self.fields = fields
        self.metadata = metadata
    }
}

/// named polygon assets. dynamic lookup enables 'file.mesh.Shape.vertices'
@dynamicMemberLookup
public struct AXBMeshCollection: Sendable {
    private let polygons: [String: AXBPolygon]
    public subscript(dynamicMember name: String) -> AXBPolygon {
        polygons[name] ?? AXBPolygon(name: name, template: nil, fields: [:], isPresent: false)
    }
    public subscript(_ name: String) -> AXBPolygon? { polygons[name] }
    public func contains(_ name: String) -> Bool { polygons[name] != nil }
    public var names: [String] { Array(polygons.keys).sorted() }

    internal init(_ polygons: [String: AXBPolygon]) { self.polygons = polygons }
}

/// parsed AXB file. 'metadata' addresses block zero; polygon-specific metadata
/// blocks can be accessed by their zero-based index with 'metadataBlocks'
public struct AXBFile: Sendable {
    public let header: AXBHeader
    public let metadataBlocks: [AXBMetadata]
    public let mesh: AXBMeshCollection

    public var metadata: AXBMetadata { metadataBlocks.first ?? AXBMetadata() }

    internal init(header: AXBHeader, metadataBlocks: [AXBMetadata], polygons: [String: AXBPolygon]) {
        self.header = header
        self.metadataBlocks = metadataBlocks
        self.mesh = AXBMeshCollection(polygons)
    }
}
