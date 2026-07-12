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

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(anchorPrimaryText)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.white.opacity(0.94))
                    Spacer(minLength: 4)
                    Text(anchorStatusText)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.62))
                }
                ProgressLine(
                    progress: store.todoProgress,
                    isTimerRunning: isTimerRunning,
                    timerStartedAt: model.activeTask?.startedAt
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
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
        VStack(alignment: .leading, spacing: 10) {
            if !requiresDailyCheckIn {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        openSettings()
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if requiresDailyCheckIn {
                DailyCheckInView(store: store, compact: true)
            } else {
                Group {
                    switch model.phase {
                    case .idle:
                        TaskInputCard(model: model, store: store)
                    case .countdown, .overtime:
                        ActiveTaskCard(model: model)
                    case .waiting:
                        WaitingCard(model: model)
                    case .wrapUp:
                        WrapUpCard(model: model)
                    }
                }
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

    private var anchorPrimaryText: String {
        if requiresDailyCheckIn { return "Daybreak" }
        return switch model.phase {
        case .countdown, .waiting, .overtime:
            model.activeTask?.title ?? anchorStatusText
        case .wrapUp:
            model.completedRecord?.title ?? "已结束"
        case .idle:
            "一隅"
        }
    }

    private var anchorStatusText: String {
        if requiresDailyCheckIn { return "待开启" }
        return switch model.phase {
        case .idle: "空闲"
        case .wrapUp: "待保存"
        case .countdown: "进行中"
        case .waiting: "到时"
        case .overtime: "继续中"
        }
    }

    private var anchorTint: Color {
        if requiresDailyCheckIn { return Color(nsColor: .systemIndigo) }
        return switch model.phase {
        case .idle, .wrapUp: Color(nsColor: .systemGray)
        case .countdown: Color(nsColor: .systemGreen)
        case .waiting: Color(nsColor: .systemYellow)
        case .overtime: Color(nsColor: .systemBlue)
        }
    }

    private var isTimerRunning: Bool {
        switch model.phase {
        case .countdown, .overtime: true
        case .idle, .waiting, .wrapUp: false
        }
    }

    private var anchorAccessibilityLabel: String {
        if requiresDailyCheckIn {
            return "一隅，等待完成每日回顾与今日确认"
        }
        if store.todoCount == 0 {
            return "一隅，\(model.statusText)，暂无待办"
        }
        return "一隅，\(model.statusText)，待办完成 \(store.completedTodoCount) / \(store.todoCount)"
    }

    private var requiresDailyCheckIn: Bool {
        model.phase == .idle && !store.isTodayConfirmed
    }
}

private struct TaskInputCard: View {
    let model: TaskSessionModel
    let store: RecordStore
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
    let isTimerRunning: Bool
    let timerStartedAt: Date?
    @State private var animationTrigger = 0

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let fillWidth = proxy.size.width * clampedProgress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.16))

                if isTimerRunning {
                    ActiveTimerProgressLine(
                        progress: clampedProgress,
                        animationEndsAt: timerStartedAt?.addingTimeInterval(3)
                    )
                } else if clampedProgress == 1 {
                    CompletionProgressLine(size: proxy.size, trigger: animationTrigger)
                } else if clampedProgress > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.22, green: 0.48, blue: 0.96),
                                    Color(red: 0.28, green: 0.75, blue: 0.96),
                                    Color(red: 0.40, green: 0.88, blue: 0.82)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)

                    ProgressPulseTrail(front: fillWidth, trigger: animationTrigger)
                }
            }
            .clipShape(Capsule())
            .animation(.spring(response: 0.35, dampingFraction: 0.78), value: clampedProgress)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
        .onChange(of: progress) { _, _ in
            animationTrigger += 1
        }
    }
}

private struct ActiveTimerProgressLine: View {
    private static let timerColors: [Color] = [
        Color(red: 0.18, green: 0.38, blue: 0.90),
        Color(red: 0.24, green: 0.70, blue: 0.98),
        Color(red: 0.46, green: 0.90, blue: 0.92),
        Color(red: 0.18, green: 0.38, blue: 0.90)
    ]

    private struct MovingDot: Identifiable {
        let id: Int
        let delay: CGFloat
        let size: CGFloat
    }

    private static let movingDots = [
        MovingDot(id: 0, delay: 0, size: 2.2),
        MovingDot(id: 1, delay: 0.29, size: 1.6),
        MovingDot(id: 2, delay: 0.61, size: 1.9)
    ]

    let progress: Double
    let animationEndsAt: Date?

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width * min(max(progress, 0), 1)
            if fillWidth > 0 {
                if let animationEndsAt, animationEndsAt > Date() {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                        let phase = Self.animationPhase(at: context.date)
                        ZStack(alignment: .leading) {
                            LinearGradient(
                                colors: Self.timerColors + Self.timerColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: fillWidth * 2)
                            .offset(x: -fillWidth * phase)

                            ForEach(Self.movingDots) { dot in
                                let position = (phase + dot.delay).truncatingRemainder(dividingBy: 1)
                                Circle()
                                    .fill(.white.opacity(0.78))
                                    .frame(width: dot.size, height: dot.size)
                                    .position(x: fillWidth * position, y: proxy.size.height / 2)
                            }
                        }
                        .frame(width: fillWidth, alignment: .leading)
                        .clipShape(Capsule())
                    }
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: Self.timerColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)
                }
            }
        }
    }

    private static func animationPhase(at date: Date) -> CGFloat {
        CGFloat((date.timeIntervalSinceReferenceDate / 2.4).truncatingRemainder(dividingBy: 1))
    }
}

