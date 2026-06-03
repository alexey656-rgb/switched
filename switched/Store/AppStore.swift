import Foundation
import Observation

@Observable
final class AppStore {
    var events: [Event] = []
    var tasks: [TaskItem] = []

    /// AI conversation thread. Stays local-only — too big and noisy for KVS,
    /// and there's no real value in syncing chat history right now.
    var chatHistory: [ChatMessage] = []

    private let eventsKey = "switched.events.v3"
    private let tasksKey  = "switched.tasks.v2"
    private let chatKey   = "switched.chat.v1"
    /// Cap stored history to keep storage size sane.
    private let maxChatHistory = 500

    /// iCloud Key-Value Store. Mirrors `events` and `tasks` to Apple's
    /// per-user iCloud KVS so they sync across iPhone / iPad / Mac
    /// automatically. 1 MB total budget — plenty for typical usage.
    private let kvs = NSUbiquitousKeyValueStore.default
    /// Suppresses save-back-to-kvs while we're applying a remote change,
    /// otherwise the device that received the update echoes it back.
    private var applyingRemote = false

    init() {
        load()
        migrateLegacyTasks()
        rolloverTasks(now: Date())
        startICloudObservation()
        // Ask iCloud to send us anything newer than what we have on disk.
        kvs.synchronize()
    }

    // MARK: - iCloud sync

