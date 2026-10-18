import CSoloud
import Foundation

// MARK: - SoLoud objects

/// the handle of a SoLoud object
///
/// SoLoud's generated C API declares every object as 'Type *', where 'Type' is
/// itself 'void *', so Swift sees one pointer type for all of them. The value is
/// the object, not a pointer to it, and nothing in the engine ever dereferences
/// it: it is only handed straight back to SoLoud. It is public so that a game
/// can reach the rest of the C API through 'import CSoloud' if it needs to.
public typealias SoloudObject = UnsafeMutablePointer<UnsafeMutableRawPointer?>

/// reads a string SoLoud handed back, which is NULL when there is nothing to say
func soloudString(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.map { String(cString: $0) } ?? ""
}

/// SoLoud's own bridge takes plain objects rather than the doubly typed handles
/// its C API uses
@inline(__always)
func soloudPointer(_ object: SoloudObject) -> UnsafeMutableRawPointer {
    UnsafeMutableRawPointer(object)
}

/// the other way around: an object Prism's bridge created
@inline(__always)
func soloudObject(_ pointer: UnsafeMutableRawPointer) -> SoloudObject {
    pointer.assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
}

/// runs one of SoLoud's constructors, which only ever fail when it is out of
/// memory - and there is nothing sensible to do about that
func makeSoloudObject(_ description: String, _ create: () -> SoloudObject?) -> SoloudObject {
    guard let object = create() else {
        fatalError("SoLoud could not create \(description): out of memory")
    }
    return object
}

/// the result codes SoLoud reports ('soloud_error.h'), named as far as the
/// engine can tell them apart
enum SoloudError: Int32 {
    case none = 0
    case invalidParameter = 1
    case fileNotFound = 2
    case fileLoadFailed = 3
    case outOfMemory = 5
    case notImplemented = 6
    case unknown = 7
}

// MARK: - errors

public enum AudioLoadingError: Error, LocalizedError {
    case couldNotOpen(URL, String)
    case unsupportedFormat(URL)
    case decodingFailed(URL)

    public var errorDescription: String? {
        switch self {
        case let .couldNotOpen(url, reason): "Audio file '\(url.lastPathComponent)' could not be opened: \(reason)"
        case let .unsupportedFormat(url): "Audio file '\(url.lastPathComponent)' has an unsupported format."
        case let .decodingFailed(url): "Audio file '\(url.lastPathComponent)' could not be decoded."
        }
    }
}

// MARK: - engine

/// the SoLoud mixer
///
/// one belongs to the engine and owns every clip, stream, bus, generator, filter
/// and voice in it. SoLoud mixes on its own thread, and unlike the single SDL
/// audio stream this replaced, 'play' is polyphonic: each call starts a new
/// voice that mixes alongside the others.
///
/// when there is no audio device - a headless machine, a container - the engine
/// falls back to a silent mixer instead of refusing to start, and 'isSilent'
/// says so. Everything still works, it just cannot be heard.
///
/// 'Audio' is '@unchecked Sendable' because its SoLoud instance and filter
/// table are only touched from the main thread
public final class Audio: @unchecked Sendable {
    /// the SoLoud instance every other audio object belongs to
    let soloud: SoloudObject

    /// true when no audio device could be opened and the engine is mixing into
    /// nothing
    public let isSilent: Bool

    /// the back-end that is mixing, for instance 'MiniAudio' or 'NULL'
    public let backendName: String

    /// how many filters SoLoud keeps per stream
    public static let filterSlotCount = 8

    /// filters loaded into the global slots. the engine holds them, because
    /// SoLoud keeps a raw pointer to whatever is loaded and would keep mixing
    /// through a filter the game had already let go of
    private var globalFilters: [Int: AudioFilter] = [:]

    public init(sampleRate: Int32 = 48_000, channels: Int32 = 2) {
        guard let instance = Soloud_create() else {
            fatalError("SoLoud could not be created: out of memory")
        }
        self.soloud = instance

        let flags = UInt32(SOLOUD_CLIP_ROUNDOFF.rawValue)
        let rate = UInt32(sampleRate)
        let outputChannels = UInt32(channels)

        // ask for a real device first, and settle for a silent mixer if there is
        // none: SoLoud only falls back to the null driver when it is asked to
        if Soloud_initEx(instance, flags, UInt32(SOLOUD_AUTO.rawValue), rate, 0, outputChannels) == SoloudError.none.rawValue {
            self.isSilent = false
        } else {
            let silent = Soloud_initEx(instance, flags, UInt32(SOLOUD_NULLDRIVER.rawValue), rate, 0, outputChannels)
            guard silent == SoloudError.none.rawValue else {
                let reason = soloudString(Soloud_getErrorString(instance, silent))
                Soloud_destroy(instance)
                fatalError("SoLoud could not start an audio back-end: \(reason)")
            }
            self.isSilent = true
        }

        self.backendName = soloudString(Soloud_getBackendString(instance))
    }

