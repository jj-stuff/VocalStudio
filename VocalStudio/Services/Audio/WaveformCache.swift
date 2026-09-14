import AVFoundation

/// Peak data for drawing a clip's waveform: one value in 0...1 per bucket, at a
/// fixed number of buckets per second of source audio. Immutable and Sendable so
/// views can hold it and slice it freely.
nonisolated struct WaveformPeaks: Sendable, Equatable {
    static let bucketsPerSecond = 40

    let peaks: [Float]
    var duration: TimeInterval { Double(peaks.count) / Double(Self.bucketsPerSecond) }

    /// The bucket that contains `time` in the source file.
    func index(at time: TimeInterval) -> Int {
        Int(time * Double(Self.bucketsPerSecond))
    }
}

/// Reads audio files once and keeps their peaks in memory, keyed by URL. An actor
/// so the decoding runs off the main thread and concurrent requests for the same
/// file share one read instead of racing.
actor WaveformCache {
    static let shared = WaveformCache()

    private var cache: [URL: WaveformPeaks] = [:]
    private var inFlight: [URL: Task<WaveformPeaks?, Never>] = [:]

    /// Peaks for `url`, decoding on first request. Nil if the file can't be read.
    func peaks(for url: URL) async -> WaveformPeaks? {
        if let cached = cache[url] { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task<WaveformPeaks?, Never> {
            Self.decode(url)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { cache[url] = result }
        return result
    }

    /// Drops a file's peaks — call when the file is deleted so the cache doesn't
    /// hand back a waveform for audio that no longer exists.
    func evict(_ url: URL) {
        cache[url] = nil
    }

    // MARK: - Decoding

    /// Walks the file in chunks and keeps the absolute peak of each bucket, mixed
    /// down across channels. Peaks (not RMS) because the clip is drawn at a few
    /// dozen pixels tall — peaks keep transients visible at that size.
    private nonisolated static func decode(_ url: URL) -> WaveformPeaks? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, file.length > 0 else { return nil }

        let framesPerBucket = max(1, Int(sampleRate) / WaveformPeaks.bucketsPerSecond)
        let bucketCount = Int(ceil(Double(file.length) / Double(framesPerBucket)))
        var peaks = [Float](repeating: 0, count: bucketCount)

        // Read in whole-bucket multiples so a bucket never straddles two chunks.
        let chunkFrames = AVAudioFrameCount(framesPerBucket * 512)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return nil }

        var frameCursor = 0
        while file.framePosition < file.length {
            do { try file.read(into: buffer, frameCount: chunkFrames) } catch { break }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let channels = buffer.floatChannelData else { break }
            let channelCount = Int(format.channelCount)

            var offset = 0
            while offset < frames {
                let bucket = (frameCursor + offset) / framesPerBucket
                guard bucket < bucketCount else { break }
                let end = min(frames, offset + framesPerBucket - ((frameCursor + offset) % framesPerBucket))
                var peak: Float = 0
                for channel in 0..<channelCount {
                    let samples = channels[channel]
                    for i in offset..<end {
                        let value = abs(samples[i])
                        if value > peak { peak = value }
                    }
                }
                peaks[bucket] = max(peaks[bucket], peak)
                offset = end
            }
            frameCursor += frames
        }

        // Normalise so a quiet take still draws as a readable shape. Cap the gain
        // so silence doesn't get blown up into noise.
        let loudest = peaks.max() ?? 0
        if loudest > 0.05 {
            let gain = min(1 / loudest, 4)
            for i in peaks.indices { peaks[i] = min(1, peaks[i] * gain) }
        }
        return WaveformPeaks(peaks: peaks)
    }
}
