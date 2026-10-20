@MainActor
public protocol UILayer: AnyObject {
    func setup(in context: UIContext)
    func teardown()
}
