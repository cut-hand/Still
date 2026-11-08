import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import CullingCore

@Test(arguments: ["HEIF", "heic", "HIF"])
func heifPairsPreviewAndArchiveWithRAW(fileExtension: String) throws {
    let dir = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let rendered = source.appendingPathComponent("BURST_001.\(fileExtension)")
    let raw = source.appendingPathComponent("burst_001.ARW")
    let sidecar = source.appendingPathComponent("BURST_001.xmp")
    // Encode a real HEIF-family image, so extension recognition and ImageIO
    // thumbnail decoding are exercised rather than just matching a filename.
    let context = try #require(CGContext(data: nil, width: 128, height: 96, bitsPerComponent: 8,
                                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 128, height: 96))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(rendered as CFURL, UTType.heic.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    try Data("raw bytes".utf8).write(to: raw)
    try Data("sidecar bytes".utf8).write(to: sidecar)

    let scanned = try Scanner.scan(source)
    let photo = try #require(scanned.first)
    #expect(scanned.count == 1)
    #expect(photo.preview.lastPathComponent == rendered.lastPathComponent)
    #expect(photo.hasRAW)
    #expect(photo.files.count == 3)
    #expect(photo.formatSummary == (fileExtension == "heic" ? "HEIC + RAW" : "HEIF + RAW"))
    let imageSource = try #require(CGImageSourceCreateWithURL(photo.preview as CFURL, nil))
    let thumbnail = try #require(CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 64
    ] as CFDictionary))
    #expect(thumbnail.width == 64)

    var session = ReviewSession(photos: scanned)
    session.setMark(.selected, at: 0)
    session.setRating(4, at: 0)
    let original = try Dictionary(uniqueKeysWithValues: photo.files.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    for grouping in ArchiveGrouping.allCases {
        for together in [true, false] {
            let result = try Archiver.archive(session, to: dir.appendingPathComponent("archive"),
                                              options: ArchiveOptions(grouping: grouping, keepPairsTogether: together))
            let renderedEntry = try #require(result.manifest.entries.first { $0.original.lastPathComponent == rendered.lastPathComponent })
            let rawEntry = try #require(result.manifest.entries.first { $0.original.lastPathComponent == raw.lastPathComponent })
            #expect(renderedEntry.archived.pathExtension == fileExtension)
            #expect(renderedEntry.archived.path.contains(grouping == .selection ? "01 精选" : "04 4星"))
            #expect((renderedEntry.archived.deletingLastPathComponent() == rawEntry.archived.deletingLastPathComponent()) == together)
            for entry in result.manifest.entries {
                #expect(try Data(contentsOf: entry.archived) == original[entry.original.lastPathComponent])
            }
            #expect(try Archiver.restore(manifestURL: result.directory.appendingPathComponent("归档清单.json")) == 3)
            for (name, bytes) in original { #expect(try Data(contentsOf: source.appendingPathComponent(name)) == bytes) }
        }
    }
}

private func photos(_ count: Int) -> [Photo] {
    (0..<count).map { i in let url = URL(fileURLWithPath: "/tmp/photo-\(i).jpg"); return Photo(preview: url, files: [url]) }
}

@Test func expandsBothDirectionsAndAdvancesBeyondGroup() {
    var session = ReviewSession(photos: photos(8)); session.cursor = 3
    session.expand(-1); session.expand(-1); session.expand(1)
    #expect(session.group == 1...4)
    session.setMark(.selected, at: 2)
    session.finishGroup(rule: .unselected)
    #expect(session.cursor == 5)
    #expect(session.group == nil)
    #expect(session.mark(at: 2) == .selected)
    #expect([1, 3, 4].allSatisfy { session.mark(at: $0) == .rejected })
    #expect(session.mark(at: 0) == .pending)
    #expect(session.mark(at: 5) == .pending)
}
@Test func noPicksRejectsWholeGroupIncludingFinalPhoto() {
    var session = ReviewSession(photos: photos(3))
    session.expand(1); session.expand(1); session.expand(1)
    #expect(session.group == 0...2)
    session.finishGroup(rule: .unselected)
    #expect(session.count(.rejected) == 3)
    #expect(session.cursor == 2)
    #expect(session.completed)
}
@Test func remainderPreferencesPreserveSelectedPhotos() {
    var session = ReviewSession(photos: photos(3))
    session.setMark(.selected, at: 0); session.expand(1)
    session.finishGroup(rule: .unselected)
    #expect(session.mark(at: 0) == .selected)
    #expect(session.mark(at: 1) == .rejected)
    session.expand(1)
    session.finishGroup(rule: .unchanged)
    #expect(session.mark(at: 2) == .pending)
}
@Test func skipOnlyChangesPendingAndBoundariesAreSafe() {
    var session = ReviewSession(photos: photos(3))
    session.previous(); #expect(session.cursor == 0)
    session.next(skip: .unchanged); #expect(session.mark(at: 0) == .pending)
    session.setMark(.selected, at: 1)
    session.next(skip: .rejected); #expect(session.mark(at: 1) == .selected)
    session.next(skip: .rejected); #expect(session.mark(at: 2) == .rejected)
    #expect(session.completed)
    var empty = ReviewSession(photos: [])
    empty.expand(-1); empty.next(skip: .rejected)
    #expect(empty.group == nil)
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StillTests-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}
@Test func scannerPairsRAWJPEGAndSidecarAndIgnoresNestedArchives() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    for name in ["DSC_10.JPG", "dsc_10.ARW", "DSC_10.xmp", "DSC_2.jpg", "alone.xmp", "notes.txt", "rawonly.dng"] {
        try Data(name.utf8).write(to: dir.appendingPathComponent(name))
    }
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("archive.jpg"), withIntermediateDirectories: true)
    let result = try Scanner.scan(dir)
    #expect(result.count == 3)
    #expect(result[0].name == "DSC_2")
    #expect(result[1].files.count == 3)
    #expect(result[1].preview.pathExtension == "JPG")
    #expect(result[1].hasRAW)
    #expect(result[2].hasRAW)
}
@Test func archiveAndRestorePreserveEveryByteAndRejectCollisions() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source"), target = dir.appendingPathComponent("archive")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    let originals = ["a.jpg", "a.arw", "a.xmp", "b.jpg"]
    for name in originals { try Data("original bytes \(name)".utf8).write(to: source.appendingPathComponent(name)) }
    var session = ReviewSession(photos: try Scanner.scan(source))
    session.setMark(.selected, at: 0); session.setMark(.rejected, at: 1)
    let result = try Archiver.archive(session, to: target)
    #expect(result.manifest.entries.count == 4)
    for entry in result.manifest.entries {
        #expect(!FileManager.default.fileExists(atPath: entry.original.path))
        #expect(try Data(contentsOf: entry.archived) == Data("original bytes \(entry.original.lastPathComponent)".utf8))
    }
    #expect(result.manifest.entries.last!.archived.path.contains("90 淘汰"))
    let manifest = result.directory.appendingPathComponent("归档清单.json")
    let collision = source.appendingPathComponent("a.jpg")
    try Data("new photo".utf8).write(to: collision)
    #expect(throws: (any Error).self) { try Archiver.restore(manifestURL: manifest) }
    #expect(try Data(contentsOf: collision) == Data("new photo".utf8))
    #expect(result.manifest.entries.allSatisfy { FileManager.default.fileExists(atPath: $0.archived.path) })
    try FileManager.default.removeItem(at: collision)
    #expect(try Archiver.restore(manifestURL: manifest) == 4)
    for name in originals {
        #expect(try Data(contentsOf: source.appendingPathComponent(name)) == Data("original bytes \(name)".utf8))
    }
}
@Test func missingSourcePreventsAnyMove() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let existing = dir.appendingPathComponent("exists.jpg")
    try Data("safe".utf8).write(to: existing)
    let missing = dir.appendingPathComponent("missing.raw")
    let session = ReviewSession(photos: [Photo(preview: existing, files: [existing, missing])])
    #expect(throws: (any Error).self) { try Archiver.archive(session, to: dir.appendingPathComponent("archive")) }
    #expect(try Data(contentsOf: existing) == Data("safe".utf8))
}
@Test func sessionReloadMatchesStableFileIDsAfterFolderChanges() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("session.json")
    let original = photos(3)
    var session = ReviewSession(photos: original); session.cursor = 1; session.setMark(.selected, at: 1); session.setRating(4, at: 1)
    try SessionStorage.save(session, to: url)
    let loaded = try SessionStorage.load(from: url, photos: [original[1], original[2]])
    #expect(loaded.cursor == 0)
    #expect(loaded.mark(at: 0) == .selected)
    #expect(loaded.marks.count == 1)
    #expect(loaded.rating(at: 0) == 4)
}

