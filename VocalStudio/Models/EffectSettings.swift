import Foundation

struct EffectSettings: Codable {
    let reverbMix: Float        // 0 – 100 (wet/dry %)
    let eqGains: [Float]        // gain per band in dB; 4 bands: bass, low-mid, high-mid, treble

    static let `default` = EffectSettings(reverbMix: 15, eqGains: [0, 0, 0, 0])
    static let eqBandLabels = ["Bass", "Low Mid", "High Mid", "Treble"]

    func withReverb(_ mix: Float) -> EffectSettings {
        EffectSettings(reverbMix: mix.clamped(to: 0...100), eqGains: eqGains)
    }

    func withEQGain(_ gain: Float, at index: Int) -> EffectSettings {
        var bands = eqGains
        guard bands.indices.contains(index) else { return self }
        bands[index] = gain.clamped(to: -12...12)
        return EffectSettings(reverbMix: reverbMix, eqGains: bands)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
