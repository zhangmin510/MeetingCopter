import AppKit
import CoreVideo
import Foundation

// MARK: - Overlay Manager

@MainActor
enum HelicopterOverlay {
    private static var overlayWindow: NSWindow?
    private static var overlayView: HelicopterView?
    private static var displayLinkHelper: DisplayLinkHelper?
    private static var engine: PhysicsEngine?

    static func show(eventTitle: String) {
        guard overlayWindow == nil else { return } // Already showing

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        // Create engine
        let physicsEngine = PhysicsEngine()
        physicsEngine.createFlightShape()

        // Flight path: left-to-right, slowly across the center of the screen.
        let startX = screenFrame.minX - 280
        let endX = screenFrame.maxX + 360
        let baseY = screenFrame.midY

        physicsEngine.flightPath = { t in
            let x = startX + (endX - startX) * t
            return CGPoint(x: x, y: baseY)
        }
        physicsEngine.placeShape(anchorAt: physicsEngine.flightPath(0))
        physicsEngine.usesRigidFlight = true
        physicsEngine.flightSpeed = FlightPreferences.currentFlightSpeed
        physicsEngine.onComplete = {
            DispatchQueue.main.async {
                HelicopterOverlay.dismiss()
            }
        }
        engine = physicsEngine

        // Create overlay window
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.hasShadow = false

        // Create custom view
        let view = HelicopterView(frame: screenFrame)
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.bannerText = "\(eventTitle) in 5 min"
        overlayView = view
        window.contentView = view

        window.orderFront(nil)
        overlayWindow = window

        // Start display link
        startDisplayLink()
    }

    private static func startDisplayLink() {
        displayLinkHelper = DisplayLinkHelper()
        displayLinkHelper?.callback = { tick() }
        displayLinkHelper?.start()
    }

    private static func tick() {
        guard let physicsEngine = engine,
              let view = overlayView else { return }

        physicsEngine.flightSpeed = FlightPreferences.currentFlightSpeed
        physicsEngine.step(dt: 1.0 / 60.0)
        view.physicsEngine = physicsEngine
        view.needsDisplay = true
    }

    static func dismiss() {
        displayLinkHelper?.stop()
        displayLinkHelper = nil
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayView = nil
        engine = nil
    }
}

// MARK: - Display Link Helper

@MainActor
private final class DisplayLinkHelper {
    nonisolated(unsafe) var callback: (() -> Void)?
    nonisolated(unsafe) private var displayLink: CVDisplayLink?

    func start() {
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard result == kCVReturnSuccess, let dl = displayLink else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context in
            let helper = Unmanaged<DisplayLinkHelper>.fromOpaque(context!).takeUnretainedValue()
            DispatchQueue.main.async {
                helper.callback?()
            }
            return kCVReturnSuccess
        }
        CVDisplayLinkSetOutputCallback(dl, callback, selfPtr)
        CVDisplayLinkStart(dl)
    }

    func stop() {
        guard let dl = displayLink else { return }
        CVDisplayLinkStop(dl)
        displayLink = nil
    }

    deinit {
        if let dl = displayLink {
            CVDisplayLinkStop(dl)
        }
    }
}

// MARK: - Thread-Safe Rendering Snapshot

/// Immutable snapshot of engine data captured on the main thread
/// before draw, so rendering never reads concurrently-mutated state.
struct RenderSnapshot {
    let points: [VerletPoint]
    let constraints: [LengthConstraint]
}

// MARK: - Custom View

final class HelicopterView: NSView {
    var physicsEngine: PhysicsEngine?
    var bannerText: String = ""
    private var snapshot: RenderSnapshot?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Capture an immutable snapshot on the main thread before drawing.
        // This prevents draw() from reading points that are being mutated
        // by the physics engine in the same frame.
        guard let engine = physicsEngine else { return }
        let points = engine.points
        snapshot = RenderSnapshot(points: points, constraints: [])

        guard !points.isEmpty, points.count >= 18 else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let anchor = points[0].position

