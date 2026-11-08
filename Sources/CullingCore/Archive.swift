import Foundation

public struct ArchiveEntry: Codable, Sendable {
    public let original: URL
    public let archived: URL
}
public struct ArchivedReview: Codable, Sendable {
    public let files: [URL]
    public let mark: PhotoMark
    public let rating: Int
}
public struct ArchiveManifest: Codable, Sendable {
    public let createdAt: Date
    public let entries: [ArchiveEntry]
    public var reviews: [ArchivedReview]? = nil
}
public struct ArchiveResult: Sendable {
    public let directory: URL
    public let manifest: ArchiveManifest
}
public enum ArchiveError: LocalizedError {
    case empty, missing(String), invalidManifest, rollback(String)
    public var errorDescription: String? {
        switch self {
        case .empty: "没有可归档的照片。"
        case .missing(let path): "找不到原文件：\(path)"
        case .invalidManifest: "归档清单包含无效的文件路径。请使用 Still 生成的原始清单。"
        case .rollback(let message): "归档中断，部分文件需要按归档清单恢复：\(message)"
        }
    }
}

public enum ArchiveGrouping: String, Codable, Sendable, CaseIterable {
    case selection, rating
    public var title: String { self == .selection ? "按精选归档" : "按星级归档" }
}
public struct ArchiveOptions: Codable, Sendable {
    public var grouping: ArchiveGrouping
    public var keepPairsTogether: Bool
    public init(grouping: ArchiveGrouping = .selection, keepPairsTogether: Bool = true) {
        self.grouping = grouping; self.keepPairsTogether = keepPairsTogether
    }
}

public enum Archiver {
    public static func folder(for mark: PhotoMark) -> String {
        switch mark {
        case .selected: "01 精选"
        case .rejected: "90 淘汰（可恢复）"
        case .pending: "99 未选择"
        }
    }
    public static func folder(for session: ReviewSession, at index: Int, options: ArchiveOptions) -> String {
        let mark = session.mark(at: index)
        if mark == .rejected || options.grouping == .selection { return folder(for: mark) }
        let rating = session.rating(at: index)
        return rating == 0 ? "00 未标星" : String(format: "%02d %d星", rating, rating)
    }
    /// Move only, never delete; a unique run folder prevents overwriting an earlier archive.
    public static func archive(_ session: ReviewSession, to parent: URL, options: ArchiveOptions = ArchiveOptions()) throws -> ArchiveResult {
        guard !session.photos.isEmpty else { throw ArchiveError.empty }
        let fm = FileManager.default
        for file in session.photos.flatMap(\.files) {
            guard fm.fileExists(atPath: file.path) else { throw ArchiveError.missing(file.path) }
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let root = parent.appendingPathComponent("Still \(stamp) \(UUID().uuidString.prefix(6))", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var planned: [ArchiveEntry] = []
        var destinations = Set<String>()
        for (index, photo) in session.photos.enumerated() {
            let category = root.appendingPathComponent(folder(for: session, at: index, options: options))
            var suffix = 0
            var entries: [ArchiveEntry] = []
            repeat {
                var withinGroup = Set<String>()
                entries = photo.files.map { file in
                    let type = Scanner.rawExtensions.contains(file.pathExtension.lowercased()) ? "RAW" : (file.pathExtension.lowercased() == "xmp" ? "XMP" : (Scanner.imageExtensions.contains(file.pathExtension.lowercased()) ? "照片" : "关联文件"))
                    let dir = options.keepPairsTogether ? category : category.appendingPathComponent(type)
                    let stem = file.deletingPathExtension().lastPathComponent + (suffix == 0 ? "" : "-\(suffix)")
                    var name = stem + "." + file.pathExtension
                    var duplicate = 1
                    while !withinGroup.insert(dir.appendingPathComponent(name).path.lowercased()).inserted {
                        name = "\(stem)-副本\(duplicate).\(file.pathExtension)"; duplicate += 1
                    }
                    return ArchiveEntry(original: file, archived: dir.appendingPathComponent(name))
                }
                suffix += 1
            } while entries.contains { destinations.contains($0.archived.path.lowercased()) }
            for entry in entries { destinations.insert(entry.archived.path.lowercased()) }
            planned.append(contentsOf: entries)
        }
        let reviews = session.photos.indices.map {
            ArchivedReview(files: session.photos[$0].files, mark: session.mark(at: $0), rating: session.rating(at: $0))
        }
        let manifest = ArchiveManifest(createdAt: Date(), entries: planned, reviews: reviews)
        // Persist the full plan before the first move for recovery after power loss.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: root.appendingPathComponent("归档清单.json"), options: .atomic)
        var moved: [ArchiveEntry] = []
        do {
            for entry in planned {
                try fm.createDirectory(at: entry.archived.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: entry.original, to: entry.archived)
                moved.append(entry)
            }
        } catch {
            let originalError = error
            var rollbackErrors: [String] = []
            for entry in moved.reversed() {
                do { try fm.moveItem(at: entry.archived, to: entry.original) }
                catch { rollbackErrors.append(error.localizedDescription) }
            }
            if !rollbackErrors.isEmpty { throw ArchiveError.rollback(rollbackErrors.joined(separator: "\n")) }
            throw originalError
        }
        return ArchiveResult(directory: root, manifest: manifest)
    }
    public static func restore(manifestURL: URL) throws -> Int {
        let manifest = try JSONDecoder().decode(ArchiveManifest.self, from: Data(contentsOf: manifestURL))
        let fm = FileManager.default
        let root = manifestURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path + "/"
        var originals = Set<String>()
        var archivedPaths = Set<String>()
        for entry in manifest.entries {
            guard entry.original.isFileURL, entry.archived.isFileURL,
                  entry.archived.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root),
                  !entry.original.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root),
                  originals.insert(entry.original.standardizedFileURL.path.lowercased()).inserted,
                  archivedPaths.insert(entry.archived.standardizedFileURL.path.lowercased()).inserted else {
                throw ArchiveError.invalidManifest
            }
        }
        // Preflight all collisions before moving anything.
        let existing = manifest.entries.filter { fm.fileExists(atPath: $0.archived.path) }
        for entry in existing {
            guard !fm.fileExists(atPath: entry.original.path) else {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: entry.original.path])
            }
        }
        var restored: [ArchiveEntry] = []
        do {
            for entry in existing {
                try fm.createDirectory(at: entry.original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: entry.archived, to: entry.original)
                restored.append(entry)
            }
        } catch {
            var failures: [String] = []
            for entry in restored.reversed() {
                do { try fm.moveItem(at: entry.original, to: entry.archived) }
                catch { failures.append(error.localizedDescription) }
            }
            if !failures.isEmpty { throw ArchiveError.rollback(failures.joined(separator: "\n")) }
            throw error
        }
        return restored.count
    }
}
