import Foundation
import Testing
@testable import ACorner

private struct LegacyTodoFixture: Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var completedAt: Date?
}

private struct LegacyDailyPlanFixture: Codable {
    var confirmedAt: Date?
    var todos: [LegacyTodoFixture]
    var carriedYesterdayTodoIDs: [UUID]
}

@Test("计划时长始终限制在 1 到 180 分钟")
@MainActor
func plannedMinutesAreClampedToSupportedRange() {
    #expect(TaskSessionModel.normalizedPlannedMinutes(0) == 1)
    #expect(TaskSessionModel.normalizedPlannedMinutes(1) == 1)
    #expect(TaskSessionModel.normalizedPlannedMinutes(180) == 180)
    #expect(TaskSessionModel.normalizedPlannedMinutes(181) == 180)
}

@Test("任务记录可稳定编码与解码")
func taskRecordRoundTrip() throws {
    let linkedTodoID = UUID()
    let record = TaskRecord(
        id: UUID(),
        title: "整理开发说明",
        plannedMinutes: 25,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        plannedEndsAt: Date(timeIntervalSince1970: 1_700_001_500),
        completedAt: Date(timeIntervalSince1970: 1_700_001_800),
        actualDuration: 1_800,
        continuedAfterPlan: true,
        additionalDuration: 300,
        note: "补充了测试文档。",
        finishKind: .completed,
        linkedTodoID: linkedTodoID
    )

    let data = try JSONEncoder().encode(record)
    let restored = try JSONDecoder().decode(TaskRecord.self, from: data)

    #expect(restored == record)
    #expect(restored.linkedTodoID == linkedTodoID)
}

@Test("整点记录可稳定编码与解码")
func hourlyCheckInRoundTrip() throws {
    let checkIn = HourlyCheckIn(
        id: UUID(),
        scheduledAt: Date(timeIntervalSince1970: 1_700_100_000),
        recordedAt: Date(timeIntervalSince1970: 1_700_100_045),
        note: "在整理开发说明。"
    )

    let data = try JSONEncoder().encode(checkIn)
    let restored = try JSONDecoder().decode(HourlyCheckIn.self, from: data)

    #expect(restored == checkIn)
}

@Test("待办事项可稳定编码与解码")
func todoItemRoundTrip() throws {
    let todo = TodoItem(
        id: UUID(),
        title: "整理首页长条交互",
        createdAt: Date(timeIntervalSince1970: 1_700_010_000),
        completedAt: Date(timeIntervalSince1970: 1_700_010_900)
    )

    let data = try JSONEncoder().encode(todo)
    let restored = try JSONDecoder().decode(TodoItem.self, from: data)

    #expect(restored == todo)
    #expect(restored.isCompleted)
}

@Test("每日待办计划可稳定编码与解码")
func dailyTodoPlanRoundTrip() throws {
    let carriedID = UUID()
    let plan = DailyTodoPlan(
        confirmedAt: Date(timeIntervalSince1970: 1_700_020_000),
        todos: [
            TodoItem(id: UUID(), title: "写下今天的待办", createdAt: .now, completedAt: nil)
        ],
        carriedYesterdayTodoIDs: [carriedID]
    )

    let data = try JSONEncoder().encode(plan)
    let restored = try JSONDecoder().decode(DailyTodoPlan.self, from: data)

    #expect(restored == plan)
}

@Test("每日待办在凌晨三点切换")
func dailyPlanDayChangesAtThreeAM() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let beforeRefresh = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 2, minute: 59))!
    let afterRefresh = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 3, minute: 0))!

    #expect(DailyPlanCalendar.dayKey(for: beforeRefresh, calendar: calendar) == "2026-07-11")
    #expect(DailyPlanCalendar.dayKey(for: afterRefresh, calendar: calendar) == "2026-07-12")
    #expect(DailyPlanCalendar.previousDayKey(for: afterRefresh, calendar: calendar) == "2026-07-11")
}

@Test("下一个整点始终按自然整点计算")
func nextHourUsesNaturalHourBoundary() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 10, minute: 42, second: 18))!
    let nextHour = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 11))!

    #expect(DailyPlanCalendar.nextHour(after: now, calendar: calendar) == nextHour)
}

@Test("期限事项会区分未来、今天和仍待处理")
func deadlineTimingUsesCalendarDays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 10))!
    let yesterday = DeadlineItem(
        id: UUID(),
        title: "昨天截止",
        dueDate: calendar.date(byAdding: .day, value: -1, to: now)!,
        completedAt: nil
    )
    let today = DeadlineItem(id: UUID(), title: "今天截止", dueDate: now, completedAt: nil)
    let tomorrow = DeadlineItem(
        id: UUID(),
        title: "明天截止",
        dueDate: calendar.date(byAdding: .day, value: 1, to: now)!,
        completedAt: nil
    )

    #expect(DeadlineTiming.status(for: yesterday, now: now, calendar: calendar) == .pending)
    #expect(DeadlineTiming.status(for: today, now: now, calendar: calendar) == .today)
    #expect(DeadlineTiming.status(for: tomorrow, now: now, calendar: calendar) == .upcoming)
}

