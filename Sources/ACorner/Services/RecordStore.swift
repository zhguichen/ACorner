import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class RecordStore {
    private enum Keys {
        static let folderBookmark = "recordsFolderBookmark"
    }

    private enum FileName {
        static func todos(for dayKey: String) -> String {
            "ACornerTodos-\(dayKey).json"
        }
    }

    private(set) var folderURL: URL?
    private(set) var records: [TaskRecord] = []
    private(set) var todos: [TodoItem] = []
    private(set) var yesterdayTodos: [TodoItem] = []
    private(set) var carriedYesterdayTodoIDs: [UUID] = []
    private(set) var todayDayKey = DailyPlanCalendar.dayKey(for: Date())
    private(set) var isTodayConfirmed = false
    private var todayConfirmedAt: Date?
    private var dailyRefreshTimer: Timer?

    init() {
        if let bookmark = UserDefaults.standard.data(forKey: Keys.folderBookmark) {
            var isStale = false
            folderURL = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        }
        reloadRecords()
        reloadDailyPlans()
        scheduleDailyRefresh()
    }

    init(folderURL: URL) {
        self.folderURL = folderURL
        reloadRecords()
        reloadDailyPlans()
        scheduleDailyRefresh()
    }

    var folderDisplayName: String? { folderURL?.path }
    var completedRecords: [TaskRecord] {
        records.sorted { $0.completedAt > $1.completedAt }
    }
    var recordDays: [TaskRecordDay] {
        Dictionary(grouping: completedRecords, by: { Self.dayKey(for: $0.completedAt) })
            .map { key, records in
                TaskRecordDay(
                    id: key,
                    title: Self.dayTitle(for: records.first?.completedAt ?? Date()),
                    records: records.sorted { $0.completedAt > $1.completedAt }
                )
            }
            .sorted { $0.id > $1.id }
    }
    var todoCount: Int { todos.count }
    var completedTodoCount: Int { todos.filter(\.isCompleted).count }
    var todoProgress: Double { TodoProgress.fraction(for: todos) }
    var pendingTodos: [TodoItem] {
        todos
            .filter { !$0.isCompleted }
            .sorted { $0.createdAt < $1.createdAt }
    }
    var completedTodos: [TodoItem] {
        todos
            .filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
    var yesterdayCompletedTodos: [TodoItem] {
        yesterdayTodos
            .filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
    var yesterdayPendingTodos: [TodoItem] {
        yesterdayTodos
            .filter { !$0.isCompleted }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func ensureFolder() -> Bool {
        folderURL != nil || selectFolder()
    }

    @discardableResult
    func selectFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "选择一隅的记录保存位置"
        panel.message = "任务记录会持续保存在此文件夹中。"
        panel.prompt = "选择此文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        folderURL = url
        if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: Keys.folderBookmark)
        }
        reloadRecords()
        reloadDailyPlans()
        return true
    }

    func save(_ record: TaskRecord) throws {
        guard let folderURL else { return }
        let url = recordFileURL(for: record.completedAt, in: folderURL)
        var updatedRecords = try loadRecords(from: url)
        if let index = updatedRecords.firstIndex(where: { $0.id == record.id }) {
            updatedRecords[index] = record
        } else {
            updatedRecords.append(record)
        }
        updatedRecords.sort { $0.startedAt > $1.startedAt }
        try saveRecords(updatedRecords, to: url)
        reloadRecords()
    }

    func removeRecord(_ record: TaskRecord) {
        guard let folderURL else { return }
        let url = recordFileURL(for: record.completedAt, in: folderURL)

        do {
            var updatedRecords = try loadRecords(from: url)
            let originalCount = updatedRecords.count
            updatedRecords.removeAll { $0.id == record.id }
            guard updatedRecords.count != originalCount else { return }

            if updatedRecords.isEmpty {
                try FileManager.default.removeItem(at: url)
            } else {
                try saveRecords(updatedRecords, to: url)
            }
            reloadRecords()
        } catch {
            presentWriteError(error)
        }
    }

    func presentWriteError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.informativeText = "一隅无法写入本地数据。请在设置中确认保存位置后重试。"
        alert.runModal()
    }

    func addTodo(title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, let folderURL else { return }
        refreshDayIfNeeded()
        mutateTodayPlan(in: folderURL) { plan in
            plan.todos.append(TodoItem(id: UUID(), title: trimmedTitle, createdAt: Date(), completedAt: nil))
        }
    }

    func setTodoCompleted(id: UUID, isCompleted: Bool) {
        guard let folderURL else { return }
        refreshDayIfNeeded()
        mutateTodayPlan(in: folderURL) { plan in
            guard let index = plan.todos.firstIndex(where: { $0.id == id }) else { return }
            plan.todos[index].completedAt = isCompleted ? Date() : nil
        }
    }

    func removeTodo(id: UUID) {
        guard let folderURL else { return }
        refreshDayIfNeeded()
        mutateTodayPlan(in: folderURL) { plan in
            plan.todos.removeAll { $0.id == id }
        }
    }

    func carryYesterdayTodo(id: UUID) {
        guard let folderURL else { return }
        refreshDayIfNeeded()
        guard !carriedYesterdayTodoIDs.contains(id),
              let todo = yesterdayPendingTodos.first(where: { $0.id == id }) else { return }
        mutateTodayPlan(in: folderURL) { plan in
            plan.todos.append(TodoItem(id: UUID(), title: todo.title, createdAt: Date(), completedAt: nil))
            plan.carriedYesterdayTodoIDs.append(id)
        }
    }

    func confirmToday() {
        guard let folderURL else { return }
        refreshDayIfNeeded()
        mutateTodayPlan(in: folderURL) { plan in
            plan.confirmedAt = Date()
        }
    }

    func pendingTodo(matchingTitle title: String) -> TodoItem? {
        refreshDayIfNeeded()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        return pendingTodos.first { $0.title == trimmedTitle }
    }

    func refreshDayIfNeeded(now: Date = Date()) {
        let newDayKey = DailyPlanCalendar.dayKey(for: now)
        guard newDayKey != todayDayKey else { return }
        todayDayKey = newDayKey
        reloadDailyPlans()
        scheduleDailyRefresh()
    }

    private func loadRecords(from url: URL) throws -> [TaskRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TaskRecord].self, from: Data(contentsOf: url))
    }

    private func saveRecords(_ records: [TaskRecord], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: url, options: .atomic)
    }

    private func reloadRecords() {
        guard let folderURL else {
            records = []
            return
        }
        do {
            let recordFiles = try FileManager.default
                .contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("ACornerTasks-") && $0.pathExtension == "json" }
            records = try recordFiles
                .flatMap { try loadRecords(from: $0) }
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            records = []
            presentWriteError(error)
        }
    }

    private func recordFileURL(for date: Date, in folderURL: URL) -> URL {
        folderURL.appendingPathComponent("ACornerTasks-\(Self.dayKey(for: date)).json")
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func dayTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    private func reloadDailyPlans() {
        guard let folderURL else {
            todos = []
            yesterdayTodos = []
            carriedYesterdayTodoIDs = []
            isTodayConfirmed = false
            todayConfirmedAt = nil
            return
        }
        do {
            let todayPlan = try loadTodoPlan(from: todoPlanURL(for: todayDayKey, in: folderURL))
            let yesterdayPlan = try loadTodoPlan(
                from: todoPlanURL(for: DailyPlanCalendar.previousDayKey(for: Date()), in: folderURL)
            )
            todos = todayPlan.todos
            yesterdayTodos = yesterdayPlan.todos
            carriedYesterdayTodoIDs = todayPlan.carriedYesterdayTodoIDs
            isTodayConfirmed = todayPlan.confirmedAt != nil
            todayConfirmedAt = todayPlan.confirmedAt
        } catch {
            todos = []
            yesterdayTodos = []
            carriedYesterdayTodoIDs = []
            isTodayConfirmed = false
            todayConfirmedAt = nil
            presentWriteError(error)
        }
    }

    private func mutateTodayPlan(in folderURL: URL, update: (inout DailyTodoPlan) -> Void) {
        var plan = DailyTodoPlan(
            confirmedAt: todayConfirmedAt,
            todos: todos,
            carriedYesterdayTodoIDs: carriedYesterdayTodoIDs
        )
        update(&plan)
        do {
            try saveTodoPlan(plan, to: todoPlanURL(for: todayDayKey, in: folderURL))
            todos = plan.todos
            carriedYesterdayTodoIDs = plan.carriedYesterdayTodoIDs
            isTodayConfirmed = plan.confirmedAt != nil
            todayConfirmedAt = plan.confirmedAt
        } catch {
            presentWriteError(error)
        }
    }

    private func loadTodoPlan(from url: URL) throws -> DailyTodoPlan {
        guard FileManager.default.fileExists(atPath: url.path) else { return DailyTodoPlan() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DailyTodoPlan.self, from: Data(contentsOf: url))
    }

    private func saveTodoPlan(_ plan: DailyTodoPlan, to url: URL) throws {
        var sortedPlan = plan
        sortedPlan.todos.sort { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            if lhs.isCompleted {
                return (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
            }
            return lhs.createdAt < rhs.createdAt
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sortedPlan).write(to: url, options: .atomic)
    }

    private func todoPlanURL(for dayKey: String, in folderURL: URL) -> URL {
        folderURL.appendingPathComponent(FileName.todos(for: dayKey))
    }

    private func scheduleDailyRefresh() {
        dailyRefreshTimer?.invalidate()
        guard let nextRefresh = DailyPlanCalendar.nextRefresh(after: Date()) else { return }
        dailyRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: max(1, nextRefresh.timeIntervalSinceNow),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDayIfNeeded()
            }
        }
    }
}
