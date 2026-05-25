import Foundation
import SwiftUI

struct Event: Identifiable, Codable, Hashable {
    enum RepeatRule: String, Codable, CaseIterable, Identifiable {
        case never, daily, weekly, biweekly, monthly, yearly

        var id: String { rawValue }
        var label: String {
            switch self {
            case .never:    "Never"
            case .daily:    "Every Day"
            case .weekly:   "Every Week"
            case .biweekly: "Every 2 Weeks"
            case .monthly:  "Every Month"
            case .yearly:   "Every Year"
            }
        }
    }

    let id: UUID
    var title: String
    var location: String
    var start: Date
    var end: Date
    var allDay: Bool
    var colorHex: String
    var iconName: String           // SF Symbol
    var notes: String
    var repeatRule: RepeatRule
    var alertMinutesBefore: Int?   // nil = none

    init(
        id: UUID = UUID(),
        title: String = "",
        location: String = "",
        start: Date = .now,
        end: Date = Date().addingTimeInterval(3600),
        allDay: Bool = false,
        colorHex: String = EventColor.presets[0].hex,
        iconName: String = "calendar",
        notes: String = "",
        repeatRule: RepeatRule = .never,
        alertMinutesBefore: Int? = 15
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.start = start
        self.end = end
        self.allDay = allDay
        self.colorHex = colorHex
        self.iconName = iconName
        self.notes = notes
        self.repeatRule = repeatRule
        self.alertMinutesBefore = alertMinutesBefore
    }
}

struct EventColor: Hashable {
    let name: String
    let hex: String

    /// Muted palette designed to harmonize with the beige + white app theme.
    static let presets: [EventColor] = [
        .init(name: "Tan",   hex: "#C9B188"),
        .init(name: "Sage",  hex: "#A8B89A"),
        .init(name: "Rose",  hex: "#D9A8A0"),
        .init(name: "Slate", hex: "#A8B4C2"),
        .init(name: "Lilac", hex: "#B8A8C8"),
        .init(name: "Coral", hex: "#E0AA90")
    ]
}

enum EventIcon {
    static let presets: [String] = [
        "calendar",
        "person.2.fill",
        "paintpalette.fill",
        "fork.knife",
        "bubble.left.fill",
        "book.fill",
        "dumbbell.fill",
        "cup.and.saucer.fill",
        "bicycle",
        "airplane",
        "bed.double.fill",
        "phone.fill"
    ]

    /// Heuristic to pick an icon based on the event title — used after voice parsing.
    static func suggest(for title: String) -> String {
        let t = title.lowercased()
        if t.contains("run") || t.contains("gym") || t.contains("workout") || t.contains("yoga") {
            return "dumbbell.fill"
        }
        if t.contains("lunch") || t.contains("dinner") || t.contains("breakfast") || t.contains("coffee") {
            return "fork.knife"
        }
        if t.contains("call") || t.contains("phone") || t.contains("1:1") {
            return "phone.fill"
        }
        if t.contains("standup") || t.contains("meeting") || t.contains("sync") {
            return "person.2.fill"
        }
        if t.contains("read") || t.contains("book") || t.contains("study") {
            return "book.fill"
        }
        if t.contains("flight") || t.contains("travel") || t.contains("trip") {
            return "airplane"
        }
        if t.contains("sleep") || t.contains("rest") || t.contains("nap") {
            return "bed.double.fill"
        }
        if t.contains("design") || t.contains("paint") {
            return "paintpalette.fill"
        }
        return "calendar"
    }
}

extension Color {
    /// Build a SwiftUI Color from a hex string like "#C9A989".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
