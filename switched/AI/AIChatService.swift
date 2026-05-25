import Foundation

/// Drives the AI assistant chat: sends conversation + current store snapshot
/// to the Switched AI Worker, parses tool calls, and applies them to the AppStore.
@MainActor
final class AIChatService {
    /// Backend URL. The Worker proxies to Anthropic with our key.
    static let backendURL = URL(string: "https://switched-ai.alexey-656.workers.dev/chat")!

    enum ChatError: Error, LocalizedError {
        case rateLimited(limit: Int, resetsAt: String?)
        case overloaded
        case http(Int, String)
        case parse(String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .rateLimited(let limit, _):
                return "You've used your \(limit) free AI messages for today. Try again tomorrow."
            case .overloaded:
                return "Claude is busy right now. Try again in a few seconds — your request didn't go through."
            case .http(let c, let m):
                return "AI error \(c): \(m)"
            case .parse(let m):
                return "Couldn't read AI response: \(m)"
            case .network(let m):
                return "Network error: \(m)"
            }
        }
    }

    /// Send a conversation to the AI and get the next assistant message.
    /// `history` must already include the latest user message at the end.
    /// Any tool calls returned by the AI are applied to `store`.
    func send(
        history: [ChatMessage],
        store: AppStore
    ) async throws -> ChatMessage {
        // Build the API request.
        let body = makeRequestBody(history: history, store: store)
        let data = try await postWorker(body: body)

        // Parse the response.
        let (replyText, toolUses) = try parseResponse(data: data)

        // Build PROPOSED actions (Direction A: AI proposes, user approves).
        // We do NOT mutate the store here — that happens when the user taps "Add".
        var actions: [ChatMessage.Action] = []
        for tu in toolUses {
            if let a = propose(tool: tu, from: store) {
                actions.append(a)
            }
        }

        // Pick the body text: AI's own prose, or a generic intro for proposed cards.
        let finalText: String
        if !replyText.isEmpty {
            finalText = replyText
        } else if !actions.isEmpty {
            finalText = actions.count == 1 ? proposalIntro(for: actions[0]) : "I'll add these:"
        } else {
            finalText = "Done."
        }

        return ChatMessage(role: .assistant, text: finalText, actions: actions)
    }

    private func proposalIntro(for action: ChatMessage.Action) -> String {
        switch action.kind {
        case .createEvent: "I'll add this:"
        case .createTask:  "I'll add this task:"
        case .updateEvent, .updateTask: "Here's the change:"
        case .deleteEvent: "Delete this?"
        case .deleteTask:  "Delete this task?"
        }
    }

    // MARK: - Request

    private func makeRequestBody(history: [ChatMessage], store: AppStore) -> [String: Any] {
        let systemPrompt = makeSystemPrompt(store: store)

        // Convert chat history into Anthropic Messages format.
        // We strip the very last user message that was just appended and re-add it;
        // it's already in history so we use the full list.
        let messages: [[String: Any]] = history.map { msg in
            return [
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.text
            ]
        }

        return [
            "model": "claude-haiku-4-5",
            "max_tokens": 800,
            "system": systemPrompt,
            "tools": Self.toolDefinitions,
            "messages": messages
        ]
    }

    private func makeSystemPrompt(store: AppStore) -> String {
        let now = Date()
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.timeZone = .current
        let todayStr = dateFmt.string(from: now)
        let dowStr = now.formatted(.dateTime.weekday(.wide))

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        timeFmt.timeZone = .current

        // Show events in a window: today through +14 days, plus any past 7 for context.
        let cal = Calendar.current
        let windowStart = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let windowEnd   = cal.date(byAdding: .day, value: 14, to: now) ?? now
        let relevantEvents = store.events
            .filter { $0.start >= windowStart && $0.start <= windowEnd }
            .sorted { $0.start < $1.start }

        var eventsBlock = "EVENTS (id | date time | title | location):\n"
        if relevantEvents.isEmpty {
            eventsBlock += "(none)\n"
        } else {
            for e in relevantEvents {
                let dStr = dateFmt.string(from: e.start)
                let tStr = e.allDay
                    ? "all-day"
                    : "\(timeFmt.string(from: e.start))-\(timeFmt.string(from: e.end))"
                let loc = e.location.isEmpty ? "" : " @ \(e.location)"
                eventsBlock += "- \(e.id.uuidString) | \(dStr) \(tStr) | \(e.title)\(loc)\n"
            }
        }

        let openTasks = store.tasks.filter { !$0.isCompleted }
        var tasksBlock = "TASKS (id | scheduled | priority | title):\n"
        if openTasks.isEmpty {
            tasksBlock += "(none)\n"
        } else {
            for t in openTasks {
                let sched = t.scheduledDate.map(dateFmt.string(from:)) ?? "backlog"
                let due = t.dueDate.map { " due:\(dateFmt.string(from: $0))" } ?? ""
                tasksBlock += "- \(t.id.uuidString) | \(sched) | \(t.priority.rawValue) | \(t.title)\(due)\n"
            }
        }

        return """
        You are the assistant inside "Switched", a calendar + task app.
        Today is \(todayStr) (\(dowStr)). Times use the user's local timezone, 24-hour clock.

        \(eventsBlock)
        \(tasksBlock)

        How to behave:
        - If the user asks to ADD something, call create_event or create_task.
        - If they ask to CHANGE or MOVE something, call update_event or update_task with the matching id.
        - If they ask to REMOVE / CANCEL, call delete_event or delete_task.
        - If they ASK A QUESTION about their schedule, answer in 1-2 short sentences using the lists above. DO NOT call tools for questions.
        - Resolve relative dates ("tomorrow", "next friday", "tonight") yourself.
        - Match items by best-fit fuzzy match on title when the user is vague (e.g. "cancel gym").
        - "Schedule", "block", "lunch/dinner/meeting with" => event. "Remind me", "add to list", "todo" => task.
        - Tasks: if the user mentions a day ("call dentist tomorrow", "gym on monday") set scheduledDate. If they say "someday", "eventually", or no day at all, leave scheduledDate off so it lands in the backlog.
        - Be brief. One sentence confirmations. No emojis. No markdown.
        """
    }

    // MARK: - Tool definitions (Anthropic schema)

    private static let toolDefinitions: [[String: Any]] = [
        [
            "name": "create_event",
            "description": "Create a calendar event on a specific date with optional start/end times.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "title":     ["type": "string"],
                    "date":      ["type": "string", "description": "YYYY-MM-DD in local time"],
                    "startTime": ["type": "string", "description": "HH:MM in 24h. Omit for all-day."],
                    "endTime":   ["type": "string", "description": "HH:MM in 24h. Defaults to start+60min."],
                    "location":  ["type": "string"]
                ],
                "required": ["title", "date"]
            ]
        ],
        [
            "name": "create_task",
            "description": "Create a to-do task. Pin it to a day with scheduledDate, or leave it unscheduled (backlog).",
            "input_schema": [
                "type": "object",
                "properties": [
                    "title":          ["type": "string"],
                    "scheduledDate":  ["type": "string", "description": "YYYY-MM-DD. Omit to leave in backlog."],
                    "priority":       ["type": "string", "enum": ["none", "low", "med", "high"]],
                    "dueDate":        ["type": "string", "description": "Hard deadline. Optional YYYY-MM-DD."]
                ],
                "required": ["title"]
            ]
        ],
        [
            "name": "update_event",
            "description": "Change an existing event. Provide its id and only the fields to change.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "id":        ["type": "string"],
                    "title":     ["type": "string"],
                    "date":      ["type": "string"],
                    "startTime": ["type": "string"],
                    "endTime":   ["type": "string"],
                    "location":  ["type": "string"]
                ],
                "required": ["id"]
            ]
        ],
        [
            "name": "update_task",
            "description": "Change an existing task. Provide its id and only the fields to change. Set completed=true to mark done. Set scheduledDate to a YYYY-MM-DD to move to a day, or the string \"backlog\" to unschedule.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "id":            ["type": "string"],
                    "title":         ["type": "string"],
                    "scheduledDate": ["type": "string"],
                    "priority":      ["type": "string", "enum": ["none", "low", "med", "high"]],
                    "dueDate":       ["type": "string"],
                    "completed":     ["type": "boolean"]
                ],
                "required": ["id"]
            ]
        ],
        [
            "name": "delete_event",
            "description": "Delete an event by id.",
            "input_schema": [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ]
        ],
        [
            "name": "delete_task",
            "description": "Delete a task by id.",
            "input_schema": [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ]
        ]
    ]

    // MARK: - Network

    /// Per-device anonymous ID, generated once and persisted in UserDefaults.
    /// Used by the Worker for rate limiting; never sent to Anthropic.
    static var deviceId: String {
        let key = "switched.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    private func postWorker(body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: Self.backendURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(Self.deviceId, forHTTPHeaderField: "x-device-id")
        req.timeoutInterval = 30
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw ChatError.network(error.localizedDescription)
        }

        guard let http = resp as? HTTPURLResponse else {
            throw ChatError.http(0, "No response")
        }

        if http.statusCode == 429 {
            // Rate-limit response shape: { error: "rate_limited", limit: N, resetsAt: "..." }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let limit = (json["limit"] as? Int) ?? 50
                let resetsAt = json["resetsAt"] as? String
                throw ChatError.rateLimited(limit: limit, resetsAt: resetsAt)
            }
            throw ChatError.rateLimited(limit: 50, resetsAt: nil)
        }

        // Anthropic's "overloaded" responses. Worker has already retried these
        // ~3 times before giving up — if we still see them, just ask the user to retry.
        if http.statusCode == 529 || http.statusCode == 503 || http.statusCode == 502 || http.statusCode == 504 {
            throw ChatError.overloaded
        }

        if http.statusCode != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw ChatError.http(http.statusCode, bodyStr)
        }
        return data
    }

    // MARK: - Response parsing

    /// Returns (assistantText, toolUses).
    private func parseResponse(data: Data) throws -> (String, [ToolUse]) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw ChatError.parse("missing content")
        }
        var text = ""
        var tools: [ToolUse] = []
        for block in content {
            let type = block["type"] as? String ?? ""
            if type == "text", let t = block["text"] as? String {
                if !text.isEmpty { text += "\n" }
                text += t.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if type == "tool_use",
                      let name = block["name"] as? String,
                      let input = block["input"] as? [String: Any] {
                tools.append(ToolUse(name: name, input: input))
            }
        }
        return (text, tools)
    }

    private struct ToolUse {
        let name: String
        let input: [String: Any]
    }

    // MARK: - Proposing actions (Direction A: no auto-execute)

    private func propose(tool: ToolUse, from store: AppStore) -> ChatMessage.Action? {
        switch tool.name {
        case "create_event":   return proposeCreateEvent(input: tool.input)
        case "create_task":    return proposeCreateTask(input: tool.input)
        case "update_event":   return proposeUpdateEvent(input: tool.input, store: store)
        case "update_task":    return proposeUpdateTask(input: tool.input, store: store)
        case "delete_event":   return proposeDeleteEvent(input: tool.input, store: store)
        case "delete_task":    return proposeDeleteTask(input: tool.input, store: store)
        default:               return nil
        }
    }

    private func proposeCreateEvent(input: [String: Any]) -> ChatMessage.Action? {
        let title = (input["title"] as? String) ?? "Untitled"
        let dateStr = (input["date"] as? String) ?? ""
        guard let date = parseDate(dateStr) else { return nil }

        let cal = Calendar.current
        var start = date
        var end = cal.date(byAdding: .hour, value: 1, to: date) ?? date
        var allDay = true

        if let s = input["startTime"] as? String, let st = combine(date: date, hhmm: s) {
            start = st
            allDay = false
            if let e = input["endTime"] as? String, let et = combine(date: date, hhmm: e) {
                end = et
            } else {
                end = cal.date(byAdding: .minute, value: 60, to: st) ?? st
            }
        }

        let event = Event(
            title: title,
            location: (input["location"] as? String) ?? "",
            start: start,
            end: end,
            allDay: allDay,
            colorHex: EventColor.presets.randomElement()?.hex ?? EventColor.presets[0].hex,
            iconName: EventIcon.suggest(for: title),
            notes: ""
        )
        return ChatMessage.Action(kind: .createEvent(event))
    }

    private func proposeCreateTask(input: [String: Any]) -> ChatMessage.Action? {
        let title = (input["title"] as? String) ?? "Untitled"
        let priorityRaw = (input["priority"] as? String) ?? "none"
        let priority = TaskItem.Priority(rawValue: priorityRaw) ?? .none
        let due = (input["dueDate"] as? String).flatMap(parseDate)
        let scheduled = (input["scheduledDate"] as? String).flatMap(parseDate)
            .map { Calendar.current.startOfDay(for: $0) }
        let legacyScope: TaskItem.Scope =
            (scheduled.map { Calendar.current.isDateInToday($0) } ?? false) ? .today : .week

        let task = TaskItem(
            title: title,
            notes: "",
            scope: legacyScope,
            priority: priority,
            dueDate: due,
            scheduledDate: scheduled
        )
        return ChatMessage.Action(kind: .createTask(task))
    }

    private func proposeUpdateEvent(input: [String: Any], store: AppStore) -> ChatMessage.Action? {
        guard let idStr = input["id"] as? String,
              let id = UUID(uuidString: idStr),
              let original = store.events.first(where: { $0.id == id }) else { return nil }
        var event = original

        if let t = input["title"] as? String { event.title = t }
        if let l = input["location"] as? String { event.location = l }

        let originalDuration = event.end.timeIntervalSince(event.start)
        var newDate = event.start
        if let d = input["date"] as? String, let parsed = parseDate(d) {
            let cal = Calendar.current
            let h = cal.component(.hour, from: event.start)
            let m = cal.component(.minute, from: event.start)
            newDate = cal.date(bySettingHour: h, minute: m, second: 0, of: parsed) ?? parsed
            event.start = newDate
            event.end = newDate.addingTimeInterval(originalDuration)
        }
        if let s = input["startTime"] as? String, let st = combine(date: newDate, hhmm: s) {
            event.start = st
            if let e = input["endTime"] as? String, let et = combine(date: newDate, hhmm: e) {
                event.end = et
            } else {
                event.end = st.addingTimeInterval(originalDuration > 0 ? originalDuration : 3600)
            }
            event.allDay = false
        } else if let e = input["endTime"] as? String, let et = combine(date: newDate, hhmm: e) {
            event.end = et
        }

        return ChatMessage.Action(kind: .updateEvent(after: event, before: original))
    }

    private func proposeUpdateTask(input: [String: Any], store: AppStore) -> ChatMessage.Action? {
        guard let idStr = input["id"] as? String,
              let id = UUID(uuidString: idStr),
              let original = store.tasks.first(where: { $0.id == id }) else { return nil }
        var task = original

        if let t = input["title"] as? String { task.title = t }
        if let p = input["priority"] as? String, let pr = TaskItem.Priority(rawValue: p) { task.priority = pr }
        if let d = input["dueDate"] as? String { task.dueDate = parseDate(d) }
        if let c = input["completed"] as? Bool { task.isCompleted = c }
        if let sd = input["scheduledDate"] as? String {
            if sd.lowercased() == "backlog" || sd.isEmpty {
                task.scheduledDate = nil
                task.scope = .week
            } else if let parsed = parseDate(sd) {
                let day = Calendar.current.startOfDay(for: parsed)
                task.scheduledDate = day
                task.scope = Calendar.current.isDateInToday(day) ? .today : .week
                task.rolledOver = false
            }
        }

        return ChatMessage.Action(kind: .updateTask(after: task, before: original))
    }

    private func proposeDeleteEvent(input: [String: Any], store: AppStore) -> ChatMessage.Action? {
        guard let idStr = input["id"] as? String,
              let id = UUID(uuidString: idStr),
              let event = store.events.first(where: { $0.id == id }) else { return nil }
        return ChatMessage.Action(kind: .deleteEvent(event))
    }

    private func proposeDeleteTask(input: [String: Any], store: AppStore) -> ChatMessage.Action? {
        guard let idStr = input["id"] as? String,
              let id = UUID(uuidString: idStr),
              let task = store.tasks.first(where: { $0.id == id }) else { return nil }
        return ChatMessage.Action(kind: .deleteTask(task))
    }

    // MARK: - Date helpers

    private func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.date(from: s)
    }

    private func combine(date: Date, hhmm: String) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
    }

}
