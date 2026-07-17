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

struct HourlyCheckIn: Codable, Identifiable, Equatable {
    var id: UUID
    var scheduledAt: Date
    var recordedAt: Date
    var note: String
}

struct TaskRecordDay: Identifiable, Equatable {
    var id: String
    var title: String
    var records: [TaskRecord]
}

struct TodoItem: Codable, Identifiable, Equatable {
    var id: UUID
    var lineageID: UUID
    var title: String
    var createdAt: Date
    var completedAt: Date?

    var isCompleted: Bool { completedAt != nil }

    init(
        id: UUID,
        title: String,
        createdAt: Date,
        completedAt: Date?,
        lineageID: UUID? = nil
    ) {
        self.id = id
        self.lineageID = lineageID ?? id
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

struct PastTodoItem: Identifiable, Equatable {
    var id: UUID
    var lineageID: UUID
    var title: String
    var sourceDayKey: String
    var createdAt: Date
}

struct DailyTodoPlan: Codable, Equatable {
    var confirmedAt: Date?
    var todos: [TodoItem]
    var carriedYesterdayTodoIDs: [UUID]

    init(
        confirmedAt: Date? = nil,
        todos: [TodoItem] = [],
        carriedYesterdayTodoIDs: [UUID] = []
    ) {
        self.confirmedAt = confirmedAt
        self.todos = todos
        self.carriedYesterdayTodoIDs = carriedYesterdayTodoIDs
    }
}

struct DeadlineItem: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var dueDate: Date
    var completedAt: Date?

    var isCompleted: Bool { completedAt != nil }
}

enum DeadlineTiming: Equatable {
    case upcoming
    case today
    case pending

    static func status(for deadline: DeadlineItem, now: Date = Date(), calendar: Calendar = .current) -> DeadlineTiming {
        let deadlineDay = calendar.startOfDay(for: deadline.dueDate)
        let today = calendar.startOfDay(for: now)
        if deadlineDay < today { return .pending }
        if calendar.isDate(deadlineDay, inSameDayAs: today) { return .today }
        return .upcoming
    }
}

extension DeadlineItem {
    func dueText(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch DeadlineTiming.status(for: self, now: now, calendar: calendar) {
        case .today:
            "今天截止"
        case .pending:
            "仍待处理"
        case .upcoming:
            dueDate.formatted(.dateTime.month().day()) + " 截止"
        }
    }
}

enum DailyPlanCalendar {
    static let refreshHour = 3

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let businessDate = calendar.date(byAdding: .hour, value: -refreshHour, to: date)!
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: businessDate)
    }

    static func previousDayKey(for date: Date, calendar: Calendar = .current) -> String {
        let previousDate = calendar.date(byAdding: .day, value: -1, to: date)!
        return dayKey(for: previousDate, calendar: calendar)
    }

    static func nextRefresh(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: refreshHour, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
    }

    static func nextHour(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: date,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
    }
}

enum TodoProgress {
    static func fraction(for todos: [TodoItem]) -> Double {
        guard !todos.isEmpty else { return 0 }
        let completedCount = todos.count { $0.isCompleted }
        return Double(completedCount) / Double(todos.count)
    }
}
