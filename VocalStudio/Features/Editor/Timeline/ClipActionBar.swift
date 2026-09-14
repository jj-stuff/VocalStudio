import SwiftUI

/// The floating actions for the selected clip: Split at the playhead, Delete.
/// Appears above the transport the moment a clip is selected, and goes away with
/// the selection — the selected clip is the only context these actions need.
struct ClipActionBar: View {
    let canSplit: Bool
    let onSplit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Button(action: onSplit) {
                    Label("Split", systemImage: "scissors")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs + DS.Spacing.xxs)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .disabled(!canSplit)
                .opacity(canSplit ? 1 : 0.45)
                .accessibilityHint(canSplit ? "Cuts the clip at the playhead" : "Move the playhead inside the clip to split it")

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.xs + DS.Spacing.xxs)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
    }
}
