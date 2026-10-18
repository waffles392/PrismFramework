import CSoloud
import Foundation

/// something SoLoud can play: a clip decoded into memory, a stream read from
/// disk, a generated effect, or a mix bus
///
/// a source outlives the voices started from it - a voice only borrows it - and
/// it holds the engine it belongs to, so SoLoud cannot be torn down underneath
/// it.
///
/// 'AudioSource' is '@unchecked Sendable' because its handle is stored once
/// and its mutable state is only touched from the main thread
public class AudioSource: @unchecked Sendable {
    /// the object SoLoud knows this source by
    public let handle: SoloudObject

    /// the engine the source was created in, held so that SoLoud outlives it
    let engine: Audio

    /// filters loaded onto the source, by the slot SoLoud keeps them in. the
    /// source holds them for as long as they are loaded, because SoLoud would
    /// otherwise keep mixing through a filter that had already been freed
    private var filters: [Int: AudioFilter] = [:]

    private var storedVolume: Float = 1
    private var storedLooping = false

    init(handle: SoloudObject, engine: Audio) {
        self.handle = handle
        self.engine = engine
    }

    deinit {
        destroy()
    }

    /// volume applied to every voice started from the source, on top of the
    /// voice's own volume
    public var volume: Float {
        get { storedVolume }
        set {
            storedVolume = newValue
            applyVolume(newValue)
        }
    }

    /// whether voices started from the source loop
    public var isLooping: Bool {
        get { storedLooping }
        set {
            storedLooping = newValue
            applyLooping(newValue)
        }
    }

    /// loads 'filter' into the source's filter slot 'index', replacing whatever
    /// was there; pass nil to clear the slot
    ///
    /// a voice takes the source's filters on when it starts. configure a filter
    /// before loading it - SoLoud copies its parameters into the instance it
    /// makes - and use 'Voice.setFilterParameter' to automate one that is
    /// already loaded
    public func setFilter(_ filter: AudioFilter?, at index: Int) {
        guard (0 ..< Audio.filterSlotCount).contains(index) else { return }
        filters[index] = filter
        applyFilter(filter, at: index)
    }

    /// the filter loaded into slot 'index', if any
    public func filter(at index: Int) -> AudioFilter? {
        filters[index]
    }

    // which of SoLoud's setters to call is the one thing only a subclass knows
    func applyVolume(_ volume: Float) {}
    func applyLooping(_ looping: Bool) {}
    func applyFilter(_ filter: AudioFilter?, at index: Int) {}
    func destroy() {}
}

/// a sound decoded into memory, ready to play instantly
///
/// 'AudioClip' is '@unchecked Sendable' because it adds no stored state and
/// inherits the main-thread-only handle of 'AudioSource'
public final class AudioClip: AudioSource, @unchecked Sendable {
    /// how long the clip plays for, in seconds
    public var length: Double { Wav_getLength(handle) }

    /// where looping restarts, in seconds
    public var loopPoint: Double {
        get { Wav_getLoopPoint(handle) }
        set { Wav_setLoopPoint(handle, newValue) }
    }

    override func applyVolume(_ volume: Float) {
        Wav_setVolume(handle, volume)
    }

    override func applyLooping(_ looping: Bool) {
        Wav_setLooping(handle, looping ? 1 : 0)
    }

    override func applyFilter(_ filter: AudioFilter?, at index: Int) {
        Wav_setFilter(handle, UInt32(index), filter?.handle)
    }

    override func destroy() {
        Wav_destroy(handle)
    }
}

/// a sound streamed from disk
///
/// nothing is decoded up front, which suits long music tracks; a clip is better
/// for short sounds that have to start instantly
///
/// 'AudioStream' is '@unchecked Sendable' because it adds no stored state
/// and inherits the main-thread-only handle of 'AudioSource'
public final class AudioStream: AudioSource, @unchecked Sendable {
    /// how long the stream plays for, in seconds; 0 until SoLoud has read far
    /// enough into the file to tell
    public var length: Double { WavStream_getLength(handle) }

    /// where looping restarts, in seconds
    public var loopPoint: Double {
        get { WavStream_getLoopPoint(handle) }
        set { WavStream_setLoopPoint(handle, newValue) }
    }

    override func applyVolume(_ volume: Float) {
        WavStream_setVolume(handle, volume)
    }

    override func applyLooping(_ looping: Bool) {
        WavStream_setLooping(handle, looping ? 1 : 0)
    }

    override func applyFilter(_ filter: AudioFilter?, at index: Int) {
        WavStream_setFilter(handle, UInt32(index), filter?.handle)
    }

    override func destroy() {
        WavStream_destroy(handle)
    }
}