@Test("确认今天会写入当天的待办计划")
@MainActor
func confirmingTodayWritesDailyTodoPlan() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ACornerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let store = RecordStore(folderURL: folder)
    store.addTodo(title: "为今天留一隅")
    #expect(!store.isTodayConfirmed)

    store.confirmToday()

    let planURL = folder.appendingPathComponent("ACornerTodos-\(DailyPlanCalendar.dayKey(for: Date())).json")
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let plan = try decoder.decode(DailyTodoPlan.self, from: Data(contentsOf: planURL))
    #expect(store.isTodayConfirmed)
    #expect(plan.confirmedAt != nil)
    #expect(plan.todos.map(\.title) == ["为今天留一隅"])
}

@Test("期限事项会写入独立本地文件")
@MainActor
func deadlineWritesToLocalFile() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ACornerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let store = RecordStore(folderURL: folder)
    let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
    store.addDeadline(title: "作业提交", dueDate: dueDate)

    let data = try Data(contentsOf: folder.appendingPathComponent("ACornerDeadlines.json"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let deadlines = try decoder.decode([DeadlineItem].self, from: data)
    #expect(deadlines.map(\.title) == ["作业提交"])
    #expect(deadlines.first?.dueDate == dueDate)
}

@Test("整点记录按凌晨三点定义的一天写入本地文件")
@MainActor
func hourlyCheckInWritesToBusinessDayFile() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ACornerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let calendar = Calendar.current
    let today = Date()
    let scheduledAt = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: today)!
    let checkIn = HourlyCheckIn(
        id: UUID(),
        scheduledAt: scheduledAt,
        recordedAt: scheduledAt.addingTimeInterval(20),
        note: "阅读资料"
    )
    let store = RecordStore(folderURL: folder)

    try store.save(checkIn)

    let dayKey = DailyPlanCalendar.dayKey(for: scheduledAt, calendar: calendar)
    let data = try Data(contentsOf: folder.appendingPathComponent("ACornerCheckIns-\(dayKey).json"))
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let savedCheckIns = try decoder.decode([HourlyCheckIn].self, from: data)
    #expect(savedCheckIns == [checkIn])
}

@Test("过去未完成待办可加入今天且保留原记录")
@MainActor
func pastPendingTodoCanBeAddedToToday() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ACornerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let pastTodo = TodoItem(id: UUID(), title: "补交作业", createdAt: .now, completedAt: nil)
    let pastPlan = DailyTodoPlan(todos: [pastTodo])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let pastDayKey = DailyPlanCalendar.previousDayKey(for: Date())
    let pastURL = folder.appendingPathComponent("ACornerTodos-\(pastDayKey).json")
    try encoder.encode(pastPlan).write(to: pastURL)

    let store = RecordStore(folderURL: folder)
    #expect(store.pastPendingTodos.map(\.title) == ["补交作业"])

    store.addPastTodo(id: pastTodo.id)

    #expect(store.pendingTodos.map(\.title) == ["补交作业"])
    #expect(store.pastPendingTodos.isEmpty)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let restoredPastPlan = try decoder.decode(DailyTodoPlan.self, from: Data(contentsOf: pastURL))
    #expect(restoredPastPlan.todos.count == 1)
    #expect(restoredPastPlan.todos.first?.id == pastTodo.id)
    #expect(restoredPastPlan.todos.first?.title == pastTodo.title)
    #expect(restoredPastPlan.todos.first?.completedAt == nil)
}

@Test("同一待办跨日带入时只保留一个未完成入口")
@MainActor
func carriedTodoUsesOneLineageAcrossDays() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ACornerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let originalID = UUID()
    let lineageID = UUID()
    let carriedID = UUID()
    let original = TodoItem(
        id: originalID,
        title: "继续整理提案",
        createdAt: .now,
        completedAt: nil,
        lineageID: lineageID
    )
    let carried = TodoItem(
        id: carriedID,
        title: "继续整理提案",
        createdAt: .now,
        completedAt: nil,
        lineageID: lineageID
    )
    let calendar = Calendar.current
    let olderDate = calendar.date(byAdding: .day, value: -1, to: Date())!
    let olderDayKey = DailyPlanCalendar.previousDayKey(for: olderDate)
    let yesterdayDayKey = DailyPlanCalendar.previousDayKey(for: Date())
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(DailyTodoPlan(todos: [original])).write(
        to: folder.appendingPathComponent("ACornerTodos-\(olderDayKey).json")
    )
    try encoder.encode(DailyTodoPlan(todos: [carried])).write(
        to: folder.appendingPathComponent("ACornerTodos-\(yesterdayDayKey).json")
    )

    let store = RecordStore(folderURL: folder)
    #expect(store.pastPendingTodos.count == 1)
    #expect(store.pastPendingTodos.first?.id == carriedID)

    store.addPastTodo(id: carriedID)
    store.addPastTodo(id: carriedID)
    #expect(store.pendingTodos.count == 1)
    #expect(store.pendingTodos.first?.lineageID == lineageID)
    #expect(store.pastPendingTodos.isEmpty)

    store.setTodoCompleted(id: store.pendingTodos[0].id, isCompleted: true)
    #expect(store.pastPendingTodos.isEmpty)
}