    deinit {
        // everything that could still be playing holds the engine alive, so
        // there is nothing left to stop except the mixer itself
        Soloud_deinit(soloud)
        Soloud_destroy(soloud)
    }

    // MARK: output

    /// volume applied to the mix as a whole, on top of every voice's own
    public var volume: Float {
        get { Soloud_getGlobalVolume(soloud) }
        set { Soloud_setGlobalVolume(soloud, newValue) }
    }

    /// hard limit on how many voices mix at once; the quietest are dropped when
    /// it is reached
    public var maxActiveVoices: Int {
        get { Int(Soloud_getMaxActiveVoiceCount(soloud)) }
        set { _ = Soloud_setMaxActiveVoiceCount(soloud, UInt32(max(1, newValue))) }
    }

    /// how many voices are mixing right now
    public var activeVoiceCount: Int { Int(Soloud_getActiveVoiceCount(soloud)) }

    /// how hard the mixer clamps its output; 1 is the default
    public var postClipScaler: Float {
        get { Soloud_getPostClipScaler(soloud) }
        set { Soloud_setPostClipScaler(soloud, newValue) }
    }

    /// the sample rate the back-end settled on
    public var outputSampleRate: Int { Int(Soloud_getBackendSamplerate(soloud)) }

    /// how many channels the back-end settled on
    public var outputChannels: Int { Int(Soloud_getBackendChannels(soloud)) }

    /// pauses or resumes every voice
    public func pauseAll(_ paused: Bool = true) {
        Soloud_setPauseAll(soloud, paused ? 1 : 0)
    }

    /// stops every voice
    public func stopAll() {
        Soloud_stopAll(soloud)
    }

    /// fades the mix's volume to 'value' over 'seconds'
    public func fadeVolume(to value: Float, over seconds: Double) {
        Soloud_fadeGlobalVolume(soloud, value, seconds)
    }

    /// swings the mix's volume between 'low' and 'high' over 'seconds'
    public func oscillateVolume(from low: Float, to high: Float, over seconds: Double) {
        Soloud_oscillateGlobalVolume(soloud, low, high, seconds)
    }

    // MARK: loading

    /// decodes WAV, MP3, FLAC or OGG into memory, ready to play
    public func loadAudio(from url: URL) throws -> AudioClip {
        guard let wav = Wav_create() else {
            throw AudioLoadingError.couldNotOpen(url, "out of memory")
        }
        let result = url.path.withCString { Wav_load(wav, $0) }
        guard result == SoloudError.none.rawValue else {
            Wav_destroy(wav)
            throw loadingError(result, for: url)
        }
        return AudioClip(handle: wav, engine: self)
    }

    /// loads a clip, trapping if the file is not valid
    ///
    /// use 'loadAudio(from:)' instead when the file may be invalid
    public func loadWAV(from url: URL) -> AudioClip {
        do { return try loadAudio(from: url) }
        catch { fatalError(error.localizedDescription) }
    }

    public func loadMP3(from url: URL) throws -> AudioClip { try loadAudio(from: url) }
    public func loadOGG(from url: URL) throws -> AudioClip { try loadAudio(from: url) }

    /// opens WAV, MP3, FLAC or OGG for streaming from disk
    ///
    /// nothing is decoded up front, which suits long music tracks; use
    /// 'loadAudio(from:)' for short sounds that have to start instantly
    public func streamAudio(from url: URL) throws -> AudioStream {
        guard let stream = WavStream_create() else {
            throw AudioLoadingError.couldNotOpen(url, "out of memory")
        }
        let result = url.path.withCString { WavStream_load(stream, $0) }
        guard result == SoloudError.none.rawValue else {
            WavStream_destroy(stream)
            throw loadingError(result, for: url)
        }
        return AudioStream(handle: stream, engine: self)
    }

    /// opens a stream, trapping if the file is not valid
    public func streamWAV(from url: URL) -> AudioStream {
        do { return try streamAudio(from: url) }
        catch { fatalError(error.localizedDescription) }
    }

    // MARK: playing

