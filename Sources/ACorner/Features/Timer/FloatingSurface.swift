import AppKit
import SwiftUI

struct FloatingSurface: View {
    let model: TaskSessionModel
    let controller: FloatingPanelController
    @State private var lastDragTranslation: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        let expanded = model.isCardPresented
        ZStack(alignment: .leading) {
            if expanded {
                card
                    .frame(width: 312, height: 300)
                    .offset(x: controller.isCardOnLeft() ? 0 : 32)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: controller.isCardOnLeft() ? .trailing : .leading)))
            }

            dot
                .offset(x: controller.isCardOnLeft() && expanded ? 322 : 0)
                .offset(y: controller.dotVerticalOffset(expanded: expanded))
        }
        .frame(width: expanded ? 344 : 22, height: expanded ? 300 : 22, alignment: .leading)
        .onHover { isInside in
            isInside ? controller.hoverStarted() : controller.hoverEnded()
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }

    private var dot: some View {
        Circle()
            .fill(dotColor)
            .overlay {
                Circle().strokeBorder(.white.opacity(0.34), lineWidth: 1)
            }
            .shadow(color: dotColor.opacity(0.28), radius: 7, y: 2)
            .frame(width: 22, height: 22)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let distance = hypot(value.translation.width, value.translation.height)
                        guard distance >= 3 else { return }
                        isDragging = true
                        let delta = CGSize(
                            width: value.translation.width - lastDragTranslation.width,
                            height: -value.translation.height + lastDragTranslation.height
                        )
                        lastDragTranslation = value.translation
                        controller.movedDot(by: delta)
                    }
                    .onEnded { _ in
                        if !isDragging {
                            controller.dotActivated()
                        }
                        lastDragTranslation = .zero
                        isDragging = false
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("一隅，\(model.statusText)")
            .accessibilityHint("点按以展开任务卡片，拖动以移动位置")
    }

    @ViewBuilder
    private var card: some View {
        Group {
            switch model.phase {
            case .idle:
                TaskInputCard(model: model)
            case .countdown, .overtime:
                ActiveTaskCard(model: model)
            case .waiting:
                WaitingCard(model: model)
            case .wrapUp:
                WrapUpCard(model: model)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 7)
        .accessibilityElement(children: .contain)
    }

    private var dotColor: Color {
        switch model.phase {
        case .idle, .wrapUp: Color(nsColor: .systemGray)
        case .countdown: Color(nsColor: .systemGreen)
        case .waiting: Color(nsColor: .systemYellow)
        case .overtime: Color(nsColor: .systemBlue)
        }
    }
}

private struct TaskInputCard: View {
    let model: TaskSessionModel
    @FocusState private var titleIsFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(eyebrow: "一隅 ACorner", title: "现在想推进什么？", status: "空闲")
            TextField("例如：整理项目提案", text: $model.draftTitle)
                .textFieldStyle(.roundedBorder)
                .focused($titleIsFocused)
                .onChange(of: model.draftTitle) { model.saveDraft() }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("投入多久？")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.draftMinutes) 分钟")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                MinuteWheel(minutes: $model.draftMinutes)
                .frame(height: 82)
                .onChange(of: model.draftMinutes) { model.saveDraft() }
            }

            Button("开始") { model.start() }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(model.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.draftMinutes <= 0)
        }
        .task(id: model.focusRequest) {
            titleIsFocused = true
        }
    }
}

private struct ActiveTaskCard: View {
    let model: TaskSessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeading(
                eyebrow: model.phase == .countdown ? "正在进行" : "仍在投入",
                title: model.activeTask?.title ?? "",
                status: model.fuzzyTimeText()
            )
            Divider()
            ActionRow(model: model)
        }
    }
}

private struct WaitingCard: View {
    let model: TaskSessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeading(eyebrow: "时间到了", title: "这段时间结束了", status: model.activeTask?.title ?? "")
            Text("可以在这里收尾，或者自然地开始下一件事。")
                .font(.callout)
                .foregroundStyle(.secondary)
            ActionRow(model: model)
        }
    }
}

