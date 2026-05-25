import SwiftUI

/// Direction A Assistant sheet. AI proposes parsed-event preview cards;
/// user taps Add / Edit / Discard.
struct AssistantSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Pre-fill the input when opened from the inline pill.
    let initialDraft: String?

    @State private var input: String = ""
    @State private var isSending: Bool = false
    @State private var voice = VoiceService()
    @State private var error: String?

    private let chat = AIChatService()

    init(initialDraft: String? = nil) {
        self.initialDraft = initialDraft
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                thread

                inputDock
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            .background(Theme.paper.ignoresSafeArea())
        }
        .onAppear {
            if let draft = initialDraft, !draft.isEmpty {
                input = draft
            }
        }
        .onChange(of: voice.state) { _, new in handleVoiceState(new) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Assistant")
                .font(.system(size: 22, weight: .bold))
                .kerning(-0.4)
                .foregroundStyle(Theme.ink)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 32, height: 32)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if store.chatHistory.isEmpty {
                        emptyState
                            .padding(.top, 24)
                    } else {
                        ForEach(store.chatHistory) { msg in
                            MessageRow(message: msg,
                                onAdd:     { id in handleAdd(message: msg, actionId: id) },
                                onDiscard: { id in handleDiscard(message: msg, actionId: id) },
                                onEdit:    { id in handleEdit(message: msg, actionId: id) },
                                onUndo:    { id in handleUndo(message: msg, actionId: id) })
                                .id(msg.id)
                        }
                    }

                    if isSending {
                        HStack(alignment: .top, spacing: 8) {
                            sparkleAvatar
                            TypingBubble()
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                    }

                    if let err = error {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 16)
                    }

                    if !store.chatHistory.isEmpty && !isSending {
                        suggestionChips
                            .padding(.top, 6)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: store.chatHistory.count) { _, _ in
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: isSending) { _, _ in
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            sparkleAvatar
            Text("Ask anything about your schedule")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
            suggestionChips
        }
        .frame(maxWidth: .infinity)
    }

    private var suggestionChips: some View {
        let prompts = ["What's tomorrow?", "Plan Saturday", "Find 30 min today"]
        return HStack(spacing: 8) {
            ForEach(prompts, id: \.self) { p in
                Button {
                    input = p
                    send()
                } label: {
                    Text(p)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.cardSoft, in: Capsule())
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sparkleAvatar: some View {
        ZStack {
            Circle().fill(Theme.claySoft).frame(width: 28, height: 28)
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.clay)
        }
    }

    // MARK: - Input dock

    private var inputDock: some View {
        HStack(spacing: 10) {
            Button { toggleListening() } label: {
                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isListening ? .white : Theme.clay)
                    .frame(width: 30, height: 30)
                    .background(isListening ? Theme.danger : Theme.cardSoft, in: Circle())
                    .scaleEffect(isListening ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isListening)
            }
            .buttonStyle(.plain)

            TextField(isListening ? "Listening…" : "Reply or ask anything…",
                      text: $input, axis: .vertical)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .lineLimit(1...4)
                .disabled(isSending)
                .onSubmit { send() }

            Button { send() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Theme.clay : Theme.ink4, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 48)
        .background(Capsule(style: .continuous).fill(Theme.card))
        .overlay(Capsule(style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }
    private var isListening: Bool {
        if case .listening = voice.state { return true }
        return false
    }

    // MARK: - Send / action handlers

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        input = ""
        error = nil
        isSending = true

        let userMsg = ChatMessage(role: .user, text: text)
        store.appendChatMessage(userMsg)
        let snapshot = store.chatHistory

        Task {
            do {
                let assistant = try await chat.send(history: snapshot, store: store)
                store.appendChatMessage(assistant)
            } catch {
                self.error = error.localizedDescription
            }
            isSending = false
        }
    }

    private func handleAdd(message: ChatMessage, actionId: String) {
        guard let action = message.actions.first(where: { $0.id == actionId }),
              action.status == .proposed else { return }
        if store.apply(action) {
            store.setActionStatus(messageId: message.id, actionId: actionId, status: .applied)
        }
    }

    private func handleDiscard(message: ChatMessage, actionId: String) {
        store.setActionStatus(messageId: message.id, actionId: actionId, status: .discarded)
    }

    private func handleEdit(message: ChatMessage, actionId: String) {
        // Phase 1 of edit: drop the proposal text into the input so the user
        // can retype with corrections. Full prefilled editor is a future polish.
        guard let action = message.actions.first(where: { $0.id == actionId }) else { return }
        store.setActionStatus(messageId: message.id, actionId: actionId, status: .discarded)
        input = "Edit: \(action.displayTitle) — "
    }

    private func handleUndo(message: ChatMessage, actionId: String) {
        guard let action = message.actions.first(where: { $0.id == actionId }),
              action.status == .applied, !action.isUndone else { return }
        if store.undo(action) {
            store.setActionStatus(messageId: message.id, actionId: actionId, status: .applied, isUndone: true)
        }
    }

    private func toggleListening() {
        error = nil
        if isListening { voice.stop() } else {
            voice.partialTranscript = ""
            voice.start()
        }
    }

    private func handleVoiceState(_ state: VoiceService.State) {
        switch state {
        case .finished(let text):
            input = text
            if !text.isEmpty { send() }
        case .error(let msg):
            error = msg
        default: break
        }
    }
}

// MARK: - Message row

private struct MessageRow: View {
    let message: ChatMessage
    let onAdd: (String) -> Void
    let onDiscard: (String) -> Void
    let onEdit: (String) -> Void
    let onUndo: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 50)
                userBubble
            } else {
                avatar
                VStack(alignment: .leading, spacing: 8) {
                    if !message.text.isEmpty { assistantText }
                    ForEach(message.actions) { action in
                        ParsedActionCard(
                            action: action,
                            onAdd:     { onAdd(action.id) },
                            onDiscard: { onDiscard(action.id) },
                            onEdit:    { onEdit(action.id) },
                            onUndo:    { onUndo(action.id) }
                        )
                    }
                }
                Spacer(minLength: 24)
            }
        }
        .padding(.horizontal, 12)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Theme.claySoft).frame(width: 28, height: 28)
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.clay)
        }
    }

    private var assistantText: some View {
        Text(message.text)
            .font(.system(size: 13))
            .lineSpacing(2)
            .foregroundStyle(Theme.ink2)
    }

    private var userBubble: some View {
        Text(message.text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 4, topTrailing: 18),
                    style: .continuous
                )
                .fill(Theme.clay)
            )
    }
}

