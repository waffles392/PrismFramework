import Testing

@testable import Core

private func metrics(
    width: Int = 800,
    height: Int = 600,
    pixelWidth: Int = 1600,
    pixelHeight: Int = 1200,
    displayScale: Float = 2
) -> WindowMetrics {
    WindowMetrics(
        width: width,
        height: height,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        displayScale: displayScale
    )
}

@Test func windowMetricsAreEqualWhenNothingChanged() {
    #expect(metrics() == metrics())
}

@Test func windowMetricsDetectEachChangedField() {
    let baseline = metrics()

    #expect(baseline != metrics(width: 801))
    #expect(baseline != metrics(height: 601))
    #expect(baseline != metrics(pixelWidth: 1601))
    #expect(baseline != metrics(pixelHeight: 1201))
    #expect(baseline != metrics(displayScale: 1))
}
