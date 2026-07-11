import AppKit
import SwiftUI

struct FloatingSurface: View {
    let model: TaskSessionModel
    let controller: FloatingPanelController
    let store: RecordStore
    let openSettings: () -> Void
    @State private var lastDragTranslation: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        let cardIsVisible = model.isCardPresented
        let hostIsExpanded = model.isCardHostExpanded
        let cardIsOnLeft = controller.isCardOnLeft()
        let cardLeading: CGFloat = cardIsOnLeft ? 0 : FloatingMetrics.anchorWidth + FloatingMetrics.gap
        ZStack(alignment: .leading) {
            if cardIsVisible {
                card
                    .frame(width: FloatingMetrics.cardWidth, height: FloatingMetrics.cardHeight)
                    .offset(x: cardLeading)
                    .transition(drawerTransition(cardIsOnLeft: cardIsOnLeft))
                    .zIndex(0)
            }

            anchorStrip
                .offset(x: cardIsOnLeft && hostIsExpanded ? FloatingMetrics.cardWidth + FloatingMetrics.gap : 0)
                .offset(y: controller.dotVerticalOffset(expanded: hostIsExpanded))
                .zIndex(1)
        }
        .frame(
            width: hostIsExpanded ? FloatingMetrics.cardWidth + FloatingMetrics.anchorWidth + FloatingMetrics.gap : FloatingMetrics.anchorWidth,
            height: hostIsExpanded ? FloatingMetrics.cardHeight : FloatingMetrics.anchorHeight,
            alignment: .leading
        )
        .onHover { isInside in
            isInside ? controller.hoverStarted() : controller.hoverEnded()
        }
    }

    private func drawerTransition(cardIsOnLeft: Bool) -> AnyTransition {
        let travel = FloatingMetrics.drawerTravel * (cardIsOnLeft ? 1 : -1)
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: travel, y: 0)),
            removal: .opacity.combined(with: .offset(x: travel, y: 0))
        )
    }

    private var anchorStrip: some View {
        ZStack {
            Capsule()
                .fill(anchorTint.gradient.opacity(0.92))
            Capsule()
                .strokeBorder(.white.opacity(0.34), lineWidth: 1)

            HStack(spacing: 7) {
                Text(anchorTitle)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.94))
                ProgressLine(progress: store.todoProgress)
            }
            .padding(.horizontal, 8)
        }
        .shadow(color: anchorTint.opacity(0.24), radius: 10, y: 2)
        .animation(.easeInOut(duration: 0.2), value: model.phase)
        .frame(width: FloatingMetrics.anchorWidth, height: FloatingMetrics.anchorHeight)
        .contentShape(Capsule())
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
        .accessibilityLabel(anchorAccessibilityLabel)
        .accessibilityHint("点按以展开任务面板，拖动以移动位置")
    }

    @ViewBuilder
    private var card: some View {
        Group {
            switch model.phase {
            case .idle:
                TaskInputCard(model: model, store: store, openSettings: openSettings)
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

    private var anchorTitle: String {
        switch model.phase {
        case .idle, .wrapUp: "空闲"
        case .countdown: "进行中"
        case .waiting: "到时"
        case .overtime: "继续中"
        }
    }

    private var anchorTint: Color {
        switch model.phase {
        case .idle, .wrapUp: Color(nsColor: .systemGray)
        case .countdown: Color(nsColor: .systemGreen)
        case .waiting: Color(nsColor: .systemYellow)
        case .overtime: Color(nsColor: .systemBlue)
        }
    }

    private var anchorAccessibilityLabel: String {
        if store.todoCount == 0 {
            return "一隅，\(model.statusText)，暂无待办"
        }
        return "一隅，\(model.statusText)，待办完成 \(store.completedTodoCount) / \(store.todoCount)"
    }
}

private struct TaskInputCard: View {
    let model: TaskSessionModel
    let store: RecordStore
    let openSettings: () -> Void
    @FocusState private var titleIsFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(eyebrow: "一隅 ACorner", title: "现在想推进什么？", status: "空闲")
            TextField("例如：整理项目提案", text: $model.draftTitle)
                .textFieldStyle(.roundedBorder)
                .focused($titleIsFocused)
                .onChange(of: model.draftTitle) { model.saveDraft() }

            TimeInput(minutes: Binding(
                get: { model.draftMinutes },
                set: { model.updateDraftMinutes($0) }
            ))
            .onChange(of: model.draftMinutes) { model.saveDraft() }

            if store.todoCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("待办进度")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(store.completedTodoCount)/\(store.todoCount) 已完成")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !store.pendingTodos.isEmpty {
                        Menu("从待办填入") {
                            ForEach(store.pendingTodos) { todo in
                                Button(todo.title) {
                                    model.useTodo(todo)
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Button {
                    openSettings()
                } label: {
                    Label("待办", systemImage: "checklist")
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Button("开始") { model.start() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(
                        model.draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        !TaskSessionModel.plannedMinutesRange.contains(model.draftMinutes)
                    )
            }
        }
        .task(id: model.focusRequest) {
            titleIsFocused = true
        }
    }
}

private struct ProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                Capsule()
                    .fill(.white.opacity(0.92))
                    .frame(width: proxy.size.width * clampedProgress)
            }
        }
        .frame(height: 4)
    }
}

private struct ActiveTaskCard: View {
    let model: TaskSessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeading(
                eyebrow: model.phase == .countdown ? "正在进行" : "仍在投入",
                title: model.activeTask?.title ?? "",
                status: model.fuzzyTimeText()
            )
            RecordNoteBox(model: model)
                .frame(minHeight: 126)
            HStack {
                Spacer(minLength: 0)
                Button("结束") { model.endCurrentTask() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
    }
}

private struct WaitingCard: View {
    let model: TaskSessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeading(eyebrow: "时间到了", title: "这段时间结束了", status: model.activeTask?.title ?? "")
            Text("可以在这里收尾，或者自然地开始下一件事。")
                .font(.callout)
                .foregroundStyle(.secondary)
            RecordNoteBox(model: model)
                .frame(minHeight: 92)
            HStack {
                Spacer(minLength: 0)
                Button("结束") { model.endCurrentTask() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
    }
}

private struct WrapUpCard: View {
    let model: TaskSessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeading(eyebrow: "已结束", title: model.completedRecord?.title ?? "", status: "待保存")
            HStack(spacing: 16) {
                TimeSummary(label: "计划", value: "\(model.completedRecord?.plannedMinutes ?? 0) 分钟")
                TimeSummary(label: "实际", value: model.completedRecord.map { durationText($0.actualDuration) } ?? "")
            }
            RecordNoteBox(model: model)
                .frame(minHeight: 116)
            HStack {
                Text("点击 Next Mission 后保存")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Button("Next Mission") { model.saveAndStartNextMission() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
        }
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

private struct RecordNoteBox: View {
    let model: TaskSessionModel
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        TextEditor(text: Binding(
            get: { model.activeNote },
            set: { model.updateNote($0) }
        ))
        .focused($noteIsFocused)
        .font(.callout)
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .accessibilityLabel("任务记录")
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                noteIsFocused = true
            }
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

private struct TimeInput: View {
    @Binding var minutes: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("投入多久？")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            TextField("25", value: $minutes, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .accessibilityLabel("投入分钟数")
                .accessibilityValue("\(minutes) 分钟")
            Text("分钟")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
