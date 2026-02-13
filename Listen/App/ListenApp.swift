import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app is recognized as a proper UI application
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct ListenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            if let img = NSImage(named: "MenuBarIconTemplate") {
                Image(nsImage: img)
            } else {
                Image(systemName: "mic.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
