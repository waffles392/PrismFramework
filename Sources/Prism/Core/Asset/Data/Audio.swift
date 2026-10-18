import Audio
import Foundation

public extension AssetStore {
    /// loads and caches a WAV clip from the bundle
    func loadWAV(
        named name: String,
        subdirectory: String? = nil,
        using audio: Audio
    ) throws -> AudioClip {
        try loadAudio(named: name, withExtension: "wav", subdirectory: subdirectory, using: audio)
    }

    /// loads and caches an MP3 clip from the bundle
    func loadMP3(named name: String, subdirectory: String? = nil, using audio: Audio) throws -> AudioClip {
        try loadAudio(named: name, withExtension: "mp3", subdirectory: subdirectory, using: audio)
    }

    /// loads and caches an OGG clip from the bundle
    func loadOGG(named name: String, subdirectory: String? = nil, using audio: Audio) throws -> AudioClip {
        try loadAudio(named: name, withExtension: "ogg", subdirectory: subdirectory, using: audio)
    }

    private func loadAudio(
        named name: String,
        withExtension fileExtension: String,
        subdirectory: String?,
        using audio: Audio
    ) throws -> AudioClip {
        let key = AssetKey(name, fileExtension, subdirectory)
        if let cached = audioCache.value(for: key) { return cached }

        let assetURL = try url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
        let clip = try audio.loadAudio(from: assetURL)

        audioCache.insert(clip, for: key)
        return clip
    }
}
