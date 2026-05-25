import SwiftUI

/// Direction-A Tasks: compact week strip with task counts, then a group-by-
/// day list. Today section is sticky-style. Empty days collapse into one line.
/// Unscheduled section pinned at the bottom.
struct TasksView: View {
    @Environment(AppStore.self) private var store

    let onOpenAssistant: (String?) -> Void

    @State private var weekAnchor: Date = Calendar.current.startOfDay(for: Date())
    @State private var editingTask: TaskItem?
    @State private var addingForDay: Date? = nil
    @State private var isAdding = false

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        return c
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleRow
                            .padding(.horizontal, 18)
                            .padding(.top, 10)

                        compactWeekStrip(proxy: proxy)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        daysList
                            .padding(.horizontal, 18)
                            .padding(.top, 4)

                        unscheduledSection
                            .padding(.horizontal, 18)
                            .padding(.top, 24)
                            .padding(.bottom, 120)
                    }
                }
                .scrollIndicators(.hidden)
            }

            InlineAIPill(placeholder: "Add a task…", sendIcon: "plus") { draft in
                onOpenAssistant(draft)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(Theme.paper)
        .sheet(isPresented: $isAdding) {
            TaskEditorSheet(defaultScheduledDate: addingForDay)
        }
        .sheet(item: $editingTask) { t in
            TaskEditorSheet(existing: t)
        }
    }

    // MARK: - Title row

    private var titleRow: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Tasks")
                .font(.system(size: 26, weight: .bold))
                .kerning(-0.5)
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(weekRangeLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink3)
        }
    }

    // MARK: - Compact week strip

    private func compactWeekStrip(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 6) {
            ForEach(daysInWeek, id: \.self) { d in
                weekPill(for: d, proxy: proxy)
            }
        }
    }

    private func weekPill(for d: Date, proxy: ScrollViewProxy) -> some View {
        let count = tasks(on: d).count
        let isToday = calendar.isDateInToday(d)
        let hasTasks = count > 0

        return Button {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo("day-\(dayKey(d))", anchor: .top)
            }
        } label: {
            VStack(spacing: 2) {
                Text(letterFor(d))
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(textColor(today: isToday, hasTasks: hasTasks))
                Text("\(calendar.component(.day, from: d))")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(textColor(today: isToday, hasTasks: hasTasks))
                Text(count == 0 ? "—" : "\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(textColor(today: isToday, hasTasks: hasTasks))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(bgColor(today: isToday, hasTasks: hasTasks))
            )
        }
        .buttonStyle(.plain)
    }

    private func bgColor(today: Bool, hasTasks: Bool) -> Color {
        if today { return Theme.clay }
        if hasTasks { return Theme.claySoft }
        return Theme.cardSoft
    }
    private func textColor(today: Bool, hasTasks: Bool) -> Color {
        if today { return .white }
        if hasTasks { return Theme.clayDeep }
        return Theme.ink3
    }

    // MARK: - Days list (today + other days + collapsed empties + unscheduled)

    private var daysList: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Today first (always shown).
            if let today = daysInWeek.first(where: { calendar.isDateInToday($0) }) {
                daySection(for: today, isToday: true)
            }
            // Other days with tasks.
            ForEach(otherDaysWithTasks, id: \.self) { d in
                daySection(for: d, isToday: false)
            }
            // Empty days collapsed.
            if !collapsedEmptyDays.isEmpty {
                collapsedEmptyLine
            }
        }
    }

    private func daySection(for day: Date, isToday: Bool) -> some View {
        let dayTasks = tasks(on: day)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(eyebrow(for: day, isToday: isToday))
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(isToday ? Theme.clay : Theme.ink2)
                Spacer()
                Text("\(dayTasks.count) " + (dayTasks.count == 1 ? "task" : "tasks"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink3)
            }
            VStack(spacing: 0) {
                ForEach(Array(dayTasks.enumerated()), id: \.element.id) { idx, t in
                    if idx > 0 {
                        Divider().background(Theme.hairline).padding(.leading, 14)
                    }
                    TaskRow(task: t,
                            onToggle: { store.toggleTask(t) },
                            onTap: { editingTask = t })
                }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
        }
        .id("day-\(dayKey(day))")
    }

    private var collapsedEmptyLine: some View {
        HStack(spacing: 4) {
            Text(collapsedEmptyDays.map { abbrev($0) }.joined(separator: ", "))
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink3)
            Text("· nothing planned ·")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink3)
            Button {
                if let first = collapsedEmptyDays.first {
                    addingForDay = first
                    isAdding = true
                }
            } label: {
                Text("add")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.clay)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: - Unscheduled section

    private var unscheduledSection: some View {
        let chips = unscheduledTasks
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("UNSCHEDULED")
                    .font(.system(size: 11, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(Theme.ink2)
                Spacer()
                if !chips.isEmpty {
                    Text("\(chips.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink3)
                }
            }
            if chips.isEmpty {
                Text("Nothing in the backlog.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink4)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(chips.enumerated()), id: \.element.id) { idx, t in
                        if idx > 0 {
                            Divider().background(Theme.hairline).padding(.leading, 14)
                        }
                        TaskRow(task: t,
                                onToggle: { store.toggleTask(t) },
                                onTap: { editingTask = t })
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }

    // MARK: - Data

    private var daysInWeek: [Date] {
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekAnchor)
        let start = calendar.date(from: comps) ?? calendar.startOfDay(for: weekAnchor)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var otherDaysWithTasks: [Date] {
        daysInWeek.filter { !calendar.isDateInToday($0) && !tasks(on: $0).isEmpty }
    }

    private var collapsedEmptyDays: [Date] {
        daysInWeek.filter { !calendar.isDateInToday($0) && tasks(on: $0).isEmpty }
    }

    private func tasks(on date: Date) -> [TaskItem] {
        store.tasks
            .filter { t in
                guard let s = t.scheduledDate else { return false }
                return calendar.isDate(s, inSameDayAs: date)
            }
            .sorted { l, r in
                if l.isCompleted != r.isCompleted { return !l.isCompleted && r.isCompleted }
                if l.priority.weight != r.priority.weight { return l.priority.weight > r.priority.weight }
                return l.createdAt < r.createdAt
            }
    }

    private var unscheduledTasks: [TaskItem] {
        store.tasks
            .filter { $0.scheduledDate == nil && !$0.isCompleted }
            .sorted { l, r in
                if l.priority.weight != r.priority.weight { return l.priority.weight > r.priority.weight }
                return l.createdAt < r.createdAt
            }
    }

    // MARK: - Formatting

    private var weekRangeLabel: String {
        let last = calendar.date(byAdding: .day, value: 6, to: daysInWeek.first ?? weekAnchor) ?? weekAnchor
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let fEnd = DateFormatter()
        let same = calendar.component(.month, from: daysInWeek.first ?? weekAnchor)
                 == calendar.component(.month, from: last)
        fEnd.dateFormat = same ? "d" : "MMM d"
        return "\(f.string(from: daysInWeek.first ?? weekAnchor)) – \(fEnd.string(from: last))"
    }

    private func eyebrow(for day: Date, isToday: Bool) -> String {
        let f = DateFormatter()
        if isToday { f.dateFormat = "EEE"; return "\(f.string(from: day).uppercased()) · TODAY" }
        f.dateFormat = "EEE d"
        return f.string(from: day).uppercased()
    }
    private func letterFor(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; return f.string(from: d)
    }
    private func abbrev(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: d)
    }
    private func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f.string(from: d)
    }
}

// MARK: - Task row used inside day cards + unscheduled card

struct TaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(task.isCompleted ? Theme.clay : Theme.ink4, lineWidth: 1.5)
                        .background(Circle().fill(task.isCompleted ? Theme.clay : Color.clear))
                        .frame(width: 20, height: 20)
                    if task.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !task.priority.flag.isEmpty {
                        Text(task.priority.flag)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.danger)
                    }
                    Text(task.title.isEmpty ? "Untitled" : task.title)
                        .font(.system(size: 15, weight: task.isCompleted ? .regular : .medium))
                        .foregroundStyle(task.isCompleted ? Theme.ink3 : Theme.ink)
                        .strikethrough(task.isCompleted, color: Theme.ink3)
                        .lineLimit(2)
                }
                if task.rolledOver {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                        Text("rolled over")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.2)
                    }
                    .foregroundStyle(Theme.clayDeep)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.claySoft, in: Capsule())
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#Preview {
    TasksView(onOpenAssistant: { _ in })
        .environment(AppStore.preview)
}
