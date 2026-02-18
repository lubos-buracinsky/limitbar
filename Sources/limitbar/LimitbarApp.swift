import AppKit
import SwiftUI

final class LimitbarAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

@main
struct LimitbarApp: App {
    @NSApplicationDelegateAdaptor(LimitbarAppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            LimitbarMenuView(state: state)
                .frame(minWidth: 420)
        } label: {
            Text(state.menuBarLabel)
                .font(.caption.weight(.semibold))
        }
        .menuBarExtraStyle(.window)
    }
}
