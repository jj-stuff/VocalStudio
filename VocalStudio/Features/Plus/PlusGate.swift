import SwiftUI

/// Wraps a Plus-only control. With Plus the content is shown as-is; without it the
/// content is dimmed and non-interactive under a lock badge, and a tap opens the
/// paywall. The control itself stays visible so people can see what they'd get.
struct PlusGate<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(PlusEntitlement.self) private var entitlement
    @State private var showingPaywall = false

    var body: some View {
        if entitlement.isActive {
            content()
        } else {
            content()
                .disabled(true)
                .opacity(0.55)
                .overlay(alignment: .topTrailing) {
                    Label(AppConfig.Plus.productName, systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xs)
                        .glassEffect(.regular.tint(DS.Brand.purple2.opacity(0.6)), in: .capsule)
                        .foregroundStyle(.white)
                        .padding(DS.Spacing.sm)
                }
                .contentShape(Rectangle())
                .onTapGesture { showingPaywall = true }
                .sheet(isPresented: $showingPaywall) { PlusPaywallView() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Requires \(AppConfig.Plus.productName)")
        }
    }
}
