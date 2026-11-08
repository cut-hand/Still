import SwiftUI
import CullingCore

extension PhotoMark {
    var color: Color {
        switch self {
        case .selected: stillAccent
        case .rejected: Color(red: 1, green: 0.42, blue: 0.42)
        case .pending: .gray
        }
    }
    var symbol: String {
        switch self {
        case .selected: "checkmark"
        case .rejected: "xmark"
        case .pending: "minus"
        }
    }
}

enum ReviewAction: String, CaseIterable, Codable, Identifiable {
    case previous, next, expandLeft, expandRight, finishGroup, mark, reject, clear
    case shrinkLeft, shrinkRight, toggleInfo
    case star1, star2, star3, star4, star5, clearRating, clearRatingAccent, toggleSidebar
    var id: String { rawValue }
    var title: String {
        switch self {
        case .toggleInfo: "显示 / 隐藏照片信息"
        case .shrinkLeft: "从左边减少一张"
        case .shrinkRight: "从右边减少一张"
        case .previous: "上一张"
        case .next: "下一张 / 跳过"
        case .expandLeft: "向左增加一张"
        case .expandRight: "向右增加一张"
        case .finishGroup: "结束连选 / 单张时跳过"
        case .mark: "切换精选"
        case .reject: "切换淘汰"
        case .clear: "清除精选 / 淘汰"
        case .star1: "标为 1 星"
        case .star2: "标为 2 星"
        case .star3: "标为 3 星"
        case .star4: "标为 4 星"
        case .star5: "标为 5 星"
        case .clearRating: "取消标星"
        case .clearRatingAccent: "取消标星（第二按键）"
        case .toggleSidebar: "显示 / 隐藏左侧边栏"
        }
    }
    var defaultKey: String {
        switch self {
        case .toggleInfo: "i"
        case .shrinkLeft: "shift+w"
        case .shrinkRight: "shift+s"
        case .previous: "a"
        case .next: "d"
        case .expandLeft: "w"
        case .expandRight: "s"
        case .finishGroup: " "
        case .mark: "f"
        case .reject: "x"
        case .clear: "r"
        case .star1: "1"
        case .star2: "2"
        case .star3: "3"
        case .star4: "4"
        case .star5: "5"
        case .clearRating: "0"
        case .clearRatingAccent: "`"
        case .toggleSidebar: "b"
        }
    }
    var rating: Int? {
        switch self {
        case .star1: 1
        case .star2: 2
        case .star3: 3
        case .star4: 4
        case .star5: 5
        case .clearRating, .clearRatingAccent: 0
        default: nil
        }
    }
}

@MainActor @Observable final class Preferences {
    var showFileNames: Bool { didSet { defaults.set(showFileNames, forKey: "showFileNames") } }
    var zoomStep: Double { didSet { defaults.set(zoomStep, forKey: "zoomStep") } }
    var remainder: RemainderRule { didSet { defaults.set(remainder.rawValue, forKey: "remainder") } }
    var skip: SkipRule { didSet { defaults.set(skip.rawValue, forKey: "skip") } }
    var autoAdvance: Bool { didSet { defaults.set(autoAdvance, forKey: "autoAdvance") } }
    var archiveGrouping: ArchiveGrouping { didSet { defaults.set(archiveGrouping.rawValue, forKey: "archiveGrouping") } }
    var keepPairsTogether: Bool { didSet { defaults.set(keepPairsTogether, forKey: "keepPairsTogether") } }
    var shortcuts: [String: String] { didSet { defaults.set(shortcuts, forKey: "shortcuts") } }
    var recording: ReviewAction?
    var shortcutError: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showFileNames = defaults.bool(forKey: "showFileNames")
        let savedStep = defaults.double(forKey: "zoomStep")
        zoomStep = savedStep > 0 ? min(20, max(1, savedStep)) : 2
        remainder = RemainderRule(rawValue: defaults.string(forKey: "remainder") ?? "") ?? .unselected
        skip = SkipRule(rawValue: defaults.string(forKey: "skip") ?? "") ?? .unchanged
        autoAdvance = defaults.object(forKey: "autoAdvance") as? Bool ?? true
        archiveGrouping = ArchiveGrouping(rawValue: defaults.string(forKey: "archiveGrouping") ?? "") ?? .selection
        keepPairsTogether = defaults.object(forKey: "keepPairsTogether") as? Bool ?? true
        // New defaults can overlap user-customized v0.1 keys. Keep old bindings and
        // assign every new action a free key rather than allowing hidden duplicates.
        let saved = defaults.dictionary(forKey: "shortcuts") as? [String: String] ?? [:]
        let choices = Array("abcdefghijklmnopqrstuvwxyz0123456789`-=[];',./ ").map(String.init)
        var assigned: [String: String] = [:]
        var used = Set<String>()
        for action in ReviewAction.allCases where saved[action.rawValue] != nil {
            let key = saved[action.rawValue]!
            if used.insert(key).inserted { assigned[action.rawValue] = key }
        }
        for action in ReviewAction.allCases where assigned[action.rawValue] == nil {
            let key = used.contains(action.defaultKey) ? choices.first(where: { !used.contains($0) })! : action.defaultKey
            used.insert(key); assigned[action.rawValue] = key
        }
        shortcuts = assigned
    }
    var archiveOptions: ArchiveOptions { ArchiveOptions(grouping: archiveGrouping, keepPairsTogether: keepPairsTogether) }
    func key(for action: ReviewAction) -> String { shortcuts[action.rawValue] ?? action.defaultKey }
    func displayKey(_ action: ReviewAction) -> String {
        let key = key(for: action)
        if key.hasPrefix("shift+") { return "⇧" + key.dropFirst(6).uppercased() }
        if key == " " { return "空格" }
        if key == "`" { return "` / ~ / ·" }
        return key.uppercased()
    }
    static func normalizedKey(_ event: NSEvent) -> String? {
        // The same physical key produces `, ~, or · depending on input source.
        if event.keyCode == 50 { return "`" }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        return event.modifierFlags.contains(.shift) ? "shift+" + key : key
    }
    func record(_ event: NSEvent) {
        guard let action = recording else { return }
        if event.keyCode == 53 { recording = nil; return }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let key = Self.normalizedKey(event), (key.count == 1 || (key.hasPrefix("shift+") && key.count == 7)),
              key.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value <= 126 }) else {
            shortcutError = "请使用单个字母、数字、符号或空格。Esc 取消录入。"; return
        }
        if let other = ReviewAction.allCases.first(where: { $0 != action && self.key(for: $0) == key }) {
            shortcutError = "该按键已用于「\(other.title)」。请先修改另一项。"; return
        }
        shortcuts[action.rawValue] = key; shortcutError = nil; recording = nil
    }
}