    /// starts 'source' playing and returns the voice it is running on
    ///
    /// 'pan' runs from -1 (hard left) through 0 to 1 (hard right), and 'bus'
    /// mixes the voice through that bus rather than straight into the output
    ///
    /// a voice's handle is 0 when SoLoud had no room for it, so check
    /// 'Voice.isValid' when it matters
    @discardableResult
    public func play(
        _ source: AudioSource,
        volume: Float = 1,
        pan: Float = 0,
        paused: Bool = false,
        bus: AudioBus? = nil
    ) -> Voice {
        let handle: UInt32
        if let bus {
            handle = Bus_playEx(bus.handle, source.handle, volume, pan, paused ? 1 : 0)
        } else {
            handle = Soloud_playEx(soloud, source.handle, volume, pan, paused ? 1 : 0, 0)
        }
        return Voice(handle: handle, engine: self)
    }

    /// stops every voice playing 'source'
    public func stop(_ source: AudioSource) {
        Soloud_stopAudioSource(soloud, source.handle)
    }

    /// how many voices are playing 'source'
    public func voiceCount(of source: AudioSource) -> Int {
        Int(Soloud_countAudioSource(soloud, source.handle))
    }

    // MARK: buses

    /// creates a mix bus: voices played through it share its volume and filters,
    /// and can be stopped together
    public func makeBus(channels: Int = 2) -> AudioBus {
        AudioBus(engine: self, channels: channels)
    }

    // MARK: generators

    /// creates an sfxr effect, the blips and explosions of 8-bit games, for
    /// sound that needs no asset at all
    public func makeSfxr(preset: AudioSfxr.Preset = .coin, seed: Int32 = 0) -> AudioSfxr {
        AudioSfxr(engine: self, preset: preset, seed: seed)
    }

    /// creates a noise generator
    public func makeNoise(_ kind: AudioNoise.Kind = .white) -> AudioNoise {
        AudioNoise(engine: self, kind: kind)
    }

    // MARK: filters

    /// loads 'filter' into global filter slot 'index', replacing whatever was
    /// there; pass nil to clear the slot
    ///
    /// SoLoud applies a filter's parameters to everything that passes through it
    /// from the moment it is loaded, so configure a filter before loading it
    public func setGlobalFilter(_ filter: AudioFilter?, at index: Int) {
        guard (0 ..< Self.filterSlotCount).contains(index) else { return }
        Soloud_setGlobalFilter(soloud, UInt32(index), filter?.handle)
        globalFilters[index] = filter
    }

    /// loads 'filter' into the first free global slot and returns that slot, or
    /// nil when every slot is taken
    @discardableResult
    public func addGlobalFilter(_ filter: AudioFilter) -> Int? {
        guard let slot = (0 ..< Self.filterSlotCount).first(where: { globalFilters[$0] == nil }) else {
            return nil
        }
        setGlobalFilter(filter, at: slot)
        return slot
    }

    /// sets parameter 'parameter' of the filter in global slot 'slot'
    ///
    /// this reaches the instance SoLoud is mixing through, so it takes effect at
    /// once, unlike changing the filter itself
    public func setGlobalFilterParameter(_ value: Float, _ parameter: Int, filter slot: Int) {
        Soloud_setFilterParameter(soloud, 0, UInt32(slot), UInt32(parameter), value)
    }

    /// reads parameter 'parameter' of the filter in global slot 'slot'
    public func globalFilterParameter(_ parameter: Int, filter slot: Int) -> Float {
        Soloud_getFilterParameter(soloud, 0, UInt32(slot), UInt32(parameter))
    }

    public func fadeGlobalFilterParameter(to value: Float, _ parameter: Int, filter slot: Int, over seconds: Double) {
        Soloud_fadeFilterParameter(soloud, 0, UInt32(slot), UInt32(parameter), value, seconds)
    }

    public func oscillateGlobalFilterParameter(from low: Float, to high: Float, _ parameter: Int, filter slot: Int, over seconds: Double) {
        Soloud_oscillateFilterParameter(soloud, 0, UInt32(slot), UInt32(parameter), low, high, seconds)
    }

    // MARK: helpers

    private func loadingError(_ code: Int32, for url: URL) -> AudioLoadingError {
        switch SoloudError(rawValue: code) ?? .unknown {
        case .fileNotFound: .couldNotOpen(url, "the file does not exist")
        case .outOfMemory: .couldNotOpen(url, "out of memory")
        case .fileLoadFailed: .decodingFailed(url)
        default: .unsupportedFormat(url)
        }
    }
}