private struct WrapUpCard: View {
    let model: TaskSessionModel
    @State private var note = ""
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeading(eyebrow: "已完成", title: model.completedRecord?.title ?? "", status: "已自动保存")
            HStack(spacing: 16) {
                TimeSummary(label: "计划", value: "\(model.completedRecord?.plannedMinutes ?? 0) 分钟")
                TimeSummary(label: "实际", value: model.completedRecord.map { durationText($0.actualDuration) } ?? "")
            }
            TextField("写点什么……", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .focused($noteIsFocused)
                .onChange(of: note) { model.updateNote(note) }
            Text("已自动保存")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .onAppear { note = model.completedRecord?.note ?? "" }
    }
}

private struct CardHeading: View {
    let eyebrow: String
    let title: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ActionRow: View {
    let model: TaskSessionModel

    var body: some View {
        HStack(spacing: 10) {
            Button("完成") { model.finish(.completed) }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            Button("下一个任务") { model.finish(.nextTask) }
                .buttonStyle(.bordered)
            Spacer(minLength: 0)
        }
    }
}

private struct TimeSummary: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium))
        }
    }
}

private func durationText(_ duration: TimeInterval) -> String {
    let roundedMinutes = max(1, Int((duration / 60).rounded()))
    return "约 \(roundedMinutes) 分钟"
}

private struct MinuteWheel: NSViewRepresentable {
    @Binding var minutes: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(minutes: $minutes)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let documentView = MinuteWheelDocumentView()
        documentView.frame = NSRect(x: 0, y: 0, width: 260, height: MinuteWheelDocumentView.contentHeight)

        scrollView.documentView = documentView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.scrollView = scrollView
        context.coordinator.documentView = documentView
        context.coordinator.installScrollObserver()
        DispatchQueue.main.async {
            context.coordinator.scroll(to: minutes)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.documentView?.frame.size.width = scrollView.contentSize.width
        context.coordinator.scroll(to: minutes)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeScrollObserver()
    }

    @MainActor
    final class Coordinator {
        private var minutes: Binding<Int>
        weak var scrollView: NSScrollView?
        weak var documentView: MinuteWheelDocumentView?
        private var observation: NSObjectProtocol?
        private var displayedMinutes = 0

        init(minutes: Binding<Int>) {
            self.minutes = minutes
        }

        func installScrollObserver() {
            guard let clipView = scrollView?.contentView else { return }
            observation = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateSelectionFromScrollPosition()
                }
            }
        }

        func removeScrollObserver() {
            if let observation {
                NotificationCenter.default.removeObserver(observation)
            }
        }

        func scroll(to value: Int) {
            guard displayedMinutes != value, let scrollView else { return }
            displayedMinutes = value
            documentView?.selectedMinutes = value
            let rowCenter = CGFloat(value - 1) * MinuteWheelDocumentView.rowHeight + MinuteWheelDocumentView.rowHeight / 2
            let proposedY = rowCenter - scrollView.contentSize.height / 2
            let maxY = max(0, MinuteWheelDocumentView.contentHeight - scrollView.contentSize.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, proposedY), maxY)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func updateSelectionFromScrollPosition() {
            guard let scrollView else { return }
            let centerY = scrollView.contentView.bounds.midY
            let row = Int((centerY / MinuteWheelDocumentView.rowHeight).rounded(.down))
            let value = min(max(row + 1, 1), 180)
            guard value != displayedMinutes else { return }
            displayedMinutes = value
            documentView?.selectedMinutes = value
            minutes.wrappedValue = value
        }
    }
}

private final class MinuteWheelDocumentView: NSView {
    static let rowHeight: CGFloat = 28
    static let contentHeight = rowHeight * 180

    var selectedMinutes = 25 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let firstRow = max(0, Int((dirtyRect.minY / Self.rowHeight).rounded(.down)))
        let lastRow = min(179, Int((dirtyRect.maxY / Self.rowHeight).rounded(.up)))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        for row in firstRow...lastRow {
            let minute = row + 1
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: minute == selectedMinutes ? 13 : 12, weight: minute == selectedMinutes ? .semibold : .regular),
                .foregroundColor: minute == selectedMinutes ? NSColor.labelColor : NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
            let rect = NSRect(x: 0, y: CGFloat(row) * Self.rowHeight + 4, width: bounds.width, height: Self.rowHeight - 8)
            "\(minute) 分钟".draw(in: rect, withAttributes: attributes)
        }
    }
}
