import SwiftUI

struct ReverbTileView: View {
    let reverbMix: Float
    let onReverbChange: (Float) -> Void

    @State private var sliderValue: Double

    init(reverbMix: Float, onReverbChange: @escaping (Float) -> Void) {
        self.reverbMix = reverbMix
        self.onReverbChange = onReverbChange
        _sliderValue = State(initialValue: Double(reverbMix))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            decayBars
            slider
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.Radius.tile))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REVERB")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Text("Room Size")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            Text("\(Int(sliderValue))%")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private var decayBars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<8, id: \.self) { i in
                let factor = CGFloat(i) / 7
                let mix = CGFloat(sliderValue) / 100
                let height = 4 + (28 * mix * (1 - factor * 0.6))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.85 - 0.6 * Double(factor)))
                    .frame(height: height)
                    .animation(.spring(duration: 0.4), value: sliderValue)
            }
            Spacer()
        }
        .frame(height: 36)
    }

    private var slider: some View {
        Slider(value: $sliderValue, in: 0...100)
            .tint(.primary)
            .onChange(of: sliderValue) { onReverbChange(Float(sliderValue)) }
            .accessibilityLabel("Reverb mix")
    }
}
