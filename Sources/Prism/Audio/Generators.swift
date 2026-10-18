import CSoloud
import Foundation

/// a sound effect generated from an sfxr preset
///
/// sfxr is the little synthesiser behind a great many 8-bit games: instead of an
/// asset it takes a handful of parameters and yields a blip, a coin or an
/// explosion. It is a good placeholder while real audio is still being made, and
/// a game can carry authored '.sfs' files instead of recording anything.
///
/// 'AudioSfxr' is '@unchecked Sendable' because its SoLoud handle is only
/// driven from the main thread
public final class AudioSfxr: AudioSource, @unchecked Sendable {
    /// the baked-in presets SoLoud ships
    public enum Preset: Int32 {
        case coin = 0
        case laser = 1
        case explosion = 2
        case powerUp = 3
        case hurt = 4
        case jump = 5
        case blip = 6
    }

    init(engine: Audio, preset: Preset, seed: Int32) {
        super.init(handle: makeSoloudObject("an sfxr source") { Sfxr_create() }, engine: engine)
        _ = Sfxr_loadPreset(handle, preset.rawValue, seed)
    }

    /// goes back to the preset the source was created from
    public func resetParameters() {
        Sfxr_resetParams(handle)
    }

    /// loads sfxr parameters from an '.sfs' file, replacing the preset
    public func loadParameters(from url: URL) throws {
        let result = url.path.withCString { Sfxr_loadParams(handle, $0) }
        guard result == SoloudError.none.rawValue else {
            throw AudioLoadingError.couldNotOpen(url, "not an sfxr parameter file")
        }
    }

    override func applyVolume(_ volume: Float) {
        Sfxr_setVolume(handle, volume)
    }

    override func applyLooping(_ looping: Bool) {
        Sfxr_setLooping(handle, looping ? 1 : 0)
    }

    override func applyFilter(_ filter: AudioFilter?, at index: Int) {
        Sfxr_setFilter(handle, UInt32(index), filter?.handle)
    }

    override func destroy() {
        Sfxr_destroy(handle)
    }
}

/// noise, from hiss to rumble
///
/// it never ends, so a voice playing it has to be stopped explicitly
///
/// 'AudioNoise' is '@unchecked Sendable' because its SoLoud handle and
/// 'kind' are only touched from the main thread
public final class AudioNoise: AudioSource, @unchecked Sendable {
    /// the colour of the noise
    public enum Kind: Int32 {
        case white = 0
        case pink = 1
        case brownish = 2
        case blueish = 3
    }

    /// the colour of the noise, which can be changed while it plays
    public var kind: Kind {
        didSet { Noise_setType(handle, kind.rawValue) }
    }

    init(engine: Audio, kind: Kind) {
        self.kind = kind
        super.init(handle: makeSoloudObject("a noise source") { Noise_create() }, engine: engine)
        Noise_setType(handle, kind.rawValue)
    }

    /// scales the volume of the first ten octaves, the first being the lowest
    ///
    /// exactly ten values are needed; SoLoud ignores anything else
    public func setOctaveScale(_ scale: [Float]) {
        guard scale.count == 10 else { return }
        Noise_setOctaveScale(handle, scale[0], scale[1], scale[2], scale[3], scale[4],
                             scale[5], scale[6], scale[7], scale[8], scale[9])
    }

    override func applyVolume(_ volume: Float) {
        Noise_setVolume(handle, volume)
    }

    override func applyLooping(_ looping: Bool) {
        Noise_setLooping(handle, looping ? 1 : 0)
    }

    override func applyFilter(_ filter: AudioFilter?, at index: Int) {
        Noise_setFilter(handle, UInt32(index), filter?.handle)
    }

    override func destroy() {
        Noise_destroy(handle)
    }
}
