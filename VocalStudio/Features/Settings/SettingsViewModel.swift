import Foundation
import Observation

@Observable
final class SettingsViewModel {
    private(set) var folderUsage: [(name: String, bytes: Int64)] = []
    private(set) var isWorking = false
    var errorMessage: String?
    var lastActionMessage: String?

    private let store: ProjectStoreInterface

    init(store: ProjectStoreInterface) {
        self.store = store
    }

    var totalBytes: Int64 { folderUsage.reduce(0) { $0 + $1.bytes } }

    func refresh() {
        folderUsage = AppStorage.usageByFolder()
    }

    /// Removes files in the managed audio folders that no current project
    /// references — e.g. leftovers from before per-project deletion cleaned up its
    /// own files, or anything orphaned by some other bug. Projects' own files are
    /// not touched here; this only sweeps what nothing points to anymore.
    func cleanUpUnusedFiles() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let projects = try await store.loadAll()
            var referenced = Set<String>()
            for project in projects {
                referenced.insert(project.sourceURL.path)
                for stem in project.stems { referenced.insert(stem.url.path) }
                for recording in project.recordings { referenced.insert(recording.url.path) }
            }
            let deletedCount = AppStorage.deleteOrphanedFiles(referencedPaths: referenced)
            refresh()
            lastActionMessage = deletedCount > 0
                ? "Removed \(deletedCount) unused file\(deletedCount == 1 ? "" : "s")."
                : "Nothing to clean up — every file on disk belongs to a project."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The nuclear option: deletes every project and every managed audio file outright.
    func deleteAllProjects() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let projects = try await store.loadAll()
            for project in projects {
                try await store.delete(id: project.id)
            }
            AppStorage.deleteAllManagedFiles()
            refresh()
            lastActionMessage = "Deleted all projects."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
