import CSoloud

/// a sound that is playing
///
/// SoLoud hands out a handle for every voice it starts; this keeps that handle
/// together with the engine it belongs to, so a playing sound's properties are
/// found in one place instead of a flat list of engine methods.
///
/// a voice is a value: holding on to one does not keep the sound alive, and its
/// handle stops being valid once the sound ends, so check 'isValid' before
/// trusting it. Its properties are settable through a 'let' binding, because
/// what they change belongs to SoLoud rather than to the value.
public struct Voice: Sendable {
    /// what SoLoud knows this voice by
    public let handle: UInt32

    /// the engine the voice plays in
    public let engine: Audio

    init(handle: UInt32, engine: Audio) {
        self.handle = handle
        self.engine = engine
    }

    /// whether the voice is still playing
    public var isValid: Bool {
        Soloud_isValidVoiceHandle(engine.soloud, handle) != 0
    }

    // MARK: playback

    public var isPaused: Bool {
        get { Soloud_getPause(engine.soloud, handle) != 0 }
        nonmutating set { Soloud_setPause(engine.soloud, handle, newValue ? 1 : 0) }
    }

    /// volume of this voice alone
    public var volume: Float {
        get { Soloud_getVolume(engine.soloud, handle) }
        nonmutating set { Soloud_setVolume(engine.soloud, handle, newValue) }
    }

    /// the volume the voice is really playing at, fades and the source's own
    /// volume included
    public var overallVolume: Float {
        Soloud_getOverallVolume(engine.soloud, handle)
    }

    /// -1 is hard left, 0 centre and 1 hard right
    public var pan: Float {
        get { Soloud_getPan(engine.soloud, handle) }
        nonmutating set { Soloud_setPan(engine.soloud, handle, newValue) }
    }

    public var isLooping: Bool {
        get { Soloud_getLooping(engine.soloud, handle) != 0 }
        nonmutating set { Soloud_setLooping(engine.soloud, handle, newValue ? 1 : 0) }
    }

    /// where looping restarts, in seconds
    public var loopPoint: Double {
        get { Soloud_getLoopPoint(engine.soloud, handle) }
        nonmutating set { Soloud_setLoopPoint(engine.soloud, handle, newValue) }
    }

    /// how many times the voice has looped
    public var loopCount: Int {
        Int(Soloud_getLoopCount(engine.soloud, handle))
    }

    /// 1 plays at the recorded speed; 2 plays an octave up
    public var relativePlaySpeed: Float {
        get { Soloud_getRelativePlaySpeed(engine.soloud, handle) }
        nonmutating set { _ = Soloud_setRelativePlaySpeed(engine.soloud, handle, newValue) }
    }

    /// the rate the voice is resampled at
    public var sampleRate: Float {
        get { Soloud_getSamplerate(engine.soloud, handle) }
        nonmutating set { Soloud_setSamplerate(engine.soloud, handle, newValue) }
    }

    /// protected voices are not dropped to make room for new ones
    public var isProtected: Bool {
        get { Soloud_getProtectVoice(engine.soloud, handle) != 0 }
        nonmutating set { Soloud_setProtectVoice(engine.soloud, handle, newValue ? 1 : 0) }
    }

    /// seconds since the voice started, pauses included
    public var streamTime: Double {
        Soloud_getStreamTime(engine.soloud, handle)
    }

    /// seconds into the sound itself
    public var streamPosition: Double {
        Soloud_getStreamPosition(engine.soloud, handle)
    }

    /// stops the voice
    public func stop() {
        Soloud_stop(engine.soloud, handle)
    }

    /// moves the voice to 'seconds' into the sound
    public func seek(to seconds: Double) {
        _ = Soloud_seek(engine.soloud, handle, seconds)
    }

    /// delays the voice by 'samples' before it starts
    public func setDelaySamples(_ samples: Int) {
        Soloud_setDelaySamples(engine.soloud, handle, UInt32(samples))
    }

    /// sets the left and right volumes directly rather than through a pan
    public func setAbsolutePan(left: Float, right: Float) {
        Soloud_setPanAbsolute(engine.soloud, handle, left, right)
    }

    public func setChannelVolume(_ volume: Float, channel: Int) {
        Soloud_setChannelVolume(engine.soloud, handle, UInt32(channel), volume)
    }

    /// whether a voice that has become inaudible keeps ticking, and whether it
    /// is killed once it is even quieter than that
    public func setInaudibleBehavior(mustTick: Bool, kill: Bool) {
        Soloud_setInaudibleBehavior(engine.soloud, handle, mustTick ? 1 : 0, kill ? 1 : 0)
    }

    // MARK: timing

    /// stops the voice 'seconds' from now
    public func stop(after seconds: Double) {
        Soloud_scheduleStop(engine.soloud, handle, seconds)
    }

    /// pauses the voice 'seconds' from now
    public func pause(after seconds: Double) {
        Soloud_schedulePause(engine.soloud, handle, seconds)
    }

    public func fadeVolume(to value: Float, over seconds: Double) {
        Soloud_fadeVolume(engine.soloud, handle, value, seconds)
    }

    public func fadePan(to value: Float, over seconds: Double) {
        Soloud_fadePan(engine.soloud, handle, value, seconds)
    }

    public func fadeRelativePlaySpeed(to value: Float, over seconds: Double) {
        Soloud_fadeRelativePlaySpeed(engine.soloud, handle, value, seconds)
    }

    /// swings the volume between 'low' and 'high' every 'seconds'
    public func oscillateVolume(from low: Float, to high: Float, over seconds: Double) {
        Soloud_oscillateVolume(engine.soloud, handle, low, high, seconds)
    }

    /// swings the pan between 'low' and 'high' every 'seconds'
    public func oscillatePan(from low: Float, to high: Float, over seconds: Double) {
        Soloud_oscillatePan(engine.soloud, handle, low, high, seconds)
    }

    public func oscillateRelativePlaySpeed(from low: Float, to high: Float, over seconds: Double) {
        Soloud_oscillateRelativePlaySpeed(engine.soloud, handle, low, high, seconds)
    }

    // MARK: filters

    /// sets parameter 'parameter' of the filter in slot 'filter' on this voice
    ///
    /// slot 0 is a filter inherited from the sound being played, and a filter
    /// loaded into a global slot is reached through handle 0 as well - see
    /// 'Audio.setGlobalFilterParameter'
    public func setFilterParameter(_ value: Float, _ parameter: Int, filter: Int = 0) {
        Soloud_setFilterParameter(engine.soloud, handle, UInt32(filter), UInt32(parameter), value)
    }

    /// reads parameter 'parameter' of the filter in slot 'filter'
    public func filterParameter(_ parameter: Int, filter: Int = 0) -> Float {
        Soloud_getFilterParameter(engine.soloud, handle, UInt32(filter), UInt32(parameter))
    }

    public func fadeFilterParameter(to value: Float, _ parameter: Int, filter: Int = 0, over seconds: Double) {
        Soloud_fadeFilterParameter(engine.soloud, handle, UInt32(filter), UInt32(parameter), value, seconds)
    }

    public func oscillateFilterParameter(from low: Float, to high: Float, _ parameter: Int, filter: Int = 0, over seconds: Double) {
        Soloud_oscillateFilterParameter(engine.soloud, handle, UInt32(filter), UInt32(parameter), low, high, seconds)
    }
}
