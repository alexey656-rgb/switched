import SwiftUI

/// iOS Calendar-style new-event editor with compact icon header,
/// Event/Reminder toggle, and inline date+time pickers per row.
struct EventEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Mode { case event, reminder }

    private let editingId: UUID?
    @State private var mode: Mode = .event

    @State private var title: String
    @State private var location: String
    @State private var notes: String
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var repeatRule: Event.RepeatRule
    @State private var alertMinutes: Int?
    @State private var colorHex: String
    @State private var iconName: String

    @State private var expanded: Field? = nil

    private enum Field { case startDate, startTime, endDate, endTime }

    init(initialStart: Date?) {
        self.editingId = nil
        let s = initialStart ?? Date()
        _title       = State(initialValue: "")
        _location    = State(initialValue: "")
        _notes       = State(initialValue: "")
        _start       = State(initialValue: s)
        _end         = State(initialValue: s.addingTimeInterval(3600))
        _allDay      = State(initialValue: false)
        _repeatRule  = State(initialValue: .never)
        _alertMinutes = State(initialValue: 15)
        _colorHex    = State(initialValue: EventColor.presets[0].hex)
        _iconName    = State(initialValue: EventIcon.presets[0])
    }

    init(existing event: Event) {
        self.editingId = event.id
        _title       = State(initialValue: event.title)
        _location    = State(initialValue: event.location)
        _notes       = State(initialValue: event.notes)
        _start       = State(initialValue: event.start)
        _end         = State(initialValue: event.end)
        _allDay      = State(initialValue: event.allDay)
        _repeatRule  = State(initialValue: event.repeatRule)
        _alertMinutes = State(initialValue: event.alertMinutesBefore)
        _colorHex    = State(initialValue: event.colorHex)
        _iconName    = State(initialValue: event.iconName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    modeToggle
                        .padding(.top, 8)

                    titleCard
                    timeCard
                    repeatCard
                    metaCard
                    iconCard
                    colorCard
                    notesCard

                    if editingId != nil {
                        Button(role: .destructive) { delete() } label: {
                            Label("Delete Event", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bgSoft)
            .navigationTitle(editingId == nil ? "New" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 32, height: 32)
                            .background(Theme.bgSoft, in: Circle())
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(isValid ? Theme.accent : Theme.bgSoft, in: Circle())
                    }
                    .disabled(!isValid)
                }
            }
            .onChange(of: start) { _, newStart in
                if end <= newStart { end = newStart.addingTimeInterval(3600) }
            }
        }
    }

    // MARK: - Subviews

    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeButton(.event,    "Event")
            modeButton(.reminder, "Reminder")
        }
        .padding(2)
        .background(Theme.bgSoft.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9).stroke(Theme.separator, lineWidth: 0.5)
        )
    }
    private func modeButton(_ m: Mode, _ label: String) -> some View {
        Button { mode = m } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(mode == m ? Theme.bgCard : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .shadow(color: mode == m ? Color.black.opacity(0.06) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var titleCard: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title)
                .font(.system(size: 17, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            Divider()
            TextField("Location", text: $location)
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private var timeCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("All-day")
                Spacer()
                Toggle("", isOn: $allDay).labelsHidden().tint(Theme.accent)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()

            startsRow
            inlinePicker(for: .startDate, binding: $start, mode: .date)
            inlinePicker(for: .startTime, binding: $start, mode: .hourAndMinute)
            Divider()

            endsRow
            inlinePicker(for: .endDate, binding: $end, mode: .date)
            inlinePicker(for: .endTime, binding: $end, mode: .hourAndMinute)
        }
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private var startsRow: some View {
        HStack {
            Text("Starts").font(.system(size: 15, weight: .medium))
            Spacer()
            pill(text: dateLabel(start), field: .startDate)
            pill(text: timeLabel(start), field: .startTime)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var endsRow: some View {
        HStack {
            Text("Ends").font(.system(size: 15, weight: .medium))
            Spacer()
            pill(text: dateLabel(end), field: .endDate)
            pill(text: timeLabel(end), field: .endTime)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func pill(text: String, field: Field) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded = (expanded == field) ? nil : field
            }
        } label: {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    expanded == field ? Theme.accentSoft : Theme.bgSoft,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(expanded == field ? Theme.accentDeep : Theme.text)
        }
        .buttonStyle(.plain)
    }

    private func inlinePicker(for field: Field, binding: Binding<Date>, mode: DatePicker.Components) -> some View {
        Group {
            if expanded == field {
                Group {
                    if mode == .date {
                        DatePicker("", selection: binding, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                            .tint(Theme.accentDeep)
                    } else {
                        DatePicker("", selection: binding, displayedComponents: [.hourAndMinute])
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }

    private var repeatCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Repeat").font(.system(size: 15, weight: .medium))
                Spacer()
                Picker("", selection: $repeatRule) {
                    ForEach(Event.RepeatRule.allCases) { r in Text(r.label).tag(r) }
                }
                .labelsHidden()
                .tint(Theme.textMuted)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private var metaCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Calendar").font(.system(size: 15, weight: .medium))
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: colorHex)).frame(width: 10, height: 10)
                    Text("Personal").foregroundStyle(Theme.textMuted)
                    Image(systemName: "chevron.right").foregroundStyle(Theme.textFaint).font(.system(size: 12))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            HStack {
                Text("Invitees").font(.system(size: 15, weight: .medium))
                Spacer()
                Text("None").foregroundStyle(Theme.textMuted)
                Image(systemName: "chevron.right").foregroundStyle(Theme.textFaint).font(.system(size: 12)).padding(.leading, 4)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            HStack {
                Text("Alert").font(.system(size: 15, weight: .medium))
                Spacer()
                Picker("", selection: Binding(
                    get: { alertMinutes ?? -1 },
                    set: { alertMinutes = $0 < 0 ? nil : $0 }
                )) {
                    Text("None").tag(-1)
                    Text("5 minutes before").tag(5)
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                    Text("1 day before").tag(1440)
                }
                .labelsHidden()
                .tint(Theme.textMuted)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private var iconCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Icon")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EventIcon.presets, id: \.self) { name in
                        Button { iconName = name } label: {
                            Image(systemName: name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(iconName == name ? .white : Theme.text)
                                .frame(width: 44, height: 44)
                                .background(iconName == name ? Color(hex: colorHex) : Theme.bgSoft, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Color")
            HStack(spacing: 12) {
                ForEach(EventColor.presets, id: \.hex) { c in
                    Button { colorHex = c.hex } label: {
                        Circle()
                            .fill(Color(hex: c.hex))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle().stroke(Theme.text, lineWidth: c.hex == colorHex ? 2 : 0).padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var notesCard: some View {
        TextField("Notes", text: $notes, axis: .vertical)
            .lineLimit(3...6)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.bgCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textMuted)
            .kerning(0.4)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }

    // MARK: - Helpers

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && end > start
    }

    private func dateLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
    private func timeLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func save() {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid else { return }

        // Reminder mode → save as task scheduled on the picked day.
        if mode == .reminder {
            let day = Calendar.current.startOfDay(for: start)
            let legacyScope: TaskItem.Scope = Calendar.current.isDateInToday(day) ? .today : .week
            store.addTask(TaskItem(
                title: cleaned,
                notes: notes,
                scope: legacyScope,
                priority: .none,
                dueDate: nil,
                scheduledDate: day
            ))
            dismiss()
            return
        }

        if let id = editingId {
            if var existing = store.events.first(where: { $0.id == id }) {
                existing.title = cleaned
                existing.location = location
                existing.start = start
                existing.end = end
                existing.allDay = allDay
                existing.colorHex = colorHex
                existing.iconName = iconName
                existing.notes = notes
                existing.repeatRule = repeatRule
                existing.alertMinutesBefore = alertMinutes
                store.updateEvent(existing)
            }
        } else {
            store.addEvent(Event(
                title: cleaned,
                location: location,
                start: start,
                end: end,
                allDay: allDay,
                colorHex: colorHex,
                iconName: iconName,
                notes: notes,
                repeatRule: repeatRule,
                alertMinutesBefore: alertMinutes
            ))
        }
        dismiss()
    }

    private func delete() {
        if let id = editingId,
           let existing = store.events.first(where: { $0.id == id }) {
            store.deleteEvent(existing)
        }
        dismiss()
    }
}

#Preview {
    EventEditorSheet(initialStart: nil)
        .environment(AppStore.preview)
}