struct SettingsView: View {
    @Bindable var preferences: Preferences
    var body: some View {
        TabView {
            Form {
                Section("连选模式") {
                    Picker("结束连选时", selection: $preferences.remainder) {
                        ForEach(RemainderRule.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("默认保留精选，其余照片标为淘汰；一张都没选时，全组淘汰。星级独立保存，不代替精选。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("单张浏览") {
                    Picker("跳过未选择照片时", selection: $preferences.skip) {
                        ForEach(SkipRule.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("精选 / 淘汰后自动进入下一张", isOn: $preferences.autoAdvance)
                    Text("标星或取消标星后停留在当前照片；连选时标记也不会自动前进。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("预览与胶片列表") {
                    Picker("缩略图名称", selection: $preferences.showFileNames) {
                        Text("序列号").tag(false)
                        Text("原文件名").tag(true)
                    }
                    Stepper("每格滚轮缩放：\(Int(preferences.zoomStep)) 个百分点", value: $preferences.zoomStep, in: 1...20, step: 1)
                    Text("默认每格增减 2 个百分点，触控板连续滚动按距离平滑调整。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("归档默认选项") {
                    Picker("分类方式", selection: $preferences.archiveGrouping) {
                        ForEach(ArchiveGrouping.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("RAW 与 JPG / HEIF / XMP 放在同一文件夹", isOn: $preferences.keepPairsTogether)
                    Text("关闭后按 RAW、照片、XMP 分文件夹。每次归档前仍可修改这两项；淘汰照片始终放入独立的可恢复文件夹。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("选片与保存", systemImage: "square.stack.3d.up") }
            Form {
                shortcutSection("浏览与选片", actions: ReviewAction.allCases.filter { ![.toggleInfo, .toggleSidebar, .star1, .star2, .star3, .star4, .star5, .clearRating, .clearRatingAccent].contains($0) })
                shortcutSection("星级", actions: [.star1, .star2, .star3, .star4, .star5, .clearRating, .clearRatingAccent])
                shortcutSection("界面", actions: [.toggleSidebar, .toggleInfo])
                Section {
                    if let error = preferences.shortcutError { Text(error).foregroundStyle(.orange).font(.caption) }
                    Text("点击按键后录入单个字母、数字、符号或空格。Esc 取消；⌘Z 撤销，⌘O 打开，⌘↩ 归档。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("恢复默认快捷键") { preferences.shortcuts = [:]; preferences.recording = nil; preferences.shortcutError = nil }
                }
            }.formStyle(.grouped).tabItem { Label("快捷键", systemImage: "keyboard") }
        }
        .padding(12).frame(width: 600, height: 650)
        .onDisappear { preferences.recording = nil }
    }
    private func shortcutSection(_ title: String, actions: [ReviewAction]) -> some View {
        Section(title) {
            ForEach(actions) { action in
                HStack {
                    Text(action.title)
                    Spacer()
                    Button(preferences.recording == action ? "按下新按键…" : preferences.displayKey(action)) {
                        preferences.recording = action; preferences.shortcutError = nil
                    }.frame(minWidth: 110).buttonStyle(.bordered)
                }
            }
        }
    }
}
