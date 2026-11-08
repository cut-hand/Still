import SwiftUI
import CullingCore

struct ImportPreview: Identifiable {
    let id = UUID()
    let directory: URL
    let photos: [Photo]
    static func combination(for photo: Photo) -> String {
        photo.files.map { $0.pathExtension.uppercased() }.sorted().joined(separator: " + ")
    }
    var combinations: [(name: String, count: Int, example: String)] {
        Dictionary(grouping: photos) { photo in
            Self.combination(for: photo)
        }.map { (name: $0.key, count: $0.value.count, example: $0.value.first?.name ?? "") }.sorted { $0.name < $1.name }
    }
}
struct ImportPreviewView: View {
    @Bindable var store: ReviewStore
    let preview: ImportPreview
    @ViewState private var excluded: Set<String> = []
    private var selectedCount: Int { preview.photos.filter { !excluded.contains(ImportPreview.combination(for: $0)) }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("确认照片组合").font(.title2)
            Text(preview.directory.lastPathComponent).foregroundStyle(.secondary)
            Text("共 \(preview.photos.count) 组，\(preview.photos.flatMap(\.files).count) 个文件。相同文件名、不同扩展名的文件作为一组，共用标记和星级。")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(preview.combinations, id: \.name) { combination in
                        HStack {
                            Toggle("导入 \(combination.name)", isOn: Binding(get: { !excluded.contains(combination.name) }, set: { enabled in
                                if enabled { excluded.remove(combination.name) } else { excluded.insert(combination.name) }
                            })).labelsHidden().toggleStyle(.checkbox)

                            VStack(alignment: .leading) {
                                Text(combination.name + (combination.name.contains(" + ") ? "" : "（单格式）")).font(.headline)
                                Text("示例：\(combination.example)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(combination.count) 组")
                        }
                    }
                }
            }.frame(maxHeight: 300)
            Text("只导入包含可识别照片格式的组；同名的其他扩展名文件也会随组归档。所有子文件夹也会扫描；不同子文件夹的同名照片也合并成组。无可识别照片的文件组不导入。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("取消", role: .cancel) { store.pendingImport = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("确认导入（\(selectedCount) 组）") { store.confirmImport(excluding: excluded) }.keyboardShortcut(.defaultAction).disabled(selectedCount == 0)
            }
        }.padding(28).frame(width: 580).preferredColorScheme(.dark)
    }
}
