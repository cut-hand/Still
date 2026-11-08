import Foundation

public enum PhotoMark: String, CaseIterable, Codable, Sendable, Identifiable {
    case pending, selected, rejected
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .pending: "未选择"
        case .selected: "精选"
        case .rejected: "淘汰"
        }
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        // Preserve all former color picks when migrating v0.1 sessions.
        case "selected", "green", "yellow", "blue", "purple": self = .selected
        case "rejected": self = .rejected
        case "pending", "skipped": self = .pending
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown photo mark: \(value)")
        }
    }
}

public struct Photo: Identifiable, Codable, Sendable, Equatable {
    public var id: String { preview.path }
    public let preview: URL
    public let files: [URL]
    public var name: String { preview.deletingPathExtension().lastPathComponent }
    public var hasRAW: Bool { files.contains { Scanner.rawExtensions.contains($0.pathExtension.lowercased()) } }
    public var previewFormat: String {
        switch preview.pathExtension.lowercased() {
        case "hif", "heif": "HEIF"
        case "jpg", "jpeg": "JPG"
        default: preview.pathExtension.uppercased()
        }
    }
    public var formatSummary: String {
        hasRAW && !Scanner.rawExtensions.contains(preview.pathExtension.lowercased()) ? "\(previewFormat) + RAW" : previewFormat
    }
    public init(preview: URL, files: [URL]) { self.preview = preview; self.files = files }
}

public enum RemainderRule: String, CaseIterable, Codable, Sendable {
    case unselected, unchanged
    public var title: String {
        switch self {
        case .unselected: "未精选的照片全部淘汰"
        case .unchanged: "保留现有状态"
        }
    }
}
public enum SkipRule: String, CaseIterable, Codable, Sendable {
    case unchanged, rejected
    public var title: String {
        switch self {
        case .unchanged: "保持未选择"
        case .rejected: "标记为淘汰"
        }
    }
}

public struct ReviewSession: Codable, Sendable {
    public var photos: [Photo]
    public var marks: [String: PhotoMark] = [:]
    public var ratings: [String: Int] = [:]
    public var cursor = 0
    public var group: ClosedRange<Int>?
    public var completed = false
    public init(photos: [Photo]) { self.photos = photos }
    enum CodingKeys: String, CodingKey { case photos, marks, ratings, cursor, group, completed }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        photos = try values.decode([Photo].self, forKey: .photos)
        marks = try values.decodeIfPresent([String: PhotoMark].self, forKey: .marks) ?? [:]
        ratings = (try values.decodeIfPresent([String: Int].self, forKey: .ratings) ?? [:]).filter { (1...5).contains($0.value) }
        cursor = min(max(0, try values.decodeIfPresent(Int.self, forKey: .cursor) ?? 0), max(0, photos.count - 1))
        group = nil // Resume on the current photo; do not silently commit an unfinished group.
        completed = try values.decodeIfPresent(Bool.self, forKey: .completed) ?? false
    }
    public func rating(at index: Int) -> Int {
        guard photos.indices.contains(index) else { return 0 }
        return min(5, max(0, ratings[photos[index].id] ?? 0))
    }
    public mutating func setRating(_ rating: Int, at index: Int) {
        guard photos.indices.contains(index) else { return }
        let bounded = min(5, max(0, rating))
        if bounded == 0 { ratings.removeValue(forKey: photos[index].id) }
        else { ratings[photos[index].id] = bounded }
    }
    public var groupIndices: [Int] { group.map { Array($0) } ?? [] }
    public func mark(at index: Int) -> PhotoMark {
        guard photos.indices.contains(index) else { return .pending }
        return marks[photos[index].id] ?? .pending
    }
    public mutating func setMark(_ mark: PhotoMark, at index: Int) {
        guard photos.indices.contains(index) else { return }
        marks[photos[index].id] = mark
    }
    public mutating func expand(_ direction: Int) {
        guard !photos.isEmpty else { return }
        let bounds = group ?? cursor...cursor
        group = direction < 0 ? max(0, bounds.lowerBound - 1)...bounds.upperBound : bounds.lowerBound...min(photos.count - 1, bounds.upperBound + 1)
        completed = false
    }
    public mutating func shrink(_ direction: Int) {
        guard let bounds = group, bounds.count > 1 else { return }
        group = direction < 0 ? (bounds.lowerBound + 1)...bounds.upperBound : bounds.lowerBound...(bounds.upperBound - 1)
        if let group { cursor = min(group.upperBound, max(group.lowerBound, cursor)) }
    }
    public mutating func finishGroup(rule: RemainderRule) {
        guard let bounds = group else { return }
        for i in bounds {
            let mark = mark(at: i)
            if rule == .unselected && mark != .selected {
                setMark(.rejected, at: i)
            }
        }
        cursor = min(bounds.upperBound + 1, max(0, photos.count - 1))
        completed = bounds.upperBound == photos.count - 1
        group = nil
    }
    public mutating func next(skip: SkipRule) {
        guard !photos.isEmpty, group == nil else { return }
        if mark(at: cursor) == .pending {
            if skip == .rejected { setMark(.rejected, at: cursor) }
        }
        if cursor + 1 < photos.count { cursor += 1 } else { completed = true }
    }
    public mutating func previous() {
        guard group == nil else { return }
        cursor = max(0, cursor - 1); completed = false
    }
    public func count(_ mark: PhotoMark) -> Int { photos.indices.filter { self.mark(at: $0) == mark }.count }
}
