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
