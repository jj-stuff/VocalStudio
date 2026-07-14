import AVFoundation
import Foundation
import Observation
import PhotosUI
import SwiftUI

@Observable
final class ProjectListViewModel {

    /// An import that is still converting/copying. Rendered as a live, disabled row
    /// in the project list — per the HIG, long-running work shows progress in place
    /// instead of blocking the whole screen behind an overlay. The list stays fully
    /// usable while these run, and several can run at once.
    struct PendingImport: Identifiable, Equatable {
        let id = UUID()
        let detail: String
    }

    private(set) var projects: [Project] = []
    private(set) var pendingImports: [PendingImport] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let store: ProjectStoreInterface

    // Business knowledge of video file types lives here, not in the view.
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]

    init(store: ProjectStoreInterface) {
        self.store = store
    }

    // MARK: - Intent

    func loadProjects() async {
        isLoading = true
        defer { isLoading = false }
        do {
            projects = try await store.loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Import from a file URL (Files picker). Detects video vs audio internally.
    func createProject(title: String, from url: URL) async {
        let isVideo = Self.videoExtensions.contains(url.pathExtension.lowercased())
        await runImport(detail: isVideo ? "Extracting audio…" : "Importing audio…", title: title) {
            try await (isVideo ? self.importVideoAsAudio(from: url) : self.importAudio(from: url))
        }
    }

    /// Import from a Photos picker item (always a video — the picker filter says so).
    /// The transfer out of the Photos library is itself slow for big videos, so the
    /// pending row appears before it starts, not just for the conversion step.
    func importPhotoItem(_ item: PhotosPickerItem) async {
        await runImport(detail: "Extracting audio…", title: "") {
            guard let video = try await item.loadTransferable(type: VideoTransferable.self) else {
                throw ImportError.photoLoadFailed
            }
            return try await self.importVideoAsAudio(from: video.url)
        }
    }

    /// Deletes by identity, not index — the view may be showing a filtered
    /// (e.g. searched) subset, where a raw `List` offset wouldn't line up with
    /// this VM's full `projects` array.
    func delete(ids: Set<UUID>) async {
        for id in ids {
            do {
                try await store.delete(id: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        projects.removeAll { ids.contains($0.id) }
    }

    // MARK: - Shared import pipeline

    private func runImport(detail: String, title: String, _ produceLocalURL: () async throws -> URL) async {
        let pending = PendingImport(detail: detail)
        pendingImports.append(pending)
        defer { pendingImports.removeAll { $0.id == pending.id } }
        do {
            let localURL = try await produceLocalURL()
            let name = title.isEmpty ? CatBreedNamer.randomName(avoiding: projects.map(\.title)) : title
            let project = Project(title: name, sourceURL: localURL)
            try await store.save(project)
            projects.append(project)
        } catch is CancellationError {
            // ignore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Audio import

    private func importAudio(from externalURL: URL) async throws -> URL {
        let accessGranted = externalURL.startAccessingSecurityScopedResource()
        defer { if accessGranted { externalURL.stopAccessingSecurityScopedResource() } }

        return try await Task.detached(priority: .userInitiated) {
            let audioDir = URL.documentsDirectory
                .appending(path: "Audio", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
            let filename = UUID().uuidString + "_" + externalURL.lastPathComponent
            let dest = audioDir.appending(path: filename)
            try FileManager.default.copyItem(at: externalURL, to: dest)
            return dest
        }.value
    }

    // MARK: - Video → audio extraction

    private func importVideoAsAudio(from videoURL: URL) async throws -> URL {
        // Security-scoped access is needed when the video came from the Files picker.
        // It's a safe no-op for temp URLs returned by PhotosPicker.
        let accessGranted = videoURL.startAccessingSecurityScopedResource()
        defer { if accessGranted { videoURL.stopAccessingSecurityScopedResource() } }

        return try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: videoURL)
            let audioDir = URL.documentsDirectory
                .appending(path: "Audio", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

            let filename = UUID().uuidString + "_" + videoURL.deletingPathExtension().lastPathComponent + ".m4a"
            let dest = audioDir.appending(path: filename)

            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw ImportError.exportSessionUnavailable
            }
            try await session.export(to: dest, as: .m4a)
            return dest
        }.value
    }
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case photoLoadFailed
    case exportSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .photoLoadFailed:
            return "Could not load the selected video."
        case .exportSessionUnavailable:
            return "Could not read audio from that video."
        }
    }
}