@Test func duplicateNamesFromDifferentSourcesAreNeverOverwritten() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    var items: [Photo] = []
    for index in 0..<2 {
        let folder = dir.appendingPathComponent("source-\(index)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("same.jpg")
        try Data("photo-\(index)".utf8).write(to: file)
        items.append(Photo(preview: file, files: [file]))
    }
    let result = try Archiver.archive(ReviewSession(photos: items), to: dir.appendingPathComponent("target"))
    #expect(Set(result.manifest.entries.map(\.archived)).count == 2)
    for (index, entry) in result.manifest.entries.enumerated() {
        #expect(try Data(contentsOf: entry.archived) == Data("photo-\(index)".utf8))
    }
    #expect(try Archiver.restore(manifestURL: result.directory.appendingPathComponent("归档清单.json")) == 2)
}
@Test func restoreRefusesFilesOutsideItsArchive() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let unrelated = dir.appendingPathComponent("outside.jpg")
    try Data("untouched".utf8).write(to: unrelated)
    let archive = dir.appendingPathComponent("archive")
    try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
    let url = archive.appendingPathComponent("归档清单.json")
    let forged = ArchiveManifest(createdAt: Date(), entries: [ArchiveEntry(original: dir.appendingPathComponent("moved.jpg"), archived: unrelated)])
    try JSONEncoder().encode(forged).write(to: url)
    #expect(throws: (any Error).self) { try Archiver.restore(manifestURL: url) }
    #expect(try Data(contentsOf: unrelated) == Data("untouched".utf8))
}

