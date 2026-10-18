import Foundation

/// errors raised while loading the renderer's built-in shaders
public enum ShaderLibraryError: Error, CustomStringConvertible {
    /// the named shader could not be found in the Graphics resource bundle
    case notFound(String)

    public var description: String {
        switch self {
        case .notFound(let name):
            return "Built-in shader '\(name)' was not found in the Graphics resource bundle"
        }
    }
}

/// loads the renderer's built-in SPIR-V shaders
///
/// shaders ship inside the 'Graphics' module's resource bundle under
/// 'Shaders/'. the '.spv' files are committed and produced from the
/// neighbouring '.slang' sources by 'Scripts/build_shaders.py'
public enum ShaderLoader {
    /// the bundle that contains the renderer's shaders
    public static let bundle: Bundle = .module

    /// loads a built-in shader by file name (for example
    /// '"base.vert.spv"'), trapping with a clear message if it is missing
    ///
    /// the '.spv' files ship with the package, so this only traps when a
    /// checkout is broken or a shader was renamed without a rebuild
    public static func load(_ name: String) -> Data {
        do {
            return try data(named: name)
        } catch {
            fatalError("""
                Failed to load built-in shader '\(name)': \(error)
                The .spv shaders are committed and bundled by SwiftPM. In a \
                source checkout, re-run `make shaders` and rebuild.
                """)
        }
    }

    /// loads a built-in shader, throwing if it is missing
    public static func data(named name: String) throws -> Data {
        guard let url = bundle.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "Shaders"
        ) else {
            throw ShaderLibraryError.notFound(name)
        }
        return try Data(contentsOf: url)
    }
}
