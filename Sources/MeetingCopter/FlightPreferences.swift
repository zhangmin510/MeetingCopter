import CoreGraphics
import Foundation

enum FlightPreferences {
    static let speedScaleKey = "helicopterFlightSpeedScale"
    static let defaultSpeedScale = 0.45
    static let minSpeedScale = 0.2
    static let maxSpeedScale = 1.2

    private static let baseFlightSpeed: CGFloat = 0.0018

    static var currentFlightSpeed: CGFloat {
        let storedScale = UserDefaults.standard.object(forKey: speedScaleKey) as? Double
        return baseFlightSpeed * CGFloat(clampedSpeedScale(storedScale ?? defaultSpeedScale))
    }

    static func clampedSpeedScale(_ value: Double) -> Double {
        min(max(value, minSpeedScale), maxSpeedScale)
    }

    static func speedLabel(for value: Double) -> String {
        "\(Int((clampedSpeedScale(value) * 100).rounded()))%"
    }
}
