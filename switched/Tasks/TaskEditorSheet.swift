import SwiftUI

/// Card-style task editor sheet (matches Direction C aesthetic).
struct TaskEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let editingId: UUID?
    @State private var title: String
    @State private var notes: String
    @State private var priority: TaskItem.Priority
    @State private var hasScheduled: Bool
    @State private var scheduledDate: Date
    @State private var hasDue: Bool
    @State private var dueDate: Date

    /// Create-mode init. `defaultScheduledDate == nil` ⇒ go to backlog.
    init(defaultScheduledDate: Date?) {
        self.editingId = nil
        _title          = State(initialValue: "")
        _notes          = State(initialValue: "")
        _priority       = State(initialValue: .none)
        _hasScheduled   = State(initialValue: defaultScheduledDate != nil)
        _scheduledDate  = State(initialValue: defaultScheduledDate ?? Date())
        _hasDue         = State(initialValue: false)
        _dueDate        = State(initialValue: Date())
    }

    /// Legacy-compat init.
    init(defaultScope: TaskItem.Scope) {
        let day: Date? = (defaultScope == .today) ? Calendar.current.startOfDay(for: Date()) : nil
        self.init(defaultScheduledDate: day)
    }

    init(existing task: TaskItem) {
        self.editingId = task.id
        _title          = State(initialValue: task.title)
        _notes          = State(initialValue: task.notes)
        _priority       = State(initialValue: task.priority)
        _hasScheduled   = State(initialValue: task.scheduledDate != nil)
        _scheduledDate  = State(initialValue: task.scheduledDate ?? Date())
        _hasDue         = State(initialValue: task.dueDate != nil)
        _dueDate        = State(initialValue: task.dueDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    titleCard
                    planCard
                    priorityCard

                    if editingId != nil {
                        Button(role: .destructive) {
                            if let id = editingId,
                               let existing = store.tasks.first(where: { $0.id == id }) {
                                store.deleteTask(existing)
                            }
                            dismiss()
                        } label: {
                            Label("Delete Task", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.paperDeep)
            .navigationTitle(editingId == nil ? "New Task" : "Edit Task")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 32, height: 32)
                            .background(Theme.paperDeep, in: Circle())
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(canSave ? Theme.clay : Theme.paperDeep, in: Circle())
                    }
                    .disabled(!canSave)
                }
            }
            .tint(Theme.clayDeep)
        }
    }

    // MARK: - Cards

    private var titleCard: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title)
                .font(.system(size: 17, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            Divider().background(Theme.hairline)
            TextField("Notes", text: $notes, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(2...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var planCard: some View {
        VStack(spacing: 0) {
            Toggle("Schedule on a day", isOn: $hasScheduled)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .tint(Theme.clay)
            if hasScheduled {
                Divider().background(Theme.hairline)
                DatePicker("Day", selection: $scheduledDate, displayedComponents: [.date])
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .tint(Theme.clayDeep)
            }
            Divider().background(Theme.hairline)
            Toggle("Has deadline", isOn: $hasDue)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .tint(Theme.clay)
            if hasDue {
                Divider().background(Theme.hairline)
                DatePicker("Due by", selection: $dueDate, displayedComponents: [.date])
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .tint(Theme.clayDeep)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var priorityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRIORITY")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(Theme.ink3)
                .padding(.horizontal, 4)
            HStack(spacing: 6) {
                ForEach(TaskItem.Priority.allCases) { p in
                    PriorityPill(
                        priority: p,
                        isSelected: priority == p,
                        action: { priority = p }
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedScheduled: Date? = hasScheduled
            ? Calendar.current.startOfDay(for: scheduledDate)
            : nil
        let resolvedDue: Date? = hasDue ? dueDate : nil

        if let id = editingId {
            if var existing = store.tasks.first(where: { $0.id == id }) {
                existing.title = cleaned
                existing.notes = notes
                existing.priority = priority
                existing.scheduledDate = resolvedScheduled
                existing.dueDate = resolvedDue
                existing.rolledOver = false
                if let d = resolvedScheduled, Calendar.current.isDateInToday(d) {
                    existing.scope = .today
                } else {
                    existing.scope = .week
                }
                store.updateTask(existing)
            }
        } else {
            let legacyScope: TaskItem.Scope =
                (resolvedScheduled.map { Calendar.current.isDateInToday($0) } ?? false) ? .today : .week
            store.addTask(TaskItem(
                title: cleaned,
                notes: notes,
                scope: legacyScope,
                priority: priority,
                dueDate: resolvedDue,
                scheduledDate: resolvedScheduled
            ))
        }
        dismiss()
    }
}

private struct PriorityPill: View {
    let priority: TaskItem.Priority
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !priority.flag.isEmpty {
                    Text(priority.flag)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? .white : Theme.danger)
                }
                Text(priority.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Theme.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.clay : Theme.paperDeep, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TaskEditorSheet(defaultScheduledDate: Calendar.current.startOfDay(for: Date()))
        .environment(AppStore.preview)
}
