import Foundation

/// writes a once-per-second FPS and memory line to the terminal
///
/// the line goes to standard error and rewrites itself in place, so it never
/// mixes with the game's own output on standard out. the clock, the memory
/// reading and the destination are all injected, which keeps the type testable
/// without a terminal
@MainActor
final class ConsoleStats {
    /// how often a line is written, in seconds
    private let interval: Double
    /// reads the current uptime, in seconds
    private let clock: () -> Double
    /// reads resident memory in megabytes, or 'nil' when unavailable
    private let memory: () -> Double?
    /// receives finished lines
    private let write: (String) -> Void

    private var frameCount = 0
    private var lastUpdate: Double

    init(
        interval: Double = 1,
        clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
        memory: @escaping () -> Double? = ProcessMemory.residentMegabytes,
        write: @escaping (String) -> Void = ConsoleStats.writeToStandardError
    ) {
        self.interval = interval
        self.clock = clock
        self.memory = memory
        self.write = write
        self.lastUpdate = clock()
    }

    /// counts a frame, writing a line once the interval has passed
    func frameCompleted() {
        frameCount += 1

        let now = clock()
        let elapsed = now - lastUpdate
        guard elapsed >= interval else { return }

        write(Self.line(fps: Double(frameCount) / elapsed, memoryMegabytes: memory()))
        frameCount = 0
        lastUpdate = now
    }

    /// ends the live line so the next output starts on a clean row
    func finish() {
        write("\n")
    }

    /// the text of a single status line
    ///
    /// pure, so the exact format can be checked without writing to a terminal
    nonisolated static func line(fps: Double, memoryMegabytes: Double?) -> String {
        let memory = memoryMegabytes.map { String(format: "%8.1f MB", $0) } ?? "unavailable"
        return String(format: "\rFPS: %6.1f | RAM: %@\u{001B}[K", fps, memory)
    }

    private nonisolated static func writeToStandardError(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}
