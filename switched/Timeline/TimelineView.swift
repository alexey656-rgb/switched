import SwiftUI

/// Direction-A Timeline: dead hours collapse into a single "free" pill,
/// events render as duration-proportional tinted blocks, MORNING/AFTERNOON/
/// EVENING section labels separate parts of the day, a red now-line floats
/// on top.
struct TimelineView: View {
    @Environment(AppStore.self) private var store
    @Binding var selectedDate: Date

    let onOpenAssistant: (String?) -> Void

    @State private var editingEvent: Event?
    @State private var addingFromHour: Date?
    @State private var nowTick: Date = Date()
    @State private var windowAnchor: Date = Calendar.current.startOfDay(for: Date())
    private let halfWindow = 14

    /// 52pt per hour vertical rhythm.
    private let hourHeight: CGFloat = 52
    private let gutterWidth: CGFloat = 50
    /// Collapse any gap ≥ this many minutes into a free-time pill.
    private let freeTimeThresholdMin = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateHeader
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 2)

            weekStrip
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            // Swipeable day pages.
            TabView(selection: dayTagBinding) {
                ForEach(pageDates, id: \.self) { date in
                    dayBody(for: date).tag(date)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Theme.paper)
        .onAppear { startNowTicker() }
        .onChange(of: selectedDate) { _, new in
            recenterWindowIfNeeded(around: new)
        }
        .sheet(item: $editingEvent) { ev in EventEditorSheet(existing: ev) }
        .sheet(item: Binding(
            get: { addingFromHour.map { DateBox(date: $0) } },
            set: { addingFromHour = $0?.date }
        )) { box in
            EventEditorSheet(initialStart: box.date)
        }
    }

    // MARK: - Date header

    private var dateHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Text(weekdayLabel(selectedDate))
                    .foregroundStyle(Theme.ink)
                Text(monthDayLabel(selectedDate))
                    .foregroundStyle(Theme.clay)
            }
            .font(.system(size: 26, weight: .bold))
            .kerning(-0.5)

            Spacer()

            Text(summaryLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink3)
        }
    }

    private var summaryLabel: String {
        let evCount = visibleEvents(for: selectedDate).count
        let tCount = visibleTasks(for: selectedDate).count
        var parts: [String] = []
        parts.append("\(evCount) " + (evCount == 1 ? "event" : "events"))
        if tCount > 0 { parts.append("\(tCount) " + (tCount == 1 ? "task" : "tasks")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Week strip (with event color dots)

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { d in
                let isSel = Calendar.current.isDate(d, inSameDayAs: selectedDate)
                let isToday = Calendar.current.isDateInToday(d)
                Button {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        selectedDate = d
                    }
                } label: {
                    VStack(spacing: 4) {
                        Text(letterFor(d))
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(isSel ? Theme.ink3 : Theme.ink3)
                        Text("\(Calendar.current.component(.day, from: d))")
                            .font(.system(size: 14, weight: isSel ? .semibold : .medium))
                            .foregroundStyle(isSel ? .white : Theme.ink)
                            .frame(width: 34, height: 34)
                            .background(
                                isSel ? Theme.clay :
                                (isToday ? Theme.claySoft : Color.clear),
                                in: Circle()
                            )

                        // Event tint dots (up to 2)
                        HStack(spacing: 2) {
                            let dots = tintDots(for: d).prefix(2)
                            ForEach(Array(dots.enumerated()), id: \.offset) { _, color in
                                Circle().fill(color).frame(width: 4, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tintDots(for date: Date) -> [Color] {
        visibleEvents(for: date).prefix(2).map { matchedTint(for: $0).rail }
    }

    // MARK: - Day body (timeline list + inline AI pill)

    private func dayBody(for date: Date) -> some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(rows(for: date)) { row in
                            rowView(row: row, date: date)
                                .id(row.id)
                        }
                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }
                .scrollIndicators(.hidden)

                // Inline AI pill, floating above scroll content.
                InlineAIPill(placeholder: "Lunch with Sarah at 1?",
                             sendIcon: "arrow.up") { draft in
                    onOpenAssistant(draft)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            .onAppear {
                // Auto-scroll to current time on today, or 9 AM on other days.
                let target: String
                if Calendar.current.isDateInToday(date) {
                    target = "now"
                } else {
                    target = "hour-9"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Row rendering

    @ViewBuilder
    private func rowView(row: TimelineRow, date: Date) -> some View {
        switch row.kind {
        case .sectionLabel(let label):
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.ink3)
                Spacer(minLength: 0)
            }
            .padding(.leading, gutterWidth + 4)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .id(row.id)

        case .event(let event):
            timelineRow {
                Text(hourLabel(event.start))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink3)
            } content: {
                TimelineEventBlock(event: event, tint: matchedTint(for: event))
                    .frame(height: heightForDuration(event))
                    .onTapGesture { editingEvent = event }
            }
            .id(row.id)

        case .task(let task):
            timelineRow {
                if let sched = task.scheduledDate {
                    Text(hourLabel(sched))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.ink3)
                }
            } content: {
                TimelineTaskRow(task: task) {
                    store.toggleTask(task)
                }
                .onTapGesture { /* future: edit task */ }
            }
            .id(row.id)

        case .freeTime(let start, let end):
            timelineRow {
                EmptyView()
            } content: {
                FreeTimePill(start: start, end: end) {
                    addingFromHour = start
                }
            }
            .id(row.id)

        case .nowLine:
            // Full-width red line w/ time label.
            HStack(spacing: 8) {
                Spacer().frame(width: gutterWidth - 10)
                Circle().fill(Theme.danger).frame(width: 8, height: 8)
                Rectangle().fill(Theme.danger).frame(height: 1.5)
                Text(nowTimeLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.danger)
            }
            .id("now")

        case .hourMarker(let hour):
            timelineRow {
                Text(hourLabel(hour: hour))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink3)
            } content: {
                Color.clear.frame(height: 8)
            }
            .id(row.id)
        }
    }

    /// Two-column row: gutter (50pt wide) + content (flex).
    private func timelineRow<Gutter: View, Content: View>(
        @ViewBuilder gutter: () -> Gutter,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                gutter()
            }
            .frame(width: gutterWidth - 6, alignment: .trailing)
            .padding(.top, 8)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Now ticker

    private func startNowTicker() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            nowTick = Date()
        }
    }

    // MARK: - Row builder

    private struct TimelineRow: Identifiable {
        let id: String
        let kind: Kind
        enum Kind {
            case event(Event)
            case task(TaskItem)
            case freeTime(start: Date, end: Date)
            case sectionLabel(String)
            case nowLine
            case hourMarker(Int)
        }
    }

    private func rows(for date: Date) -> [TimelineRow] {
        let events = visibleEvents(for: date).sorted { $0.start < $1.start }
        let timedTasks = visibleTasks(for: date)
            .filter { _ in false } // Tasks don't have a time component in the model yet.
            .sorted { (l, r) in (l.scheduledDate ?? .distantPast) < (r.scheduledDate ?? .distantPast) }
        let untimedTasks = visibleTasks(for: date)

        // Merge events and timed-tasks into a single time-ordered list.
        var combined: [(Date, Date?, TimelineRow.Kind)] = []
        for e in events {
            combined.append((e.start, e.end, .event(e)))
        }
        for t in timedTasks {
            if let s = t.scheduledDate {
                combined.append((s, nil, .task(t)))
            }
        }
        combined.sort { $0.0 < $1.0 }

        var rows: [TimelineRow] = []
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        // Section label tracker
        var seenSection: Set<String> = []
        func ensureSection(for time: Date) {
            let label = sectionLabel(for: time)
            if !seenSection.contains(label) {
                rows.append(TimelineRow(id: "sec-\(label)", kind: .sectionLabel(label)))
                seenSection.insert(label)
            }
        }

        // Now line placement (only on today)
        let showNow = cal.isDateInToday(date)
        var nowInserted = false
        let now = nowTick

        // Free-time pill BEFORE the first event (if applicable).
        if let first = combined.first {
            let gap = first.0.timeIntervalSince(dayStart) / 60.0
            if gap >= Double(freeTimeThresholdMin) {
                let pillEnd = first.0
                // Use 1 AM (or dayStart if first is very early) as the displayed start.
                let pillStart = max(dayStart, cal.date(byAdding: .hour, value: 1, to: dayStart) ?? dayStart)
                rows.append(TimelineRow(
                    id: "free-pre-\(first.0.timeIntervalSince1970)",
                    kind: .freeTime(start: pillStart, end: pillEnd)
                ))
            } else {
                // Show a single hour marker for the morning context.
                let hour = cal.component(.hour, from: dayStart)
                if hour < cal.component(.hour, from: first.0) {
                    rows.append(TimelineRow(id: "hm-\(hour)", kind: .hourMarker(hour)))
                }
            }
        }

        for (i, entry) in combined.enumerated() {
            let (start, end, kind) = entry

            // Insert now line if it falls before this entry.
            if showNow, !nowInserted, now <= start {
                rows.append(TimelineRow(id: "now-row", kind: .nowLine))
                nowInserted = true
            }

            ensureSection(for: start)
            rows.append(TimelineRow(id: "ent-\(start.timeIntervalSince1970)-\(i)", kind: kind))

            // Compute next-start to determine gap behavior.
            let nextStart: Date? = (i + 1 < combined.count) ? combined[i + 1].0 : nil
            let blockEnd = end ?? start.addingTimeInterval(60 * 60) // assumed task 1h
            if let ns = nextStart {
                let gapMin = ns.timeIntervalSince(blockEnd) / 60.0
                if gapMin >= Double(freeTimeThresholdMin) {
                    rows.append(TimelineRow(
                        id: "free-\(blockEnd.timeIntervalSince1970)",
                        kind: .freeTime(start: blockEnd, end: ns)
                    ))
                }
            } else {
                // After last entry: free-time pill if rest of day is empty and >=2h remain.
                let gapMin = dayEnd.timeIntervalSince(blockEnd) / 60.0
                if gapMin >= Double(freeTimeThresholdMin) {
                    let pillEnd = cal.date(bySettingHour: 22, minute: 0, second: 0, of: date) ?? blockEnd
                    rows.append(TimelineRow(
                        id: "free-tail-\(blockEnd.timeIntervalSince1970)",
                        kind: .freeTime(start: blockEnd, end: pillEnd)
                    ))
                }
            }
        }

        // Now line if AFTER all entries.
        if showNow, !nowInserted {
            rows.append(TimelineRow(id: "now-row", kind: .nowLine))
        }

        // If there are NO events/tasks at all, show one big "free all day" pill.
        if combined.isEmpty {
            let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            let end = cal.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
            rows.append(TimelineRow(
                id: "free-allday",
                kind: .freeTime(start: start, end: end)
            ))
        }

        // Untimed tasks pinned at the bottom.
        if !untimedTasks.isEmpty {
            rows.append(TimelineRow(id: "sec-TASKS", kind: .sectionLabel("TASKS")))
            for t in untimedTasks {
                rows.append(TimelineRow(id: "task-\(t.id.uuidString)", kind: .task(t)))
            }
        }

        return rows
    }

    // MARK: - Data

    private func visibleEvents(for date: Date) -> [Event] {
        let cal = Calendar.current
        return store.events
            .filter { cal.isDate($0.start, inSameDayAs: date) }
    }
    private func visibleTasks(for date: Date) -> [TaskItem] {
        let cal = Calendar.current
        return store.tasks.filter {
            guard let s = $0.scheduledDate else { return false }
            return cal.isDate(s, inSameDayAs: date)
        }
    }

    private func heightForDuration(_ ev: Event) -> CGFloat {
        let mins = max(15, ev.end.timeIntervalSince(ev.start) / 60)
        return max(CGFloat(mins / 60) * hourHeight, 32)
    }

    private func sectionLabel(for date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        if h < 12 { return "MORNING" }
        if h < 18 { return "AFTERNOON" }
        return "EVENING"
    }

    // MARK: - Date / format helpers

    private func weekdayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: d)
    }
    private func monthDayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }
    private func letterFor(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; return f.string(from: d)
    }
    private func hourLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h a"; return f.string(from: d)
    }
    private func hourLabel(hour: Int) -> String {
        let ampm = hour >= 12 ? "PM" : "AM"
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(h12) \(ampm)"
    }
    private var nowTimeLabel: String {
        let f = DateFormatter(); f.dateFormat = "h:mm"; return f.string(from: nowTick)
    }

    // MARK: - Week navigation

    private var weekDays: [Date] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: selectedDate)
        let mondayOffset = (weekday + 5) % 7
        guard let monday = cal.date(byAdding: .day, value: -mondayOffset, to: selectedDate) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    private var pageDates: [Date] {
        let cal = Calendar.current
        return (-halfWindow...halfWindow).compactMap {
            cal.date(byAdding: .day, value: $0, to: windowAnchor)
        }
    }

    private var dayTagBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: selectedDate) },
            set: { selectedDate = $0 }
        )
    }

    private func recenterWindowIfNeeded(around date: Date) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let first = pageDates.first ?? day
        let last = pageDates.last ?? day
        if day < (cal.date(byAdding: .day, value: 3, to: first) ?? first) ||
           day > (cal.date(byAdding: .day, value: -3, to: last) ?? last) {
            windowAnchor = day
        }
    }

    // MARK: - Tint matching

    private func matchedTint(for event: Event) -> EventTint {
        let title = event.title.lowercased()
        if title.contains("lunch") || title.contains("dinner") || title.contains("coffee")
            || title.contains("breakfast") { return EventTints.butter }
        if title.contains("standup") || title.contains("meeting") || title.contains("sync")
            || title.contains("1:1") { return EventTints.sage }
        if title.contains("gym") || title.contains("run") || title.contains("workout") { return EventTints.rose }
        if title.contains("design") || title.contains("review") { return EventTints.lavender }
        // Title-derived fallback so wedding/etc. get lavender, others sky.
        if title.contains("wedding") || title.contains("birthday") { return EventTints.lavender }
        return EventTints.sky
    }
}

