import Prism
import Testing

/// single-threaded CPU workloads the frame loop pays for every frame.
extension BenchmarkSuite {

    @Suite("Benchmark CPU", .timeLimit(.minutes(1))) struct CPUWorkloadBenchmarks {

        @Test @MainActor func particlesSimulateAndBuildVertices() {
            benchmarkSection("CPU")
            let system = ParticleSystem()
            let count = BenchmarkEnvironment.particleCount

            let (_, emitDuration) = measure {
                system.emitBurst(
                    at: .zero, count: count, color: SIMD4(1, 1, 1, 1), speedRange: 0...0,
                    sizeRange: 0.001...0.002, lifeRange: 100...100)
            }

            let (vertices, buildDuration) = measure { system.buildVertices() }
            #expect(vertices.count == count * 6)

            var steps = 0
            let (_, updateDuration) = measure {
                for _ in 0..<120 {
                    system.update(deltaTime: Float(1) / 120)
                    steps += 1
                }
            }
            #expect(steps == 120)

            benchmarkReport("emit \(benchmarkCount(count)) particles", emitDuration)
            benchmarkReport(
                "build particle vertices", buildDuration,
                "\(benchmarkCount(vertices.count)) vertices, "
                    + megabytes(vertices.count * MemoryLayout<ParticleVertex>.stride))
            benchmarkReport(
                "120 particle updates", updateDuration, perSecond(steps, in: updateDuration))
        }

        @Test @MainActor func sceneTraversesManyObjects() {
            benchmarkSection("CPU")
            let scene = Scene2D()
            let count = BenchmarkEnvironment.sceneObjectCount

            let (_, buildDuration) = measure {
                for _ in 0..<count { scene.addRootChild(MovingObject()) }
            }
            #expect(scene.root.children.count == count)

            let (_, updateDuration) = measure {
                for _ in 0..<60 { scene.update(deltaTime: Float(1) / 60) }
            }

            benchmarkReport("build scene", buildDuration, "\(benchmarkCount(count)) objects")
            benchmarkReport(
                "60 scene updates", updateDuration, "\(benchmarkCount(count * 60)) update calls")
        }
    }
}

@MainActor private final class MovingObject: GameObject {
    override func update(deltaTime: Float) { position.x += deltaTime }
}
