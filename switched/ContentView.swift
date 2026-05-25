import SwiftUI
import UIKit

// MARK: - Design tokens

extension UIColor {
    fileprivate convenience init(themeHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8) & 0xFF) / 255.0
        let b = CGFloat(v & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    /// A color that adapts between light and dark mode.
    static func adaptive(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(themeHex: dark)
                : UIColor(themeHex: light)
        })
    }
}

/// Central design tokens. Direction-C clay palette.
/// Two naming families intentionally:
///   - Legacy names (`bg`, `text`, `accent`, …) so existing views keep compiling
///     without a thousand-file rename — the hex values behind them are NEW.
///   - Direction-C names (`paper`, `ink`, `clay`, …) for any new code.
enum Theme {
    // === Direction C names ===
    static let paper       = Color.adaptive(light: "#FAF5EB", dark: "#1A1814")
    static let paperDeep   = Color.adaptive(light: "#F3EBDA", dark: "#27231C")
    static let card        = Color.adaptive(light: "#FFFFFF", dark: "#24211C")
    static let cardSoft    = Color.adaptive(light: "#FBF7EE", dark: "#2A2620")

    static let ink         = Color.adaptive(light: "#1F1A14", dark: "#F4ECE0")
    static let ink2        = Color.adaptive(light: "#5A4F3E", dark: "#C9BFA9")
    static let ink3        = Color.adaptive(light: "#8A7E6C", dark: "#9D9282")
    static let ink4        = Color.adaptive(light: "#BDB1A0", dark: "#5F584D")

    static let hairline    = Color.adaptive(light: "#EBE2D0", dark: "#3A352D")
    static let hairline2   = Color.adaptive(light: "#D9CCB5", dark: "#4A4337")

    static let clay        = Color.adaptive(light: "#B8845A", dark: "#C99272")
    static let clayDeep    = Color.adaptive(light: "#9D6A45", dark: "#D9A37E")
    static let claySoft    = Color.adaptive(light: "#E8D5BD", dark: "#3D3327")
    static let clayWash    = Color.adaptive(light: "#F4E9D8", dark: "#332B22")

    static let danger      = Color.adaptive(light: "#C0432D", dark: "#E36C57")
    static let dangerSoft  = Color.adaptive(light: "#F0D8D2", dark: "#4A2E28")

    // === Legacy aliases (keep older views compiling, point to new tokens) ===
    static let bg          = paper
    static let bgCard      = card
    static let bgSoft      = paperDeep
    static let text        = ink
    static let textMuted   = ink3
    static let textFaint   = ink4
    static let separator   = hairline
    static let accent      = clay
    static let accentDeep  = clayDeep
    static let accentSoft  = claySoft
}

/// Event tint pair: a saturated rail color + a pale background.
struct EventTint: Hashable {
    let name: String
    let rail: Color
    let bg: Color
}

enum EventTints {
    static let lavender = EventTint(name: "lavender",
        rail: Color.adaptive(light: "#BCB4D1", dark: "#8E84A8"),
        bg:   Color.adaptive(light: "#E3DFEE", dark: "#2F2A38"))
    static let sage     = EventTint(name: "sage",
        rail: Color.adaptive(light: "#A8B89D", dark: "#7A8A6E"),
        bg:   Color.adaptive(light: "#DDE5D6", dark: "#2A312A"))
    static let sky      = EventTint(name: "sky",
        rail: Color.adaptive(light: "#A9BCCD", dark: "#7A8FA1"),
        bg:   Color.adaptive(light: "#DDE6EF", dark: "#28323A"))
    static let rose     = EventTint(name: "rose",
        rail: Color.adaptive(light: "#C9A4A4", dark: "#A77575"),
        bg:   Color.adaptive(light: "#ECDCDC", dark: "#3A2D2D"))
    static let butter   = EventTint(name: "butter",
        rail: Color.adaptive(light: "#D4BF86", dark: "#A38E5C"),
        bg:   Color.adaptive(light: "#EFE6C9", dark: "#33301F"))

    static let all: [EventTint] = [lavender, sage, sky, rose, butter]
}

// MARK: - Root view

enum AppTab: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case tasks    = "Tasks"
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var tab: AppTab = .timeline
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    @State private var showAssistant: Bool = false
    @State private var assistantInitialDraft: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            TopTabBar(selection: $tab)

            Group {
                switch tab {
                case .timeline:
                    TimelineView(selectedDate: $selectedDate) { draft in
                        openAssistant(with: draft)
                    }
                    .transition(.opacity)
                case .tasks:
                    TasksView { draft in
                        openAssistant(with: draft)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showAssistant) {
            AssistantSheet(initialDraft: assistantInitialDraft)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func openAssistant(with draft: String?) {
        assistantInitialDraft = draft
        showAssistant = true
    }
}

// MARK: - Top tab bar

private struct TopTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    TabPill(title: tab.rawValue, isActive: selection == tab) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            selection = tab
                        }
                    }
                }
            }
            .padding(.top, 4)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

private struct TabPill: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? Theme.ink : Theme.ink3)
                    .padding(.top, 8)
                Capsule()
                    .fill(isActive ? Theme.clay : Color.clear)
                    .frame(width: 26, height: 2)
                    .offset(y: 1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environment(AppStore.preview)
}
