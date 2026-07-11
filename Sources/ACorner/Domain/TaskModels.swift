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
}
