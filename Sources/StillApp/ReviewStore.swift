import SwiftUI
import CullingCore
import CryptoKit

@MainActor @Observable final class ReviewStore {
    var session = ReviewSession(photos: [])
    var filmstripRevision = UUID()
    var directory: URL?
    var busy = false
    var error: String?
    var notice: String?
    var showArchive = false
    var pendingImport: ImportPreview?
    var library: [Photo] = []
    var hiddenCombinations: Set<String> = []
    private var retainedMarks: [String: PhotoMark] = [:]
    private var retainedRatings: [String: Int] = [:]
    var combinations: [(name: String, count: Int, example: String)] {
        ImportPreview(directory: directory ?? URL(fileURLWithPath: "/"), photos: library).combinations
    }
    private func retainDecisions() {
        for photo in session.photos {
            retainedMarks[photo.id] = session.marks[photo.id] ?? .pending
            retainedRatings[photo.id] = session.ratings[photo.id] ?? 0
        }
    }
    func toggleCombination(_ name: String, enabled: Bool) {
        guard !busy else { return }
        retainDecisions()
        if enabled { hiddenCombinations.remove(name) } else { hiddenCombinations.insert(name) }
        let currentID = session.photos.indices.contains(session.cursor) ? session.photos[session.cursor].id : nil
        var filtered = ReviewSession(photos: library.filter { !hiddenCombinations.contains(ImportPreview.combination(for: $0)) })
        filtered.marks = retainedMarks; filtered.ratings = retainedRatings
        if let currentID, let cursor = filtered.photos.firstIndex(where: { $0.id == currentID }) { filtered.cursor = cursor }
        session = filtered; filmstripRevision = UUID(); history = []; sharedZoom = 1; sharedPan = .zero
        scheduleSave()
    }
    var syncZoom = true
    var syncPan = true
    var sharedPan = CGSize.zero
    var sharedZoom: CGFloat = 1
    var showInfo = true
    var sidebarVisibility: NavigationSplitViewVisibility = .all
    var demo = false
    var lastArchive: URL?
    let preferences = Preferences()
    private var history: [ReviewSession] = []
    private var saveTask: Task<Void, Never>?
    private var monitor: Any?
    @ObservationIgnored weak var reviewWindow: NSWindow?
    var photos: [Photo] { session.photos }
    var isComparing: Bool { session.group != nil }
    var indices: [Int] { isComparing ? session.groupIndices : (photos.isEmpty ? [] : [session.cursor]) }
    var picked: Int { photos.indices.filter { session.mark(at: $0) == .selected }.count }
    var processed: Int { photos.count - session.count(.pending) }
    var storageURL: URL? {
        guard let directory else { return nil }
        return Self.sessionURL(for: directory)
    }
    private static func sessionURL(for directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(directory.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return URL.applicationSupportDirectory.appendingPathComponent("Still/Sessions/\(digest).json")
    }
    func startKeyboard() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKeyboard(event) ?? false }
            return handled ? nil : event
        }
    }
    private func handleKeyboard(_ event: NSEvent) -> Bool {
        if preferences.recording != nil { preferences.record(event); return true }
        guard NSApp.keyWindow === reviewWindow, reviewWindow?.attachedSheet == nil, !busy, !showArchive,
              !(NSApp.keyWindow?.firstResponder is NSTextView),
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        if event.keyCode == 53, isComparing {
            change { $0.group = nil }; return true
        }
        guard let key = Preferences.normalizedKey(event),
              let action = ReviewAction.allCases.first(where: { preferences.key(for: $0) == key }) else { return false }
        if !event.isARepeat { perform(action) }
        return true
    }
    func openFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "打开"; panel.title = "打开照片文件夹"
        panel.message = "选择照片所在文件夹；同名 RAW 与 JPG / HEIF / HEIC（含 HIF）自动配对，并关联 XMP。"
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }
    func load(_ url: URL) {
        flushSave(); busy = true; notice = nil
        Task {
            do {
                let scanned = try await Task.detached(priority: .userInitiated) { try Scanner.scan(url) }.value
                pendingImport = ImportPreview(directory: url, photos: scanned)
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func confirmImport(excluding combinations: Set<String> = []) {
        guard let pendingImport else { return }
        let saved = Self.sessionURL(for: pendingImport.directory)
        let selected = pendingImport.photos.filter { !combinations.contains(ImportPreview.combination(for: $0)) }
        guard !selected.isEmpty else { return }
        var imported = ReviewSession(photos: pendingImport.photos)
        if FileManager.default.fileExists(atPath: saved.path) {
            do { imported = try SessionStorage.load(from: saved, photos: pendingImport.photos) }
            catch { notice = "先前进度无法读取，已重新载入照片。" }
        }
        directory = pendingImport.directory; demo = false; history = []; session = imported
        library = pendingImport.photos; retainedMarks = imported.marks; retainedRatings = imported.ratings
        hiddenCombinations = combinations
        toggleCombination("", enabled: true)
        sharedZoom = 1; sharedPan = .zero; self.pendingImport = nil
    }
    func change(_ mutation: (inout ReviewSession) -> Void) {
        guard !busy, !photos.isEmpty else { return }
        history.append(session)
        if history.count > 100 { history.removeFirst() }
        mutation(&session); scheduleSave()
    }
    func perform(_ action: ReviewAction) {
        if let rating = action.rating { rate(rating); return }
        switch action {
        case .previous: change { $0.previous() }
        case .next:
            if isComparing { finishGroup() } else { change { $0.next(skip: preferences.skip) } }
        case .shrinkLeft: change { $0.shrink(-1) }
        case .shrinkRight: change { $0.shrink(1) }
        case .expandLeft: change { $0.expand(-1) }
        case .expandRight: change { $0.expand(1) }
        case .finishGroup:
            if isComparing { finishGroup() } else { change { $0.next(skip: preferences.skip) } }
        case .mark: mark(session.cursor, as: .selected)
        case .reject: mark(session.cursor, as: .rejected)
        case .clear: change { $0.setMark(.pending, at: $0.cursor) }
        case .toggleInfo: showInfo.toggle()
        case .toggleSidebar:
            withAnimation { sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly }
        case .star1, .star2, .star3, .star4, .star5, .clearRating, .clearRatingAccent: break
        }
    }
    func rate(_ rating: Int) { change { $0.setRating(rating, at: $0.cursor) } }
    func focus(_ index: Int) {
        guard photos.indices.contains(index), !busy else { return }
        session.cursor = index; scheduleSave()
    }
    func finishGroup() { change { $0.finishGroup(rule: preferences.remainder) } }
    func mark(_ index: Int, as mark: PhotoMark = .selected) {
        let value = mark
        change {
            let toggled = $0.mark(at: index) == value ? PhotoMark.pending : value
            $0.setMark(toggled, at: index)
            $0.cursor = index
            if $0.group == nil, preferences.autoAdvance { $0.next(skip: .unchanged) }
        }
    }
    func navigate(_ index: Int) {
        guard !isComparing else { return }
        change { $0.cursor = index; $0.completed = false }
    }
    func undo() {
        guard !busy, let old = history.popLast() else { return }
        session = old; scheduleSave()
    }
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            self?.flushSave()
        }
    }
    func flushSave() {
        saveTask?.cancel()
        guard !demo, let storageURL, !library.isEmpty else { return }
        retainDecisions()
        var full = ReviewSession(photos: library)
        full.marks = retainedMarks; full.ratings = retainedRatings
        if session.photos.indices.contains(session.cursor), let cursor = library.firstIndex(where: { $0.id == session.photos[session.cursor].id }) { full.cursor = cursor }
        do { try SessionStorage.save(full, to: storageURL) }
        catch { self.error = "进度保存失败：\(error.localizedDescription)" }
    }
    func archive(to url: URL, options: ArchiveOptions) {
        guard !busy, !isComparing else { return }
        let snapshot = session
        busy = true; showArchive = false; flushSave()
        Task {
            do {
                let result = try await Task.detached { try Archiver.archive(snapshot, to: url, options: options) }.value
                lastArchive = result.directory
                notice = "已归档 \(snapshot.photos.count) 组照片。淘汰照片已保存在独立文件夹，可通过归档清单还原。"
                let moved = Set(snapshot.photos.map(\.id))
                library.removeAll { moved.contains($0.id) }
                session = ReviewSession(photos: []); history = []
                if library.isEmpty, let storageURL { try? FileManager.default.removeItem(at: storageURL) } else { flushSave() }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func restoreArchive() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.message = "选择 Still 生成的「归档清单.json」，将照片移回原位置。"
        panel.allowedContentTypes = [.json]; panel.prompt = "还原"; panel.title = "选择归档清单"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true
        Task {
            do {
                let count = try await Task.detached { try Archiver.restore(manifestURL: url) }.value
                notice = "已还原 \(count) 个文件。可重新打开原照片文件夹。"
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    func loadDemo() {
        guard !busy else { return }
        do {
            let dir = try DemoLibrary.create()
            flushSave(); directory = dir; demo = true; history = []
            session = ReviewSession(photos: try Scanner.scan(dir))
            filmstripRevision = UUID()
            library = session.photos; hiddenCombinations = []; retainedMarks = [:]; retainedRatings = [:]
            notice = "演示图库 · 这些图像由应用生成，可以放心体验。"
        } catch { self.error = error.localizedDescription }
    }
}
