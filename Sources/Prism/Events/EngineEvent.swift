/// base protocol for all engine events
///
/// events carry metadata and a 'handled' flag. A handler that fully
/// processes an event may set 'handled = true' to suppress later handlers
public protocol EngineEvent: AnyObject {
    /// the event's creation timestamp in seconds since engine start
    var timestamp: Float { get }
    /// when 'true', no further handlers will be invoked for this event
    var handled: Bool { get set }
}

/// convenience base class for events that do not need custom storage
///
/// 'timestamp' is mutable so an 'EventDispatcher' can stamp events
/// with its 'timeProvider' on publish; events created directly carry
/// the timestamp passed to 'init' (default '0')
open class BaseEvent: EngineEvent {
    public var timestamp: Float
    public var handled: Bool = false

    public init(timestamp: Float = 0) {
        self.timestamp = timestamp
    }
}
