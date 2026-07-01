import Foundation

/// Pure FileManager queries over the app's managed audio folders (Documents/Audio,
/// Recordings, Stems) — no state of its own, so a static namespace rather than an
/// injected service is appropriate here (same reasoning as a stateless formatter).
enum AppStorage {
    static let managedFolderNames = ["Audio", "Recordings", "Stems"]

    static func usageByFolder() -> [(name: String, bytes: Int64)] {
        managedFolderNames.map { name in
            (name, folderSize(at: folderURL(named: name)))
        }
    }

    /// Deletes files in the managed folders that aren't referenced by any current
    /// project (e.g. a recording left behind after its project was deleted some
    /// other way, or a stem from a separation that never got linked in). Returns
    /// how many files were removed.
    static func deleteOrphanedFiles(referencedPaths: Set<String>) -> Int {
        var deletedCount = 0
        for name in managedFolderNames {
            let folder = folderURL(named: name)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            ) else { continue }
            for fileURL in contents where !referencedPaths.contains(fileURL.path) {
                if (try? FileManager.default.removeItem(at: fileURL)) != nil {
                    deletedCount += 1
                }
            }
        }
        return deletedCount
    }

    /// Nuclear option backing "Delete All Projects" — wipes every managed folder
    /// outright, no reference-checking.
    static func deleteAllManagedFiles() {
        for name in managedFolderNames {
            try? FileManager.default.removeItem(at: folderURL(named: name))
        }
    }

    private static func folderURL(named name: String) -> URL {
        URL.documentsDirectory.appending(path: name, directoryHint: .isDirectory)
    }

    private static func folderSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