    private func startICloudObservation() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs,
            queue: .main
        ) { [weak self] note in
            self?.handleICloudChange(note)
        }
    }

    private func handleICloudChange(_ note: Notification) {
        let userInfo = note.userInfo ?? [:]
        let reason = (userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int) ?? -1

        switch reason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            // Normal incoming change from another device, or the initial
            // hand-off after enabling iCloud. Apply whatever keys changed.
            let keys = (userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
            applyRemoteKeys(keys)

        case NSUbiquitousKeyValueStoreAccountChange:
            // User signed in/out of iCloud, or switched account. Re-read
            // everything from KVS (it has the new account's values) and
            // overwrite local cache. Local-only chat history is preserved.
            applyRemoteKeys([eventsKey, tasksKey])

        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            // Over the 1 MB iCloud KVS budget. Skip the sync, log loudly
            // so it shows up in console during testing. Future: migrate
            // to CloudKit when this fires for real users.
            print("⚠️ Switched: iCloud KVS quota exceeded — sync paused")

        default:
            // Unknown reason code — be conservative and re-pull everything.
            applyRemoteKeys([eventsKey, tasksKey])
        }
    }

    private func applyRemoteKeys(_ keys: [String]) {
        applyingRemote = true
        defer { applyingRemote = false }

        if keys.contains(eventsKey),
           let data = kvs.data(forKey: eventsKey),
           let decoded = try? JSONDecoder().decode([Event].self, from: data) {
            events = decoded
            UserDefaults.standard.set(data, forKey: eventsKey)
        }
        if keys.contains(tasksKey),
           let data = kvs.data(forKey: tasksKey),
           let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
            tasks = decoded
            UserDefaults.standard.set(data, forKey: tasksKey)
        }
    }

    // MARK: - Chat history

    func appendChatMessage(_ msg: ChatMessage) {
        chatHistory.append(msg)
        if chatHistory.count > maxChatHistory {
            chatHistory.removeFirst(chatHistory.count - maxChatHistory)
        }
        saveChat()
    }

    func clearChatHistory() {
        chatHistory = []
        saveChat()
    }

    /// Update the status of a previously-proposed action in chat history.
    func setActionStatus(messageId: UUID, actionId: String, status: ChatMessage.Action.Status, isUndone: Bool? = nil) {
        guard let mi = chatHistory.firstIndex(where: { $0.id == messageId }) else { return }
        guard let ai = chatHistory[mi].actions.firstIndex(where: { $0.id == actionId }) else { return }
        chatHistory[mi].actions[ai].status = status
        if let u = isUndone { chatHistory[mi].actions[ai].isUndone = u }
        saveChat()
    }

    /// Execute a proposed action. Adds/updates/deletes the underlying row.
    /// Returns true on success — caller should then transition the action's status.
    @discardableResult
    func apply(_ action: ChatMessage.Action) -> Bool {
        switch action.kind {
        case .createEvent(let event):
            // Guard against double-apply.
            guard !events.contains(where: { $0.id == event.id }) else { return false }
            addEvent(event)
            return true
        case .createTask(let task):
            guard !tasks.contains(where: { $0.id == task.id }) else { return false }
            addTask(task)
            return true
        case .updateEvent(let after, _):
            guard events.contains(where: { $0.id == after.id }) else { return false }
            updateEvent(after)
            return true
        case .updateTask(let after, _):
            guard tasks.contains(where: { $0.id == after.id }) else { return false }
            updateTask(after)
            return true
        case .deleteEvent(let target):
            guard events.contains(where: { $0.id == target.id }) else { return false }
            deleteEvent(target)
            return true
        case .deleteTask(let target):
            guard tasks.contains(where: { $0.id == target.id }) else { return false }
            deleteTask(target)
            return true
        }
    }

    /// Reverse an applied chat action. Returns true if the undo was applied.
    @discardableResult
    func undo(_ action: ChatMessage.Action) -> Bool {
        switch action.kind {
        case .createEvent(let event):
            if let ev = events.first(where: { $0.id == event.id }) {
                deleteEvent(ev)
                return true
            }
        case .createTask(let task):
            if let t = tasks.first(where: { $0.id == task.id }) {
                deleteTask(t)
                return true
            }
        case .updateEvent(_, let before):
            if events.contains(where: { $0.id == before.id }) {
                updateEvent(before)
                return true
            }
        case .updateTask(_, let before):
            if tasks.contains(where: { $0.id == before.id }) {
                updateTask(before)
                return true
            }
        case .deleteEvent(let target):
            if !events.contains(where: { $0.id == target.id }) {
                addEvent(target)
                return true
            }
        case .deleteTask(let target):
            if !tasks.contains(where: { $0.id == target.id }) {
                addTask(target)
                return true
            }
        }
        return false
    }

    /// One-time migration: tasks saved before the weekly view existed only had
    /// `scope` (today / week). Give them a `scheduledDate` so they show up in
    /// the new week view. `today` => today. `week` => unscheduled (backlog),
    /// so the user can drag them onto days as they plan.
    private func migrateLegacyTasks() {
        let todayStart = Calendar.current.startOfDay(for: Date())
        var didChange = false
        for idx in tasks.indices where tasks[idx].scheduledDate == nil {
            if tasks[idx].scope == .today {
                tasks[idx].scheduledDate = todayStart
                didChange = true
            }
            // .week tasks intentionally left nil (backlog).
        }
        if didChange { saveTasks() }
    }

    /// Convert an untimed task into a timed event at the given start time.
    /// Used when the user drags a right-rail task chip onto an hour slot.
    /// The original task is removed and replaced by a new event.
    @discardableResult
    func convertTaskToEvent(_ task: TaskItem, at start: Date, durationMinutes: Int = 60) -> Event {
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let event = Event(
            title: task.title,
            location: "",
            start: start,
            end: end,
            allDay: false,
            colorHex: EventColor.presets.randomElement()?.hex ?? "#A8B89A",
            iconName: EventIcon.suggest(for: task.title),
            notes: task.notes,
            repeatRule: .never,
            alertMinutesBefore: nil
        )
        addEvent(event)
        deleteTask(task)
        return event
    }

    /// Pin a task to a specific calendar day (or `nil` for backlog).
    /// Used by drag-drop in the week view.
    func moveTask(_ task: TaskItem, to day: Date?) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let normalized = day.map { Calendar.current.startOfDay(for: $0) }
        tasks[idx].scheduledDate = normalized
        tasks[idx].lastMovedAt = Date()
        tasks[idx].rolledOver = false
        // Keep legacy `scope` roughly in sync so older code paths still work.
        if let d = normalized, Calendar.current.isDateInToday(d) {
            tasks[idx].scope = .today
        } else {
            tasks[idx].scope = .week
        }
        saveTasks()
    }

    // MARK: - Events

    func addEvent(_ event: Event) {
        events.append(event)
        saveEvents()
    }

    func updateEvent(_ event: Event) {
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[idx] = event
        saveEvents()
    }

    func deleteEvent(_ event: Event) {
        events.removeAll { $0.id == event.id }
        saveEvents()
    }

    // MARK: - Tasks

    func addTask(_ task: TaskItem) {
        tasks.append(task)
        saveTasks()
    }

    func updateTask(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx] = task
        saveTasks()
    }

    func toggleTask(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].isCompleted.toggle()
        if tasks[idx].isCompleted { tasks[idx].rolledOver = false }
        saveTasks()
    }

    func clearRolledOverFlag(for id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].rolledOver = false
        saveTasks()
    }

    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        saveTasks()
    }

    // MARK: - Rollover

    /// Bumps any unchecked task whose `scheduledDate` is in the past forward to today,
    /// flagging it as rolled-over so the UI can show the indicator.
    /// Done tasks and backlog (`scheduledDate == nil`) tasks are left alone.
    func rolloverTasks(now: Date) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)

        var didChange = false
        for idx in tasks.indices {
            guard !tasks[idx].isCompleted,
                  let sched = tasks[idx].scheduledDate else { continue }
            if cal.startOfDay(for: sched) < todayStart {
                tasks[idx].scheduledDate = todayStart
                tasks[idx].lastMovedAt = todayStart
                tasks[idx].rolledOver = true
                tasks[idx].scope = .today
                didChange = true
            }
        }
        if didChange { saveTasks() }
    }

    private func startOfWeek(for date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }

    // MARK: - Persistence

    private func load() {
        let d = UserDefaults.standard

        // For events + tasks, iCloud wins over local cache if both exist
        // (a newer device may have pushed an update before this one opened).
        let eventsRemote = kvs.data(forKey: eventsKey)
        let eventsLocal  = d.data(forKey: eventsKey)
        if let data = eventsRemote ?? eventsLocal,
           let decoded = try? JSONDecoder().decode([Event].self, from: data) {
            events = decoded
            // If we restored from iCloud, mirror into the local cache too.
            if eventsRemote != nil { d.set(data, forKey: eventsKey) }
        }

        let tasksRemote = kvs.data(forKey: tasksKey)
        let tasksLocal  = d.data(forKey: tasksKey)
        if let data = tasksRemote ?? tasksLocal,
           let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
            tasks = decoded
            if tasksRemote != nil { d.set(data, forKey: tasksKey) }
        }

        // Chat history stays local-only.
        if let data = d.data(forKey: chatKey),
           let decoded = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            chatHistory = decoded
        }
    }

    private func saveChat() {
        guard let data = try? JSONEncoder().encode(chatHistory) else { return }
        UserDefaults.standard.set(data, forKey: chatKey)
    }

    private func saveEvents() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: eventsKey)
        // Don't echo a remote-received change straight back to iCloud.
        guard !applyingRemote else { return }
        pushToICloud(data: data, key: eventsKey)
    }

    private func saveTasks() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: tasksKey)
        guard !applyingRemote else { return }
        pushToICloud(data: data, key: tasksKey)
    }

    /// 1 MB per-value KVS limit, with some headroom.
    private static let kvsPerValueByteBudget = 900_000

    private func pushToICloud(data: Data, key: String) {
        if data.count > Self.kvsPerValueByteBudget {
            print("⚠️ Switched: \(key) is \(data.count / 1024) KB — skipping iCloud push to avoid quota error")
            return
        }
        kvs.set(data, forKey: key)
        kvs.synchronize()
    }

    /// Pull the latest snapshot from iCloud on demand (e.g. when the
    /// app comes back to the foreground). Cheap to call.
    func refreshFromICloud() {
        kvs.synchronize()
        applyingRemote = true
        defer { applyingRemote = false }
        if let data = kvs.data(forKey: eventsKey),
           let decoded = try? JSONDecoder().decode([Event].self, from: data),
           decoded != events {
            events = decoded
            UserDefaults.standard.set(data, forKey: eventsKey)
        }
        if let data = kvs.data(forKey: tasksKey),
           let decoded = try? JSONDecoder().decode([TaskItem].self, from: data),
           decoded != tasks {
            tasks = decoded
            UserDefaults.standard.set(data, forKey: tasksKey)
        }
    }
}

