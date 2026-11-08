import SwiftUI
import CullingCore

struct PhotoCard: View {
    let photo: Photo
    let mark: PhotoMark
    let rating: Int
    let comparing: Bool
    let focused: Bool
    let zoomStep: Double
    let synchronized: Bool
    @Binding var sharedScale: CGFloat
    let panSynchronized: Bool
    @Binding var sharedOffset: CGSize
    let onMark: () -> Void
    let onFocus: () -> Void
    @ViewState private var localScale: CGFloat = 1
    private var scale: CGFloat { synchronized ? sharedScale : localScale }
    private func setScale(_ value: CGFloat) {
        let bounded = min(8, max(1, value))
        if synchronized { sharedScale = bounded } else { localScale = bounded }
        if bounded == 1 { offset = .zero }
    }
    @ViewState private var localOffset = CGSize.zero
    @ViewState private var viewport = CGSize(width: 1, height: 1)
    @ViewState private var dragOrigin: CGSize?
    private var offset: CGSize {
        get { panSynchronized ? sharedOffset : localOffset }
        nonmutating set { if panSynchronized { sharedOffset = newValue } else { localOffset = newValue } }
    }
    @GestureState private var magnification: CGFloat = 1
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                PhotoImage(photo: photo, size: comparing ? 1600 : 3000)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(min(8, max(1, scale * magnification)))
                    .offset(x: offset.width * geometry.size.width, y: offset.height * geometry.size.height)
                    .onAppear { viewport = geometry.size }
                    .onChange(of: geometry.size) { _, size in viewport = size }
            }
            .overlay { WheelZoom { delta in setScale(scale + delta * CGFloat(zoomStep) / 100) } }
            .background(Color.black.opacity(0.28)).clipped().contentShape(Rectangle())
            .gesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                .onEnded { value in setScale(scale * value.magnification); if scale == 1 { offset = .zero } })
            .simultaneousGesture(DragGesture(minimumDistance: 3)
                .onChanged { value in
                    guard scale > 1 else { return }
                    if dragOrigin == nil { dragOrigin = offset }
                    let start = dragOrigin ?? .zero
                    offset = CGSize(width: start.width + value.translation.width / max(1, viewport.width),
                                    height: start.height + value.translation.height / max(1, viewport.height))
                }.onEnded { _ in dragOrigin = nil })
            .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.15)) { setScale(scale == 1 ? 2 : 1); offset = .zero } }
            .onTapGesture { if comparing { onMark() } }
            HStack(spacing: 8) {
                Text(photo.name).onTapGesture(perform: onFocus).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                Text(photo.formatSummary).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                if scale > 1 { Text("\(Int(scale * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                if rating > 0 {
                    Text(String(repeating: "★", count: rating)).font(.system(size: 12)).foregroundStyle(.yellow)
                }


            }.padding(9).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8)).padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(mark == .pending ? .white.opacity(0.09) : mark.color, lineWidth: mark == .pending ? 1 : 5))
        .overlay(alignment: .topTrailing) {
            if mark != .pending {
                Label(mark.title, systemImage: mark.symbol).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black).padding(10).background(mark.color, in: Capsule()).padding(12)
            }
        }
        .overlay(alignment: .topLeading) {
            if comparing && focused {
                Text("当前").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                    .foregroundStyle(.black).background(.white, in: Capsule()).padding(10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(photo.name)，\(mark.title)，\(rating) 星")
        .accessibilityAction(named: "切换标记", onMark)
        .onChange(of: panSynchronized) { _, enabled in if !enabled { localOffset = sharedOffset } }
        .onChange(of: synchronized) { _, enabled in if !enabled { localScale = sharedScale } }
        .onChange(of: sharedScale) { _, value in if value == 1 { offset = .zero } }
        .onChange(of: photo.id) { _, _ in localScale = 1; localOffset = .zero; dragOrigin = nil }
    }
}