@Test("旧版每日待办会迁移为带脉络标识的新结构")
@MainActor
func legacyDailyPlanIsMigratedWithBackup() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ACornerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let legacyTodo = LegacyTodoFixture(id: UUID(), title: "旧待办", createdAt: .now, completedAt: nil)
    let legacyPlan = LegacyDailyPlanFixture(confirmedAt: nil, todos: [legacyTodo], carriedYesterdayTodoIDs: [])
    let dayKey = DailyPlanCalendar.previousDayKey(for: Date())
    let planURL = folder.appendingPathComponent("ACornerTodos-\(dayKey).json")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(legacyPlan).write(to: planURL)

    _ = RecordStore(folderURL: folder)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let migratedPlan = try decoder.decode(DailyTodoPlan.self, from: Data(contentsOf: planURL))
    #expect(migratedPlan.todos.first?.lineageID == legacyTodo.id)
    #expect(FileManager.default.fileExists(atPath: planURL.appendingPathExtension("backup-v1").path))
}

@Test("删除过去未完成会移除所有日期的未完成副本")
@MainActor
func deletingPastTodoLineageRemovesAllPendingCopies() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ACornerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let lineageID = UUID()
    let original = TodoItem(id: UUID(), title: "放弃的事项", createdAt: .now, completedAt: nil, lineageID: lineageID)
    let carried = TodoItem(id: UUID(), title: "放弃的事项", createdAt: .now, completedAt: nil, lineageID: lineageID)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let calendar = Calendar.current
    let olderDate = calendar.date(byAdding: .day, value: -1, to: Date())!
    let olderURL = folder.appendingPathComponent(
        "ACornerTodos-\(DailyPlanCalendar.previousDayKey(for: olderDate)).json"
    )
    let yesterdayURL = folder.appendingPathComponent(
        "ACornerTodos-\(DailyPlanCalendar.previousDayKey(for: Date())).json"
    )
    try encoder.encode(DailyTodoPlan(todos: [original])).write(to: olderURL)
    try encoder.encode(DailyTodoPlan(todos: [carried])).write(to: yesterdayURL)

    let store = RecordStore(folderURL: folder)
    store.deletePastTodoLineage(id: carried.id)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let olderPlan = try decoder.decode(DailyTodoPlan.self, from: Data(contentsOf: olderURL))
    let yesterdayPlan = try decoder.decode(DailyTodoPlan.self, from: Data(contentsOf: yesterdayURL))
    #expect(store.pastPendingTodos.isEmpty)
    #expect(olderPlan.todos.isEmpty)
    #expect(yesterdayPlan.todos.isEmpty)
}

@Test("待办完成度按已完成数量计算")
func todoProgressMatchesCompletedFraction() {
    let todos = [
        TodoItem(id: UUID(), title: "A", createdAt: .now, completedAt: nil),
        TodoItem(id: UUID(), title: "B", createdAt: .now, completedAt: .now),
        TodoItem(id: UUID(), title: "C", createdAt: .now, completedAt: .now)
    ]

    #expect(TodoProgress.fraction(for: []) == 0)
    #expect(TodoProgress.fraction(for: todos) == 2.0 / 3.0)
}

@Test("删除完成记录会同步移除当天的本地文件")
@MainActor
func deletingOnlyRecordRemovesDailyFile() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ACornerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let store = RecordStore(folderURL: folder)
    let record = TaskRecord(
        id: UUID(),
        title: "删除测试",
        plannedMinutes: 25,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        plannedEndsAt: Date(timeIntervalSince1970: 1_700_001_500),
        completedAt: Date(timeIntervalSince1970: 1_700_001_800),
        actualDuration: 1_800,
        continuedAfterPlan: false,
        additionalDuration: 0,
        note: "",
        finishKind: .completed
    )

    try store.save(record)
    #expect(store.records == [record])

    store.removeRecord(record)

    #expect(store.records.isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
}
