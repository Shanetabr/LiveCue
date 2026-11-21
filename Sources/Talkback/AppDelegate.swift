import AppKit
import SwiftUI

/// Asks to save unsaved work before quitting. Closing the main window quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: Model?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (model?.confirmDiscardChanges(action: "quit") ?? true) ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Menu items and buttons that open the Status window.
struct OpenStatusButton: View {
    @Environment(\.openWindow) private var openWindow
    var model: Model
    var runTest = false
    var title: String

    var body: some View {
        Button(title) {
            openWindow(id: "status")
            if runTest { model.connectionTest.run() }
        }
    }
}