extension AppStore {
    /// Preview-only convenience: in-memory store seeded with sample data.
    static var preview: AppStore {
        let s = AppStore()
        let cal = Calendar.current
        let today = Date()
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        s.events = [
            Event(title: "Morning standup", start: at(9), end: at(9, 30),
                  colorHex: "#A8B4C2", iconName: "person.2.fill"),
            Event(title: "Design review", start: at(11), end: at(12),
                  colorHex: "#B8A8C8", iconName: "paintpalette.fill"),
            Event(title: "Lunch with Sarah", start: at(13), end: at(14),
                  colorHex: "#E0AA90", iconName: "fork.knife"),
            Event(title: "1:1 with mentor", start: at(15, 30), end: at(16),
                  colorHex: "#A8B89A", iconName: "bubble.left.fill"),
            Event(title: "Gym", start: at(18, 30), end: at(19, 30),
                  colorHex: "#D9A8A0", iconName: "dumbbell.fill")
        ]
        let todayStart = cal.startOfDay(for: today)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let wed = cal.date(byAdding: .day, value: 2, to: todayStart) ?? todayStart
        s.tasks = [
            TaskItem(title: "Reply to investor email", scope: .today, priority: .high, scheduledDate: todayStart),
            TaskItem(title: "Finish slide deck",       scope: .today, priority: .med,  scheduledDate: todayStart),
            TaskItem(title: "Daily journal",           scope: .today, priority: .none, scheduledDate: todayStart),
            TaskItem(title: "Read chapter 4",          isCompleted: true, scope: .today, priority: .none, scheduledDate: todayStart),
            TaskItem(title: "Book flights for May",    scope: .today, priority: .high, scheduledDate: tomorrow),
            TaskItem(title: "Renew gym membership",    scope: .today, priority: .low,  scheduledDate: wed),
            TaskItem(title: "Call dentist",            scope: .week,  priority: .none, scheduledDate: nil)
        ]
        return s
    }
}
