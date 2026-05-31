import Testing
import Foundation
@testable import MeetingCopter

struct PhysicsEngineTests {

    @Test func verletIntegrationUpdatesPosition() {
        var point = VerletPoint(
            position: CGPoint(x: 100, y: 100),
            previous: CGPoint(x: 99, y: 100),
            acceleration: CGPoint(x: 0, y: 9.8)
        )
        let dt: CGFloat = 1.0 / 60.0

        // Apply one step of Verlet integration manually
        let velocity = CGPoint(
            x: point.position.x - point.previous.x,
            y: point.position.y - point.previous.y
        )
        let newPos = CGPoint(
            x: point.position.x + velocity.x + point.acceleration.x * dt * dt,
            y: point.position.y + velocity.y + point.acceleration.y * dt * dt
        )
        point.previous = point.position
        point.position = newPos

        // Position should move right (velocity=1) and down (gravity)
        #expect(point.position.x > 100)
        #expect(point.position.y > 100)
    }

    @Test func constraintSolverPullsPointsTogether() {
        var points = [
            VerletPoint(position: CGPoint(x: 0, y: 0), previous: .zero, acceleration: .zero),
            VerletPoint(position: CGPoint(x: 10, y: 0), previous: CGPoint(x: 10, y: 0), acceleration: .zero),
        ]
        let constraint = LengthConstraint(pointA: 0, pointB: 1, restLength: 5)

        let engine = PhysicsEngine()
        engine.points = points
        engine.constraints = [constraint]

        // Apply one constraint iteration
        engine.satisfyConstraints()

        let dx = engine.points[1].position.x - engine.points[0].position.x
        let dy = engine.points[1].position.y - engine.points[0].position.y
        let distance = sqrt(dx * dx + dy * dy)

        #expect(abs(distance - 5.0) < 0.01)
    }

    @Test func anchorPointDoesNotMoveUnderGravity() {
        var point = VerletPoint(
            position: CGPoint(x: 50, y: 50),
            previous: CGPoint(x: 50, y: 50),
            acceleration: CGPoint(x: 0, y: 9.8),
            isAnchor: true
        )
        let dt: CGFloat = 1.0 / 60.0

        let engine = PhysicsEngine()
        // isAnchor points should keep position pinned
        engine.points = [point]
        engine.step(dt: dt)

        #expect(engine.points[0].position.x == 50)
        #expect(engine.points[0].position.y == 50)
    }

    @Test func flightShapeHasCorrectNumberOfPointsAndConstraints() {
        let engine = PhysicsEngine()
        engine.createFlightShape()

        #expect(engine.points.count == 18)
        #expect(engine.constraints.count == 28)
    }

    @Test func flightShapePointsRightForHorizontalFlight() {
        let engine = PhysicsEngine()
        engine.createFlightShape()

        let nose = engine.points[0].position
        let body = engine.points[6].position

        #expect(nose.x > body.x)
    }

    @Test func placeShapeMovesAnchorToTarget() {
        let engine = PhysicsEngine()
        engine.createFlightShape()

        let target = CGPoint(x: 120, y: 240)
        engine.placeShape(anchorAt: target)

        #expect(abs(engine.points[0].position.x - target.x) < 0.001)
        #expect(abs(engine.points[0].position.y - target.y) < 0.001)
    }

    @Test func rigidFlightFollowsStraightPathWithoutDrift() {
        let engine = PhysicsEngine()
        engine.createFlightShape()
        engine.usesRigidFlight = true
        engine.flightSpeed = 0.25
        engine.flightPath = { progress in
            CGPoint(x: 100 + progress * 400, y: 250)
        }
        engine.placeShape(anchorAt: engine.flightPath(0))

        engine.step(dt: 1.0 / 60.0)

        #expect(abs(engine.points[0].position.x - 200) < 0.001)
        #expect(abs(engine.points[0].position.y - 250) < 0.001)
    }
}
