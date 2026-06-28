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
        .background(tileBackground)
        .clipShape(.rect(cornerRadius: 24))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VOLUME")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(2)
                Text("Track Level")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("\(Int(sliderValue * 100))%")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .fontDesign(.monospaced)
        }
    }

    private var levelBars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<16, id: \.self) { i in
                let threshold = Double(i) / 16
                let isLit = threshold <= sliderValue
                RoundedRectangle(cornerRadius: 2)
                    .fill(isLit ? barColor(at: i) : Color.white.opacity(0.08))
                    .frame(height: 6 + CGFloat(i) * 1.6)
                    .animation(.spring(duration: 0.3), value: sliderValue)
            }
        }
        .frame(height: 36, alignment: .bottom)
    }

    private func barColor(at index: Int) -> Color {
        index > 12 ? Color(red: 1.0, green: 0.55, blue: 0.2) : Color(red: 0.35, green: 0.65, blue: 1.0)
    }

    private var slider: some View {
        Slider(value: $sliderValue, in: 0...1.5)
            .tint(Color(red: 0.35, green: 0.65, blue: 1.0))
            .onChange(of: sliderValue) { onVolumeChange(Float(sliderValue)) }
            .accessibilityLabel("Track volume")
    }

    private var tileBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.09, blue: 0.2), Color(red: 0.06, green: 0.12, blue: 0.26)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.3, green: 0.55, blue: 1.0).opacity(0.3), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 200
            )
        }
    }
}
