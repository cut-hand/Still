import SwiftUI

// Explicit alias selects the State property wrapper in CLI toolchains.
typealias ViewState<Value> = SwiftUI.State<Value>

let stillAccent = Color(red: 0.65, green: 0.86, blue: 0.66)
let canvasColor = Color(red: 0.063, green: 0.071, blue: 0.071)

struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24)
                .fill(LinearGradient(colors: [Color(red: 0.22, green: 0.36, blue: 0.29), Color(red: 0.07, green: 0.15, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.10).stroke(.white.opacity(0.24), lineWidth: size * 0.028)
                .frame(width: size * 0.48, height: size * 0.52).rotationEffect(.degrees(-16)).offset(x: -size * 0.09, y: -size * 0.02)
            RoundedRectangle(cornerRadius: size * 0.10)
                .fill(LinearGradient(colors: [stillAccent, Color(red: 0.36, green: 0.65, blue: 0.49)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.46, height: size * 0.54).rotationEffect(.degrees(10)).offset(x: size * 0.08, y: size * 0.02)
            Image(systemName: "checkmark").font(.system(size: size * 0.24, weight: .semibold)).foregroundStyle(Color(red: 0.10, green: 0.23, blue: 0.16)).offset(x: size * 0.08, y: size * 0.03)
        }.frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).stroke(.white.opacity(0.15), lineWidth: 1))
            .accessibilityLabel("Still 留选")
    }
}
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 3)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.08)))
    }
}