@Test func starRatingsAreIndependentAndDoNotAdvance() throws {
    var session = ReviewSession(photos: photos(3))
    session.setMark(.selected, at: 0)
    for rating in 1...5 {
        session.setRating(rating, at: 0)
        #expect(session.rating(at: 0) == rating)
        #expect(session.cursor == 0)
        #expect(session.mark(at: 0) == .selected)
    }
    session.setRating(0, at: 0)
    #expect(session.rating(at: 0) == 0)
    #expect(session.mark(at: 0) == .selected)
    session.setRating(5, at: 1)
    session.expand(1); session.finishGroup(rule: .unselected)
    #expect(session.mark(at: 1) == .rejected)
    #expect(session.rating(at: 1) == 5)
    let restored = try JSONDecoder().decode(ReviewSession.self, from: JSONEncoder().encode(session))
    #expect(restored.rating(at: 1) == 5)
}
@Test func oldSessionsMigrateWithoutLosingColorPicks() throws {
    let items = photos(7)
    let session = ReviewSession(photos: items)
    let data = try JSONEncoder().encode(session)
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let legacy = ["green", "yellow", "blue", "purple", "rejected", "skipped", "pending"]
    json["marks"] = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, legacy[$0.offset]) })
    json.removeValue(forKey: "ratings")
    let restored = try JSONDecoder().decode(ReviewSession.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(restored.count(.selected) == 4)
    #expect(restored.count(.rejected) == 1)
    #expect(restored.count(.pending) == 2)
    #expect(restored.ratings.isEmpty)
}
@Test func archiveSupportsBothClassificationAndFolderLayouts() throws {
    for grouping in ArchiveGrouping.allCases {
        for together in [true, false] {
            let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            let source = dir.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            for name in ["a.jpg", "a.arw", "a.xmp", "b.jpg", "c.jpg"] {
                try Data("bytes \(name)".utf8).write(to: source.appendingPathComponent(name))
            }
            var session = ReviewSession(photos: try Scanner.scan(source))
            session.setMark(.selected, at: 0); session.setRating(5, at: 0)
            session.setMark(.rejected, at: 1); session.setRating(4, at: 1)
            let options = ArchiveOptions(grouping: grouping, keepPairsTogether: together)
            let result = try Archiver.archive(session, to: dir.appendingPathComponent("archive"), options: options)
            let pickedFiles = result.manifest.entries.filter { $0.original.deletingPathExtension().lastPathComponent == "a" }
            let pickedFolder = grouping == .rating ? "05 5星" : "01 精选"
            #expect(pickedFiles.allSatisfy { $0.archived.path.contains(pickedFolder) })
            #expect(Set(pickedFiles.map { $0.archived.deletingLastPathComponent() }).count == (together ? 1 : 3))
            let rejected = try #require(result.manifest.entries.first { $0.original.lastPathComponent == "b.jpg" })
            #expect(rejected.archived.path.contains("90 淘汰"))
            let unmarked = try #require(result.manifest.entries.first { $0.original.lastPathComponent == "c.jpg" })
            #expect(unmarked.archived.path.contains(grouping == .rating ? "00 未标星" : "99 未选择"))
            #expect(result.manifest.reviews?.first?.rating == 5)
            for entry in result.manifest.entries {
                #expect(try Data(contentsOf: entry.archived) == Data("bytes \(entry.original.lastPathComponent)".utf8))
            }
            #expect(try Archiver.restore(manifestURL: result.directory.appendingPathComponent("归档清单.json")) == 5)
        }
    }
}

