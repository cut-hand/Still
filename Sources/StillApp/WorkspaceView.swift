import SwiftUI
import CullingCore

struct WorkspaceView: View {
    @Bindable var store: ReviewStore
    var body: some View {
        HStack(spacing: 0) {
            if store.sidebarVisibility != .detailOnly {
                sidebar.frame(width: 230).frame(maxHeight: .infinity).background(.regularMaterial).clipped()
                Divider()
            }
            VStack(spacing: 0) {
                if store.photos.isEmpty {
                    if store.library.isEmpty { welcome } else { ContentUnavailableView("没有选中的组合", systemImage: "line.3.horizontal.decrease", description: Text("在左侧勾选要显示的照片组合。")) }
                } else { review }

            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(canvasColor).clipped()
                .navigationTitle(store.directory?.lastPathComponent ?? "留住值得的瞬间")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { compactControls }
                        .sharedBackgroundVisibility(.hidden)
                }
        }
        .frame(minWidth: 1050, minHeight: 700)
        .background(WindowReader { store.reviewWindow = $0 }.frame(width: 0, height: 0))
        .overlay { if store.busy { ZStack { Color.black.opacity(0.35); ProgressView("正在处理照片…").padding(28).glassEffect(in: .rect(cornerRadius: 20)) } } }
        .sheet(item: $store.pendingImport) { preview in ImportPreviewView(store: store, preview: preview) }
        .sheet(isPresented: $store.showArchive) { ArchiveView(store: store) }
        .alert("操作未完成", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("好", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private var compactControls: some View {
        HStack(spacing: 10) {
            Button { store.perform(.toggleSidebar) } label: { Image(systemName: "sidebar.left") }
                .help("显示 / 隐藏左侧边栏")
            if store.isComparing {
                Toggle(isOn: $store.syncZoom) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("倍率关联").onChange(of: store.syncZoom) { _, enabled in if enabled { store.sharedZoom = 1 } }
                Toggle(isOn: $store.syncPan) { Image(systemName: "arrow.up.and.down.and.arrow.left.and.right") }.help("移动关联")
            }
            Button { store.showArchive = true } label: { Image(systemName: "archivebox") }
                .help("归档照片 · ⌘↩").disabled(store.photos.isEmpty || store.isComparing || store.busy)
            Button { store.showInfo.toggle() } label: { Image(systemName: "sidebar.right") }
                .help("显示 / 隐藏照片信息").disabled(store.photos.isEmpty)
        }.font(.system(size: 13)).buttonStyle(.plain).controlSize(.mini).labelsHidden().padding(.horizontal, 4)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Still").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-1)
                    Text("留选 · 照片筛选").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, 12)
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel("本次选片")
                stat("全部照片", count: store.photos.count, symbol: "photo.on.rectangle", color: .secondary)
                ForEach([PhotoMark.selected, .rejected]) { mark in
                    stat(mark.title, count: store.session.count(mark), symbol: mark.symbol, color: mark.color)
                }
            }
            Spacer(minLength: 8)
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("照片组合")
                ForEach(store.combinations, id: \.name) { combination in
                    Toggle(isOn: Binding(get: { !store.hiddenCombinations.contains(combination.name) }, set: { store.toggleCombination(combination.name, enabled: $0) })) {
                        Text("\(combination.name) · \(combination.count) 组").font(.caption).lineLimit(2)
                    }.toggleStyle(.checkbox).disabled(store.busy)
                }
                Divider()
                Text(store.isComparing ? "连续选片 · \(store.indices.count) 张比较中" : "单张浏览").font(.caption).foregroundStyle(stillAccent)
                if !store.photos.isEmpty { Text("\(store.session.cursor + 1) / \(store.photos.count)").font(.caption.monospacedDigit()) }
                if store.isComparing {
                    Text("点击照片精选，再次点击取消\n⇧W / ⇧S 缩减左 / 右范围").font(.caption2).foregroundStyle(.secondary)
                    Text(store.preferences.remainder.title).font(.caption2).foregroundStyle(.secondary)
                }
                if store.session.completed { Text("已到最后一张").font(.caption).foregroundStyle(stillAccent) }
                if let notice = store.notice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                    if let archive = store.lastArchive { Button("在 Finder 中查看") { NSWorkspace.shared.open(archive) } }
                }
            }.padding(.vertical, 4)
            }.frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("筛选进度").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(store.photos.isEmpty ? "—" : "\(Int(Double(store.processed) / Double(store.photos.count) * 100))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(stillAccent)
                }
                ProgressView(value: Double(store.processed), total: Double(max(1, store.photos.count))).tint(stillAccent)
                Text("\(store.processed) / \(store.photos.count) 组已处理").font(.caption2).foregroundStyle(.tertiary)
            }
        }.padding(.horizontal, 20).padding(.bottom, 20)
    }
    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).tracking(1.5)
    }
    private func stat(_ title: String, count: Int, symbol: String, color: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(color).frame(width: 17)
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text("\(count)").font(.system(size: 12, design: .monospaced)).foregroundStyle(count == 0 ? .tertiary : .secondary)
        }.padding(.horizontal, 10)
    }
    private var welcome: some View {
        HStack(spacing: 55) {
            VStack(alignment: .leading, spacing: 24) {
                Text("A LITTLE LESS. A LITTLE BETTER.").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2.5).foregroundStyle(stillAccent)
                Text("把好照片，\n留在一起。").font(.system(size: 47, weight: .regular, design: .serif)).lineSpacing(9)
                Text("让相似的瞬间并排呈现。\n选中喜欢的，把其余的交给 Still。").font(.system(size: 14)).lineSpacing(8).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    Button(action: store.openFolder) { Label("打开照片文件夹", systemImage: "folder.badge.plus").padding(.horizontal, 14).padding(.vertical, 8) }
                        .buttonStyle(.glassProminent).tint(stillAccent)
                    Button("先体验演示图库", action: store.loadDemo).buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 9)
                HStack(spacing: 8) {
                    Text("RAW + JPG / HEIF 自动配对"); Text("·"); Text("全程本地处理")
                }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 24)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.16, green: 0.23, blue: 0.20))
                    .frame(width: 220, height: 290).rotationEffect(.degrees(-12)).offset(x: -25, y: 8)
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)).frame(width: 220, height: 290).rotationEffect(.degrees(-12)).offset(x: -25, y: 8) }
                VStack(spacing: 0) {
                    ZStack {
                        LinearGradient(colors: [Color(red: 0.62, green: 0.72, blue: 0.66), Color(red: 0.30, green: 0.46, blue: 0.37)], startPoint: .top, endPoint: .bottom)
                        Image(systemName: "mountain.2.fill").font(.system(size: 100)).foregroundStyle(Color(red: 0.12, green: 0.27, blue: 0.20))
                        Circle().fill(Color(red: 0.93, green: 0.88, blue: 0.70)).frame(width: 33, height: 33).offset(x: 60, y: -68)
                    }
                    HStack { Text("值得留下").font(.caption); Spacer(); Image(systemName: "checkmark.circle.fill").foregroundStyle(stillAccent) }.padding(16).background(Color(red: 0.13, green: 0.18, blue: 0.15))
                }.frame(width: 220, height: 290).clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(stillAccent.opacity(0.75), lineWidth: 2))
                    .rotationEffect(.degrees(7)).shadow(color: .black.opacity(0.35), radius: 28, y: 16)
            }.frame(width: 270, height: 350).accessibilityHidden(true)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(38)
    }
    private var review: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 12) {
                    photoGrid

                }.padding(.horizontal, 22).padding(.bottom, 18)
                if store.showInfo { inspector.frame(width: 190).padding(.trailing, 22) }
            }.frame(maxHeight: .infinity)
            filmstrip
        }
    }
    private var photoGrid: some View {
        GeometryReader { geometry in
            let count = store.indices.count
            let columns = count <= 1 ? 1 : (count <= 4 ? 2 : 3)
            let rows = max(1, Int(ceil(Double(count) / Double(columns))))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                    ForEach(store.indices, id: \.self) { index in
                        PhotoCard(photo: store.photos[index], mark: store.session.mark(at: index), rating: store.session.rating(at: index), comparing: store.isComparing, focused: index == store.session.cursor, zoomStep: store.preferences.zoomStep, synchronized: store.isComparing && store.syncZoom, sharedScale: $store.sharedZoom, panSynchronized: store.isComparing && store.syncPan, sharedOffset: $store.sharedPan, onMark: { store.mark(index) }, onFocus: { store.focus(index) })
                            .frame(height: max(165, (geometry.size.height - CGFloat(rows - 1) * 12) / CGFloat(rows)))
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionLabel("照片信息")
            let photo = store.photos[store.session.cursor]
            VStack(alignment: .leading, spacing: 9) {
                Text(photo.name).font(.system(size: 14, weight: .medium)).lineLimit(2)
                Text(photo.formatSummary).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("星级")
                Text(store.session.rating(at: store.session.cursor) == 0 ? "未标星" : String(repeating: "★", count: store.session.rating(at: store.session.cursor)))
                    .foregroundStyle(.yellow)

            }
            MetadataView(photo: photo)
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("关联文件")
                ForEach(photo.files, id: \.self) { url in
                    Text(url.lastPathComponent).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Label(store.session.mark(at: store.session.cursor).title, systemImage: store.session.mark(at: store.session.cursor).symbol)
                .font(.caption).foregroundStyle(store.session.mark(at: store.session.cursor).color)
        }.padding(.top, 6)
    }
    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(store.photos.enumerated()), id: \.element.id) { index, photo in
                        let mark = store.session.mark(at: index)
                        let rating = store.session.rating(at: index)
                        Button {
                            if store.isComparing { store.focus(index) } else { store.navigate(index) }
                        } label: {
                            VStack(spacing: 8) {
                                PhotoImage(photo: photo, size: 300)
                                    .frame(width: 112, height: 76).background(.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(mark == .pending ? .white.opacity(0.12) : mark.color, lineWidth: mark == .pending ? 1 : 3))
                                    .overlay(alignment: .topTrailing) {
                                        if mark != .pending {
                                            Image(systemName: mark.symbol).font(.system(size: 11, weight: .heavy))
                                                .foregroundStyle(.black.opacity(0.85)).frame(width: 27, height: 23)
                                                .background(mark.color, in: RoundedRectangle(cornerRadius: 6)).padding(4)
                                        }
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(index == store.session.cursor ? .white : .clear, lineWidth: 2).padding(-3))
                                HStack {
                                    Text(store.preferences.showFileNames ? photo.preview.lastPathComponent : String(format: "%03d", index + 1)).lineLimit(1).truncationMode(.middle).help(photo.preview.lastPathComponent).foregroundStyle(.secondary)
                                    Spacer()
                                    if rating > 0 {
                                        HStack(spacing: 3) {
                                            Image(systemName: "star.fill")
                                            Text("\(rating)").monospacedDigit()
                                        }.foregroundStyle(.yellow)
                                    }
                                }.font(.system(size: 11, weight: .medium, design: .monospaced))
                            }.frame(width: 112)
                        }.buttonStyle(.plain).id(photo.id)
                            .accessibilityLabel("\(photo.name)，\(mark.title)，\(rating) 星")
                            .opacity(store.isComparing && !store.indices.contains(index) ? 0.5 : 1)
                            .disabled(store.isComparing && !store.indices.contains(index))
                    }
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }.background(FilmstripWheel()).clipped().frame(height: 126).scrollIndicators(.hidden).background(.black.opacity(0.17))
                .onAppear { if store.photos.indices.contains(store.session.cursor) { proxy.scrollTo(store.photos[store.session.cursor].id, anchor: .center) } }
                .onChange(of: store.session.cursor) { _, value in withAnimation(.easeOut(duration: 0.2)) { if store.photos.indices.contains(value) { proxy.scrollTo(store.photos[value].id, anchor: .center) } } }
        }
        .id(store.filmstripRevision)
    }
}

struct MetadataView: View {
    let photo: Photo
    @ViewState private var rows: [MetadataRow] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.label).font(.system(size: 10)).foregroundStyle(.tertiary)
                    Text(row.value).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }.task(id: photo.id) {
            let metadata = await ImagePipeline.shared.metadata(photo.preview)
            if !Task.isCancelled { rows = metadata }
        }
    }
}

struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> ReaderView { let view = ReaderView(); view.onWindow = onWindow; return view }
    func updateNSView(_ view: ReaderView, context: Context) { view.onWindow = onWindow }
    final class ReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onWindow?(window) }
    }
}
