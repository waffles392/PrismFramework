import CSoloud

/// a mix bus
///
/// a bus is a voice in its own right that other voices are played through, so
/// they can share its volume and filters and be stopped together - one for
/// music, one for effects, one for the interface. SoLoud mixes the bus and
/// everything routed into it before the global filters see it.
///
/// 'AudioBus' is '@unchecked Sendable' because its handle is stored once and
/// its 'channels' are only touched from the main thread
public final class AudioBus: AudioSource, @unchecked Sendable {
    /// stops every voice playing through the bus
    public func stopAll() {
        Bus_stop(handle)
    }

    /// how many voices are playing through the bus
    public var activeVoiceCount: Int {
        Int(Bus_getActiveVoiceCount(handle))
    }

    private var storedChannels: Int

    /// how many channels the bus mixes
    public var channels: Int {
        get { storedChannels }
        set {
            guard newValue > 0, newValue <= 8,
                  Bus_setChannels(handle, UInt32(newValue)) == SoloudError.none.rawValue else { return }
            storedChannels = newValue
        }
    }

    init(engine: Audio, channels: Int) {
        // SoLoud's own default, kept when the requested channel count is refused
        self.storedChannels = 2
        super.init(handle: makeSoloudObject("a bus") { Bus_create() }, engine: engine)

        self.channels = channels

        // a bus only mixes once SoLoud is playing it, and its instance never
        // ends, so it is started here and left running for the voices routed
        // into it. it is protected because losing its voice to a newer sound
        // would take the whole bus with it
        let voice = Soloud_play(engine.soloud, handle)
        Soloud_setProtectVoice(engine.soloud, voice, 1)
    }

    /// starts 'source' playing through the bus
    @discardableResult
    public func play(_ source: AudioSource, volume: Float = 1, pan: Float = 0, paused: Bool = false) -> Voice {
        let handle = Bus_playEx(self.handle, source.handle, volume, pan, paused ? 1 : 0)
        return Voice(handle: handle, engine: engine)
    }

    /// moves a voice that is already playing into the bus
    public func annex(_ voice: Voice) {
        Bus_annexSound(handle, voice.handle)
    }

    override func applyVolume(_ volume: Float) {
        Bus_setVolume(handle, volume)
    }

    override func applyLooping(_ looping: Bool) {
        Bus_setLooping(handle, looping ? 1 : 0)
    }

    override func applyFilter(_ filter: AudioFilter?, at index: Int) {
        Bus_setFilter(handle, UInt32(index), filter?.handle)
    }

    override func destroy() {
        Bus_destroy(handle)
    }
}
