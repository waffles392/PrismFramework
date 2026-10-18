/// an ordered group of game objects within a scene
@MainActor
public final class Collection {
    public private(set) var objects: [GameObject]

    public init(objects: [GameObject] = []) {
        self.objects = objects
    }

    public func add(_ object: GameObject) {
        objects.append(object)
    }

    @discardableResult
    public func remove(_ object: GameObject) -> Bool {
        guard let index: Array<GameObject>.Index = objects.firstIndex(where: { $0 === object }) else {
            return false
        }

        objects.remove(at: index)
        return true
    }

    public func removeAll() {
        objects.removeAll()
    }
}
