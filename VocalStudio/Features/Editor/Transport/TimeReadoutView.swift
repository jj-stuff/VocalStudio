import SwiftUI

/// The big position readout above the timeline: current time, with the project
/// length underneath. Rounded monospaced digits so the numbers tick without
/// jittering — the same treatment Apple gives the numbers in Fitness and Clock.
struct TimeReadoutView: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isRecording: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(Self.format(currentTime))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isRecording ? Color.red : Color.primary)
                .contentTransition(.numericText())
            Text(Self.format(duration))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .animation(DS.Animation.smooth, value: isRecording)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Position \(Self.format(currentTime)) of \(Self.format(duration))")
    }

    /// "1:23.4"
    private static func format(_ t: TimeInterval) -> String {
        let clamped = max(0, t)
        let m = Int(clamped) / 60
        let s = Int(clamped) % 60
        let tenths = Int((clamped.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, tenths)
    }
}
