import Foundation
import Testing
@testable import Prism

@Test func assetStoreLoadsAndCachesBundledData() throws {
    let store = AssetStore(bundle: Bundle.module)
    let first = try store.loadData(named: "text", withExtension: "txt", subdirectory: "Resources/assets")
    let second = try store.loadData(named: "text", withExtension: "txt", subdirectory: "Resources/assets")

    #expect(first == second)
    #expect(String(data: first, encoding: .utf8)?.contains("const float TILE_SIZE = 32.0") == true)
    #expect(try store.url(forResource: "mesh", withExtension: "axb", subdirectory: "Resources/assets").lastPathComponent == "mesh.axb")
}

@Test func assetStoreParsesAXBMesh() throws {
    let store = AssetStore(bundle: Bundle.module)
    let file = try store.loadAXB(named: "mesh", subdirectory: "Resources/assets")

    #expect(file.header.version.major == 1)
    #expect(file.mesh.contains("Shape"))
    #expect(file.mesh.Shape.isPresent)
    #expect(file.mesh.Shape.template == "Ground")
    #expect(file.mesh.Shape.vertices.count == 3)
    #expect(file.mesh.Shape.vertices[0].x == 1.2)
    #expect(file.mesh.Shape.vertices[2].y == -1.8)
    #expect(!file.mesh.MissingShape.isPresent)
}

@Test func assetStoreReportsMissingResources() {
    let store = AssetStore(bundle: Bundle.module)

    do {
        _ = try store.loadData(named: "absent", withExtension: "bin")
        Issue.record("Expected a missing asset error")
    } catch let error as AssetError {
        guard case .notFound(name: "absent", fileExtension: "bin", subdirectory: nil) = error else {
            Issue.record("Unexpected asset error: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
