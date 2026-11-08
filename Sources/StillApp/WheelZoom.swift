import SwiftUI

// A local event monitor observes only scrolls inside this photo, leaving the
// filmstrip and surrounding scroll views with their normal scrolling behavior.
struct WheelZoom: NSViewRepresentable {
    let zoom: (CGFloat) -> Void
    func makeNSView(context: Context) -> WheelView { let view = WheelView(); view.zoom = zoom; return view }
    func updateNSView(_ view: WheelView, context: Context) { view.zoom = zoom }
    static func dismantleNSView(_ view: WheelView, coordinator: ()) { view.stop() }
    final class WheelView: NSView {
        var zoom: ((CGFloat) -> Void)?
        var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, self.window === event.window, !self.isHiddenOrHasHiddenAncestor,
                          self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)),
                          event.scrollingDeltaY != 0 else { return false }
                    self.zoom?(event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 20 : (event.scrollingDeltaY > 0 ? 1 : -1)); return true
                }
                return handled ? nil : event
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}

struct FilmstripWheel: NSViewRepresentable {
    func makeNSView(context: Context) -> StripView { StripView() }
    func updateNSView(_ view: StripView, context: Context) {}
    static func dismantleNSView(_ view: StripView, coordinator: ()) { view.stop() }
    final class StripView: NSView {
        var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let self, self.window === event.window,
                          self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)),
                          abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                          let scroll = self.containingStrip() else { return false }
                    let clip = scroll.contentView
                    let limit = max(0, (scroll.documentView?.frame.width ?? 0) - clip.bounds.width)
                    let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)
                    clip.scroll(to: NSPoint(x: min(limit, max(0, clip.bounds.origin.x - delta)), y: clip.bounds.origin.y))
                    scroll.reflectScrolledClipView(clip); return true
                }
                return handled ? nil : event
            }
        }
        func containingStrip() -> NSScrollView? {
            var ancestor = superview
            while let current = ancestor {
                if let scroll = findScroll(current) { return scroll }
                ancestor = current.superview
            }
            return nil
        }
        func findScroll(_ root: NSView?) -> NSScrollView? {
            guard let root else { return nil }
            if let scroll = root as? NSScrollView, (scroll.documentView?.frame.width ?? 0) > scroll.contentView.bounds.width + 1 { return scroll }
            for child in root.subviews { if let result = findScroll(child) { return result } }
            return nil
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}
