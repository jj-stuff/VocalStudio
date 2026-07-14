import AVFoundation

/// Generates a short silent stereo audio file to use as the `sourceURL` for projects
/// that have no real backing track yet (the instant-record flow: "sing and play at
/// the same time, separate later" has no source audio to import up front). Reuses the
/// existing Project storage pipeline unchanged; the editor recognizes the placeholder
/// (via `hasSilentPlaceholderSource`) and hides it rather than showing a fake clip.
enum SilentAudioFile {
    /// Filename suffix that marks a generated placeholder — `Project` uses it to
    /// recognize instant-record projects that have no real source audio.
    static let fileSuffix = "_silence.caf"

    static func make(duration: TimeInterval = 1.0) throws -> URL {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let dir = URL.documentsDirectory.appending(path: "Audio", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(UUID().uuidString + fileSuffix)

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let totalFrames = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = totalFrames   // zero-initialized — silence
        try file.write(from: buffer)
        return url
    }
}

extension Project {
    /// True for instant-record projects whose "source" is the generated silent
    /// placeholder — there's no real audio behind it, so the editor hides the
    /// source track and the Separate button for these.
    var hasSilentPlaceholderSource: Bool {
        sourceURL.lastPathComponent.hasSuffix(SilentAudioFile.fileSuffix)
    }
}
