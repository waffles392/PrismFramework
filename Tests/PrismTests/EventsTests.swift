import Testing
@testable import Events
@testable import Math
@testable import Input

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
    
    dispatcher.publish(WindowResizedEvent(width: 1024, height: 768))
    #expect(windowWidth == 1024)
    #expect(!handled)
    
    dispatcher.publish(KeyPressedEvent(key: .space, isRepeat: false))
    #expect(handled)
    
    // testing unsubscription
    token1.cancel()
    windowWidth = 0
    dispatcher.publish(WindowResizedEvent(width: 800, height: 600))
    #expect(windowWidth == 0) // should not have updated
    
    _ = token2 // keep token2 alive
}

@MainActor
@Test func eventDispatcherStampsEventsWithDoubleTimestamp() {
    let dispatcher = EventDispatcher(timeProvider: { 1_000_000.000_001 })
    var timestamp: Double = 0

    let token = dispatcher.subscribe { (e: WindowResizedEvent) in
        timestamp = e.timestamp
    }
    dispatcher.publish(WindowResizedEvent(width: 1024, height: 768))

    #expect(timestamp == 1_000_000.000_001)
    token.cancel()
}

@Test func inputActionMapQueries() {
    var map = InputActionMap(name: "Test")
    let fire = InputAction(name: "Fire", keys: [.space], mouseButtons: [.left])
    map.addAction(fire)
    
    let move = InputAxis2D(name: "Move", rightKeys: [.d], leftKeys: [.a], upKeys: [.w], downKeys: [.s])
    map.addAxis2D(move)
    
    #expect(map.name == "Test")
    #expect(map.action(named: "Fire")?.name == "Fire")
    #expect(map.action(named: "Unknown") == nil)
    #expect(map.axis2D(named: "Move")?.name == "Move")
}
