import SwiftUI
import EventKit

struct MenuBarView: View {
    @ObservedObject var monitor: CalendarMonitor
    @AppStorage(FlightPreferences.speedScaleKey)
    private var speedScale = FlightPreferences.defaultSpeedScale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "airplane")
                    .font(.title2)
                Text("MeetingCopter")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            // Status
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                Text(monitor.statusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // Test button — triggers mock reminder immediately
            Button(action: {
                HelicopterOverlay.show(eventTitle: "Meeting with Andrew")
            }) {
                HStack {
                    Image(systemName: "helicopter")
                    Text("Test: Fly Helicopter")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "speedometer")
                    Text("Speed")
                    Spacer()
                    Text(FlightPreferences.speedLabel(for: speedScale))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: speedBinding,
                    in: FlightPreferences.minSpeedScale...FlightPreferences.maxSpeedScale,
                    step: 0.05
                )
            }
            .font(.caption)
            .padding(.horizontal)

            // Upcoming events
            if monitor.authorizationStatus == .authorized ||
               monitor.authorizationStatus == .fullAccess ||
               monitor.authorizationStatus == .writeOnly {
                Divider()

                if monitor.upcomingEvents.isEmpty {
                    Text("No upcoming meetings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                } else {
                    ForEach(monitor.upcomingEvents.prefix(5), id: \.eventIdentifier) { event in
                        EventRow(event: event)
                            .padding(.horizontal)
                    }
                }
            }

            Divider()

            // Quit button
            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(width: 280)
    }

    private var statusIcon: String {
        switch monitor.authorizationStatus {
        case .notDetermined: return "questionmark.circle"
        case .denied, .restricted, .writeOnly: return "xmark.circle"
        case .authorized, .fullAccess: return "checkmark.circle"
        @unknown default: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch monitor.authorizationStatus {
        case .notDetermined: return .orange
        case .denied, .restricted, .writeOnly: return .red
        case .authorized, .fullAccess: return .green
        @unknown default: return .orange
        }
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { FlightPreferences.clampedSpeedScale(speedScale) },
            set: { speedScale = FlightPreferences.clampedSpeedScale($0) }
        )
    }
}

struct EventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Untitled")
                    .font(.subheadline)
                    .lineLimit(1)
                Text(formatTime(event.startDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private func formatTime(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
