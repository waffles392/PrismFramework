import Foundation
import Math

/// a normalized sRGB RGBA color used by graphics APIs
///
/// components are typically in the range 0...1, but may exceed 1 for
/// HDR emissive colors
public struct Color: Equatable, Sendable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        self.red = max(0, red)
        self.green = max(0, green)
        self.blue = max(0, blue)
        self.alpha = max(0, alpha)
    }

    public init(_ value: Float, alpha: Float = 1) {
        self.init(red: value, green: value, blue: value, alpha: alpha)
    }

    public init(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float = 1) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    public init(rgba8 red: UInt8, _ green: UInt8, _ blue: UInt8, _ alpha: UInt8 = 255) {
        self.init(
            red: Float(red) / 255,
            green: Float(green) / 255,
            blue: Float(blue) / 255,
            alpha: Float(alpha) / 255
        )
    }

    public init(rgba16 red: UInt16, _ green: UInt16, _ blue: UInt16, _ alpha: UInt16 = 65535) {
        self.init(
            red: Float(red) / 65535,
            green: Float(green) / 65535,
            blue: Float(blue) / 65535,
            alpha: Float(alpha) / 65535
        )
    }

    /// parses #RGB, #RGBA, #RRGGBB, or #RRGGBBAA
    public init(hex: String) {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let expanded: String

        switch value.count {
        case 3, 4:
            expanded = value.map { "\($0)\($0)" }.joined()
        case 6, 8:
            expanded = value
        default:
            preconditionFailure("Invalid color hex string: \(hex)")
        }

        guard let encoded = UInt32(expanded, radix: 16) else {
            preconditionFailure("Invalid color hex string: \(hex)")
        }

        let hasAlpha = expanded.count == 8
        let red = UInt8((encoded >> (hasAlpha ? 24 : 16)) & 0xff)
        let green = UInt8((encoded >> (hasAlpha ? 16 : 8)) & 0xff)
        let blue = UInt8((encoded >> (hasAlpha ? 8 : 0)) & 0xff)
        let alpha = hasAlpha ? UInt8(encoded & 0xff) : 255
        self.init(rgba8: red, green, blue, alpha)
    }

    public var rgba8: (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        (
            Self.toByte(red),
            Self.toByte(green),
            Self.toByte(blue),
            Self.toByte(alpha)
        )
    }

    public var rgba16: (red: UInt16, green: UInt16, blue: UInt16, alpha: UInt16) {
        (
            UInt16((red * 65535).rounded()),
            UInt16((green * 65535).rounded()),
            UInt16((blue * 65535).rounded()),
            UInt16((alpha * 65535).rounded())
        )
    }

    public func hex(includeAlpha: Bool = false) -> String {
        let c = rgba8
        let base = String(format: "#%02X%02X%02X", c.red, c.green, c.blue)
        return includeAlpha ? base + String(format: "%02X", c.alpha) : base
    }

    public var isVisible: Bool { alpha > 0 }

    public func withAlpha(_ alpha: Float) -> Color {
        Color(red: red, green: green, blue: blue, alpha: alpha)
    }

    public func multiplied(by factor: Float) -> Color {
        Color(red: red * factor, green: green * factor, blue: blue * factor, alpha: alpha)
    }

    public func multiplied(by other: Color) -> Color {
        Color(red: red * other.red, green: green * other.green, blue: blue * other.blue, alpha: alpha * other.alpha)
    }

    public func adding(_ other: Color) -> Color {
        Color(red: red + other.red, green: green + other.green, blue: blue + other.blue, alpha: alpha + other.alpha)
    }

    public func subtracting(_ other: Color) -> Color {
        Color(red: red - other.red, green: green - other.green, blue: blue - other.blue, alpha: alpha)
    }

    public func interpolated(to other: Color, amount: Float) -> Color {
        let t = Self.clamp01(amount)
        return Color(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }

    public func lightened(by amount: Float) -> Color {
        interpolated(to: Color(1, alpha: alpha), amount: amount)
    }

    public func darkened(by amount: Float) -> Color {
        interpolated(to: Color(0, alpha: alpha), amount: amount)
    }

    public var inverted: Color {
        Color(red: 1 - red, green: 1 - green, blue: 1 - blue, alpha: alpha)
    }

    public var luminance: Float {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    public var simdValue: SIMD4<Float> {
        SIMD4(red, green, blue, alpha)
    }

    /// the color converted from sRGB input values to linear-light RGB
    public var linearValue: SIMD4<Float> {
        func linearize(_ component: Float) -> Float {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return SIMD4(linearize(red), linearize(green), linearize(blue), alpha)
    }

    private static func clamp01(_ value: Float) -> Float {
        min(1, max(0, value))
    }

    private static func toByte(_ value: Float) -> UInt8 {
        UInt8((clamp01(value) * 255).rounded())
    }

    // MARK: - Common Colors

    public static let clear = Color(0, 0, 0, 0)
    public static let black = Color(0, 0, 0)
    public static let white = Color(1, 1, 1)
    public static let red = Color(1, 0, 0)
    public static let green = Color(0, 1, 0)
    public static let blue = Color(0, 0, 1)
    public static let yellow = Color(1, 1, 0)
    public static let cyan = Color(0, 1, 1)
    public static let magenta = Color(1, 0, 1)
    public static let gray = Color(0.5, 0.5, 0.5)
}

/// blend operation used while drawing a surface or 2D primitive
///
/// 'normal' disables blending entirely (opaque writes)
///
/// 'multiply', 'screen', and 'overlay' are approximated with fixed-function
/// blend factors by the GPU pipeline - they are not exact shader-level blends
public enum BlendMode: CaseIterable, Equatable, Sendable {
    case normal
    case alpha
    case additive
    case multiply
    case screen
    case overlay
}