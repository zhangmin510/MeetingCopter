import Foundation

// MARK: - Data Structures

struct VerletPoint {
    var position: CGPoint
    var previous: CGPoint = .zero
    var acceleration: CGPoint = .zero
    var isAnchor: Bool = false
}

struct LengthConstraint {
    let pointA: Int
    let pointB: Int
    let restLength: CGFloat
}

// MARK: - Physics Engine

final class PhysicsEngine {
    var points: [VerletPoint] = []
    var constraints: [LengthConstraint] = []

    private let gravity: CGFloat = 980.0       // pixels/s² (scaled)
    private let jitter: CGFloat = 0.017
    private let constraintIterations = 3
    private let anchorSmoothing: CGFloat = 0.1

    // Flight path state
    var flightProgress: CGFloat = 0
    var flightSpeed: CGFloat = 0.005
    var flightPath: (CGFloat) -> CGPoint = { t in .zero }
    var usesRigidFlight = false
    var onComplete: (() -> Void)?
    private var hasCompleted = false

    // MARK: - Flight Shape

    func createFlightShape() {
        // Lightweight flight rig: 18 points, 28 constraints
        let scale: CGFloat = 80
        let centerX: CGFloat = 0
        let centerY: CGFloat = 0

        points = [
            // 0: Nose tip (anchor)
            VerletPoint(position: CGPoint(x: centerX, y: centerY - scale * 1.0),
                        previous: CGPoint(x: centerX, y: centerY - scale * 1.0),
                        isAnchor: true),
            // 1: Left nose
            VerletPoint(position: CGPoint(x: centerX - scale * 0.2, y: centerY - scale * 0.7)),
            // 2: Right nose
            VerletPoint(position: CGPoint(x: centerX + scale * 0.2, y: centerY - scale * 0.7)),
            // 3: Center body front
            VerletPoint(position: CGPoint(x: centerX, y: centerY - scale * 0.4)),
            // 4: Left wing shoulder
            VerletPoint(position: CGPoint(x: centerX - scale * 0.35, y: centerY - scale * 0.2)),
            // 5: Right wing shoulder
            VerletPoint(position: CGPoint(x: centerX + scale * 0.35, y: centerY - scale * 0.2)),
            // 6: Center body
            VerletPoint(position: CGPoint(x: centerX, y: centerY)),
            // 7: Left wing mid
            VerletPoint(position: CGPoint(x: centerX - scale * 0.55, y: centerY - scale * 0.3)),
            // 8: Right wing mid
            VerletPoint(position: CGPoint(x: centerX + scale * 0.55, y: centerY - scale * 0.3)),
            // 9: Left wing tip
            VerletPoint(position: CGPoint(x: centerX - scale * 1.1, y: centerY + scale * 0.1)),
            // 10: Right wing tip
            VerletPoint(position: CGPoint(x: centerX + scale * 1.1, y: centerY + scale * 0.1)),
            // 11: Left wing rear
            VerletPoint(position: CGPoint(x: centerX - scale * 0.7, y: centerY + scale * 0.5)),
            // 12: Right wing rear
            VerletPoint(position: CGPoint(x: centerX + scale * 0.7, y: centerY + scale * 0.5)),
            // 13: Center body rear
            VerletPoint(position: CGPoint(x: centerX, y: centerY + scale * 0.3)),
            // 14: Left tail
            VerletPoint(position: CGPoint(x: centerX - scale * 0.15, y: centerY + scale * 0.7)),
            // 15: Right tail
            VerletPoint(position: CGPoint(x: centerX + scale * 0.15, y: centerY + scale * 0.7)),
            // 16: Left tail tip
            VerletPoint(position: CGPoint(x: centerX - scale * 0.15, y: centerY + scale * 1.0)),
            // 17: Right tail tip
            VerletPoint(position: CGPoint(x: centerX + scale * 0.15, y: centerY + scale * 1.0)),
        ]

        // The source shape is defined nose-up. Rotate it so the nose points right,
        // matching the left-to-right flight path.
        points = points.map { point in
            var orientedPoint = point
            let position = Self.orientedForHorizontalFlight(point.position)
            orientedPoint.position = position
            orientedPoint.previous = position
            return orientedPoint
        }

        constraints = [
            // Body line
            LengthConstraint(pointA: 0, pointB: 3, restLength: distance(0, 3)),
            LengthConstraint(pointA: 3, pointB: 6, restLength: distance(3, 6)),
            LengthConstraint(pointA: 6, pointB: 13, restLength: distance(6, 13)),

            // Nose triangle
            LengthConstraint(pointA: 0, pointB: 1, restLength: distance(0, 1)),
            LengthConstraint(pointA: 0, pointB: 2, restLength: distance(0, 2)),
            LengthConstraint(pointA: 1, pointB: 3, restLength: distance(1, 3)),
            LengthConstraint(pointA: 2, pointB: 3, restLength: distance(2, 3)),

            // Left wing structure
            LengthConstraint(pointA: 3, pointB: 4, restLength: distance(3, 4)),
            LengthConstraint(pointA: 4, pointB: 7, restLength: distance(4, 7)),
            LengthConstraint(pointA: 4, pointB: 9, restLength: distance(4, 9)),
            LengthConstraint(pointA: 7, pointB: 9, restLength: distance(7, 9)),
            LengthConstraint(pointA: 7, pointB: 11, restLength: distance(7, 11)),
            LengthConstraint(pointA: 9, pointB: 11, restLength: distance(9, 11)),
            LengthConstraint(pointA: 6, pointB: 11, restLength: distance(6, 11)),

            // Right wing structure
            LengthConstraint(pointA: 3, pointB: 5, restLength: distance(3, 5)),
            LengthConstraint(pointA: 5, pointB: 8, restLength: distance(5, 8)),
            LengthConstraint(pointA: 5, pointB: 10, restLength: distance(5, 10)),
            LengthConstraint(pointA: 8, pointB: 10, restLength: distance(8, 10)),
            LengthConstraint(pointA: 8, pointB: 12, restLength: distance(8, 12)),
            LengthConstraint(pointA: 10, pointB: 12, restLength: distance(10, 12)),
            LengthConstraint(pointA: 6, pointB: 12, restLength: distance(6, 12)),

            // Cross braces
            LengthConstraint(pointA: 4, pointB: 5, restLength: distance(4, 5)),
            LengthConstraint(pointA: 7, pointB: 8, restLength: distance(7, 8)),
            LengthConstraint(pointA: 11, pointB: 12, restLength: distance(11, 12)),

            // Tail
            LengthConstraint(pointA: 13, pointB: 14, restLength: distance(13, 14)),
            LengthConstraint(pointA: 13, pointB: 15, restLength: distance(13, 15)),
            LengthConstraint(pointA: 14, pointB: 16, restLength: distance(14, 16)),
            LengthConstraint(pointA: 15, pointB: 17, restLength: distance(15, 17)),
        ]
    }

