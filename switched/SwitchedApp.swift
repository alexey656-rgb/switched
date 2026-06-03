import SwiftUI

@main
struct SwitchedApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                #if os(macOS)
                .frame(minWidth: 720, minHeight: 600)
                #endif
                .onChange(of: scenePhase) { _, phase in
                    // When the app comes back from the background, pull
                    // the latest snapshot from iCloud KVS in case another
                    // device wrote something we haven't picked up yet.
                    if phase == .active {
                        store.refreshFromICloud()
                    }
                }
        }
        #if os(macOS) || targetEnvironment(macCatalyst)
        .windowResizability(.contentMinSize)
        .commands {
            // Notification-driven menu commands. ContentView listens for
            // these to switch tabs / move days via ⌘1-3 and ⌘[ / ⌘].
            CommandGroup(replacing: .newItem) {
                Button("New Event") {
                    NotificationCenter.default.post(name: .switchedNewEvent, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
                Button("New Task") {
                    NotificationCenter.default.post(name: .switchedNewTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("Navigate") {
                Button("Timeline") {
                    NotificationCenter.default.post(name: .switchedSelectTab, object: "timeline")
                }
                .keyboardShortcut("1", modifiers: [.command])
                Button("Tasks") {
                    NotificationCenter.default.post(name: .switchedSelectTab, object: "tasks")
                }
                .keyboardShortcut("2", modifiers: [.command])
                Button("Assistant…") {
                    NotificationCenter.default.post(name: .switchedOpenAssistant, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
                Divider()
                Button("Previous Day") {
                    NotificationCenter.default.post(name: .switchedShiftDay, object: -1)
                }
                .keyboardShortcut("[", modifiers: [.command])
                Button("Next Day") {
                    NotificationCenter.default.post(name: .switchedShiftDay, object: 1)
                }
                .keyboardShortcut("]", modifiers: [.command])
                Button("Today") {
                    NotificationCenter.default.post(name: .switchedShiftDay, object: 0)
                }
                .keyboardShortcut("t", modifiers: [.command])
            }
        }
        #endif
    }
}

extension Notification.Name {
    static let switchedSelectTab     = Notification.Name("switched.selectTab")
    static let switchedShiftDay      = Notification.Name("switched.shiftDay")
    static let switchedNewEvent      = Notification.Name("switched.newEvent")
    static let switchedNewTask       = Notification.Name("switched.newTask")
    static let switchedOpenAssistant = Notification.Name("switched.openAssistant")
}
