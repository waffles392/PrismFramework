import Testing

/// parent suite for every benchmark. `.serialized` is recursive, so a single
/// workload runs at a time: this keeps the measurements comparable and avoids
/// opening more than one GPU device at once.
@Suite("Benchmark", .serialized, .enabled(if: BenchmarkEnvironment.isEnabled)) struct BenchmarkSuite
{}
