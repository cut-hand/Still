import SwiftUI
import CullingCore

struct ArchiveView: View {
    @Bindable var store: ReviewStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var destination: URL?
    var body: some View {
        @Bindable var preferences = store.preferences
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Image(systemName: "archivebox").font(.system(size: 26)).foregroundStyle(stillAccent)
                    .frame(width: 54, height: 54).glassEffect(in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text("给照片一个去处").font(.system(size: 23, weight: .medium))
                    Text("将 \(store.photos.count) 组照片移动到新的归档目录。").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                Picker("分类方式", selection: $preferences.archiveGrouping) {
                    ForEach(ArchiveGrouping.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("RAW 与 JPG / HEIF / XMP 放在同一文件夹", isOn: $preferences.keepPairsTogether)
                    .font(.system(size: 12))
                Text(store.preferences.keepPairsTogether ? "同组的 RAW、JPG / HEIF / HEIC、XMP 保存在相同分类目录。" : "每个分类目录内再分为 RAW、照片、XMP。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                ForEach(categoryCounts, id: \.folder) { category in
                    HStack {
                        Image(systemName: category.folder.contains("淘汰") ? "xmark.circle.fill" : "folder")
                            .foregroundStyle(category.folder.contains("淘汰") ? PhotoMark.rejected.color : stillAccent).frame(width: 20)
                        Text(category.folder).font(.system(size: 12))
                        Spacer()
                        Text("\(category.count) 组").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }.padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("归档位置").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("选择位置…", action: chooseDestination)
                }
                Text(destination?.path ?? "请选择一个文件夹")
                    .font(.system(size: 11)).foregroundStyle(destination == nil ? .tertiary : .secondary)
                    .lineLimit(3).textSelection(.enabled)
            }
            Label {
                Text("淘汰照片会移到独立文件夹。所有原片保持原格式，RAW / JPG / HEIF / HEIC / XMP 一起归档；附带清单可将文件还原到原位置。")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
            } icon: { Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(stillAccent) }
            HStack {
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("移动并归档") { if let destination { store.archive(to: destination, options: store.preferences.archiveOptions) } }
                    .buttonStyle(.glassProminent).tint(stillAccent)
                    .disabled(destination == nil || store.photos.isEmpty || store.isComparing)
            }
        }.padding(30).frame(width: 540).preferredColorScheme(.dark)
    }
    private var categoryCounts: [(folder: String, count: Int)] {
        let grouped = Dictionary(grouping: store.photos.indices) {
            Archiver.folder(for: store.session, at: $0, options: store.preferences.archiveOptions)
        }
        return grouped.map { (folder: $0.key, count: $0.value.count) }.sorted { $0.folder < $1.folder }
    }
    private func chooseDestination() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "选择"; panel.title = "选择归档位置"
        panel.message = "选择归档位置。Still 会创建独立的归档文件夹。"
        if panel.runModal() == .OK { destination = panel.url }
    }
}
