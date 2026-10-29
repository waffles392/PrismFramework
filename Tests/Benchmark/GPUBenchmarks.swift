import Foundation
import Graphics
import Prism
import Testing

@testable import Core

extension BenchmarkSuite {

    /// a tiny, always-safe GPU smoke test. this opens a visible window and
    /// acquires a real device, but only clears and presents frames.
    @Suite("Benchmark GPU smoke", .timeLimit(.minutes(1))) struct GPUSmokeBenchmarks {

        @Test @MainActor func deviceAndSwapchainComeUp() throws {
            benchmarkSection("GPU smoke")
            let gpu = try BenchmarkGPU(title: "Prism Benchmark - GPU smoke")
            defer { gpu.shutdown() }

            #expect(gpu.renderer.device.isAlive)
            #expect(!gpu.renderer.device.driverName.isEmpty)

            let frameCount = BenchmarkEnvironment.gpuFrameCount
            var frames = 0
            let (_, duration) = try measure {
                for _ in 0..<frameCount {
                    try gpu.drawFrame { _, _ in }
                    frames += 1
                }
            }

            #expect(frames == frameCount)
            benchmarkReport(
                "\(frames) empty frames", duration, "\(perSecond(frames, in: duration))")
        }
    }

    /// guarded GPU workloads. these only run when `PRISM_BENCHMARK_GPU=1` is set
    /// alongside `PRISM_BENCHMARK=1`.
    @Suite(
        "Benchmark GPU", .timeLimit(.minutes(1)), .enabled(if: BenchmarkEnvironment.isGPUEnabled))
    struct GPUBenchmarks {

        @Test @MainActor func gridMeshUploadsAndDraws() throws {
            benchmarkSection("GPU mesh")
            let gpu = try BenchmarkGPU(title: "Prism Benchmark - grid mesh")
            defer { gpu.shutdown() }

            let triangleCount = BenchmarkEnvironment.triangleCount
            let (vertices, buildDuration) = measure {
                makeGridTriangles(triangleCount: triangleCount)
            }
            #expect(vertices.count == triangleCount * 3)

            // opaque geometry keeps the smoke test away from alpha-blend overdraw
            let surface = Surface(
                vertexShader: ShaderLoader.load("base.vert.spv"),
                fragmentShader: ShaderLoader.load("base.frag.spv"), blendMode: .normal)

            let (mesh, createDuration) = try measure {
                try Mesh(
                    device: gpu.renderer.device, sampler: gpu.renderer.linearSampler,
                    vertices: vertices, surface: surface)
            }
            #expect(mesh.vertexCount == vertices.count)

            let (_, uploadDuration) = try measure {
                try gpu.drawFrame(
                    prepare: { frame in try mesh.prepare(commandBuffer: frame.commandBuffer) },
                    draw: { _, pass in mesh.draw(in: pass) })
            }

            let frameCount = BenchmarkEnvironment.gpuFrameCount
            var frames = 0
            let (_, renderDuration) = try measure {
                for _ in 0..<frameCount {
                    try gpu.drawFrame(
                        prepare: { frame in try mesh.prepare(commandBuffer: frame.commandBuffer) },
                        draw: { _, pass in mesh.draw(in: pass) })
                    frames += 1
                }
            }

            benchmarkReport(
                "build \(benchmarkCount(triangleCount)) grid triangles", buildDuration,
                megabytes(mesh.vertexCount * Vertex.stride))
            benchmarkReport("create GPU mesh", createDuration)
            benchmarkReport("grid first frame", uploadDuration, "upload + draw")
            benchmarkReport(
                "\(frames) grid frames", renderDuration, "\(perSecond(frames, in: renderDuration))")
        }

