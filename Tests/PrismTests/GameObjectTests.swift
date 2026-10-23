import Prism
import Testing

@MainActor
@Test func gameObjectRejectsSelfParenting() {
    let object = GameObject()

    object.addChild(object)

    #expect(object.children.isEmpty)
    #expect(object.parent == nil)
}

@MainActor
@Test func gameObjectRejectsParentingAnAncestor() {
    let grandparent = GameObject()
    let parent = GameObject()
    let child = GameObject()

    grandparent.addChild(parent)
    parent.addChild(child)

    child.addChild(grandparent)

    #expect(grandparent.parent == nil)
    #expect(parent.parent === grandparent)
    #expect(child.children.isEmpty)
}

@MainActor
@Test func gameObjectAllowsReparentingADescendant() {
    let root = GameObject()
    let branch = GameObject()
    let leaf = GameObject()

    root.addChild(branch)
    branch.addChild(leaf)

    root.addChild(leaf)

    #expect(root.children.count == 2)
    #expect(branch.children.isEmpty)
    #expect(leaf.parent === root)
}