    func placeShape(anchorAt target: CGPoint) {
        guard let anchorIndex = points.firstIndex(where: { $0.isAnchor }) else { return }

        let anchor = points[anchorIndex].position
        let offset = CGPoint(
            x: target.x - anchor.x,
            y: target.y - anchor.y
        )

        for i in points.indices {
            points[i].position.x += offset.x
            points[i].position.y += offset.y
            points[i].previous.x += offset.x
            points[i].previous.y += offset.y
        }
    }

    private static func orientedForHorizontalFlight(_ point: CGPoint) -> CGPoint {
        CGPoint(x: -point.y, y: point.x)
    }

    private func distance(_ i: Int, _ j: Int) -> CGFloat {
        let dx = points[i].position.x - points[j].position.x
        let dy = points[i].position.y - points[j].position.y
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - Physics Step

    func step(dt: CGFloat) {
        if usesRigidFlight {
            flightProgress += flightSpeed
            placeShape(anchorAt: flightPath(flightProgress))
            completeIfNeeded()
            return
        }

        // 1. Verlet integration: update all non-anchor points
        for i in 0..<points.count where !points[i].isAnchor {
            let p = points[i]
            let velocity = CGPoint(
                x: p.position.x - p.previous.x,
                y: p.position.y - p.previous.y
            )
            points[i].previous = p.position
            points[i].position = CGPoint(
                x: p.position.x + velocity.x + p.acceleration.x * dt * dt,
                y: p.position.y + velocity.y + p.acceleration.y * dt * dt
            )
            points[i].acceleration = .zero
        }

        // 2. Apply gravity to non-anchor points
        for i in 0..<points.count where !points[i].isAnchor {
            points[i].acceleration.y += gravity
        }

        // 3. Apply jitter to wing points (indices 4-12 = wing structure)
        let jitterEnd = min(12, points.count - 1)
        if jitterEnd >= 4 {
            for i in 4...jitterEnd where !points[i].isAnchor {
                points[i].position.x += CGFloat.random(in: -jitter...jitter)
                points[i].position.y += CGFloat.random(in: -jitter...jitter)
            }
        }

        // 4. Satisfy constraints (multiple iterations for stability)
        satisfyConstraints()

        // 5. Anchor smoothing: pull anchors along flight path
        if points.count >= 3 {
            flightProgress += flightSpeed
            let target = flightPath(flightProgress)
            for i in 0..<points.count where points[i].isAnchor {
                points[i].position = CGPoint(
                    x: points[i].position.x + (target.x - points[i].position.x) * anchorSmoothing,
                    y: points[i].position.y + (target.y - points[i].position.y) * anchorSmoothing
                )
                points[i].previous = points[i].position
            }
        }

        // Check if flight is complete
        completeIfNeeded()
    }

    private func completeIfNeeded() {
        if flightProgress >= 1.0, !hasCompleted {
            hasCompleted = true
            onComplete?()
        }
    }

    func satisfyConstraints() {
        for _ in 0..<constraintIterations {
            for constraint in constraints {
                guard constraint.pointA < points.count,
                      constraint.pointB < points.count else { continue }
                let pA = points[constraint.pointA]
                let pB = points[constraint.pointB]
                let dx = pB.position.x - pA.position.x
                let dy = pB.position.y - pA.position.y
                let dist = sqrt(dx * dx + dy * dy)
                guard dist > 0.0001 else { continue }

                let correction = (dist - constraint.restLength) / dist * 0.5
                let cx = dx * correction
                let cy = dy * correction

                if !pA.isAnchor {
                    points[constraint.pointA].position.x += cx
                    points[constraint.pointA].position.y += cy
                }
                if !pB.isAnchor {
                    points[constraint.pointB].position.x -= cx
                    points[constraint.pointB].position.y -= cy
                }
            }
        }
    }
}
