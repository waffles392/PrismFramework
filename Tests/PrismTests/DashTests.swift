import Testing
import Math
@testable import Graphics

private let tolerance: Float = 1e-4

private func close(_ a: Vector2D, _ b: Vector2D) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

private func closeRun(_ run: [Vector2D], _ expected: [Vector2D]) -> Bool {
    run.count == expected.count && zip(run, expected).allSatisfy { close($0, $1) }
}

private func straightLine(_ length: Float) -> [Vector2D] {
    [Vector2D(0, 0), Vector2D(length, 0)]
}

private let square = [
    Vector2D(0, 0),
    Vector2D(10, 0),
    Vector2D(10, 10),
    Vector2D(0, 10)
]

// MARK: - open paths

@Test func dashSplitsAStraightPath() {
    let runs = DashPattern(pattern: [4, 2]).segments(of: straightLine(10), closed: false)

    #expect(runs.count == 2)
    #expect(closeRun(runs[0], [Vector2D(0, 0), Vector2D(4, 0)]))
    #expect(closeRun(runs[1], [Vector2D(6, 0), Vector2D(10, 0)]))
}

@Test func dashPhaseMovesThePatternAlong() {
    let runs = DashPattern(pattern: [4, 2], phase: 2).segments(of: straightLine(10), closed: false)

    #expect(runs.count == 2)
    #expect(closeRun(runs[0], [Vector2D(0, 0), Vector2D(2, 0)]))
    #expect(closeRun(runs[1], [Vector2D(4, 0), Vector2D(8, 0)]))
}

@Test func dashPhaseWrapsAroundThePattern() {
    let wrapped = DashPattern(pattern: [4, 2], phase: 8).segments(of: straightLine(10), closed: false)
    let equivalent = DashPattern(pattern: [4, 2], phase: 2).segments(of: straightLine(10), closed: false)

    #expect(wrapped.count == equivalent.count)
    for (run, expected) in zip(wrapped, equivalent) {
        #expect(closeRun(run, expected))
    }
}

@Test func dashOddPatternRepeatsLikeSVG() {
    let odd = DashPattern(pattern: [4, 2, 1]).segments(of: straightLine(10), closed: false)
    let doubled = DashPattern(pattern: [4, 2, 1, 4, 2, 1]).segments(of: straightLine(10), closed: false)

    #expect(odd.count == doubled.count)
    for (run, expected) in zip(odd, doubled) {
        #expect(closeRun(run, expected))
    }
}

@Test func dashCarriesAcrossPathVertices() {
    // a dash longer than one edge keeps going around the corner, and a gap
    // that spans a corner takes the vertex with it
    let path = [Vector2D(0, 0), Vector2D(3, 0), Vector2D(3, 3), Vector2D(6, 3)]
    let runs = DashPattern(pattern: [5, 2]).segments(of: path, closed: false)

    #expect(runs.count == 2)
    #expect(closeRun(runs[0], [Vector2D(0, 0), Vector2D(3, 0), Vector2D(3, 2)]))
    #expect(closeRun(runs[1], [Vector2D(4, 3), Vector2D(6, 3)]))
}

@Test func dashZeroLengthEntryDrawsNothing() {
    // 'draw 0, skip 5' never draws, which is what a zero length means with
    // butt caps
    #expect(DashPattern(pattern: [0, 5]).segments(of: straightLine(10), closed: false).isEmpty)
}

@Test func dashFallsBackToASolidLine() {
    // no lengths, no distance at all, or a negative entry all leave it solid
    for pattern in [[], [0, 0], [-4, 2]] as [[Float]] {
        let runs = DashPattern(pattern: pattern).segments(of: straightLine(10), closed: false)
        #expect(runs.count == 1)
        #expect(closeRun(runs[0], straightLine(10)))
    }
}

@Test func dashLeavesShortPathsAlone() {
    #expect(DashPattern(pattern: [4, 2]).segments(of: [Vector2D(1, 1)], closed: false).count == 1)
    #expect(
        closeRun(
            DashPattern(pattern: [4, 2]).segments(of: straightLine(1), closed: false)[0],
            straightLine(1)
        )
    )
}

// MARK: - closed paths

@Test func dashOnAClosedPathWrapsTheSeam() {
    // a 40-long perimeter with a 6-long pattern finishes the last dash exactly
    // on the seam, so the run that reaches it and the run that leaves it are
    // really one dash
    let runs = DashPattern(pattern: [4, 2]).segments(of: square, closed: true)

    #expect(runs.count == 6)
    #expect(close(runs[0].first!, Vector2D(0, 4)))
    #expect(close(runs[0].last!, Vector2D(4, 0)))
    #expect(runs[0].contains { close($0, Vector2D(0, 0)) })
}

@Test func dashOnAClosedPathLeavesAGapAlone() {
    // a 7-long pattern puts the seam inside a gap, so nothing is merged
    let runs = DashPattern(pattern: [4, 3]).segments(of: square, closed: true)

    #expect(runs.count == 6)
    #expect(close(runs[0].first!, Vector2D(0, 0)))
    #expect(close(runs.last!.last!, Vector2D(0, 1)))
}
