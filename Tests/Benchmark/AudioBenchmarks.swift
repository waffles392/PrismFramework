import Foundation
import Prism
import Testing

/// exercises SoLoud's real decoding path with a file large enough that the
/// work is measurable, then opens a stream and starts a voice.
extension BenchmarkSuite {

    @Suite("Benchmark audio", .timeLimit(.minutes(1))) struct AudioBenchmarks {

        @Test @MainActor func largeWAVDecodesStreamsAndPlays() throws {
            benchmarkSection("Audio")
            let audio = Audio()
            let seconds = 30.0
            let url = try makeSilentWAV(seconds: seconds)
            defer { try? FileManager.default.removeItem(at: url) }

            let (clip, loadDuration) = try measure { try audio.loadAudio(from: url) }
            #expect(abs(clip.length - seconds) < 0.1)

            let voice = audio.play(clip)
            #expect(voice.isValid)
            voice.stop()

            let (stream, streamDuration) = try measure { try audio.streamAudio(from: url) }
            #expect(abs(stream.length - seconds) < 0.1)

            benchmarkReport(
                "decode 30s WAV", loadDuration,
                "\(megabytes(url.fileSize)) via \(audio.backendName)"
                    + (audio.isSilent ? " (silent fallback)" : ""))
            benchmarkReport("open WAV stream", streamDuration)
        }
    }
}

extension URL {
    fileprivate var fileSize: Int { (try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
}
