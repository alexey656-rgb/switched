import SwiftUI

/// The bottom-of-screen AI input pill that appears on Timeline + Tasks.
/// Tapping anywhere on it opens the full AssistantSheet, pre-filling the
/// input if the user already started typing here.
struct InlineAIPill: View {
    let placeholder: String
    let onOpen: (String?) -> Void
    let sendIcon: String      // "arrow.up" on Timeline, "plus" on Tasks

    @State private var preview: String = ""
    @FocusState private var focused: Bool

    init(
        placeholder: String = "Lunch with Sarah at 1?",
        sendIcon: String = "arrow.up",
        onOpen: @escaping (String?) -> Void
    ) {
        self.placeholder = placeholder
        self.sendIcon = sendIcon
        self.onOpen = onOpen
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.clay)
                .padding(.leading, 16)

            ZStack(alignment: .leading) {
                if preview.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink3)
                }
                Text(preview)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onOpen(preview.isEmpty ? nil : preview)
                preview = ""
            } label: {
                Image(systemName: sendIcon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.clay, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
        }
        .frame(height: 48)
        .background(
            Capsule(style: .continuous).fill(Theme.card)
        )
        .overlay(
            Capsule(style: .continuous).stroke(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
        .contentShape(Capsule())
        // Tap anywhere except the send button → open sheet.
        .onTapGesture {
            onOpen(preview.isEmpty ? nil : preview)
            preview = ""
        }
    }
}

#Preview {
    VStack(spacing: 14) {
        InlineAIPill(placeholder: "Lunch with Sarah at 1?", sendIcon: "arrow.up") { _ in }
        InlineAIPill(placeholder: "Add a task…", sendIcon: "plus") { _ in }
    }
    .padding(20)
    .background(Theme.paper)
}
