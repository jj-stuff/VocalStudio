import Accelerate
@preconcurrency import AVFoundation
import CoreML

/// Real on-device source separation via a pre-trained HTDemucs Core ML model —
/// MIT-licensed, converted from facebookresearch/demucs by the community
/// (Resources/Models/HTDemucs_SourceSeparation_F32.mlpackage). Mixes the model's
/// 4 native stems (drums, bass, other, vocals) down to the vocal/instrumental
/// split this app's editor works with.
///
/// An `actor` because loading the 100MB model and running inference are both
/// heavy, blocking calls — isolating them off the main actor keeps the UI free,
/// per the project's actor-for-heavy-compute convention.
actor CoreMLStemSeparator: StemSeparationService {

    private enum ModelStem: Int, CaseIterable {
        case drums = 0, bass = 1, other = 2, vocals = 3
    }

    private var loadedModel: MLModel?

    func separate(
        sourceURL: URL,
        onProgress: @Sendable @escaping (SeparationProgress) -> Void
    ) async throws -> StemSeparationResult {
        onProgress(.loading)
        let model = try loadModel()
        let (left, right) = try Self.loadStereoSamples(from: sourceURL)
        let totalSamples = left.count
        guard totalSamples > 0 else { throw StemSeparationError.emptySource }

        let stride = Int(Double(DemucsDSP.segmentLength) * (1 - DemucsDSP.overlapRatio))
        let chunkCount = max(1, Int(ceil(Double(max(0, totalSamples - DemucsDSP.segmentLength)) / Double(stride))) + 1)
        let crossfade = Self.buildCrossfadeWeight()

        var accumulatedLeft = ModelStem.allCases.map { _ in [Float](repeating: 0, count: totalSamples) }
        var accumulatedRight = ModelStem.allCases.map { _ in [Float](repeating: 0, count: totalSamples) }
        var weightSum = [Float](repeating: 0, count: totalSamples)

        for chunkIndex in 0..<chunkCount {
            let offset = min(chunkIndex * stride, max(0, totalSamples - DemucsDSP.segmentLength))
            let chunkLength = min(DemucsDSP.segmentLength, totalSamples - offset)

            var segmentLeft = Array(left[offset..<offset + chunkLength])
            var segmentRight = Array(right[offset..<offset + chunkLength])
            if chunkLength < DemucsDSP.segmentLength {
                segmentLeft += [Float](repeating: 0, count: DemucsDSP.segmentLength - chunkLength)
                segmentRight += [Float](repeating: 0, count: DemucsDSP.segmentLength - chunkLength)
            }

            let stems = try Self.runModel(model, left: segmentLeft, right: segmentRight)
            for stem in ModelStem.allCases {
                let i = stem.rawValue
                for sample in 0..<chunkLength {
                    accumulatedLeft[i][offset + sample] += stems[i].left[sample] * crossfade[sample]
                    accumulatedRight[i][offset + sample] += stems[i].right[sample] * crossfade[sample]
                }
            }
            for sample in 0..<chunkLength {
                weightSum[offset + sample] += crossfade[sample]
            }

            onProgress(.processing(Double(chunkIndex + 1) / Double(chunkCount)))
        }

        for stem in ModelStem.allCases {
            let i = stem.rawValue
            for sample in 0..<totalSamples where weightSum[sample] > 1e-8 {
                accumulatedLeft[i][sample] /= weightSum[sample]
                accumulatedRight[i][sample] /= weightSum[sample]
            }
        }

        let vocalsIndex = ModelStem.vocals.rawValue
        var instrumentalLeft = accumulatedLeft[ModelStem.drums.rawValue]
        var instrumentalRight = accumulatedRight[ModelStem.drums.rawValue]
        for stem: ModelStem in [.bass, .other] {
            vDSP_vadd(instrumentalLeft, 1, accumulatedLeft[stem.rawValue], 1, &instrumentalLeft, 1, vDSP_Length(totalSamples))
            vDSP_vadd(instrumentalRight, 1, accumulatedRight[stem.rawValue], 1, &instrumentalRight, 1, vDSP_Length(totalSamples))
        }

        let stemsDir = URL.documentsDirectory.appending(path: "Stems", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stemsDir, withIntermediateDirectories: true)
        let vocalURL = stemsDir.appendingPathComponent(UUID().uuidString + "_vocal.caf")
        let instrumentalURL = stemsDir.appendingPathComponent(UUID().uuidString + "_instrumental.caf")
        try Self.writeStereoFile(left: accumulatedLeft[vocalsIndex], right: accumulatedRight[vocalsIndex], to: vocalURL)
        try Self.writeStereoFile(left: instrumentalLeft, right: instrumentalRight, to: instrumentalURL)

        onProgress(.done)
        return StemSeparationResult(vocalURL: vocalURL, instrumentalURL: instrumentalURL)
    }

    // MARK: - Model loading

    private func loadModel() throws -> MLModel {
        if let loadedModel { return loadedModel }
        guard let url = Bundle.main.url(forResource: "HTDemucs_SourceSeparation_F32", withExtension: "mlmodelc") else {
            throw StemSeparationError.modelNotFound
        }
        let configuration = MLModelConfiguration()
        // The Neural Engine compiler for this graph has been flaky across OS builds;
        // CPU+GPU is slower but reliable, and this is a one-time prep step, not real-time.
        configuration.computeUnits = .cpuAndGPU
        let model = try MLModel(contentsOf: url, configuration: configuration)
        loadedModel = model
        return model
    }

    // MARK: - Per-segment inference

    /// Runs one `segmentLength`-sample stereo segment through the model and returns
    /// all 4 native Demucs stems (indexed by `ModelStem.rawValue`) as stereo audio.
    nonisolated private static func runModel(
        _ model: MLModel,
        left: [Float],
        right: [Float]
    ) throws -> [(left: [Float], right: [Float])] {
        let leftSpectrogram = DemucsDSP.forwardSTFT(
            of: DemucsDSP.reflectPad(left, left: DemucsDSP.forwardPadLeft, right: DemucsDSP.forwardPadRight)
        )
        let rightSpectrogram = DemucsDSP.forwardSTFT(
            of: DemucsDSP.reflectPad(right, left: DemucsDSP.forwardPadLeft, right: DemucsDSP.forwardPadRight)
        )

        let spectral = try MLMultiArray(
            shape: [1, 4, NSNumber(value: DemucsDSP.frequencyBinCount), NSNumber(value: DemucsDSP.frameCount)],
            dataType: .float32
        )
        // Channel order matches the model's "cac" (complex-as-channels) training layout.
        writeChannel2D(leftSpectrogram.real, into: spectral, channel: 0)
        writeChannel2D(leftSpectrogram.imag, into: spectral, channel: 1)
        writeChannel2D(rightSpectrogram.real, into: spectral, channel: 2)
        writeChannel2D(rightSpectrogram.imag, into: spectral, channel: 3)

        let waveform = try MLMultiArray(shape: [1, 2, NSNumber(value: DemucsDSP.segmentLength)], dataType: .float32)
        writeChannel1D(left, into: waveform, channel: 0)
        writeChannel1D(right, into: waveform, channel: 1)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "spectral_magnitude": MLFeatureValue(multiArray: spectral),
            "audio_waveform": MLFeatureValue(multiArray: waveform),
        ])
        let output = try model.prediction(from: input)
        guard let freqOutput = output.featureValue(for: "freq_output")?.multiArrayValue,
              let timeOutput = output.featureValue(for: "time_output")?.multiArrayValue else {
            throw StemSeparationError.missingModelOutput
        }

        var results = [(left: [Float], right: [Float])](
            repeating: (left: [], right: []), count: ModelStem.allCases.count
        )
        for stem in ModelStem.allCases {
            let i = stem.rawValue

            let freqLeft = DemucsDSP.timeDomain(
                real: readChannel2D(from: freqOutput, channel: 4 * i),
                imag: readChannel2D(from: freqOutput, channel: 4 * i + 1)
            )
            let freqRight = DemucsDSP.timeDomain(
                real: readChannel2D(from: freqOutput, channel: 4 * i + 2),
                imag: readChannel2D(from: freqOutput, channel: 4 * i + 3)
            )
            let timeLeft = readChannel1D(from: timeOutput, channel: 2 * i)
            let timeRight = readChannel1D(from: timeOutput, channel: 2 * i + 1)

            var stemLeft = [Float](repeating: 0, count: DemucsDSP.segmentLength)
            var stemRight = [Float](repeating: 0, count: DemucsDSP.segmentLength)
            vDSP_vadd(freqLeft, 1, timeLeft, 1, &stemLeft, 1, vDSP_Length(DemucsDSP.segmentLength))
            vDSP_vadd(freqRight, 1, timeRight, 1, &stemRight, 1, vDSP_Length(DemucsDSP.segmentLength))
            results[i] = (left: stemLeft, right: stemRight)
        }
        return results
    }

    // MARK: - MLMultiArray marshaling

    /// Writes a `[frequencyBinCount, frameCount]` plane into one channel of a
    /// `[1, 4, bins, frames]` Float32 array, respecting its actual strides.
    nonisolated private static func writeChannel2D(_ plane: [Float], into array: MLMultiArray, channel: Int) {
        let strides = array.strides.map(\.intValue)
        let base = channel * strides[1]
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        if strides[3] == 1 && strides[2] == DemucsDSP.frameCount {
            _ = plane.withUnsafeBufferPointer { src in
                memcpy(ptr + base, src.baseAddress!, plane.count * MemoryLayout<Float>.size)
            }
        } else {
            for bin in 0..<DemucsDSP.frequencyBinCount {
                for frame in 0..<DemucsDSP.frameCount {
                    ptr[base + bin * strides[2] + frame * strides[3]] = plane[bin * DemucsDSP.frameCount + frame]
                }
            }
        }
    }

    /// Writes a `segmentLength`-sample channel into a `[1, 2, segmentLength]` Float32 array.
    nonisolated private static func writeChannel1D(_ samples: [Float], into array: MLMultiArray, channel: Int) {
        let strides = array.strides.map(\.intValue)
        let base = channel * strides[1]
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        if strides[2] == 1 {
            _ = samples.withUnsafeBufferPointer { src in
                memcpy(ptr + base, src.baseAddress!, samples.count * MemoryLayout<Float>.size)
            }
        } else {
            for sample in 0..<samples.count {
                ptr[base + sample * strides[2]] = samples[sample]
            }
        }
    }

    /// Reads one `[frequencyBinCount, frameCount]` channel out of a 4D model output,
    /// converting from the model's native Float16 storage.
    nonisolated private static func readChannel2D(from array: MLMultiArray, channel: Int) -> [Float] {
        let strides = array.strides.map(\.intValue)
        let base = channel * strides[1]
        var result = [Float](repeating: 0, count: DemucsDSP.frequencyBinCount * DemucsDSP.frameCount)
        switch array.dataType {
        case .float16:
            let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: array.count)
            for bin in 0..<DemucsDSP.frequencyBinCount {
                let rowBase = base + bin * strides[2]
                for frame in 0..<DemucsDSP.frameCount {
                    result[bin * DemucsDSP.frameCount + frame] = Float(ptr[rowBase + frame * strides[3]])
                }
            }
        default:
            let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            for bin in 0..<DemucsDSP.frequencyBinCount {
                let rowBase = base + bin * strides[2]
                for frame in 0..<DemucsDSP.frameCount {
                    result[bin * DemucsDSP.frameCount + frame] = ptr[rowBase + frame * strides[3]]
                }
            }
        }
        return result
    }

    /// Reads one `segmentLength`-sample channel out of a 3D model output, converting
    /// from the model's native Float16 storage.
    nonisolated private static func readChannel1D(from array: MLMultiArray, channel: Int) -> [Float] {
        let strides = array.strides.map(\.intValue)
        let base = channel * strides[1]
        var result = [Float](repeating: 0, count: DemucsDSP.segmentLength)
        switch array.dataType {
        case .float16:
            let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: array.count)
            for sample in 0..<DemucsDSP.segmentLength {
                result[sample] = Float(ptr[base + sample * strides[2]])
            }
        default:
            let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            for sample in 0..<DemucsDSP.segmentLength {
                result[sample] = ptr[base + sample * strides[2]]
            }
        }
        return result
    }

    // MARK: - Audio I/O

    nonisolated private static func loadStereoSamples(from url: URL) throws -> (left: [Float], right: [Float]) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

        let sourceFile = try AVAudioFile(forReading: url)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: DemucsDSP.sampleRate, channels: 2, interleaved: false
        ) else {
            throw StemSeparationError.processingFailed
        }

        let ratio = DemucsDSP.sampleRate / sourceFile.processingFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(sourceFile.length) * ratio) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrames) else {
            throw StemSeparationError.processingFailed
        }

        if sourceFile.processingFormat.sampleRate == DemucsDSP.sampleRate,
           sourceFile.processingFormat.channelCount == 2,
           sourceFile.processingFormat.commonFormat == .pcmFormatFloat32 {
            try sourceFile.read(into: outputBuffer)
        } else {
            guard let converter = AVAudioConverter(from: sourceFile.processingFormat, to: targetFormat),
                  let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: AVAudioFrameCount(sourceFile.length))
            else {
                throw StemSeparationError.processingFailed
            }
            try sourceFile.read(into: sourceBuffer)
            // The whole input is already in memory as one buffer, so the simple
            // one-shot conversion applies — no need for the closure-based streaming
            // API, which also sidesteps having to capture a non-Sendable
            // AVAudioPCMBuffer in an @Sendable closure.
            try converter.convert(to: outputBuffer, from: sourceBuffer)
        }

        let frameCount = Int(outputBuffer.frameLength)
        guard frameCount > 0, let channelData = outputBuffer.floatChannelData else {
            throw StemSeparationError.emptySource
        }
        let rightChannelIndex = outputBuffer.format.channelCount > 1 ? 1 : 0
        let left = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        let right = Array(UnsafeBufferPointer(start: channelData[rightChannelIndex], count: frameCount))
        return (left, right)
    }

    nonisolated private static func writeStereoFile(left: [Float], right: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: DemucsDSP.sampleRate, channels: 2, interleaved: false
        ) else {
            throw StemSeparationError.processingFailed
        }
        let frameCount = AVAudioFrameCount(min(left.count, right.count))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData else {
            throw StemSeparationError.processingFailed
        }
        buffer.frameLength = frameCount
        left.withUnsafeBufferPointer { src in channelData[0].update(from: src.baseAddress!, count: Int(frameCount)) }
        right.withUnsafeBufferPointer { src in channelData[1].update(from: src.baseAddress!, count: Int(frameCount)) }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    /// Triangular crossfade window for blending overlapping chunks back together.
    nonisolated private static func buildCrossfadeWeight() -> [Float] {
        let half = DemucsDSP.segmentLength / 2
        var weight = [Float](repeating: 0, count: DemucsDSP.segmentLength)
        for i in 0..<half { weight[i] = Float(i + 1) }
        for i in half..<DemucsDSP.segmentLength { weight[i] = Float(DemucsDSP.segmentLength - i) }
        var maxValue: Float = 0
        vDSP_maxv(weight, 1, &maxValue, vDSP_Length(weight.count))
        if maxValue > 0 {
            var inverse = 1 / maxValue
            vDSP_vsmul(weight, 1, &inverse, &weight, 1, vDSP_Length(weight.count))
        }
        return weight
    }
}

// MARK: - Errors

enum StemSeparationError: LocalizedError {
    case modelNotFound
    case emptySource
    case missingModelOutput
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "The separation model could not be found in the app bundle."
        case .emptySource:
            return "The source track has no audio to separate."
        case .missingModelOutput:
            return "The separation model did not return the expected output."
        case .processingFailed:
            return "Audio processing failed while preparing for separation."
        }
    }
}
