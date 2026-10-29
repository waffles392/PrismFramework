import CSDL3
import Foundation
import Graphics
import Prism

// MARK: - Environment

/// the benchmark suite opens a real window and talks to the GPU, so it is
/// opt-in. the gates are cumulative:
///
/// - `PRISM_BENCHMARK=1` - safe suites: asset parsing, audio, CPU workloads,
///   and a tiny device + swapchain smoke test
/// - `PRISM_BENCHMARK_GPU=1` - the GPU workloads (mesh, canvas, AXB upload),
///   conservative: 640x360, vsync, 30 frames
///
/// every workload stays small enough to run on an ordinary integrated GPU.
enum BenchmarkEnvironment {
    static var isEnabled: Bool { flag("PRISM_BENCHMARK") }
    static var isGPUEnabled: Bool { isEnabled && flag("PRISM_BENCHMARK_GPU") }

    /// GPU frames per workload
    static var gpuFrameCount: Int { 30 }

    /// a non-overlapping grid of this many triangles is drawn per frame
    static var triangleCount: Int { integer("PRISM_BENCHMARK_TRIANGLES", default: 5_000) }

    /// AXB polygons parsed and triangulated (CPU only)
    static var axbPolygonCount: Int { integer("PRISM_BENCHMARK_AXB_POLYGONS", default: 2_048) }

    /// AXB polygons converted into a GPU mesh in the guarded GPU suite
    static var axbGPUPolygonCount: Int { integer("PRISM_BENCHMARK_AXB_GPU_POLYGONS", default: 128) }

    /// circles recorded through `Canvas2D` in the safe GPU suite
    static var canvasPrimitiveCount: Int {
        integer("PRISM_BENCHMARK_CANVAS_PRIMITIVES", default: 2_000)
    }

    /// particles simulated on the CPU
    static var particleCount: Int { integer("PRISM_BENCHMARK_PARTICLES", default: 100_000) }

    /// objects added to a `Scene2D` for traversal timing
    static var sceneObjectCount: Int { integer("PRISM_BENCHMARK_SCENE_OBJECTS", default: 20_000) }

    private static func flag(_ key: String) -> Bool {
        ProcessInfo.processInfo.environment[key] == "1"
    }

    private static func integer(_ key: String, default value: Int) -> Int {
        guard let raw = ProcessInfo.processInfo.environment[key], let parsed = Int(raw) else {
            return value
        }
        return max(1, parsed)
    }
}

// MARK: - Timing

extension Duration {
    /// the duration in seconds, for throughput and FPS reporting
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

/// measures a synchronous block and returns its value alongside its duration
func measure<T>(_ body: () throws -> T) rethrows -> (value: T, duration: Duration) {
    let clock = ContinuousClock()
    var value: T?
    let duration = try clock.measure { value = try body() }
    return (value!, duration)
}

/// records one benchmark line for the summary shown when the test run exits
func benchmarkReport(_ label: String, _ duration: Duration, _ detail: String = "") {
    BenchmarkResults.shared.add(label, duration, detail)
}

func megabytes(_ bytes: Int) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

func benchmarkCount(_ value: Int) -> String {
    let text = String(value)
    var result = ""
    for (offset, character) in text.enumerated() {
        if offset > 0, (text.count - offset) % 3 == 0 { result.append(",") }
        result.append(character)
    }
    return result
}

func perSecond(_ count: Int, in duration: Duration) -> String {
    guard duration.seconds > 0 else { return "n/a" }
    return String(format: "%.0f/s", Double(count) / duration.seconds)
}

// MARK: - GPU harness

enum BenchmarkError: Error {
    case cancelled
    case deviceUnavailable
}

extension BenchmarkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cancelled: return "benchmark cancelled by closing the window"
        case .deviceUnavailable: return "GPU device became unavailable"
        }
    }
}

extension SDL_EventType {
    /// SDL's event enum imports as UInt32 on Linux and Int32 with MSVC
    fileprivate var rawUInt32: UInt32 { UInt32(truncatingIfNeeded: rawValue) }
}

/// a visible window, a real GPU device, and the engine's post-processor,
/// wired the same way `Prism.run` wires them.
///
/// the harness renders through an offscreen scene target because the built-in
/// 2D shader writes a colour and an emissive target; `PostProcessor` then
/// presents that target to the swapchain.
///
/// safety rails: vsync is left on, the window is small, SDL events are pumped
/// every frame (so a close request stops the run), and the device is checked
/// for life after every frame.
@MainActor final class BenchmarkGPU {
    let window: Window
    let renderer: Renderer
    let postProcessor: PostProcessor