        @Test @MainActor func canvasBuildsAndDrawsManyPrimitives() throws {
            benchmarkSection("Canvas 2D")
            let gpu = try BenchmarkGPU(title: "Prism Benchmark - canvas")
            defer { gpu.shutdown() }

            let canvas = Canvas2D()
            try canvas.configure(
                renderer: gpu.renderer, vertexShaderCode: ShaderLoader.load("base.vert.spv"),
                fragmentShaderCode: ShaderLoader.load("base.frag.spv"))

            let primitiveCount = BenchmarkEnvironment.canvasPrimitiveCount
            let width = Float(gpu.window.width)
            let height = Float(gpu.window.height)
            let columns = 80

            // mirror Prism.renderFrame: rebuild the immediate-mode canvas every
            // frame, then upload and draw it
            let buildCanvas = {
                canvas.begin(windowWidth: gpu.window.width, windowHeight: gpu.window.height)
                for index in 0..<primitiveCount {
                    let x = Float(index % columns) * (width / Float(columns))
                    let y = Float(index / columns % 45) * (height / 45)
                    canvas.circle(at: Vector2D(x, y), radius: 1.5, segments: 12, filled: true)
                }
            }

            let buildIterations = 10
            let (_, buildDuration) = measure { for _ in 0..<buildIterations { buildCanvas() } }

            let (_, uploadDuration) = try measure {
                try gpu.drawFrame(
                    prepare: { frame in
                        buildCanvas()
                        try canvas.prepare(frame: frame)
                    }, draw: { _, pass in canvas.draw(in: pass) })
            }

            let frameCount = BenchmarkEnvironment.gpuFrameCount
            var frames = 0
            let (_, drawDuration) = try measure {
                for _ in 0..<frameCount {
                    try gpu.drawFrame(
                        prepare: { frame in
                            buildCanvas()
                            try canvas.prepare(frame: frame)
                        }, draw: { _, pass in canvas.draw(in: pass) })
                    frames += 1
                }
            }

            #expect(canvas.vertexCount > 0)
            #expect(canvas.drawCallCount > 0)
            #expect(canvas.triangleCount == canvas.vertexCount / 3)

            benchmarkReport(
                "canvas build", buildDuration,
                "\(buildIterations) frames, \(benchmarkCount(primitiveCount)) circles, "
                    + String(
                        format: "%.2f ms/frame",
                        buildDuration.seconds * 1_000 / Double(buildIterations)))
            benchmarkReport("canvas first frame", uploadDuration, "build + upload + draw")
            let drawCalls =
                canvas.drawCallCount == 1
                ? "1 draw call" : "\(benchmarkCount(canvas.drawCallCount)) draw calls"
            benchmarkReport(
                "\(frames) canvas frames", drawDuration,
                "\(perSecond(frames, in: drawDuration)), \(drawCalls)")
        }

        @Test @MainActor func axbMeshUploadsAndDraws() throws {
            benchmarkSection("GPU assets")
            let polygonCount = BenchmarkEnvironment.axbGPUPolygonCount
            let data = makeHeavyAXB(polygonCount: polygonCount, verticesPerPolygon: 32)
            let (file, parseDuration) = try measure {
                try AXBParser.parse(data, resourceName: "gpu-heavy.axb")
            }

            let vertices = makeVertices(from: file)
            #expect(!vertices.isEmpty)

            let gpu = try BenchmarkGPU(title: "Prism Benchmark - AXB upload")
            defer { gpu.shutdown() }

            let surface = Surface(
                vertexShader: ShaderLoader.load("base.vert.spv"),
                fragmentShader: ShaderLoader.load("base.frag.spv"), blendMode: .normal)
            let (mesh, createDuration) = try measure {
                try Mesh(
                    device: gpu.renderer.device, sampler: gpu.renderer.linearSampler,
                    vertices: vertices, surface: surface)
            }
            #expect(mesh.vertexCount == vertices.count)

            let (_, uploadDuration) = try measure {
                try gpu.drawFrame(
                    prepare: { frame in try mesh.prepare(commandBuffer: frame.commandBuffer) },
                    draw: { _, pass in mesh.draw(in: pass) })
            }

            let frameCount = BenchmarkEnvironment.gpuFrameCount
            var frames = 0
            let (_, renderDuration) = try measure {
                for _ in 0..<frameCount {
                    try gpu.drawFrame(
                        prepare: { frame in try mesh.prepare(commandBuffer: frame.commandBuffer) },
                        draw: { _, pass in mesh.draw(in: pass) })
                    frames += 1
                }
            }

            benchmarkReport(
                "parse AXB for GPU", parseDuration,
                "\(benchmarkCount(polygonCount)) polygons, \(megabytes(data.count))")
            benchmarkReport("create GPU mesh from AXB", createDuration)
            benchmarkReport("AXB first frame", uploadDuration, "upload + draw")
            benchmarkReport(
                "\(frames) AXB frames", renderDuration, perSecond(frames, in: renderDuration))
        }
    }
}
