import SwiftUI
import ImageIO
import CullingCore

actor ImagePipeline {
    static let shared = ImagePipeline()
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.totalCostLimit = 180 * 1024 * 1024 }
    func image(_ url: URL, size: Int) -> CGImage? {
        let key = "\(url.path)-\(size)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceThumbnailMaxPixelSize: size,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
    func metadata(_ url: URL) -> [MetadataRow] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [] }
        var result: [MetadataRow] = []
        if let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int {
            result.append(.init(label: "尺寸", value: "\(width) × \(height)"))
        }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        if let camera = tiff[kCGImagePropertyTIFFModel] as? String { result.append(.init(label: "相机", value: camera)) }
        if let lens = exif[kCGImagePropertyExifLensModel] as? String { result.append(.init(label: "镜头", value: lens)) }
        if let f = exif[kCGImagePropertyExifFNumber] as? Double { result.append(.init(label: "光圈", value: "ƒ/\(f.formatted())")) }
        if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            result.append(.init(label: "快门", value: t < 1 ? "1/\(Int((1/t).rounded())) s" : "\(t.formatted()) s"))
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { result.append(.init(label: "ISO", value: "\(iso)")) }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double { result.append(.init(label: "焦距", value: "\(focal.formatted()) mm")) }
        if let date = exif[kCGImagePropertyExifDateTimeOriginal] as? String { result.append(.init(label: "拍摄时间", value: date)) }
        return result
    }
}
struct MetadataRow: Sendable, Identifiable {
    var id: String { label }
    let label: String
    let value: String
}

struct PhotoImage: View {
    let photo: Photo
    var size = 1800
    @ViewState private var image: CGImage?
    @ViewState private var loaded = false
    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else if loaded {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                    Text("无法预览此格式").font(.caption)
                    Text(photo.preview.lastPathComponent).font(.caption2).foregroundStyle(.secondary)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: "\(photo.id)-\(size)") {
            loaded = false; image = nil
            let decoded = await ImagePipeline.shared.image(photo.preview, size: size)
            guard !Task.isCancelled else { return }
            image = decoded; loaded = true
        }
    }
}

@MainActor enum DemoLibrary {
    static func create() throws -> URL {
        let root = URL.applicationSupportDirectory.appendingPathComponent("Still/Demo-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<12 {
            let w = 1400, h = 1000
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            let warm = index % 3 == 0
            let sky = NSGradient(starting: NSColor(calibratedRed: warm ? 0.85 : 0.47, green: warm ? 0.71 : 0.68, blue: warm ? 0.55 : 0.72, alpha: 1), ending: NSColor(calibratedRed: 0.84, green: 0.85, blue: 0.77, alpha: 1))!
            sky.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
            let offset = CGFloat(index % 4) * 32
            NSColor(calibratedRed: 0.98, green: 0.90, blue: 0.68, alpha: 0.86).setFill()
            NSBezierPath(ovalIn: NSRect(x: 1000 - offset, y: 700, width: 100, height: 100)).fill()
            for layer in 0..<4 {
                let path = NSBezierPath(); path.move(to: .init(x: 0, y: 0))
                let base = CGFloat(520 - layer * 105)
                path.line(to: .init(x: 0, y: base))
                for step in 0...16 {
                    let x = CGFloat(step) * 100
                    let y = base + sin(CGFloat(step) * 0.67 + CGFloat(layer) * 1.7 + CGFloat(index) * 0.12) * CGFloat(130 - layer * 20) + cos(CGFloat(step) * 1.2) * 30
                    path.line(to: .init(x: x, y: y))
                }
                path.line(to: .init(x: w, y: 0)); path.close()
                NSColor(calibratedRed: 0.35 - Double(layer) * 0.065, green: 0.48 - Double(layer) * 0.075, blue: 0.43 - Double(layer) * 0.064, alpha: 1).setFill(); path.fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            if let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.93]) {
                try data.write(to: root.appendingPathComponent(String(format: "STILL_%04d.jpg", index + 1)))
            }
        }
        return root
    }
}
