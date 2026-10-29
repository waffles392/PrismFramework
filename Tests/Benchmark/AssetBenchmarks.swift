import Prism
import Testing

@testable import Core

/// parses a generated, non-trivial AXB asset through the real parser. this is
/// CPU-only: uploading and drawing the resulting mesh lives in the guarded GPU
/// suite.
extension BenchmarkSuite {

    @Suite("Benchmark asset", .timeLimit(.minutes(1))) struct AssetBenchmarks {

        @Test @MainActor func heavyAXBParsesAndTriangulates() throws {
            benchmarkSection("Assets")
            let polygonCount = BenchmarkEnvironment.axbPolygonCount
            let verticesPerPolygon = 64
            let data = makeHeavyAXB(
                polygonCount: polygonCount, verticesPerPolygon: verticesPerPolygon)

            let (file, parseDuration) = try measure {
                try AXBParser.parse(data, resourceName: "heavy.axb")
            }
            #expect(file.mesh.names.count == polygonCount)

            let parsedVertexCount = file.mesh.names.reduce(0) {
                $0 + (file.mesh[$1]?.vertices.count ?? 0)
            }
            #expect(parsedVertexCount == polygonCount * verticesPerPolygon)

            let (vertices, triangulateDuration) = measure { makeVertices(from: file) }
            #expect(!vertices.isEmpty)
            #expect(vertices.count % 3 == 0)

            benchmarkReport(
                "parse AXB", parseDuration,
                "\(benchmarkCount(polygonCount)) polygons, \(megabytes(data.count))")
            benchmarkReport(
                "triangulate AXB", triangulateDuration,
                "\(benchmarkCount(vertices.count / 3)) triangles")
        }
    }
}
