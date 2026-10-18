import Foundation

#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// reads how much memory the process is using
enum ProcessMemory {
    /// the resident set size in megabytes, or 'nil' when the platform cannot
    /// report it
    static func residentMegabytes() -> Double? {
        #if os(Linux)
        guard
            let contents = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8),
            let residentPages = contents.split(whereSeparator: \.isWhitespace).dropFirst().first
                .flatMap({ Int64($0) }),
            residentPages >= 0
        else { return nil }

        let pageSize = sysconf(Int32(_SC_PAGESIZE))
        guard pageSize > 0 else { return nil }
        return Double(residentPages * Int64(pageSize)) / 1_048_576
        #elseif canImport(Darwin)
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        // Darwin reports ru_maxrss in bytes; this is the process high-water mark
        return Double(usage.ru_maxrss) / 1_048_576
        #else
        return nil
        #endif
    }
}
