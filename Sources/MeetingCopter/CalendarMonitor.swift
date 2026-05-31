import EventKit
import Combine

final class CalendarMonitor: ObservableObject {
    private let eventStore = EKEventStore()
    private var timer: Timer?
    private var notifiedEventIDs = Set<String>()

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var upcomingEvents: [EKEvent] = []

    var onReminderTriggered: ((EKEvent) -> Void)?

    // MARK: - Permission

    func requestAccess() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if authorizationStatus == .notDetermined {
            eventStore.requestAccess(to: .event) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        self?.startPolling()
                    }
                }
            }
        } else if authorizationStatus == .authorized {
            startPolling()
        }
    }

    // MARK: - Polling

    func startPolling() {
        checkUpcomingEvents() // Immediate first check
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkUpcomingEvents()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func checkUpcomingEvents() {
        guard authorizationStatus == .authorized else { return }

        let calendars = eventStore.calendars(for: .event)
        let now = Date()
        let fiveMinutesFromNow = now.addingTimeInterval(5 * 60)
        let thirtySecondsAgo = now.addingTimeInterval(-30)

        let predicate = eventStore.predicateForEvents(
            withStart: thirtySecondsAgo,
            end: fiveMinutesFromNow,
            calendars: calendars
        )
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { !notifiedEventIDs.contains($0.eventIdentifier) }
            .sorted { $0.startDate < $1.startDate }

        upcomingEvents = events.filter { $0.startDate > now }

        for event in events {
            let timeToStart = event.startDate.timeIntervalSince(now)
            if timeToStart <= 5 * 60 && timeToStart > -30 {
                notifiedEventIDs.insert(event.eventIdentifier)
                onReminderTriggered?(event)
            }
        }
    }

    // MARK: - Status Text

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    var statusText: String {
        switch authorizationStatus {
        case .notDetermined: return "Requesting calendar access..."
        case .denied, .restricted, .writeOnly: return "Calendar access denied"
        case .authorized, .fullAccess: return upcomingEvents.isEmpty
            ? "No upcoming meetings" : "Next: \(formattedTime(upcomingEvents[0]))"
        @unknown default: return "Unknown"
        }
    }

    private func formattedTime(_ event: EKEvent) -> String {
        let time = Self.timeFormatter.string(from: event.startDate)
        return "\(event.title ?? "Meeting") at \(time)"
    }
}