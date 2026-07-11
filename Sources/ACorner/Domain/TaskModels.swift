import Foundation

enum TaskPhase: String, Codable, Equatable {
    case idle
    case countdown
    case waiting
    case overtime
    case wrapUp
}

enum FinishKind: String, Codable, Equatable {
    case completed
    case nextTask
}

struct ActiveTask: Codable, Equatable {
    var id: UUID
    var title: String
    var plannedMinutes: Int
    var startedAt: Date
    var plannedEndsAt: Date
    var linkedTodoID: UUID? = nil
}

struct TaskRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var plannedMinutes: Int
    var startedAt: Date
    var plannedEndsAt: Date
    var completedAt: Date
    var actualDuration: TimeInterval
    var continuedAfterPlan: Bool
    var additionalDuration: TimeInterval
    var note: String
    var finishKind: FinishKind
    var linkedTodoID: UUID? = nil
}

struct TodoItem: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var completedAt: Date?

    var isCompleted: Bool { completedAt != nil }
}

enum TodoProgress {
    static func fraction(for todos: [TodoItem]) -> Double {
        guard !todos.isEmpty else { return 0 }
        let completedCount = todos.count { $0.isCompleted }
        return Double(completedCount) / Double(todos.count)
    }
}