        drawBanner(context: context, helicopterAnchor: anchor)
        drawHelicopter(context: context, anchor: anchor)
    }

    private func drawHelicopter(context: CGContext, anchor: CGPoint) {
        context.saveGState()
        defer { context.restoreGState() }

        let bodyRect = CGRect(x: anchor.x - 138, y: anchor.y - 34, width: 122, height: 62)
        let cabinRect = CGRect(x: anchor.x - 86, y: anchor.y - 4, width: 58, height: 30)
        let tailStart = CGPoint(x: bodyRect.minX + 8, y: bodyRect.midY - 2)
        let tailEnd = CGPoint(x: anchor.x - 226, y: bodyRect.midY - 6)
        let rotorCenter = CGPoint(x: bodyRect.midX + 8, y: bodyRect.maxY + 34)
        let landingY = bodyRect.minY - 26

        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.setStrokeColor(CGColor(red: 0.42, green: 0.05, blue: 0.04, alpha: 1))
        context.setLineWidth(9)
        context.move(to: CGPoint(x: rotorCenter.x - 94, y: rotorCenter.y))
        context.addLine(to: CGPoint(x: rotorCenter.x + 94, y: rotorCenter.y))
        context.strokePath()

        context.setLineWidth(5)
        context.move(to: rotorCenter)
        context.addLine(to: CGPoint(x: bodyRect.midX + 8, y: bodyRect.maxY - 2))
        context.strokePath()

        let tailPath = CGMutablePath()
        tailPath.move(to: tailStart)
        tailPath.addLine(to: tailEnd)
        tailPath.addLine(to: CGPoint(x: tailEnd.x + 8, y: tailEnd.y - 16))
        tailPath.move(to: tailEnd)
        tailPath.addLine(to: CGPoint(x: tailEnd.x + 8, y: tailEnd.y + 16))
        context.setStrokeColor(CGColor(red: 0.72, green: 0.04, blue: 0.03, alpha: 1))
        context.setLineWidth(8)
        context.addPath(tailPath)
        context.strokePath()

        context.setStrokeColor(CGColor(red: 0.42, green: 0.05, blue: 0.04, alpha: 1))
        context.setLineWidth(4)
        context.move(to: CGPoint(x: tailEnd.x - 16, y: tailEnd.y))
        context.addLine(to: CGPoint(x: tailEnd.x + 24, y: tailEnd.y))
        context.move(to: CGPoint(x: tailEnd.x + 4, y: tailEnd.y - 20))
        context.addLine(to: CGPoint(x: tailEnd.x + 4, y: tailEnd.y + 20))
        context.strokePath()

        let bodyPath = CGPath(
            roundedRect: bodyRect,
            cornerWidth: 26,
            cornerHeight: 26,
            transform: nil
        )
        context.setFillColor(CGColor(red: 0.9, green: 0.05, blue: 0.04, alpha: 0.98))
        context.addPath(bodyPath)
        context.fillPath()

        context.setStrokeColor(CGColor(red: 0.42, green: 0.04, blue: 0.03, alpha: 0.95))
        context.setLineWidth(3)
        context.addPath(bodyPath)
        context.strokePath()

        let nosePath = CGMutablePath()
        nosePath.move(to: CGPoint(x: bodyRect.maxX - 8, y: bodyRect.minY + 8))
        nosePath.addQuadCurve(
            to: CGPoint(x: anchor.x + 18, y: bodyRect.midY - 2),
            control: CGPoint(x: anchor.x + 8, y: bodyRect.minY + 8)
        )
        nosePath.addQuadCurve(
            to: CGPoint(x: bodyRect.maxX - 10, y: bodyRect.maxY - 8),
            control: CGPoint(x: anchor.x + 8, y: bodyRect.maxY - 8)
        )
        nosePath.closeSubpath()
        context.setFillColor(CGColor(red: 0.95, green: 0.11, blue: 0.08, alpha: 0.98))
        context.addPath(nosePath)
        context.fillPath()

        let cabinPath = CGPath(
            roundedRect: cabinRect,
            cornerWidth: 14,
            cornerHeight: 14,
            transform: nil
        )
        context.setFillColor(CGColor(red: 0.5, green: 0.82, blue: 0.96, alpha: 0.9))
        context.addPath(cabinPath)
        context.fillPath()

        context.setStrokeColor(CGColor(red: 0.23, green: 0.36, blue: 0.42, alpha: 0.8))
        context.setLineWidth(2)
        context.addPath(cabinPath)
        context.strokePath()

        context.setStrokeColor(CGColor(red: 0.18, green: 0.12, blue: 0.1, alpha: 0.82))
        context.setLineWidth(4)
        context.move(to: CGPoint(x: bodyRect.minX + 24, y: bodyRect.minY + 2))
        context.addLine(to: CGPoint(x: bodyRect.minX + 34, y: landingY))
        context.move(to: CGPoint(x: bodyRect.maxX - 26, y: bodyRect.minY + 2))
        context.addLine(to: CGPoint(x: bodyRect.maxX - 16, y: landingY))
        context.move(to: CGPoint(x: bodyRect.minX + 6, y: landingY))
        context.addLine(to: CGPoint(x: bodyRect.maxX + 4, y: landingY))
        context.strokePath()
    }

    private func drawBanner(context: CGContext, helicopterAnchor anchor: CGPoint) {
        let bannerHeight: CGFloat = 52
        let bannerWidth = min(max(textWidth(for: bannerText) + 52, 260), 560)
        let ropeStart = CGPoint(x: anchor.x - 226, y: anchor.y - 6)
        let bannerOrigin = CGPoint(
            x: anchor.x - bannerWidth - 360,
            y: anchor.y - bannerHeight / 2 - 2
        )
        let bannerRect = CGRect(
            x: bannerOrigin.x,
            y: bannerOrigin.y,
            width: bannerWidth,
            height: bannerHeight
        )
        let ropeEnd = CGPoint(x: bannerRect.maxX, y: bannerRect.midY)

        context.saveGState()
        defer { context.restoreGState() }

        context.setStrokeColor(CGColor(red: 0.27, green: 0.24, blue: 0.2, alpha: 0.72))
        context.setLineWidth(2)
        context.move(to: ropeStart)
        context.addQuadCurve(
            to: ropeEnd,
            control: CGPoint(x: ropeStart.x - 42, y: ropeStart.y + 18)
        )
        context.strokePath()

        let bannerPath = CGPath(
            roundedRect: bannerRect,
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil
        )
        context.setFillColor(CGColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 0.95))
        context.addPath(bannerPath)
        context.fillPath()

        context.setStrokeColor(CGColor(red: 0.51, green: 0.35, blue: 0.12, alpha: 0.88))
        context.setLineWidth(2)
        context.addPath(bannerPath)
        context.strokePath()

        let notch = CGMutablePath()
        notch.move(to: CGPoint(x: bannerRect.minX, y: bannerRect.minY + 10))
        notch.addLine(to: CGPoint(x: bannerRect.minX + 22, y: bannerRect.midY))
        notch.addLine(to: CGPoint(x: bannerRect.minX, y: bannerRect.maxY - 10))
        notch.closeSubpath()
        context.setFillColor(CGColor(red: 0.9, green: 0.74, blue: 0.38, alpha: 0.38))
        context.addPath(notch)
        context.fillPath()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.25, green: 0.17, blue: 0.08, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        let textRect = bannerRect.insetBy(dx: 24, dy: 11)
        bannerText.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    private func textWidth(for text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
        ]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
