import Observation

/// Whether the user has the paid tier. One observable object, injected through the
/// environment, so any screen can gate a feature with `entitlement.isActive` and
/// react the moment it flips. Today it never flips — StoreKit is a TODO — but the
/// gating code is already in place so wiring purchases later is a one-file change.
@Observable
final class PlusEntitlement {
    /// True when the user has Aria Plus. Always false until StoreKit is wired.
    private(set) var isActive = false

    /// Placeholder for the StoreKit transaction check. Kept async so the call site
    /// shape doesn't change when the real implementation arrives.
    func refresh() async {
        // TODO: StoreKit 2 — check `Transaction.currentEntitlements`.
        isActive = false
    }
}
