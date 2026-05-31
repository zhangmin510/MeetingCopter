import AppKit
import SwiftUI
import EventKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var calendarMonitor: CalendarMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Calendar monitor
        calendarMonitor = CalendarMonitor()
        calendarMonitor.onReminderTriggered = { event in
            let title = event.title ?? "Meeting"
            HelicopterOverlay.show(eventTitle: title)
        }
        calendarMonitor.requestAccess()

        // Status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "airplane",
                accessibilityDescription: "MeetingCopter"
            )
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.title = "MeetingCopter"
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Popover with SwiftUI content
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(monitor: calendarMonitor)
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        calendarMonitor?.stopPolling()
        HelicopterOverlay.dismiss()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
