/// an opaque token returned when subscribing to an event channel
///
/// hold onto the token for as long as the subscription should remain
/// active. when the token is deallocated, the subscription is
/// automatically cancelled. you can also call 'cancel()' explicitly
@MainActor
public final class SubscriptionToken {
    private let cancellation: @MainActor () -> Void
    private var isCancelled = false

    internal init(cancellation: @escaping @MainActor () -> Void) {
        self.cancellation = cancellation
    }

    /// whether the subscription is still active
    public var isActive: Bool {
        !isCancelled
    }

    /// explicitly cancels the subscription
    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        cancellation()
    }

    deinit {
        // cannot call MainActor-isolated cancellation directly from deinit
        // users should call cancel() explicitly or store the token in a
        // @MainActor context so deinit runs on the main actor
    }
}

/// a collection of 'SubscriptionToken' values that cancels all
/// of them at once - useful for tearing down a system's
/// subscriptions together
///
/// 'cancelAll()' is safe to call from any context on the
/// main actor. because 'deinit' cannot reliably run on the
/// main actor, do not rely on deinit for cancellation -
/// call 'cancelAll()' explicitly during teardown
@MainActor
public final class EventTokens {
    private var tokens: [SubscriptionToken] = []

    public init() {}

    /// adds a token to the collection and returns it
    @discardableResult
    public func add(_ token: SubscriptionToken) -> SubscriptionToken {
        tokens.append(token)
        return token
    }

    /// cancels every token in the collection
    public func cancelAll() {
        for token in tokens {
            token.cancel()
        }
        tokens.removeAll(keepingCapacity: true)
    }

    /// the number of active tokens
    public var count: Int {
        tokens.reduce(0) { $0 + ( $1.isActive ? 1 : 0) }
    }

    public func removeAll() {
        tokens.removeAll(keepingCapacity: true)
    }
}
