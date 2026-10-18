import Testing
@testable import Audio
@testable import Window

@Test func platformModulesExposeTheirPublicTypes() {
    // device creation is intentionally not performed here: these tests must
    // stay safe on headless CI machines without video/audio hardware
    let _: Window.Type = Window.self
    let _: Audio.Type = Audio.self
    let _: AudioClip.Type = AudioClip.self
}