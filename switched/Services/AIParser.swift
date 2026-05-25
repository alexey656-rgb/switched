import Foundation

/// Output of a voice/text parse — what the user "meant" in structured form.
struct ParsedCommand: Equatable {
    enum Kind: String { case event, task }
    var kind: Kind
    var title: String
    var date: Date
    var startTime: Date?         // nil = all-day / no time
    var endTime: Date?
    var person: String?
    var location: String?
}

/// Parses natural-language commands ("schedule a 30-min run tomorrow at 7am")
/// into a ParsedCommand. Uses Claude Haiku if an API key is configured,
/// falls back to a heuristic regex parser otherwise.
enum AIParser {
    static var apiKey: String? {
        get { UserDefaults.standard.string(forKey: "anthropicKey") }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: "anthropicKey")
            } else {
                UserDefaults.standard.removeObject(forKey: "anthropicKey")
            }
        }
    }

    static func parse(_ text: String) async -> ParsedCommand {
        if let key = apiKey {
            if let claude = try? await parseWithClaude(text, apiKey: key) {
                return claude
            }
        }
        return parseHeuristic(text)
    }

    // MARK: - Claude

    private static func parseWithClaude(_ text: String, apiKey: String) async throws -> ParsedCommand {
        let today = Date()
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]
        let todayStr = isoFmt.string(from: today)
        let dow = today.formatted(.dateTime.weekday(.wide))

        let systemPrompt = """
        You parse spoken commands into JSON. Today is \(todayStr) (\(dow)).
        Return ONLY JSON, no markdown.
        Schema: {"type":"event"|"task","title":string,"date":"YYYY-MM-DD","startTime":"HH:MM" (24h, omit for all-day),"endTime":"HH:MM" (events only),"person":string|null,"location":string|null}
        Rules: "Remind me to..." or "add to list" => task. "Schedule", "block", "lunch with" => event.
        Resolve relative dates (tomorrow, next Friday, tonight).
        """
        let userPrompt = "Parse: \"\(text)\""

        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 400,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userPrompt]]
        ]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "AIParser", code: 1)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        var txt = (content?.first?["text"] as? String) ?? ""
        // Strip ```json fences
        txt = txt.trimmingCharacters(in: .whitespacesAndNewlines)
        if txt.hasPrefix("```") {
            txt = txt.replacingOccurrences(of: #"```(json)?"#, with: "", options: .regularExpression)
            txt = txt.replacingOccurrences(of: "```", with: "")
            txt = txt.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let parsedData = txt.data(using: .utf8),
              let parsedJson = try? JSONSerialization.jsonObject(with: parsedData) as? [String: Any] else {
            throw NSError(domain: "AIParser", code: 2)
        }
        return makeCommand(from: parsedJson)
    }

    private static func makeCommand(from json: [String: Any]) -> ParsedCommand {
        let cal = Calendar.current
        let typeStr = (json["type"] as? String) ?? "event"
        let kind: ParsedCommand.Kind = (typeStr == "task") ? .task : .event
        let title = (json["title"] as? String) ?? "Untitled"
        let dateStr = (json["date"] as? String) ?? ISO8601DateFormatter().string(from: Date()).prefix(10).description

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        let date = df.date(from: dateStr) ?? cal.startOfDay(for: Date())

        var start: Date? = nil
        var end: Date? = nil
        if let s = json["startTime"] as? String, let st = combine(date: date, hhmm: s) {
            start = st
            if let e = json["endTime"] as? String, let et = combine(date: date, hhmm: e) {
                end = et
            } else {
                end = cal.date(byAdding: .minute, value: 60, to: st)
            }
        }

        return ParsedCommand(
            kind: kind,
            title: title,
            date: date,
            startTime: start,
            endTime: end,
            person: json["person"] as? String,
            location: json["location"] as? String
        )
    }

    private static func combine(date: Date, hhmm: String) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date)
    }

    // MARK: - Heuristic fallback

    static func parseHeuristic(_ text: String) -> ParsedCommand {
        let lower = text.lowercased()
        let cal = Calendar.current
        var date = cal.startOfDay(for: Date())
        let now = Date()

        // --- Type detection
        var kind: ParsedCommand.Kind = .event
        let taskWords = ["remind", "remember", "add", "todo", "to do", "task"]
        let eventWords = ["schedule", "meeting", "lunch", "dinner", "call with", "block", "appointment"]
        if taskWords.contains(where: { lower.contains($0) }) { kind = .task }
        if eventWords.contains(where: { lower.contains($0) }) { kind = .event }

        // --- Relative dates
        if lower.contains("tomorrow") { date = cal.date(byAdding: .day, value: 1, to: date)! }
        else if lower.contains("yesterday") { date = cal.date(byAdding: .day, value: -1, to: date)! }
        else if lower.contains("next week") { date = cal.date(byAdding: .day, value: 7, to: date)! }
        else {
            let days = ["sunday","monday","tuesday","wednesday","thursday","friday","saturday"]
            for (i, name) in days.enumerated() where lower.contains(name) {
                let todayDow = cal.component(.weekday, from: now) - 1
                var diff = (i - todayDow + 7) % 7
                if diff == 0 { diff = 7 }
                date = cal.date(byAdding: .day, value: diff, to: date)!
                break
            }
        }

        // --- Time
        var hour: Int? = nil
        var minute = 0
        if let r = lower.range(of: #"(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?"#, options: .regularExpression) {
            let match = String(lower[r])
            let nums = match.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if let h = nums.first { hour = h }
            if nums.count > 1 { minute = nums[1] }
            let ampm = match.replacingOccurrences(of: ".", with: "").lowercased()
            if ampm.contains("pm"), let h = hour, h < 12 { hour = h + 12 }
            if ampm.contains("am"), let h = hour, h == 12 { hour = 0 }
            if !ampm.contains("am") && !ampm.contains("pm"), let h = hour, h <= 12 {
                if (lower.contains("tonight") || lower.contains("evening")) && h >= 1 && h <= 11 { hour = h + 12 }
                else if lower.contains("afternoon") && h <= 6 { hour = h + 12 }
            }
        } else if lower.contains("noon") { hour = 12 }
        else if lower.contains("morning") { hour = 9 }
        else if lower.contains("afternoon") { hour = 14 }
        else if lower.contains("evening") { hour = 18 }
        else if lower.contains("tonight") { hour = 19 }

        // --- Duration
        var durationMin = (kind == .event) ? 60 : 0
        if let r = lower.range(of: #"(\d+)\s*(min|minute|hour|hr)"#, options: .regularExpression) {
            let m = String(lower[r])
            let n = m.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }.first ?? 0
            durationMin = (m.contains("hour") || m.contains("hr")) ? n * 60 : n
        }

        // --- Person
        var person: String? = nil
        if let r = text.range(of: #"with\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)"#, options: .regularExpression) {
            let captured = String(text[r]).replacingOccurrences(of: "with ", with: "")
            person = captured
        }

        // --- Title (strip command words + time/date tokens)
        var title = text
        let patterns = [
            #"\b(schedule|remind me to|remember to|add|book|set up|create|move my|put|block|today|tomorrow|tonight|yesterday|next week|in the morning|in the afternoon|in the evening|at noon|at midnight)\b"#,
            #"\b\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.)?\b"#,
            #"\b\d+\s*(min|minute|minutes|hour|hours|hr)\b"#,
            #"\b(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
            #"\bwith\s+[A-Z][a-z]+(\s+[A-Z][a-z]+)?\b"#
        ]
        for p in patterns {
            title = title.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
        }
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                     .trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = title.first, "aAnN tThHeEmMyYtToO".contains(first) {
            title = title.replacingOccurrences(of: #"^(a|an|the|my|to)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        }
        if title.isEmpty { title = "Untitled" }
        title = title.prefix(1).uppercased() + title.dropFirst()

        var start: Date? = nil
        var end: Date? = nil
        if let h = hour, let s = cal.date(bySettingHour: h, minute: minute, second: 0, of: date) {
            start = s
            if kind == .event {
                end = cal.date(byAdding: .minute, value: max(durationMin, 30), to: s)
            }
        }

        return ParsedCommand(
            kind: kind,
            title: title,
            date: date,
            startTime: start,
            endTime: end,
            person: person,
            location: nil
        )
    }
}
