import CSoloud

/// a SoLoud effect, loaded onto the engine, a source or a bus
///
/// SoLoud copies a filter's parameters into the instance it creates when the
/// filter is loaded, so a filter is configured by its initialiser and changing
/// it afterwards is not heard. Changing a filter that is already loaded is done
/// through its instance instead - 'Voice.setFilterParameter' and
/// 'Audio.setGlobalFilterParameter'.
public class AudioFilter {
    /// the object SoLoud knows this filter by
    public let handle: SoloudObject

    init(handle: SoloudObject) {
        self.handle = handle
    }

    deinit {
        Prism_Filter_destroy(soloudPointer(handle))
    }

    /// what SoLoud lets a parameter hold
    public enum Kind: UInt32 {
        case float = 0
        case integer = 1
        case boolean = 2
    }

    /// how many parameters SoLoud exposes for the filter
    public var parameterCount: Int {
        Int(Prism_Filter_getParamCount(soloudPointer(handle)))
    }

    /// the name SoLoud gives parameter 'index', which is how the parameters of
    /// a loaded filter are addressed
    public func parameterName(at index: Int) -> String {
        soloudString(Prism_Filter_getParamName(soloudPointer(handle), UInt32(index)))
    }

    public func parameterKind(at index: Int) -> Kind {
        Kind(rawValue: Prism_Filter_getParamType(soloudPointer(handle), UInt32(index))) ?? .float
    }

    /// the values SoLoud accepts for parameter 'index'
    public func parameterRange(at index: Int) -> ClosedRange<Float> {
        let low = Prism_Filter_getParamMin(soloudPointer(handle), UInt32(index))
        let high = Prism_Filter_getParamMax(soloudPointer(handle), UInt32(index))
        return low ... max(low, high)
    }
}

/// an eight band equaliser
///
/// SoLoud fixes the frequency of each band and lets only its volume be set, so
/// bands are raised or lowered in place. Volume 1 is flat, and the bands run
/// from the lowest frequency up.
public final class AudioEqualizerFilter: AudioFilter {
    /// how many bands the equaliser has
    public static let bandCount = 8

    public init() {
        // SoLoud's own C API has no EQ filter, so Prism's bridge creates this one
        guard let filter = Prism_EqFilter_create() else {
            fatalError("SoLoud could not create an equaliser: out of memory")
        }
        super.init(handle: soloudObject(filter))
    }

    /// sets the volume of one band, which is numbered 1 to 'bandCount'
    ///
    /// returns false when the band or the volume is out of range, leaving the
    /// band as it was
    @discardableResult
    public func setBand(_ band: Int, volume: Float) -> Bool {
        guard (1 ... Self.bandCount).contains(band) else { return false }
        return Prism_EqFilter_setParam(soloudPointer(handle), UInt32(band), volume) == SoloudError.none.rawValue
    }
}

/// raises (or lowers) the bass
public final class AudioBassBoostFilter: AudioFilter {
    /// how much to boost the low end; 1 leaves it alone
    public init(boost: Float = 2) {
        super.init(handle: makeSoloudObject("a bass boost filter") { BassboostFilter_create() })
        _ = BassboostFilter_setParams(handle, boost)
    }
}

/// a resonant filter with a cut-off frequency
public final class AudioBiquadResonantFilter: AudioFilter {
    /// which part of the spectrum is kept
    public enum Kind: Int32 {
        case lowPass = 0
        case highPass = 1
        case bandPass = 2
    }

    /// - parameters:
    ///   - kind: which part of the spectrum to keep
    ///   - frequency: the cut-off, in hertz
    ///   - resonance: how much the cut-off is emphasised; 0 is none
    public init(kind: Kind = .lowPass, frequency: Float = 1_000, resonance: Float = 1) {
        super.init(handle: makeSoloudObject("a biquad resonant filter") { BiquadResonantFilter_create() })
        _ = BiquadResonantFilter_setParams(handle, kind.rawValue, frequency, resonance)
    }
}

