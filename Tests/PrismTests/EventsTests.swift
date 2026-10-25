import Testing

@testable import Events
@testable import Input
@testable import Math

@MainActor
@Test func eventDispatcherDelivery() async {
    let dispatcher = EventDispatcher()
    var handled = false
    var windowWidth = 0

    let token1 = dispatcher.subscribe { (e: WindowResizedEvent) in
        windowWidth = e.width
    }

    let token2 = dispatcher.subscribe { (e: KeyPressedEvent) in
        handled = true
    }

    dispatcher.publish(
        WindowResizedEvent(
            width: 1024,
            height: 768,
            pixelWidth: 2048,
            pixelHeight: 1536,
            displayScale: 2
        )
    )
    #expect(windowWidth == 1024)
    #expect(!handled)

    dispatcher.publish(KeyPressedEvent(key: .space, isRepeat: false))
    #expect(handled)

    // testing unsubscription
    token1.cancel()
    windowWidth = 0
    dispatcher.publish(
        WindowResizedEvent(
            width: 800,
            height: 600,
            pixelWidth: 1600,
            pixelHeight: 1200,
            displayScale: 2
        )
    )
    #expect(windowWidth == 0)  // should not have updated

    _ = token2  // keep token2 alive
}

@MainActor
@Test func eventDispatcherStampsEventsWithDoubleTimestamp() {
    let dispatcher = EventDispatcher(timeProvider: { 1_000_000.000_001 })
    var timestamp: Double = 0

    let token = dispatcher.subscribe { (e: WindowResizedEvent) in
        timestamp = e.timestamp
    }
    dispatcher.publish(
        WindowResizedEvent(
            width: 1024,
            height: 768,
            pixelWidth: 2048,
            pixelHeight: 1536,
            displayScale: 2
        )
    )

    #expect(timestamp == 1_000_000.000_001)
    token.cancel()
}

@Test func windowResizedEventPreservesMetrics() {
    let event = WindowResizedEvent(
        width: 1024,
        height: 768,
        pixelWidth: 2048,
        pixelHeight: 1536,
        displayScale: 2
    )

    #expect(event.width == 1024)
    #expect(event.height == 768)
    #expect(event.pixelWidth == 2048)
    #expect(event.pixelHeight == 1536)
    #expect(event.displayScale == 2)
    #expect(event.timestamp == 0)
}

@MainActor
@Test func eventTokensRemoveAllCancelsSubscriptions() {
    let dispatcher = EventDispatcher()
    let tokens = EventTokens()
    var received = 0

    let token = dispatcher.subscribe { (_: WindowResizedEvent) in
        received += 1
    }
    tokens.add(token)

    dispatcher.publish(
        WindowResizedEvent(
            width: 1024,
            height: 768,
            pixelWidth: 2048,
            pixelHeight: 1536,
            displayScale: 2
        )
    )
    #expect(received == 1)
    #expect(token.isActive)
    #expect(tokens.count == 1)

    tokens.removeAll()

    #expect(!token.isActive)
    #expect(tokens.count == 0)

    dispatcher.publish(
        WindowResizedEvent(
            width: 800,
            height: 600,
            pixelWidth: 1600,
            pixelHeight: 1200,
            displayScale: 2
        )
    )
    #expect(received == 1)
}

@Test func inputActionMapQueries() {
    var map = InputActionMap(name: "Test")
    let fire = InputAction(name: "Fire", keys: [.space], mouseButtons: [.left])
    map.addAction(fire)

    let move = InputAxis2D(
        name: "Move", rightKeys: [.d], leftKeys: [.a], upKeys: [.w], downKeys: [.s])
    map.addAxis2D(move)

    #expect(map.name == "Test")
    #expect(map.action(named: "Fire")?.name == "Fire")
    #expect(map.action(named: "Unknown") == nil)
    #expect(map.axis2D(named: "Move")?.name == "Move")
}