    init(title: String, width: Int32 = 640, height: Int32 = 360) throws {
        let window = Window(title: title, width: width, height: height, flags: [.resizable])
        self.window = window

        let renderer = try Renderer(window: window.handle, windowOwner: window)
        self.renderer = renderer
        // vsync paces the workload without sleeping in the benchmark itself
        renderer.setVsync(true)

        let postProcessor = try PostProcessor(renderer: renderer)
        postProcessor.isEnabled = false
        self.postProcessor = postProcessor

        benchmarkContext("Driver", renderer.device.driverName)
        benchmarkContext("Window", "\(width)x\(height)")
        benchmarkContext("Frames", "\(BenchmarkEnvironment.gpuFrameCount)")
    }

    func shutdown() { renderer.shutdown() }

    /// acquires a frame, runs optional preparation (uploads must happen
    /// before a render pass begins), then draws through `body` into the HDR
    /// scene target and presents it. nothing touches the swapchain directly.
    func drawFrame(
        prepare: (Frame) throws -> Void = { _ in }, draw body: (Frame, RenderEncoder) throws -> Void
    ) throws {
        try pumpEvents()
        guard renderer.device.isAlive else { throw BenchmarkError.deviceUnavailable }

        // SDL 3.4 exposes no GPU device-lost event. a failed swapchain
        // acquisition or an interrupted renderer is the loss signal we get,
        // so stop the run rather than spin on a dead device.
        guard let frame = try renderer.beginFrame() else { throw BenchmarkError.deviceUnavailable }

        // geometry uploads open copy passes, which cannot be nested inside a
        // render pass: mirror the engine's prepare-then-render order
        try prepare(frame)
        postProcessor.prepare(frame: frame)

        let scene = try postProcessor.sceneTarget(width: frame.width, height: frame.height)
        let emissive = try postProcessor.emissiveTarget(width: frame.width, height: frame.height)
        let pass = try frame.beginRenderPass(
            to: scene, emissive: emissive, clearColor: Color(0, 0, 0, 1))

        try body(frame, pass)
        pass.end()

        postProcessor.draw(frame: frame, settings: PostProcessingSettings(), elapsedTime: 0)
        renderer.endFrame(frame)

        guard renderer.device.isAlive else { throw BenchmarkError.deviceUnavailable }
    }

    /// drains SDL events and stops when the user closes the window
    private func pumpEvents() throws {
        SDL_PumpEvents()
        var event = SDL_Event()
        while SDL_PollEvent(&event) {
            switch event.type {
            case SDL_EVENT_QUIT.rawUInt32, SDL_EVENT_WINDOW_CLOSE_REQUESTED.rawUInt32:
                throw BenchmarkError.cancelled
            default: break
            }
        }
    }
}

// MARK: - Generated workloads

/// a non-overlapping grid of small triangles in normalized device coordinates.
/// each triangle gets its own cell, so the workload tests vertex throughput
/// without asking the GPU to blend one hundred layers of full-screen overdraw.
func makeGridTriangles(triangleCount: Int, color: SIMD4<Float> = SIMD4(0.2, 0.6, 1, 1)) -> [Vertex]
{
    let columns = max(1, Int(Double(triangleCount).squareRoot().rounded(.up)))
    let rows = max(1, (triangleCount + columns - 1) / columns)
    let cellWidth = 2 / Float(columns)
    let cellHeight = 2 / Float(rows)

    var vertices: [Vertex] = []
    vertices.reserveCapacity(triangleCount * 3)

    for index in 0..<triangleCount {
        let column = index % columns
        let row = index / columns
        let x0 = -1 + Float(column) * cellWidth
        let y0 = -1 + Float(row) * cellHeight
        let x1 = x0 + cellWidth
        let y1 = y0 + cellHeight

        let a = Vector2D(x0 + cellWidth * 0.1, y0 + cellHeight * 0.1)
        let b = Vector2D(x1 - cellWidth * 0.1, y0 + cellHeight * 0.1)
        let c = Vector2D((x0 + x1) * 0.5, y1 - cellHeight * 0.1)

        vertices.append(Vertex(position: a, color: color))
        vertices.append(Vertex(position: b, color: color))
        vertices.append(Vertex(position: c, color: color))
    }

    return vertices
}

