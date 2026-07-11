import Foundation
import Observation

private struct SavedSession: Codable {
    var activeTask: ActiveTask?
    var draftTitle: String
    var draftMinutes: Int
}

@MainActor
@Observable
final class TaskSessionModel {
    private enum Keys {
        static let session = "savedSession"
    }

    private let store: RecordStore
    private var phaseTimer: Timer?
    private var refreshTimer: Timer?
    private var wrapUpDismissWorkItem: DispatchWorkItem?

    var phase: TaskPhase = .idle
    var activeTask: ActiveTask?
    var draftTitle: String
    var draftMinutes: Int
    var completedRecord: TaskRecord?
    var focusRequest = 0
    var isCardPresented = false

    var onPhaseChanged: ((TaskPhase) -> Void)?
    var onRequestCollapse: (() -> Void)?

    init(store: RecordStore) {
        self.store = store
        let session = Self.loadSession()
        self.activeTask = session.activeTask
        self.draftTitle = session.draftTitle
        self.draftMinutes = session.draftMinutes
        refreshPhase()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPhase()
            }
        }
    }

    var statusText: String {
        switch phase {
        case .idle: "空闲"
        case .countdown: "正在进行"
        case .waiting: "这段时间结束了"
        case .overtime: "仍在投入"
        case .wrapUp: "已完成"
        }
    }

    func start() {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, draftMinutes > 0 else { return }

        let now = Date()
        activeTask = ActiveTask(
            id: UUID(),
            title: trimmedTitle,
            plannedMinutes: draftMinutes,
            startedAt: now,
            plannedEndsAt: now.addingTimeInterval(TimeInterval(draftMinutes * 60))
        )
        draftTitle = ""
        persistSession()
        refreshPhase()
        onRequestCollapse?()
    }

    func finish(_ kind: FinishKind) {
        guard let activeTask else { return }
        guard store.ensureFolder() else { return }

        let completedAt = Date()
        let actualDuration = max(0, completedAt.timeIntervalSince(activeTask.startedAt))
        let additionalDuration = max(0, completedAt.timeIntervalSince(activeTask.plannedEndsAt))
        let record = TaskRecord(
            id: activeTask.id,
            title: activeTask.title,
            plannedMinutes: activeTask.plannedMinutes,
            startedAt: activeTask.startedAt,
            plannedEndsAt: activeTask.plannedEndsAt,
            completedAt: completedAt,
            actualDuration: actualDuration,
            continuedAfterPlan: additionalDuration > 0,
            additionalDuration: additionalDuration,
            note: "",
            finishKind: kind
        )

        do {
            try store.save(record)
        } catch {
            store.presentWriteError(error)
            return
        }

        self.activeTask = nil
        phaseTimer?.invalidate()
        persistSession()

        switch kind {
        case .completed:
            completedRecord = record
            setPhase(.wrapUp)
            scheduleEmptyWrapUpDismissal()
        case .nextTask:
            completedRecord = nil
            draftTitle = ""
            focusRequest += 1
            setPhase(.idle)
        }
    }

    func updateNote(_ note: String) {
        guard var record = completedRecord else { return }
        wrapUpDismissWorkItem?.cancel()
        record.note = note
        completedRecord = record
        do {
            try store.save(record)
        } catch {
            store.presentWriteError(error)
        }
    }

    func closeWrapUp() {
        wrapUpDismissWorkItem?.cancel()
        completedRecord = nil
        setPhase(.idle)
    }

    func fuzzyTimeText(now: Date = Date()) -> String {
        guard let activeTask else { return "" }
        let interval: TimeInterval
        let prefix: String
        switch phase {
        case .countdown:
            interval = max(0, activeTask.plannedEndsAt.timeIntervalSince(now))
            prefix = "剩余"
        case .overtime:
            interval = max(0, now.timeIntervalSince(activeTask.plannedEndsAt))
            prefix = "已继续"
        default:
            return ""
        }
        if interval < 60 { return "\(prefix)不到 1 分钟" }
        return "\(prefix)约 \(Int((interval / 60).rounded(.down))) 分钟"
    }

    func saveDraft() {
        guard phase == .idle else { return }
        persistSession()
    }

    private func refreshPhase() {
        guard let task = activeTask else {
            if phase != .wrapUp { setPhase(.idle) }
            return
        }
        let now = Date()
        if now < task.plannedEndsAt {
            setPhase(.countdown)
            schedulePhaseChange(at: task.plannedEndsAt)
        } else {
            let waitingEndsAt = task.plannedEndsAt.addingTimeInterval(10)
            if now < waitingEndsAt {
                setPhase(.waiting)
                schedulePhaseChange(at: waitingEndsAt)
            } else {
                setPhase(.overtime)
                phaseTimer?.invalidate()
            }
        }
    }

    private func setPhase(_ newPhase: TaskPhase) {
        guard phase != newPhase else { return }
        phase = newPhase
        onPhaseChanged?(newPhase)
    }

    private func schedulePhaseChange(at date: Date) {
        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: max(0.01, date.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPhase()
            }
        }
    }

    private func scheduleEmptyWrapUpDismissal() {
        let workItem = DispatchWorkItem { [weak self] in
            self?.completedRecord = nil
            self?.setPhase(.idle)
            self?.onRequestCollapse?()
        }
        wrapUpDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    private func persistSession() {
        let session = SavedSession(activeTask: activeTask, draftTitle: draftTitle, draftMinutes: draftMinutes)
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: Keys.session)
    }

    private static func loadSession() -> SavedSession {
        guard let data = UserDefaults.standard.data(forKey: Keys.session),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data) else {
            return SavedSession(activeTask: nil, draftTitle: "", draftMinutes: 25)
        }
        return session
    }
}
