import AVFoundation
import Foundation
import Observation

@Observable
final class ProjectListViewModel {
    private(set) var projects: [Project] = []
    private(set) var isLoading = false
    private(set) var isConvertingVideo = false
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

    /// Single entry point for all file-based imports. Internally detects video vs audio.
    func createProject(title: String, from url: URL) async {
        let isVideo = Self.videoExtensions.contains(url.pathExtension.lowercased())
        if isVideo { isConvertingVideo = true }
        defer { isConvertingVideo = false }
        do {
            let localURL = try await (isVideo ? importVideoAsAudio(from: url) : importAudio(from: url))
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
                throw NSError(domain: "VocalStudio", code: 0,
                              userInfo: [NSLocalizedDescriptionKey: "Cannot create export session"])
            }
            try await session.export(to: dest, as: .m4a)
            return dest
        }.value
    }
}