/// builds a valid AXB file with `polygonCount` regular polygons, so the
/// benchmark exercises the real parser rather than a hand-built array
func makeHeavyAXB(polygonCount: Int, verticesPerPolygon: Int) -> Data {
    precondition((3...255).contains(verticesPerPolygon))

    var state: UInt64 = 0xC0FF_EE00_1234_5678
    var polygons = Data()

    for index in 0..<polygonCount {
        appendString("P\(index)", to: &polygons)
        polygons.append(0)  // no template
        appendLE(UInt16(1), to: &polygons)  // one field

        appendString("vertices", to: &polygons)
        polygons.append(0x30)  // array
        polygons.append(0x10)  // vector2 element
        appendLE(UInt16(0), to: &polygons)  // array parameter
        polygons.append(1)  // has a default value
        polygons.append(UInt8(verticesPerPolygon))

        let center = Vector2D(unit(&state) * 2 - 1, unit(&state) * 2 - 1)
        let radius = 0.001 + unit(&state) * 0.002
        for vertex in 0..<verticesPerPolygon {
            let angle = Float(vertex) / Float(verticesPerPolygon) * 2 * .pi
            polygons.append(2)
            appendLE(Float(center.x + cos(angle) * radius), to: &polygons)
            appendLE(Float(center.y + sin(angle) * radius), to: &polygons)
        }
    }

    var data = Data()
    data.append(contentsOf: Array("AXIS".utf8))
    appendLE(UInt16(1), to: &data)  // major
    appendLE(UInt16(0), to: &data)  // minor
    appendLE(UInt32(0), to: &data)  // flags
    appendLE(UInt32(32), to: &data)  // metadata offset
    appendLE(UInt32(0), to: &data)  // metadata size
    appendLE(UInt32(32), to: &data)  // polygon offset
    appendLE(UInt32(polygons.count), to: &data)
    appendLE(UInt32(polygonCount), to: &data)
    data.append(polygons)
    return data
}

/// fan-triangulates every parsed polygon into the engine's 2D vertex layout
func makeVertices(from file: AXBFile, color: SIMD4<Float> = SIMD4(1, 1, 1, 1)) -> [Vertex] {
    var vertices: [Vertex] = []

    for name in file.mesh.names {
        guard let polygon = file.mesh[name], polygon.vertices.count >= 3 else { continue }
        let points = polygon.vertices
        let first = points[0]

        for index in 1..<(points.count - 1) {
            vertices.append(Vertex(position: first, color: color))
            vertices.append(Vertex(position: points[index], color: color))
            vertices.append(Vertex(position: points[index + 1], color: color))
        }
    }

    return vertices
}

/// writes a silent PCM16 WAV file large enough to make decoding visible
func makeSilentWAV(seconds: Double, sampleRate: Int = 48_000, channels: Int = 2) throws -> URL {
    let frames = Int(seconds * Double(sampleRate))
    let bytesPerSample = 2
    let payloadBytes = frames * channels * bytesPerSample

    var data = Data(capacity: 44 + payloadBytes)
    data.append(contentsOf: Array("RIFF".utf8))
    appendLE(UInt32(36 + payloadBytes), to: &data)
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    appendLE(UInt32(16), to: &data)
    appendLE(UInt16(1), to: &data)  // PCM
    appendLE(UInt16(channels), to: &data)
    appendLE(UInt32(sampleRate), to: &data)
    appendLE(UInt32(sampleRate * channels * bytesPerSample), to: &data)
    appendLE(UInt16(channels * bytesPerSample), to: &data)
    appendLE(UInt16(16), to: &data)
    data.append(contentsOf: Array("data".utf8))
    appendLE(UInt32(payloadBytes), to: &data)
    data.append(Data(count: payloadBytes))

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "prism-benchmark-\(UUID().uuidString).wav")
    try data.write(to: url)
    return url
}

// MARK: - Binary helpers

private func unit(_ state: inout UInt64) -> Float {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Float(state >> 40) / Float(1 << 24)
}

private func appendString(_ string: String, to data: inout Data) {
    let bytes = Array(string.utf8)
    precondition(bytes.count <= 255)
    data.append(UInt8(bytes.count))
    data.append(contentsOf: bytes)
}

private func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}

private func appendLE(_ value: Float, to data: inout Data) { appendLE(value.bitPattern, to: &data) }
