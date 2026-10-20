import Foundation

/// thread-safe (MainActor-isolated) pub/sub event dispatcher
/// usage:
/// ```swift
/// // Subscribe
/// let token = events.subscribe { (e: KeyPressedEvent) in
///     print("Key pressed: \(e.key)")
/// }
/// // Subscribe to a base type to receive all its subtypes
/// let engineToken = events.subscribe { (e: BaseEvent) in
///     print("any engine event at \(e.timestamp)s")
/// }
/// // One-shot subscription
/// events.subscribeOnce { (e: WindowCloseEvent) in ... }
/// // Publish (synchronous - all handlers fire immediately)
/// events.publish(KeyPressedEvent(key: .space, isRepeat: false))
/// // Queue for deferred dispatch (flushed at the top of each frame)
/// events.queue(WindowResizedEvent(width: 1280, height: 720))
/// events.flush()
/// ```
///
/// delivery semantics:
/// - Exact-type subscribers are invoked first (in ascending
///   'priority', then subscription order), followed by
///   supertype subscribers (same ordering)
/// - If a handler marks the event as 'handled', no further
///   handlers receive it
/// - A supertype subscriber may receive events of *any*
///   subtype it can cast to - use the typed generic form
///   ('subscribe { (e: ConcreteEvent) in ... }') for safety
/// - 'publish' stamps 'BaseEvent' subclasses with the
///   dispatcher's 'timeProvider' before delivery
@MainActor
public final class EventDispatcher {
    private struct Subscription {
        let id: UInt64
        let handler: (any EngineEvent) -> Void
        let eventType: ObjectIdentifier
        /// returns 'true' when an event's dynamic type
        /// is the subscribed type or a subtype of it
        /// captured at subscribe time so the check
        /// needs no runtime superclass walk
        let matches: (any EngineEvent) -> Bool
        let priority: Int
        let once: Bool
    }

    private var subscriptions: [Subscription] = []
    private var nextID: UInt64 = 0
    private var deferred: [any EngineEvent] = []

    /// stamps published 'BaseEvent' subclasses with a
    /// timestamp (seconds since engine start)
    public let timeProvider: @MainActor () -> Double

    /// when 'true', every 'publish' logs the event and its
    /// handler count to stderr. wire this to
    /// 'PrismEnvironment.dumpEvents'
    public var logEnabled: Bool = false

    /// creates a dispatcher
    ///
    /// - Parameter timeProvider: supplies timestamps for
    ///   published events. defaults to a zero provider;
    ///   the engine passes 'time.elapsedTime'
    public init(
        timeProvider: @MainActor @escaping () -> Double = { 0 }
    ) {
        self.timeProvider = timeProvider
    }

    // MARK: - Subscribe

    /// registers a typed handler and returns a token that
    /// controls its lifetime
    ///
    /// - Parameters:
    ///   - handler: invoked for events whose dynamic type
    ///     matches 'E' exactly, or whose type is a subtype
    ///     of 'E'
    ///   - priority: ascending dispatch order within the
    ///     exact-type and supertype delivery groups
    @discardableResult
    public func subscribe<E: EngineEvent>(
        priority: Int = 0,
        _ handler: @escaping @MainActor (E) -> Void
    ) -> SubscriptionToken {
        let id = nextID
        nextID &+= 1

        let subscription = Subscription(
            id: id,
            handler: { event in
                guard let typed = event as? E else { return }
                handler(typed)
            },
            eventType: ObjectIdentifier(E.self),
            matches: { event in event is E },
            priority: priority,
            once: false
        )
        subscriptions.append(subscription)

        return token(for: id)
    }

    /// registers a handler that is automatically unsubscribed
    /// after its first delivery
    @discardableResult
    public func subscribeOnce<E: EngineEvent>(
        priority: Int = 0,
        _ handler: @escaping @MainActor (E) -> Void
    ) -> SubscriptionToken {
        let id = nextID
        nextID &+= 1

        let subscription = Subscription(
            id: id,
            handler: { event in
                guard let typed = event as? E else { return }
                handler(typed)
            },
            eventType: ObjectIdentifier(E.self),
            matches: { event in event is E },
            priority: priority,
            once: true
        )
        subscriptions.append(subscription)

        return token(for: id)
    }

    private func token(for id: UInt64) -> SubscriptionToken {
        SubscriptionToken { [weak self] in
            self?.subscriptions.removeAll { $0.id == id }
        }
    }

    /// cancels every subscription and clears the deferred queue
    public func unsubscribeAll() {
        subscriptions.removeAll(keepingCapacity: true)
        deferred.removeAll(keepingCapacity: true)
    }

    // MARK: - Publish

    /// synchronously dispatches 'event' to all matching
    /// subscribers. handlers are invoked in ascending
    /// 'priority' order. if a handler marks the event as
    /// handled, no further handlers receive it
    public func publish(_ event: any EngineEvent) {
        // stamp BaseEvent subclasses with the current time
        if let stamped = event as? BaseEvent {
            stamped.timestamp = timeProvider()
        }

        let concreteType = type(of: event)
        let concreteIdentifier = ObjectIdentifier(concreteType)

        var exactMatches: [Subscription] = []
        var supertypeMatches: [Subscription] = []

        for subscription in subscriptions {
            if subscription.eventType == concreteIdentifier {
                exactMatches.append(subscription)
            } else if subscription.matches(event) {
                supertypeMatches.append(subscription)
            }
        }

        let orderedExact = exactMatches.sorted(by: order)
        let orderedSupertype = supertypeMatches.sorted(by: order)

        let total = orderedExact.count + orderedSupertype.count
        if logEnabled {
            let name = String(describing: concreteType)
            let payload = eventLogPayload(event)
            let message = payload.isEmpty
                ? "[events] \(name) -> \(total) handlers"
                : "[events] \(name)(\(payload)) -> \(total) handlers"
            FileHandle.standardError.write(
                Data((message + "\n").utf8)
            )
        }

        for subscription in orderedExact {
            guard !event.handled else { return }
            subscription.handler(event)
            if subscription.once {
                subscriptions.removeAll { $0.id == subscription.id }
            }
        }

        for subscription in orderedSupertype {
            guard !event.handled else { return }
            subscription.handler(event)
            if subscription.once {
                subscriptions.removeAll { $0.id == subscription.id }
            }
        }
    }

    private func order(_ lhs: Subscription, _ rhs: Subscription) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        return lhs.id < rhs.id
    }

    private func eventLogPayload(_ event: any EngineEvent) -> String {
        let mirror = Mirror(reflecting: event)
        var pairs: [String] = []
        for child in mirror.children {
            guard let label = child.label else { continue }
            let value = String(describing: child.value)
            if value.count > 40 {
                pairs.append("\(label)=...")
            } else {
                pairs.append("\(label)=\(value)")
            }
        }
        return pairs.joined(separator: ", ")
    }

    // MARK: - Deferred queue

    /// enqueues an event for deferred dispatch on the next 'flush()' call
    public func queue(_ event: any EngineEvent) {
        deferred.append(event)
    }

    /// dispatches all queued events in FIFO order and clears the queue
    /// call once per frame before the update phase
    public func flush() {
        let pending = deferred
        deferred.removeAll(keepingCapacity: true)
        for event in pending {
            publish(event)
        }
    }
}
