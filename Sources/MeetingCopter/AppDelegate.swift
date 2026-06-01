import AppKit
import SwiftUI
import EventKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var menuPanel: MenuBarPanel!
    private var menuHostingController: NSHostingController<MenuBarView>!
    private var menuVisualEffect: NSVisualEffectView!
    private var outsideClickMonitor: Any?
    private var calendarMonitor: CalendarMonitor!

    private static let menuWidth: CGFloat = 280
    private static let menuMaxHeight: CGFloat = 600
    private static let menuCornerRadius: CGFloat = 10
    private static let menuGap: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Calendar monitor
        calendarMonitor = CalendarMonitor()
        calendarMonitor.onReminderTriggered = { event in
            let title = event.title ?? "Meeting"
            HelicopterOverlay.show(eventTitle: title)
        }
        calendarMonitor.requestAccess()

        // Status item — icon only (popover anchors to icon, not text)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "airplane",
                accessibilityDescription: "MeetingCopter"
            )
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.toolTip = "MeetingCopter"
            button.action = #selector(toggleMenu)
            button.target = self
        }

        setupMenuPanel()
    }

    private func setupMenuPanel() {
        // NSHostingController manages SwiftUI lifecycle properly; using
        // NSHostingView directly tends to skip layout passes when hosted
        // in a borderless NSPanel, which leaves SwiftUI Text un-rendered.
        menuHostingController = NSHostingController(rootView: MenuBarView(monitor: calendarMonitor))

        // Round corners via maskImage instead of layer.cornerRadius; the
        // layer mask interferes with SwiftUI's own CALayer hierarchy and
        // makes Text disappear in some macOS 14+ releases.
        menuVisualEffect = NSVisualEffectView()
        menuVisualEffect.material = .menu
        menuVisualEffect.state = .active
        menuVisualEffect.blendingMode = .behindWindow
        menuVisualEffect.maskImage = Self.roundedMaskImage(cornerRadius: Self.menuCornerRadius)

        let hosted = menuHostingController.view
        hosted.translatesAutoresizingMaskIntoConstraints = false
        menuVisualEffect.addSubview(hosted)
        NSLayoutConstraint.activate([
            hosted.topAnchor.constraint(equalTo: menuVisualEffect.topAnchor),
            hosted.leadingAnchor.constraint(equalTo: menuVisualEffect.leadingAnchor),
            hosted.trailingAnchor.constraint(equalTo: menuVisualEffect.trailingAnchor),
            hosted.bottomAnchor.constraint(equalTo: menuVisualEffect.bottomAnchor),
        ])

        let initialRect = NSRect(x: 0, y: 0, width: Self.menuWidth, height: 320)
        menuPanel = MenuBarPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        menuPanel.level = .popUpMenu
        menuPanel.isMovable = false
        menuPanel.hidesOnDeactivate = false
        menuPanel.backgroundColor = .clear
        menuPanel.isOpaque = false
        menuPanel.hasShadow = true
        menuPanel.delegate = self
        menuPanel.contentView = menuVisualEffect
    }

    private static func roundedMaskImage(cornerRadius r: CGFloat) -> NSImage {
        let edge = r * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }

    func applicationWillTerminate(_ notification: Notification) {
        calendarMonitor?.stopPolling()
        HelicopterOverlay.dismiss()
        stopOutsideClickMonitor()
    }

    @objc private func toggleMenu() {
        guard let button = statusItem.button else { return }
        if menuPanel.isVisible {
            hideMenu()
        } else {
            showMenu(under: button)
        }
    }

    private func showMenu(under button: NSStatusBarButton) {
        // Compute the SwiftUI content's natural size, then commit it to the
        // panel BEFORE positioning — otherwise the panel keeps its initial
        // size and ends up clipping or mis-positioned.
        let target = NSSize(width: Self.menuWidth, height: Self.menuMaxHeight)
        let fitting = menuHostingController.sizeThatFits(in: target)
        let height = max(80, min(Self.menuMaxHeight, fitting.height))
        let size = NSSize(width: Self.menuWidth, height: height)
        menuHostingController.preferredContentSize = size
        menuPanel.setContentSize(size)

        positionPanel(under: button)
        menuPanel.makeKeyAndOrderFront(nil)
        startOutsideClickMonitor()
    }

    private func hideMenu() {
        guard menuPanel.isVisible else { return }
        menuPanel.orderOut(nil)
        stopOutsideClickMonitor()
    }

    private func positionPanel(under button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonRectOnScreen = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        let panelSize = menuPanel.frame.size
        let x = buttonRectOnScreen.midX - panelSize.width / 2
        let y = buttonRectOnScreen.minY - panelSize.height - Self.menuGap
        menuPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Outside-click dismiss

    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.hideMenu() }
        }
    }

    private func stopOutsideClickMonitor() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === menuPanel else { return }
        hideMenu()
    }
}

// Borderless panel that can become key while keeping the app in
// .accessory mode — required so SwiftUI's responder chain (Text layout,
// keyboard focus, etc.) is wired up.
final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
