import Foundation

public enum Scanner {
    public static let rawExtensions: Set<String> = ["cr2", "cr3", "nef", "nrw", "arw", "sr2", "srf", "raf", "orf", "rw2", "pef", "rwl", "3fr", "iiq", "srw", "x3f", "dng", "raw"]
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "hif", "png", "tif", "tiff"]
    public static func scan(_ directory: URL) throws -> [Photo] {
        var scanError: Error?
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in scanError = error; return false }) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true { files.append(url) }
        }
        if let scanError { throw scanError }
        // Match camera basenames across the complete imported directory tree.
        let groups = Dictionary(grouping: files) { $0.deletingPathExtension().lastPathComponent.lowercased() }
        return groups.values.compactMap { urls -> Photo? in
            let images = urls.filter { imageExtensions.contains($0.pathExtension.lowercased()) || rawExtensions.contains($0.pathExtension.lowercased()) }
            let ordered = images.sorted {
                let a = previewRank($0), b = previewRank($1)
                return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
            }
            guard let preview = ordered.first else { return nil }
            return Photo(preview: preview, files: urls.sorted { $0.lastPathComponent < $1.lastPathComponent })
        }.sorted { $0.preview.path.localizedStandardCompare($1.preview.path) == .orderedAscending }
    }
    private static func previewRank(_ url: URL) -> Int {
        if ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) { return 0 }
        return imageExtensions.contains(url.pathExtension.lowercased()) ? 1 : 2
    }
}

public enum SessionStorage {
    public static func save(_ session: ReviewSession, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: url, options: .atomic)
    }
    public static func load(from url: URL, photos: [Photo]) throws -> ReviewSession {
        let old = try JSONDecoder().decode(ReviewSession.self, from: Data(contentsOf: url))
        var result = ReviewSession(photos: photos)
        var byFile: [String: String] = [:]
        for photo in old.photos { for file in photo.files { byFile[file.path] = photo.id } }
        for (index, photo) in photos.enumerated() {
            let priorIDs = Set(photo.files.compactMap { byFile[$0.path] } + [photo.id])
            let priorMarks = priorIDs.compactMap { old.marks[$0] }
            if priorMarks.contains(.selected) { result.marks[photo.id] = .selected }
            else if priorMarks.contains(.rejected) { result.marks[photo.id] = .rejected }
            if let rating = priorIDs.compactMap({ old.ratings[$0] }).max() { result.ratings[photo.id] = rating }
            if old.photos.indices.contains(old.cursor), priorIDs.contains(old.photos[old.cursor].id) { result.cursor = index }
        }
        return result
    }
}
