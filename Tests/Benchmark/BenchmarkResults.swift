import Foundation

struct BenchmarkResultRow {
    let label: String
    let duration: Duration
    let detail: String
}

struct BenchmarkResultSection {
    let name: String
    var rows: [BenchmarkResultRow]
}

/// collects benchmark rows while tests run and prints a terminal summary when
/// the test process exits. `atexit` is used instead of a synthetic final test
/// because Swift Testing does not guarantee test ordering.
final class BenchmarkResults: @unchecked Sendable {
    static let shared = BenchmarkResults()

    private let lock = NSLock()
    private var sections: [BenchmarkResultSection] = []
    private var context: [String: String] = [:]
    private var currentSection = "General"

    private init() { atexit(benchmarkSummaryAtExit) }

    func beginSection(_ name: String) {
        lock.lock()
        defer { lock.unlock() }

        currentSection = name
        if !sections.contains(where: { $0.name == name }) {
            sections.append(BenchmarkResultSection(name: name, rows: []))
        }
    }

    func setContext(_ key: String, _ value: String) {
        lock.lock()
        defer { lock.unlock() }
        context[key] = value
    }

    func add(_ label: String, _ duration: Duration, _ detail: String) {
        lock.lock()
        defer { lock.unlock() }

        let row = BenchmarkResultRow(label: label, duration: duration, detail: detail)
        if let index = sections.firstIndex(where: { $0.name == currentSection }) {
            sections[index].rows.append(row)
        } else {
            sections.append(BenchmarkResultSection(name: currentSection, rows: [row]))
        }
    }

    func render() {
        lock.lock()
        let sections = sections.filter { !$0.rows.isEmpty }
        let context = context
        lock.unlock()

        guard !sections.isEmpty else { return }

        let output = BenchmarkSummaryRenderer(sections: sections, context: context).render()
        FileHandle.standardOutput.write(Data(output.utf8))
    }
}

private func benchmarkSummaryAtExit() { BenchmarkResults.shared.render() }

func benchmarkSection(_ name: String) { BenchmarkResults.shared.beginSection(name) }

func benchmarkContext(_ key: String, _ value: String) {
    BenchmarkResults.shared.setContext(key, value)
}

// MARK: - Rendering

private struct BenchmarkSummaryRenderer {
    let sections: [BenchmarkResultSection]
    let context: [String: String]

    private let ansi = BenchmarkANSI()
    private let width: Int = {
        let columns = ProcessInfo.processInfo.environment["COLUMNS"].flatMap(Int.init) ?? 100
        return max(80, min(columns, 120))
    }()

    private var labelWidth: Int {
        let longest = sections.flatMap { $0.rows }.map(\.label.count).max() ?? 20
        return max(20, min(longest, 34))
    }

    private var timeWidth: Int { 10 }
    private var detailWidth: Int { max(12, width - labelWidth - timeWidth - 6) }

    func render() -> String {
        var lines: [String] = []
        lines.append(ansi.paint("prism benchmark", "1"))

        var meta = ["\(platform.lowercased()) / \(cores) logical CPUs"]
        if let driver = context["Driver"] { meta.append(driver) }
        if let window = context["Window"] { meta.append(window) }
        if let frames = context["Frames"] { meta.append("\(frames) frames") }
        lines.append(ansi.paint(meta.joined(separator: " / "), "2"))

        for section in sections {
            lines.append("")
            lines.append(ansi.paint(section.name.lowercased(), "1"))

            for row in section.rows {
                var line = "  " + padRight(row.label, labelWidth)
                line += "  " + ansi.paint(padLeft(formatDuration(row.duration), timeWidth), "32")
                if !row.detail.isEmpty { line += "  " + fit(row.detail, detailWidth) }
                lines.append(line)
            }
        }

        if context["Driver"] != nil {
            lines.append("")
            lines.append(ansi.paint("gpu frame times are vsync-paced", "2"))
        }

        return "\n" + lines.joined(separator: "\n") + "\n"
    }

    private var platform: String {
        #if os(Linux)
            let os = "Linux"
        #elseif os(macOS)
            let os = "macOS"
        #elseif os(Windows)
            let os = "Windows"
        #else
            let os = "Unknown"
        #endif

        #if arch(x86_64)
            let arch = "x86_64"
        #elseif arch(arm64)
            let arch = "arm64"
        #else
            let arch = "unknown"
        #endif

        return "\(os) \(arch)"
    }

    private var cores: Int { ProcessInfo.processInfo.processorCount }

    private func formatDuration(_ duration: Duration) -> String {
        let seconds = duration.seconds
        if seconds >= 1 { return String(format: "%.2f s", seconds) }

        let milliseconds = seconds * 1_000
        if milliseconds >= 100 { return String(format: "%.0f ms", milliseconds) }
        if milliseconds >= 10 { return String(format: "%.1f ms", milliseconds) }
        return String(format: "%.2f ms", milliseconds)
    }

    private func padRight(_ text: String, _ width: Int) -> String {
        let fitted = fit(text, width)
        return fitted + String(repeating: " ", count: max(0, width - fitted.count))
    }

    private func padLeft(_ text: String, _ width: Int) -> String {
        let fitted = fit(text, width)
        return String(repeating: " ", count: max(0, width - fitted.count)) + fitted
    }

    private func fit(_ text: String, _ width: Int) -> String {
        guard text.count > width else { return text }
        guard width > 0 else { return "" }
        return String(text.prefix(width - 1)) + "…"
    }
}

private struct BenchmarkANSI {
    private let enabled: Bool

    init() {
        let environment = ProcessInfo.processInfo.environment
        if environment["NO_COLOR"] != nil || environment["TERM"] == "dumb" {
            enabled = false
        } else {
            enabled =
                environment["TERM"] != nil || environment["COLORTERM"] != nil
                || environment["WT_SESSION"] != nil
        }
    }

    func paint(_ text: String, _ code: String) -> String {
        guard enabled else { return text }
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }
}
