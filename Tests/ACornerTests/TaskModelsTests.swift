import Foundation
import Testing
@testable import ACorner

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
