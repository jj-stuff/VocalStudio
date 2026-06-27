import Foundation

/// Result of a stem separation pass.
struct StemSeparationResult {
    let vocalURL: URL
    let instrumentalURL: URL
}

/// Separation progress reported during a long-running inference job.
enum SeparationProgress: Sendable {
    case loading        // model is loading
    case processing(Double)  // 0.0 – 1.0
    case done
}

/// Contract for any stem separator implementation (mock, MLX, server-side, etc.)
protocol StemSeparationService: Sendable {
    /// Separate `sourceURL` into vocal + instrumental stems.
    /// Sends progress events via the `AsyncThrowingStream` before returning the result.
    func separate(
        sourceURL: URL,
        onProgress: @Sendable @escaping (SeparationProgress) -> Void
    ) async throws -> StemSeparationResult
}
