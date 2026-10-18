import Testing
@testable import Input
@testable import Math

@Test func keyMappingsRoundTrip() {
    let mappings: [(Key, Int32)] = [
        (.escape, 41),
        (.enter, 40),
        (.left, 80),
        (.right, 79),
        (.up, 82),
        (.down, 81),
        (.leftShift, 225),
        (.rightControl, 228)
    ]

    for (key, rawValue) in mappings {
        #expect(key.rawValue == rawValue)
        #expect(Key(rawValue: rawValue) == key)
    }
}

@Test func inputEventsAreValueTypes() {
    let position = Vector2D(12, 8)
    let delta = Vector2D(2, -1)

    #expect(InputEvent.quit == .quit)
    #expect(InputEvent.keyDown(.space, isRepeat: false) == .keyDown(.space, isRepeat: false))
    #expect(InputEvent.mouseMoved(position: position, delta: delta) == .mouseMoved(position: position, delta: delta))
    #expect(MouseButton(rawValue: 1) == .left)
}
