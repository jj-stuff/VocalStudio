import SwiftUI

/// Volume control — shown for every track kind (unlike Reverb/EQ/Autotune, which
/// only apply to vocal/recording tracks), since instrumental tracks still need
/// level control relative to the vocal.
struct VolumeTileView: View {
    let volume: Float
    let onVolumeChange: (Float) -> Void

    @State private var sliderValue: Double

    init(volume: Float, onVolumeChange: @escaping (Float) -> Void) {
        self.volume = volume
        self.onVolumeChange = onVolumeChange
        _sliderValue = State(initialValue: Double(volume))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            levelBars
            slider
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.Radius.tile))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VOLUME")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(2)
                Text("Track Level")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            Text("\(Int(sliderValue * 100))%")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private var levelBars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<16, id: \.self) { i in
                let threshold = Double(i) / 16
                let isLit = threshold <= sliderValue
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLit ? barColor(at: i) : Color(.tertiarySystemFill))
                    .frame(height: 6 + CGFloat(i) * 1.6)
                    .animation(.spring(duration: 0.3), value: sliderValue)
            }
        }
        .frame(height: 36, alignment: .bottom)
    }

    private func barColor(at index: Int) -> Color {
        // Monochrome meter; only the overdrive range (>100%) warns in red.
        index > 12 ? .red : .primary
    }

    private var slider: some View {
        Slider(value: $sliderValue, in: 0...1.5)
            .tint(.primary)
            .onChange(of: sliderValue) { onVolumeChange(Float(sliderValue)) }
            .accessibilityLabel("Track volume")
    }
}
