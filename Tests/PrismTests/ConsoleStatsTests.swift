import Testing
@testable import Core

@MainActor
@Test func consoleStatsWritesOncePerInterval() {
    var clock = 0.0
    var written: [String] = []
    let stats = ConsoleStats(
        interval: 1,
        clock: { clock },
        memory: { 42 },
        write: { written.append($0) }
    )

    // two frames spread over half a second: nothing is written yet
    stats.frameCompleted()
    clock = 0.5
    stats.frameCompleted()
    #expect(written.isEmpty)

    // a third frame lands on the one-second mark: 3 frames / 1s = 3 FPS
    clock = 1.0
    stats.frameCompleted()

    #expect(written.count == 1)
    #expect(written[0].contains("FPS:"))
    #expect(written[0].contains("3.0"))
    #expect(written[0].contains("42.0 MB"))

    stats.finish()
    #expect(written.count == 2)
    #expect(written[1] == "\n")
}

@Test func consoleStatsLineFormatsTheStatusLine() {
    let line = ConsoleStats.line(fps: 59.94, memoryMegabytes: 128.5)

    #expect(line.hasPrefix("\rFPS: "))
    #expect(line.contains("59.9"))
    #expect(line.contains("128.5 MB"))
    #expect(line.hasSuffix("\u{001B}[K"))
}

@Test func consoleStatsLineReportsUnavailableMemory() {
    let line = ConsoleStats.line(fps: 60, memoryMegabytes: nil)

    #expect(line.contains("unavailable"))
}

@Test func processMemoryIsPositiveWhenAvailable() {
    if let megabytes = ProcessMemory.residentMegabytes() {
        #expect(megabytes > 0)
    }
}