private struct CompletionProgressLine: View {
    private static let completionColors: [Color] = [
        Color(red: 0.95, green: 0.24, blue: 0.37),
        Color(red: 0.99, green: 0.43, blue: 0.31),
        Color(red: 1.00, green: 0.67, blue: 0.24),
        Color(red: 0.98, green: 0.82, blue: 0.36),
        Color(red: 1.00, green: 0.54, blue: 0.29),
        Color(red: 0.95, green: 0.24, blue: 0.37)
    ]

    let size: CGSize
    let trigger: Int

    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: Self.completionColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.62), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size.width * 0.42)
                .keyframeAnimator(
                    initialValue: CompletionFlowValues(),
                    trigger: trigger
                ) { content, value in
                    content
                        .opacity(value.sweepOpacity)
                        .offset(x: size.width * value.sweepPosition)
                } keyframes: { _ in
                    KeyframeTrack(\.sweepPosition) {
                        MoveKeyframe(-0.7)
                        LinearKeyframe(1.1, duration: 0.64)
                    }
                    KeyframeTrack(\.sweepOpacity) {
                        MoveKeyframe(0)
                        CubicKeyframe(0.82, duration: 0.14)
                        CubicKeyframe(0, duration: 0.50)
                    }
                }

            CompletionSparkles(size: size)
                .keyframeAnimator(
                    initialValue: CompletionFlowValues(),
                    trigger: trigger
                ) { content, value in
                    content.opacity(value.sparkleOpacity)
                } keyframes: { _ in
                    KeyframeTrack(\.sparkleOpacity) {
                        CubicKeyframe(1, duration: 0.22)
                        CubicKeyframe(0.58, duration: 0.46)
                    }
                }

        }
        .frame(width: size.width, height: size.height)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.46), lineWidth: 0.5)
        }
    }
}

private struct CompletionFlowValues {
    var sweepPosition: CGFloat = -0.7
    var sweepOpacity = 0.0
    var sparkleOpacity = 0.58
}

private struct CompletionSparkles: View {
    private struct Sparkle: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let delay: Double
        let size: CGFloat
    }

    private static let sparkles: [Sparkle] = [
        Sparkle(id: 0, x: 0.12, y: 0.63, delay: 0.0, size: 1.6),
        Sparkle(id: 1, x: 0.26, y: 0.24, delay: 0.9, size: 2.1),
        Sparkle(id: 2, x: 0.39, y: 0.72, delay: 1.7, size: 1.5),
        Sparkle(id: 3, x: 0.52, y: 0.36, delay: 2.4, size: 2.2),
        Sparkle(id: 4, x: 0.65, y: 0.66, delay: 3.1, size: 1.6),
        Sparkle(id: 5, x: 0.75, y: 0.28, delay: 4.0, size: 1.9)
    ]

    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(Self.sparkles) { sparkle in
                Circle()
                    .fill(.white.opacity(0.58))
                    .frame(width: sparkle.size, height: sparkle.size)
                    .position(
                        x: size.width * sparkle.x,
                        y: size.height * sparkle.y
                    )
            }
        }
    }
}

private struct ProgressPulseTrail: View {
    let front: CGFloat
    let trigger: Int

    var body: some View {
        Color.clear
            .frame(width: 0, height: 12)
            .overlay {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 2.5, height: 2.5)
                        .offset(x: -10, y: -1.2)
                    Circle()
                        .fill(.white.opacity(0.82))
                        .frame(width: 2, height: 2)
                        .offset(x: -6, y: 0.8)
                    Circle()
                        .fill(.white.opacity(0.64))
                        .frame(width: 1.5, height: 1.5)
                        .offset(x: -2, y: -0.4)
                }
            }
            .offset(x: front - 14)
            .keyframeAnimator(
                initialValue: ProgressPulseValues(),
                trigger: trigger
            ) { content, value in
                content
                    .opacity(value.opacity)
                    .scaleEffect(value.scale, anchor: .leading)
                    .offset(x: value.travel)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.08)
                    LinearKeyframe(1, duration: 0.24)
                    CubicKeyframe(0, duration: 0.18)
                }
                KeyframeTrack(\.travel) {
                    LinearKeyframe(0, duration: 0.08)
                    CubicKeyframe(12, duration: 0.42)
                }
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1, duration: 0.12)
                    SpringKeyframe(0.82, duration: 0.38)
                }
            }
    }
}

private struct ProgressPulseValues {
    var opacity = 0.0
    var travel: CGFloat = 0
    var scale: CGFloat = 0.72
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
