import Foundation

struct TaskItem: Identifiable, Codable, Hashable {
    enum Scope: String, Codable, CaseIterable, Identifiable {
        case today
        case week

        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: "Today"
            case .week:  "This Week"
            }
        }
    }

    enum Priority: String, Codable, CaseIterable, Identifiable {
        case none, low, med, high

        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: "None"
            case .low:  "Low"
            case .med:  "Med"
            case .high: "High"
            }
        }
        var flag: String {
            switch self {
            case .none: ""
            case .low:  "!"
            case .med:  "!!"
            case .high: "!!!"
            }
        }
        var weight: Int {
            switch self {
            case .none: 0
            case .low:  1
            case .med:  2
            case .high: 3
            }
        }
    }

    let id: UUID
    var title: String
    var notes: String
    var isCompleted: Bool
    /// Legacy bucket. Kept for older saves; new code uses `scheduledDate`.
    var scope: Scope
    var priority: Priority
    /// Hard deadline. "Must be done BY".
    var dueDate: Date?
    /// The day this task is planned to be done. nil = backlog / unscheduled.
    /// Stored as start-of-day in local timezone.
    var scheduledDate: Date?
    var createdAt: Date

    /// Date the task was last placed in its current slot. Used for automatic rollover.
    var lastMovedAt: Date

    /// Transient UI flag, set when the task was automatically rolled forward. Cleared on check/edit.
    var rolledOver: Bool

    init(
        id: UUID = UUID(),
        title: String = "",
        notes: String = "",
        isCompleted: Bool = false,
        scope: Scope = .today,
        priority: Priority = .none,
        dueDate: Date? = nil,
        scheduledDate: Date? = nil,
        createdAt: Date = .now,
        lastMovedAt: Date = .now,
        rolledOver: Bool = false
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.scope = scope
        self.priority = priority
        self.dueDate = dueDate
        self.scheduledDate = scheduledDate
        self.createdAt = createdAt
        self.lastMovedAt = lastMovedAt
        self.rolledOver = rolledOver
    }
}
