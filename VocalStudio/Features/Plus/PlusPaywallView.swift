import SwiftUI

/// The Siasca Plus screen. A placeholder until StoreKit is wired: it explains what
/// Plus is for and shows a disabled purchase button, so the flow can be designed
/// around a real screen now and the button only needs a real action later.
struct PlusPaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.xl) {
                    header
                    features
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.xl)
            }
            .background(AppBackground())
            .safeAreaInset(edge: .bottom) { purchaseButton }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(
                    LinearGradient(colors: [DS.Brand.accent, DS.Brand.purple2],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text(AppConfig.Plus.productName)
                .font(.largeTitle.weight(.bold))
            Text("Studio tools for the takes you care about.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var features: some View {
        VStack(spacing: DS.Spacing.sm) {
            FeatureRow(
                systemImage: "tuningfork",
                title: "Autotune",
                detail: "Pitch correction with key, scale, amount and retune speed."
            )
            FeatureRow(
                systemImage: "square.and.arrow.up",
                title: "Export",
                detail: "Mix down a project to a single file and share it. Coming soon."
            )
            FeatureRow(
                systemImage: "sparkles.rectangle.stack",
                title: "Everything next",
                detail: "New studio features land in Plus first."
            )
        }
    }

    private var purchaseButton: some View {
        VStack(spacing: DS.Spacing.xs) {
            Button {
                // TODO: StoreKit 2 purchase flow.
            } label: {
                Text(AppConfig.Plus.purchasingEnabled ? "Continue" : "Coming Soon")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.xxs)
            }
            .buttonStyle(.glassProminent)
            .tint(DS.Brand.accent)
            .foregroundStyle(.white)
            .disabled(!AppConfig.Plus.purchasingEnabled)

            Text("Plus is not on sale yet. Everything else in \(AppConfig.appName) is free.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
    }
}

private struct FeatureRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            SettingsIconTile(systemImage: systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: DS.Radius.md))
    }
}