// MARK: - Event block

struct TimelineEventBlock: View {
    let event: Event
    let tint: EventTint

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.bg)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint.rail)
                .frame(width: 3)
                .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var subtitle: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        let durMin = Int(event.end.timeIntervalSince(event.start) / 60)
        let durStr: String
        if durMin < 60 {
            durStr = "\(durMin) min"
        } else {
            let h = durMin / 60
            let m = durMin % 60
            durStr = m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
        }
        return "\(f.string(from: event.start)) · \(durStr)"
    }
}

// MARK: - Inline task row (on timeline)

struct TimelineTaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(task.isCompleted ? Theme.clay : Theme.ink4, lineWidth: 1.5)
                        .background(Circle().fill(task.isCompleted ? Theme.clay : Color.clear))
                        .frame(width: 18, height: 18)
                    if task.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 14))
                .foregroundStyle(task.isCompleted ? Theme.ink3 : Theme.ink)
                .strikethrough(task.isCompleted, color: Theme.ink3)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("TASK")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(Theme.clay)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Free-time pill

struct FreeTimePill: View {
    let start: Date
    let end: Date
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(hour(start)) – \(hour(end)) · free")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink3)
            Spacer(minLength: 0)
            Button(action: onAdd) {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text("event").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.clay)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cardSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Theme.hairline2,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
        )
    }

    private func hour(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h a"; return f.string(from: d)
    }
}

// MARK: - Date box wrapper

struct DateBox: Identifiable {
    let id = UUID()
    let date: Date
}

#Preview {
    TimelineView(selectedDate: .constant(Date()), onOpenAssistant: { _ in })
        .environment(AppStore.preview)
}
