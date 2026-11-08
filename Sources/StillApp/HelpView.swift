import SwiftUI

struct HelpView: View {
    @Bindable var preferences: Preferences
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Still 使用帮助").font(.largeTitle)
                section("导入与照片组合", "⌘O 选择文件夹，递归扫描子文件夹。同名、不同扩展名跨目录配为一组；没有配对文件的单张照片也会导入。确认页默认全选组合。左侧组合复选框只筛选显示，重新勾选后标记与星级保留。")
                section("选片与连选", "W / S 向左 / 向右增加照片，Shift+W / Shift+S 从对应方向减少。点击照片切换精选；空格完成本组并前进。默认未精选照片全部淘汰。Esc 离开连选但不结算；⌘Z 撤销。下面列出你当前的实际快捷键。")
                ForEach(ReviewAction.allCases) { action in
                    HStack { Text(action.title); Spacer(); KeyCap(text: preferences.displayKey(action)) }
                }
                section("缩放与移动", "在照片上滚动鼠标缩放，双击放大或复位，放大后拖动。倍率关联和移动关联为独立开关。胶片条上的垂直滚轮用于横向滚动列表。设置中可调整缩放步进、文件名显示和全部单键快捷键。")
                section("保存与恢复", "⌘↩ 打开归档，选择按精选或按星级分类，以及 RAW 与照片是否同目录。归档移动原文件，淘汰照片放入独立的可恢复文件夹；隐藏的组合不会归档。归档清单保存原位置，使用「选片 → 从归档清单还原」恢复。遇到同名原文件会停止，避免覆盖。")
                section("找不到照片或缩略图", "检查左侧照片组合是否勾选。切换组合会重建胶片条，只显示当前组合。重新打开原文件夹可恢复已保存进度。系统不支持解码的相机格式可能无法预览，但文件仍保留。")
            }.padding(28)
        }.frame(minWidth: 590, minHeight: 580).preferredColorScheme(.dark)
    }
    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(text).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled) }
    }
}

struct ReviewCommands: Commands {
    @Bindable var store: ReviewStore
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开照片文件夹…", action: store.openFolder).keyboardShortcut("o").disabled(store.busy)
            Button("体验演示图库", action: store.loadDemo).disabled(store.busy)
        }
        CommandGroup(after: .sidebar) {
            action(.toggleSidebar)
            action(.toggleInfo)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("撤销上一步", action: store.undo).keyboardShortcut("z").disabled(store.busy)
        }
        CommandMenu("选片") {
            action(.previous); action(.next)
            Divider()
            action(.mark); action(.reject); action(.clear)
            Menu("星级") {
                ForEach([ReviewAction.star1, .star2, .star3, .star4, .star5, .clearRating, .clearRatingAccent]) { action($0) }
            }
            Divider()
            action(.expandLeft); action(.expandRight)
            action(.shrinkLeft); action(.shrinkRight); action(.finishGroup)
            Button("离开连选（不结算）") { store.change { $0.group = nil } }.keyboardShortcut(.escape, modifiers: []).disabled(!store.isComparing)
            Toggle("倍率关联", isOn: $store.syncZoom)
            Toggle("移动关联", isOn: $store.syncPan)
            Divider()
            Button("归档照片…") { store.showArchive = true }.keyboardShortcut(.return, modifiers: .command)
                .disabled(store.photos.isEmpty || store.isComparing || store.busy)
            Button("从归档清单还原…", action: store.restoreArchive).disabled(store.busy)
        }
        CommandGroup(replacing: .help) {
            Button("Still 使用帮助") { openWindow(id: "help") }.keyboardShortcut("?", modifiers: .command)
        }
    }
    private func action(_ action: ReviewAction) -> some View {
        let key = store.preferences.key(for: action)
        let shifted = key.hasPrefix("shift+")
        let character = (shifted ? String(key.dropFirst(6)) : key).first ?? " "
        let needsPhotos = ![ReviewAction.toggleSidebar, .toggleInfo].contains(action)
        let groupOnly = [ReviewAction.shrinkLeft, .shrinkRight, .finishGroup].contains(action)
        return Button(action.title) { store.perform(action) }
            .keyboardShortcut(KeyEquivalent(character), modifiers: shifted ? .shift : [])
            .disabled(store.busy || (needsPhotos && store.photos.isEmpty) || (groupOnly && !store.isComparing) || (action == .previous && store.isComparing))
    }
}