/// removes the constant offset some recordings carry
public final class AudioDCRemovalFilter: AudioFilter {
    /// how long a stretch to average over, in seconds
    public init(length: Float = 0.1) {
        super.init(handle: makeSoloudObject("a DC removal filter") { DCRemovalFilter_create() })
        _ = DCRemovalFilter_setParamsEx(handle, length)
    }
}

/// repeats the sound back, quieter each time
public final class AudioEchoFilter: AudioFilter {
    /// - parameters:
    ///   - delay: seconds before the first echo comes back
    ///   - decay: how much of the volume each echo keeps
    ///   - filter: how much the echoes are muffled; 0 keeps them bright
    public init(delay: Float = 0.2, decay: Float = 0.7, filter: Float = 0) {
        super.init(handle: makeSoloudObject("an echo filter") { EchoFilter_create() })
        _ = EchoFilter_setParamsEx(handle, delay, decay, filter)
    }
}

/// sweeps a copy of the sound in and out of phase with itself
public final class AudioFlangerFilter: AudioFilter {
    /// - parameters:
    ///   - delay: the shortest delay the sweep uses, in seconds
    ///   - frequency: how fast the sweep runs, in hertz
    public init(delay: Float = 0.005, frequency: Float = 0.5) {
        super.init(handle: makeSoloudObject("a flanger filter") { FlangerFilter_create() })
        _ = FlangerFilter_setParams(handle, delay, frequency)
    }
}

/// a reverb, built from SoLoud's Freeverb
public final class AudioReverbFilter: AudioFilter {
    /// - parameters:
    ///   - freeze: 1 holds the reverb decaying forever, 0 lets it fade
    ///   - roomSize: how large the room sounds
    ///   - damp: how much the reverb is muffled
    ///   - width: how wide the stereo reverb is
    public init(freeze: Float = 0, roomSize: Float = 0.5, damp: Float = 0.5, width: Float = 1) {
        super.init(handle: makeSoloudObject("a reverb filter") { FreeverbFilter_create() })
        _ = FreeverbFilter_setParams(handle, freeze, roomSize, damp, width)
    }
}

/// leaves the sound untouched; useful as a slot filler or a measurement point
public final class AudioFFTFilter: AudioFilter {
    public init() {
        super.init(handle: makeSoloudObject("an FFT filter") { FFTFilter_create() })
    }
}

/// lowers the sample rate and bit depth, the sound of a cheap 1980s machine
public final class AudioLofiFilter: AudioFilter {
    /// - parameters:
    ///   - sampleRate: the rate to pretend to sample at, in hertz
    ///   - bitDepth: the number of bits to keep
    public init(sampleRate: Float = 8_000, bitDepth: Float = 5) {
        super.init(handle: makeSoloudObject("a lo-fi filter") { LofiFilter_create() })
        _ = LofiFilter_setParams(handle, sampleRate, bitDepth)
    }
}

/// replaces the sound with a robot voice, tracked to its waveform
public final class AudioRobotizeFilter: AudioFilter {
    /// the waveform the voice is quantised to ('SOLOUD_WAVE_*')
    public enum Waveform: Int32 {
        case square = 0
        case saw = 1
        case sine = 2
        case triangle = 3
        case bounce = 4
        case jaws = 5
        case humps = 6
        case fSquare = 7
        case fSaw = 8
    }

    /// - parameters:
    ///   - frequency: the pitch the voice is quantised to, in hertz
    ///   - waveform: the waveform it is quantised onto
    public init(frequency: Float = 30, waveform: Waveform = .square) {
        super.init(handle: makeSoloudObject("a robotize filter") { RobotizeFilter_create() })
        RobotizeFilter_setParams(handle, frequency, waveform.rawValue)
    }
}

/// waveshapes the sound, which thickens or distorts it
public final class AudioWaveShaperFilter: AudioFilter {
    /// how hard to shape the wave; 1 is barely at all
    public init(amount: Float = 1) {
        super.init(handle: makeSoloudObject("a wave shaper filter") { WaveShaperFilter_create() })
        _ = WaveShaperFilter_setParams(handle, amount)
    }
}
