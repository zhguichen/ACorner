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
    private var presentationWorkItem: DispatchWorkItem?
    private var dismissalWorkItem: DispatchWorkItem?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var dotCenter: CGPoint

    private let cardPresentationDuration: TimeInterval = 0.24
    private let cardDismissalDuration: TimeInterval = 0.16

    init(model: TaskSessionModel, store: RecordStore, openSettings: @escaping () -> Void) {
        self.model = model
        self.dotCenter = Self.savedDotCenter() ?? Self.defaultDotCenter()
        self.panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: FloatingMetrics.anchorWidth, height: FloatingMetrics.anchorHeight),
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
        panel.contentView = NSHostingView(
            rootView: FloatingSurface(model: model, controller: self, store: store, openSettings: openSettings)
        )

        model.onPhaseChanged = { [weak self] phase in
            self?.respond(to: phase)
        }
        model.onRequestCollapse = { [weak self] in
            self?.collapse()
        }
        model.onHourlyCheckInRequested = { [weak self] in
            self?.presentHourlyCheckIn()
        }
        model.onHourlyCheckInResolved = { [weak self] in
            self?.hourlyCheckInResolved()
        }
        installOutsideClickMonitor()
        relayout()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hoverStarted() {
        guard displayMode == .collapsed else { return }
        displayMode = .transient
        presentCard()
    }

    func hoverEnded() {
        // 展开后的卡片保持可见，交由点击卡片外部的操作来收起。
    }

    func dotActivated() {
        displayMode = .fixed
        presentCard(focusAfterPresentation: true)
        activateForTextEntry()
    }

    func movedDot(by delta: CGSize) {
        guard delta.width != 0 || delta.height != 0 else { return }
        let visible = screenForDot().visibleFrame.insetBy(dx: FloatingMetrics.anchorWidth / 2, dy: FloatingMetrics.anchorHeight / 2)
        dotCenter.x = min(max(dotCenter.x + delta.width, visible.minX), visible.maxX)
        dotCenter.y = min(max(dotCenter.y + delta.height, visible.minY), visible.maxY)
        UserDefaults.standard.set([dotCenter.x, dotCenter.y], forKey: "floatingDotCenter")
        relayout()
    }

    func collapse() {
        guard !model.hasPendingHourlyCheckIn else { return }
        presentationWorkItem?.cancel()
        dismissalWorkItem?.cancel()
        displayMode = .collapsed
        withAnimation(.easeIn(duration: cardDismissalDuration)) {
            model.isCardPresented = false
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.displayMode == .collapsed else { return }
            self.model.isCardHostExpanded = false
            self.relayout()
        }
        dismissalWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + cardDismissalDuration, execute: workItem)
        panel.resignKey()
        if model.phase == .wrapUp {
            model.closeWrapUp()
        } else {
            model.saveDraft()
        }
    }

    private func respond(to phase: TaskPhase) {
        switch phase {
        case .waiting:
            displayMode = .automatic
            presentCard()
        case .wrapUp:
            if displayMode == .collapsed {
                displayMode = .automatic
            }
            presentCard()
        case .overtime:
            if !model.hasPendingHourlyCheckIn { collapse() }
        case .countdown:
            if displayMode == .automatic, !model.hasPendingHourlyCheckIn { collapse() }
        case .idle:
            if displayMode == .automatic, !model.hasPendingHourlyCheckIn { collapse() }
        }
    }

    private func presentHourlyCheckIn() {
        displayMode = .automatic
        presentCard()
    }

    private func hourlyCheckInResolved() {
        guard !model.hasPendingHourlyCheckIn else { return }
        collapse()
    }

    private func presentCard(focusAfterPresentation: Bool = false) {
        dismissalWorkItem?.cancel()
        presentationWorkItem?.cancel()

        guard !model.isCardPresented else {
            if focusAfterPresentation { model.focusRequest += 1 }
            return
        }

        model.isCardHostExpanded = true
        relayout()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.displayMode.isExpanded else { return }
            withAnimation(.easeOut(duration: cardPresentationDuration)) {
                self.model.isCardPresented = true
            }
            if focusAfterPresentation { self.model.focusRequest += 1 }
        }
        presentationWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func relayout() {
        let expanded = displayMode.isExpanded
        let targetSize = expanded
            ? NSSize(
                width: FloatingMetrics.cardWidth + FloatingMetrics.anchorWidth + FloatingMetrics.gap,
                height: FloatingMetrics.cardHeight
            )
            : NSSize(width: FloatingMetrics.anchorWidth, height: FloatingMetrics.anchorHeight)
        let frame = panelFrame(for: targetSize, expanded: expanded)
        panel.setContentSize(targetSize)
        panel.setFrameOrigin(frame.origin)
    }

    private func panelFrame(for size: NSSize, expanded: Bool) -> NSRect {
        guard expanded else {
            return NSRect(
                x: dotCenter.x - FloatingMetrics.anchorWidth / 2,
                y: dotCenter.y - FloatingMetrics.anchorHeight / 2,
                width: size.width,
                height: size.height
            )
        }
        let screen = screenForDot()
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let needsLeft = dotCenter.x + size.width - FloatingMetrics.anchorWidth / 2 > visible.maxX
        let x = needsLeft
            ? dotCenter.x - FloatingMetrics.anchorWidth / 2 - FloatingMetrics.gap - FloatingMetrics.cardWidth
            : dotCenter.x - FloatingMetrics.anchorWidth / 2
        let y: CGFloat
        switch verticalAnchor(on: screen) {
        case .center:
            y = dotCenter.y - size.height / 2
        case .above:
            y = dotCenter.y - FloatingMetrics.anchorHeight / 2
        case .below:
            y = dotCenter.y - size.height + FloatingMetrics.anchorHeight / 2
        }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    func isCardOnLeft() -> Bool {
        let visible = screenForDot().visibleFrame.insetBy(dx: 8, dy: 8)
        return dotCenter.x + FloatingMetrics.cardWidth + FloatingMetrics.gap + FloatingMetrics.anchorWidth / 2 > visible.maxX
    }

    func dotVerticalOffset(expanded: Bool) -> CGFloat {
        guard expanded else { return 0 }
        return switch verticalAnchor(on: screenForDot()) {
        case .center: 0
        case .above: FloatingMetrics.cardHeight / 2 - FloatingMetrics.anchorHeight / 2
        case .below: -(FloatingMetrics.cardHeight / 2 - FloatingMetrics.anchorHeight / 2)
        }
    }

    private func screenForDot() -> NSScreen {
        NSScreen.screens.min(by: { $0.visibleFrame.distance(to: dotCenter) < $1.visibleFrame.distance(to: dotCenter) }) ?? NSScreen.main!
    }

    private func verticalAnchor(on screen: NSScreen) -> VerticalAnchor {
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let halfHeight = FloatingMetrics.cardHeight / 2
        if dotCenter.y - halfHeight >= visible.minY, dotCenter.y + halfHeight <= visible.maxY {
            return .center
        }
        if dotCenter.y - FloatingMetrics.anchorHeight / 2 >= visible.minY,
           dotCenter.y - FloatingMetrics.anchorHeight / 2 + FloatingMetrics.cardHeight <= visible.maxY {
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
        displayMode = .fixed
        activateForTextEntry()
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
        return CGPoint(x: frame.maxX - 86, y: frame.maxY - 42)
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
