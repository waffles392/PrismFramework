/// an opaque token returned when subscribing to an event channel
///
/// the subscription stays active while the token is retained. releasing the
/// token does not cancel the subscription automatically - call 'cancel()' or
/// add the token to an 'EventTokens' collection and call 'cancelAll()' during
/// teardown
///
/// automatic cancellation from 'deinit' is not provided because the dispatcher
/// publishes on the main actor and 'deinit' cannot safely call main-actor
/// isolated cancellation. keep tokens in a '@MainActor' context and release
/// them explicitly
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
}

/// a collection of 'SubscriptionToken' values that cancels all
/// of them at once - useful for tearing down a system's
/// subscriptions together
///
/// 'cancelAll()' is safe to call from any context on the main actor. releasing
/// the tokens does not cancel their subscriptions, so call 'cancelAll()'
/// explicitly during teardown
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
        tokens.reduce(0) { $0 + ($1.isActive ? 1 : 0) }
    }

    /// cancels every token and removes it from the collection
    ///
    /// equivalent to 'cancelAll()'. clearing the array without cancelling
    /// would leave the dispatcher subscriptions alive
    public func removeAll() {
        cancelAll()
    }
}
