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
        .background(tileBackground)
        .clipShape(.rect(cornerRadius: 24))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REVERB")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.6))
                    .tracking(2)
                Text("Room Size")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("\(Int(sliderValue))%")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .fontDesign(.monospaced)
        }
    }

    private var decayBars: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<8, id: \.self) { i in
                let factor = CGFloat(i) / 7
                let mix = CGFloat(sliderValue) / 100
                let height = 4 + (28 * mix * (1 - factor * 0.6))
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.3, green: 0.9, blue: 0.7), Color(red: 0.1, green: 0.65, blue: 0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .opacity(0.4 + 0.6 * Double(1 - factor * 0.5))
                    )
                    .frame(height: height)
                    .animation(.spring(duration: 0.4), value: sliderValue)
            }
            Spacer()
        }
        .frame(height: 36)
    }

    private var slider: some View {
        Slider(value: $sliderValue, in: 0...100)
            .tint(Color(red: 0.3, green: 0.9, blue: 0.6))
            .onChange(of: sliderValue) { onReverbChange(Float(sliderValue)) }
    }

    private var tileBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.18, blue: 0.17), Color(red: 0.05, green: 0.23, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.1, green: 0.8, blue: 0.6).opacity(0.3), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 180
            )
        }
    }
}
