import Accelerate
import Foundation

/// Signal-processing constants and STFT helpers for `CoreMLStemSeparator`.
///
/// These numbers are not tunable — they're the exact preprocessing contract the
/// HTDemucs Core ML model was exported with (4096-point FFT, 1024 hop, 343980-sample
/// segments at 44.1kHz, normalized + reflect-padded STFT matching PyTorch's
/// `torch.stft(..., normalized: true)` semantics). Changing any of them desyncs the
/// input tensors from what the model's weights were trained against.
///
/// `nonisolated`: pure computation with no shared mutable state, called from
/// `CoreMLStemSeparator`'s actor context — without this it would inherit the app
/// target's default MainActor isolation and need `await` from every call site.
nonisolated enum DemucsDSP {
    static let sampleRate: Double = 44_100
    static let segmentLength = 343_980
    static let overlapRatio: Double = 0.25

    static let fftSize = 4_096
    static let hopSize = 1_024
    static let frequencyBinCount = fftSize / 2     // 2048
    static let frameCount = 336

    /// Periodic Hann window — matches `torch.hann_window(periodic: true)`.
    static let window: [Float] = (0..<fftSize).map { i in
        0.5 * (1 - cos(2 * Float.pi * Float(i) / Float(fftSize)))
    }

    /// Left/right reflect-pad applied before the forward STFT so it yields exactly
    /// `frameCount` frames over one `segmentLength`-sample segment.
    static let forwardPadLeft = hopSize / 2 * 3
    static let forwardPadRight = forwardPadLeft + frameCount * hopSize - segmentLength

    // MARK: - Padding

    /// Reflect-pads a signal the way `F.pad(..., mode: "reflect")` does: the padding
    /// mirrors the signal back across its edge, excluding the edge sample itself.
    static func reflectPad(_ signal: [Float], left: Int, right: Int) -> [Float] {
        var padded = [Float](repeating: 0, count: left + signal.count + right)
        for i in 0..<left {
            padded[i] = signal[min(left - i, signal.count - 1)]
        }
        _ = padded.withUnsafeMutableBufferPointer { dst in
            signal.withUnsafeBufferPointer { src in
                memcpy(dst.baseAddress! + left, src.baseAddress!, signal.count * MemoryLayout<Float>.size)
            }
        }
        for i in 0..<right {
            let mirrored = signal.count - 2 - i
            padded[left + signal.count + i] = signal[max(mirrored, 0)]
        }
        return padded
    }

    // MARK: - Forward STFT

    /// One channel's spectrogram, laid out bin-major/frame-minor (`bin * frameCount + frame`)
    /// to match the model's `[bins, frames]` tensor layout.
    struct Spectrogram {
        var real: [Float]
        var imag: [Float]
    }

    /// Normalized STFT of a reflect-padded, single-channel signal.
    static func forwardSTFT(of paddedSignal: [Float]) -> Spectrogram {
        let setup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }

        var real = [Float](repeating: 0, count: frequencyBinCount * frameCount)
        var imag = [Float](repeating: 0, count: frequencyBinCount * frameCount)
        let normalization = Float(1 / Double(fftSize).squareRoot())

        var frame = [Float](repeating: 0, count: fftSize)
        var splitReal = [Float](repeating: 0, count: fftSize / 2)
        var splitImag = [Float](repeating: 0, count: fftSize / 2)

        for f in 0..<frameCount {
            let start = f * hopSize
            _ = paddedSignal.withUnsafeBufferPointer { src in
                frame.withUnsafeMutableBufferPointer { dst in
                    memcpy(dst.baseAddress!, src.baseAddress! + start, fftSize * MemoryLayout<Float>.size)
                }
            }
            vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(fftSize))

            frame.withUnsafeBufferPointer { framePtr in
                framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complex in
                    splitReal.withUnsafeMutableBufferPointer { rp in
                        splitImag.withUnsafeMutableBufferPointer { ip in
                            var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(fftSize / 2))
                        }
                    }
                }
            }
            splitReal.withUnsafeMutableBufferPointer { rp in
                splitImag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(kFFTDirection_Forward))
                }
            }

            // vDSP's real FFT packs Nyquist into the imaginary part of bin 0; unpack it
            // and rescale (vDSP's forward FFT is unnormalized, off by a factor of 2 in
            // this packed representation) before writing into the [bin, frame] layout.
            real[0 * frameCount + f] = splitReal[0] * 0.5 * normalization
            imag[0 * frameCount + f] = 0
            for bin in 1..<frequencyBinCount {
                real[bin * frameCount + f] = splitReal[bin] * 0.5 * normalization
                imag[bin * frameCount + f] = splitImag[bin] * 0.5 * normalization
            }
        }
        return Spectrogram(real: real, imag: imag)
    }

    // MARK: - Inverse STFT

    /// Inverse of `forwardSTFT`, with Hann-squared overlap-add normalization, for a
    /// spectrogram already padded to `frameCount + 4` frames (see
    /// `CoreMLStemSeparator.timeDomainEstimate`).
    static func inverseSTFT(real: [Float], imag: [Float], totalFrames: Int) -> [Float] {
        let setup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(setup) }

        let outputLength = (totalFrames - 1) * hopSize + fftSize
        var output = [Float](repeating: 0, count: outputLength)
        var windowEnergy = [Float](repeating: 0, count: outputLength)
        // Undoes forwardSTFT's "* 0.5 * normalization": vDSP's packed real-FFT format
        // is off by a factor of 2 from the normalized DFT values stored in `real`/`imag`.
        let inverseScale = Float(2) * Float(Double(fftSize).squareRoot())

        var splitReal = [Float](repeating: 0, count: fftSize / 2)
        var splitImag = [Float](repeating: 0, count: fftSize / 2)
        var frame = [Float](repeating: 0, count: fftSize)

        for f in 0..<totalFrames {
            splitReal[0] = real[0 * totalFrames + f] * inverseScale
            splitImag[0] = 0   // true Nyquist bin was never stored — reconstruct as zero, matching forwardSTFT's discard
            for bin in 1..<frequencyBinCount {
                splitReal[bin] = real[bin * totalFrames + f] * inverseScale
                splitImag[bin] = imag[bin * totalFrames + f] * inverseScale
            }

            splitReal.withUnsafeMutableBufferPointer { rp in
                splitImag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(kFFTDirection_Inverse))
                    frame.withUnsafeMutableBufferPointer { dst in
                        dst.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complex in
                            vDSP_ztoc(&split, 1, complex, 2, vDSP_Length(fftSize / 2))
                        }
                    }
                }
            }

            var scale = Float(1) / Float(2 * fftSize)
            vDSP_vsmul(frame, 1, &scale, &frame, 1, vDSP_Length(fftSize))
            vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(fftSize))

            let start = f * hopSize
            for i in 0..<fftSize {
                output[start + i] += frame[i]
                windowEnergy[start + i] += window[i] * window[i]
            }
        }

        for i in 0..<outputLength where windowEnergy[i] > 1e-8 {
            output[i] /= windowEnergy[i]
        }
        return output
    }

    /// Reconstructs one `segmentLength`-sample time-domain channel from the model's
    /// frequency-branch output for that channel. The model's spectrogram is centered
    /// with 2 extra frames of context on each side relative to the analysis window
    /// (matching PyTorch's `_ispec`), so the raw ISTFT result is wider than one segment
    /// and must be trimmed back down to it.
    static func timeDomain(real: [Float], imag: [Float]) -> [Float] {
        let totalFrames = frameCount + 4
        var paddedReal = [Float](repeating: 0, count: frequencyBinCount * totalFrames)
        var paddedImag = [Float](repeating: 0, count: frequencyBinCount * totalFrames)

        for bin in 0..<frequencyBinCount {
            let srcOffset = bin * frameCount
            let dstOffset = bin * totalFrames + 2
            _ = real.withUnsafeBufferPointer { src in
                paddedReal.withUnsafeMutableBufferPointer { dst in
                    memcpy(dst.baseAddress! + dstOffset, src.baseAddress! + srcOffset, frameCount * MemoryLayout<Float>.size)
                }
            }
            _ = imag.withUnsafeBufferPointer { src in
                paddedImag.withUnsafeMutableBufferPointer { dst in
                    memcpy(dst.baseAddress! + dstOffset, src.baseAddress! + srcOffset, frameCount * MemoryLayout<Float>.size)
                }
            }
        }

        let raw = inverseSTFT(real: paddedReal, imag: paddedImag, totalFrames: totalFrames)
        let trimStart = fftSize / 2 + forwardPadLeft
        return Array(raw[trimStart..<trimStart + segmentLength])
    }
}
