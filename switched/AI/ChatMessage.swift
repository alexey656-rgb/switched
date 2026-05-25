import Foundation

/// One message in the AI assistant conversation. Persisted to disk so the
/// thread survives app restarts.
struct ChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant }

    /// A "parsed action" the AI is proposing (Direction A: AI proposes, user approves).
    /// Renders as a preview card with Add / Edit / Discard buttons until the user acts.
    struct Action: Equatable, Identifiable, Codable {
        enum Kind: Equatable, Codable {
            /// A new event the AI wants to add (not yet in the store).
            case createEvent(Event)
            /// A new task the AI wants to add (not yet in the store).
            case createTask(TaskItem)
            /// An edit the AI wants to apply. `after` is the proposed new state.
            case updateEvent(after: Event, before: Event)
            case updateTask(after: TaskItem, before: TaskItem)
            /// A row the AI wants to delete (still in the store at proposal time).
            case deleteEvent(Event)
            case deleteTask(TaskItem)
        }

        enum Status: String, Codable {
            case proposed   // initial — preview card shows Add/Edit/Discard
            case applied    // user tapped Add → executed
            case discarded  // user tapped Discard
        }

        var kind: Kind
        var status: Status = .proposed
        /// True if the user later tapped Undo on an applied action.
        var isUndone: Bool = false

        var id: String {
            switch kind {
            case .createEvent(let e):           return "ce-\(e.id.uuidString)"
            case .createTask(let t):            return "ct-\(t.id.uuidString)"
            case .updateEvent(_, let before):    return "ue-\(before.id.uuidString)"
            case .updateTask(_, let before):     return "ut-\(before.id.uuidString)"
            case .deleteEvent(let e):            return "de-\(e.id.uuidString)"
            case .deleteTask(let t):             return "dt-\(t.id.uuidString)"
            }
        }

        /// Display title for the preview card.
        var displayTitle: String {
            switch kind {
            case .createEvent(let e),
                 .updateEvent(let e, _),
                 .deleteEvent(let e):
                return e.title.isEmpty ? "Untitled" : e.title
            case .createTask(let t),
                 .updateTask(let t, _),
                 .deleteTask(let t):
                return t.title.isEmpty ? "Untitled" : t.title
            }
        }

        var isEvent: Bool {
            switch kind {
            case .createEvent, .updateEvent, .deleteEvent: true
            case .createTask, .updateTask, .deleteTask:    false
            }
        }

        var isDestructive: Bool {
            switch kind {
            case .deleteEvent, .deleteTask: true
            default: false
            }
        }
    }

    let id: UUID
    let role: Role
    var text: String
    var actions: [Action]
    let timestamp: Date

    init(role: Role, text: String, actions: [Action] = []) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.actions = actions
        self.timestamp = Date()
    }
}