@Test func previewChangesPreserveMarksAndStars() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let raw = dir.appendingPathComponent("same.ARW"), hif = dir.appendingPathComponent("same.HIF")
    let prior = Photo(preview: raw, files: [raw])
    var session = ReviewSession(photos: [prior]); session.setMark(.selected, at: 0); session.setRating(5, at: 0)
    let saved = dir.appendingPathComponent("session.json"); try SessionStorage.save(session, to: saved)
    let changed = Photo(preview: hif, files: [hif, raw])
    let loaded = try SessionStorage.load(from: saved, photos: [changed])
    #expect(loaded.mark(at: 0) == .selected)
    #expect(loaded.rating(at: 0) == 5)
}
@Test func sameNamesIncludeAllCompanionExtensions() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    for file in ["shot.HIF", "shot.ARW", "shot.json", "shot.wav", "unrelated.txt"] {
        try Data(file.utf8).write(to: dir.appendingPathComponent(file))
    }
    let scanned = try Scanner.scan(dir)
    #expect(scanned.count == 1)
    #expect(scanned.first?.files.count == 4)
}

@Test func shrinkGroupClampsCursorWithoutChangingDecisions() {
    var session = ReviewSession(photos: photos(5)); session.cursor = 2
    session.expand(-1); session.expand(1)
    session.setMark(.selected, at: 1); session.cursor = 1
    session.shrink(-1)
    #expect(session.group == 2...3)
    #expect(session.cursor == 2)
    #expect(session.mark(at: 1) == .selected)
    session.shrink(1); session.shrink(1)
    #expect(session.group == 2...2)
}
@Test func recursiveScanMergesSameNamesAcrossFolders() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    for child in ["one", "two/nested"] {
        let folder = dir.appendingPathComponent(child)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["same.jpg", "same.ARW"] { try Data(name.utf8).write(to: folder.appendingPathComponent(name)) }
    }
    let scanned = try Scanner.scan(dir)
    #expect(scanned.count == 1)
    #expect(scanned.first?.files.count == 4)
    let result = try Archiver.archive(ReviewSession(photos: scanned), to: dir.appendingPathComponent("archive"))
    let names = Set(result.manifest.entries.map { $0.archived.lastPathComponent })
    #expect(names == Set(["same.jpg", "same.ARW", "same-副本1.jpg", "same-副本1.ARW"]))
    #expect(try Archiver.restore(manifestURL: result.directory.appendingPathComponent("归档清单.json")) == 4)
}

@Test func splitHEIFAndRAWDirectoriesFormOneGroup() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    for name in ["heif/DSC_001.HIF", "raw/nested/dsc_001.ARW", "other/DSC_002.JPG"] {
        let file = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(name.utf8).write(to: file)
    }
    let scanned = try Scanner.scan(dir)
    #expect(scanned.count == 2)
    let pair = try #require(scanned.first { $0.name.lowercased() == "dsc_001" })
    #expect(pair.files.count == 2)
    #expect(pair.formatSummary == "HEIF + RAW")
}

@Test func unpairedSingleFormatsAreAlwaysIncluded() throws {
    let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    for name in ["alone.JPG", "heifOnly.HEIF", "rawOnly.ARW", "pair.HIF", "pair.DNG"] {
        try Data(name.utf8).write(to: dir.appendingPathComponent(name))
    }
    let scanned = try Scanner.scan(dir)
    #expect(scanned.count == 4)
    #expect(scanned.filter { $0.files.count == 1 }.count == 3)
    #expect(scanned.first { $0.name == "pair" }?.files.count == 2)
}