// MARK: - Parsed action card (proposed / applied / discarded states)

private struct ParsedActionCard: View {
    let action: ChatMessage.Action
    let onAdd: () -> Void
    let onDiscard: () -> Void
    let onEdit: () -> Void
    let onUndo: () -> Void

    var body: some View {
        switch action.status {
        case .proposed:  proposedView
        case .applied:   appliedView
        case .discarded: discardedView
        }
    }

    // MARK: Proposed (full card with Add / Edit / Discard)

    private var proposedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                tintAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if let sub = subtitleLine {
                        Text(sub)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                primaryButton(title: action.isDestructive ? "Delete" : "Add",
                              tint: action.isDestructive ? Theme.danger : Theme.clay,
                              action: onAdd)
                secondaryButton(title: "Edit", action: onEdit)
                secondaryButton(title: "Discard", action: onDiscard)
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var tintAvatar: some View {
        ZStack {
            Circle().fill(Theme.cardSoft).frame(width: 28, height: 28)
            tintChip
        }
    }

    private var tintChip: some View {
        let tint = matchedTint
        return RoundedRectangle(cornerRadius: 3)
            .fill(tint.bg)
            .frame(width: 12, height: 12)
            .overlay(
                Rectangle().fill(tint.rail).frame(width: 2)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func primaryButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(tint, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.paperDeep, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: Applied (confirmation strip with Undo)

    private var appliedView: some View {
        HStack(spacing: 8) {
            Image(systemName: action.isUndone ? "arrow.uturn.backward" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(action.isUndone ? Theme.ink3 : Theme.clay)
            Text(confirmationText)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink2)
                .strikethrough(action.isUndone, color: Theme.ink3)
            Spacer(minLength: 0)
            if !action.isUndone {
                Button { onUndo() } label: {
                    Text("Undo")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.clayDeep)
                        .underline()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.cardSoft, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
    }

    private var confirmationText: String {
        let title = action.displayTitle
        switch action.kind {
        case .createEvent: return "Added “\(title)”."
        case .createTask:  return "Added task “\(title)”."
        case .updateEvent: return "Updated “\(title)”."
        case .updateTask:  return "Updated “\(title)”."
        case .deleteEvent: return "Deleted “\(title)”."
        case .deleteTask:  return "Deleted task “\(title)”."
        }
    }

    // MARK: Discarded

    private var discardedView: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink4)
            Text("Discarded — “\(action.displayTitle)”")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink3)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(0.7)
    }

    // MARK: Subtitle (date+time) + tint matching

    private var subtitleLine: String? {
        let df = DateFormatter(); df.dateFormat = "EEE, MMM d"
        let tf = DateFormatter(); tf.dateFormat = "h:mm a"
        switch action.kind {
        case .createEvent(let e), .updateEvent(let e, _), .deleteEvent(let e):
            let day = df.string(from: e.start)
            if e.allDay { return "\(day) · all day" }
            return "\(day) · \(tf.string(from: e.start)) – \(tf.string(from: e.end))"
        case .createTask(let t), .updateTask(let t, _), .deleteTask(let t):
            if let sched = t.scheduledDate {
                return df.string(from: sched)
            }
            return t.scope.label
        }
    }

    private var matchedTint: EventTint {
        let title = action.displayTitle.lowercased()
        if title.contains("lunch") || title.contains("dinner") || title.contains("coffee")
            || title.contains("breakfast") { return EventTints.butter }
        if title.contains("standup") || title.contains("meeting") || title.contains("sync")
            || title.contains("1:1") { return EventTints.sage }
        if title.contains("gym") || title.contains("run") || title.contains("workout") { return EventTints.rose }
        if title.contains("design") || title.contains("review") { return EventTints.lavender }
        return EventTints.sky
    }
}

// MARK: - Typing dots

private struct TypingBubble: View {
    @State private var phase: Int = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.ink3)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.claySoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.32, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}

#Preview {
    AssistantSheet()
        .environment(AppStore.preview)
}
