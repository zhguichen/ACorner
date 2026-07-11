import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private enum VerticalAnchor {
        case center
        case above
        case below
    }

    private enum DisplayMode {
        case collapsed
        case transient
        case fixed
        case automatic

        var isExpanded: Bool { self != .collapsed }
    }

    private let model: TaskSessionModel
    private let panel: FloatingPanel
    private var displayMode: DisplayMode = .collapsed
    private var collapseWorkItem: DispatchWorkItem?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var dotCenter: CGPoint

    private let dotSize: CGFloat = 22
    private let cardWidth: CGFloat = 312
    private let cardHeight: CGFloat = 300
    private let gap: CGFloat = 10

    init(model: TaskSessionModel) {
        self.model = model
        self.dotCenter = Self.savedDotCenter() ?? Self.defaultDotCenter()
        self.panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 22, height: 22),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.delegate = self
        panel.title = "一隅 ACorner"
        panel.contentView = NSHostingView(rootView: FloatingSurface(model: model, controller: self))

        model.onPhaseChanged = { [weak self] phase in
            self?.respond(to: phase)
        }
        model.onRequestCollapse = { [weak self] in
            self?.collapse()
        }
        installOutsideClickMonitor()
        relayout(animated: false)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hoverStarted() {
        collapseWorkItem?.cancel()
        guard displayMode == .collapsed else { return }
        displayMode = .transient
        model.isCardPresented = true
        relayout()
    }

    func hoverEnded() {
        // 展开后的卡片保持可见，交由点击卡片外部的操作来收起。
    }

    func dotActivated() {
        collapseWorkItem?.cancel()
        displayMode = .fixed
        model.isCardPresented = true
        model.focusRequest += 1
        relayout()
        activateForTextEntry()
    }

    func movedDot(by delta: CGSize) {
        guard delta.width != 0 || delta.height != 0 else { return }
        let visible = screenForDot().visibleFrame.insetBy(dx: dotSize / 2, dy: dotSize / 2)
        dotCenter.x = min(max(dotCenter.x + delta.width, visible.minX), visible.maxX)
        dotCenter.y = min(max(dotCenter.y + delta.height, visible.minY), visible.maxY)
        UserDefaults.standard.set([dotCenter.x, dotCenter.y], forKey: "floatingDotCenter")
        relayout(animated: false)
    }

    func collapse() {
        collapseWorkItem?.cancel()
        displayMode = .collapsed
        model.isCardPresented = false
        relayout()
        panel.resignKey()
        if model.phase == .wrapUp {
            model.closeWrapUp()
        } else {
            model.saveDraft()
        }
    }

    private func respond(to phase: TaskPhase) {
        switch phase {
        case .waiting, .wrapUp:
            displayMode = .automatic
            model.isCardPresented = true
            relayout()
        case .overtime:
            collapse()
        case .countdown:
            if displayMode == .automatic { collapse() }
        case .idle:
            if displayMode == .automatic { collapse() }
        }
    }

    private func relayout(animated: Bool = true) {
        let expanded = displayMode.isExpanded
        let targetSize = expanded
            ? NSSize(width: cardWidth + dotSize + gap, height: cardHeight)
            : NSSize(width: dotSize, height: dotSize)
        let frame = panelFrame(for: targetSize, expanded: expanded)
        let update = {
            self.panel.setContentSize(targetSize)
            self.panel.setFrameOrigin(frame.origin)
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = expanded ? 0.34 : 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().setFrame(frame, display: true)
            }
        } else {
            update()
        }
    }

    private func panelFrame(for size: NSSize, expanded: Bool) -> NSRect {
        guard expanded else {
            return NSRect(x: dotCenter.x - dotSize / 2, y: dotCenter.y - dotSize / 2, width: size.width, height: size.height)
        }
        let screen = screenForDot()
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let needsLeft = dotCenter.x + size.width - dotSize / 2 > visible.maxX
        let x = needsLeft
            ? dotCenter.x - dotSize / 2 - gap - cardWidth
            : dotCenter.x - dotSize / 2
        let y: CGFloat
        switch verticalAnchor(on: screen) {
        case .center:
            y = dotCenter.y - size.height / 2
        case .above:
            y = dotCenter.y - dotSize / 2
        case .below:
            y = dotCenter.y - size.height + dotSize / 2
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    func isCardOnLeft() -> Bool {
        let visible = screenForDot().visibleFrame.insetBy(dx: 8, dy: 8)
        return dotCenter.x + cardWidth + gap + dotSize / 2 > visible.maxX
    }

    func dotVerticalOffset(expanded: Bool) -> CGFloat {
        guard expanded else { return 0 }
        return switch verticalAnchor(on: screenForDot()) {
        case .center: cardHeight / 2 - dotSize / 2
        case .above: 0
        case .below: cardHeight - dotSize
        }
    }

    private func screenForDot() -> NSScreen {
        NSScreen.screens.min(by: { $0.visibleFrame.distance(to: dotCenter) < $1.visibleFrame.distance(to: dotCenter) }) ?? NSScreen.main!
    }

    private func verticalAnchor(on screen: NSScreen) -> VerticalAnchor {
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let halfHeight = cardHeight / 2
        if dotCenter.y - halfHeight >= visible.minY, dotCenter.y + halfHeight <= visible.maxY {
            return .center
        }
        if dotCenter.y - dotSize / 2 >= visible.minY,
           dotCenter.y - dotSize / 2 + cardHeight <= visible.maxY {
            return .above
        }
        return .below
    }

    private func installOutsideClickMonitor() {
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.closeForOutsideClick(event)
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.closeForOutsideClick(event)
        }
    }

    private func closeForOutsideClick(_ event: NSEvent) {
        guard displayMode.isExpanded else { return }
        guard event.window === panel else {
            collapse()
            return
        }
        if model.phase == .idle {
            activateForTextEntry()
        }
    }

    private func activateForTextEntry() {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private static func savedDotCenter() -> CGPoint? {
        guard let coordinates = UserDefaults.standard.array(forKey: "floatingDotCenter") as? [Double], coordinates.count == 2 else { return nil }
        return CGPoint(x: coordinates[0], y: coordinates[1])
    }

    private static func defaultDotCenter() -> CGPoint {
        let frame = NSScreen.main?.visibleFrame ?? .zero
        return CGPoint(x: frame.maxX - 42, y: frame.maxY - 42)
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private extension NSRect {
    func distance(to point: CGPoint) -> CGFloat {
        let dx = max(minX - point.x, 0, point.x - maxX)
        let dy = max(minY - point.y, 0, point.y - maxY)
        return hypot(dx, dy)
    }
}
