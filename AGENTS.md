# AGENTS.md

Guidance for AI coding agents working on MeetingCopter.

## Project Overview

MeetingCopter is a Swift Package that builds a macOS menu bar app. It watches upcoming calendar events and shows a full-screen transparent reminder animation: a red helicopter flying left-to-right with a banner message.

## Important Paths

- `Package.swift`: Swift package definition.
- `Sources/MeetingCopter/`: app source.
- `Sources/MeetingCopter/CalendarMonitor.swift`: EventKit calendar access and polling.
- `Sources/MeetingCopter/HelicopterOverlay.swift`: reminder overlay, animation loop, helicopter/banner drawing.
- `Sources/MeetingCopter/FlightPreferences.swift`: animation speed settings.
- `Sources/MeetingCopter/MenuBarView.swift`: SwiftUI menu bar popover.
- `Tests/MeetingCopterTests/`: Swift Testing tests.
- `scripts/build-app.sh`: builds and signs `.build/MeetingCopter.app`.

## Common Commands

```sh
swift test
swift run MeetingCopter
./scripts/build-app.sh
open .build/MeetingCopter.app
```

## Development Notes

- Keep the app name `MeetingCopter` in user-facing UI and package metadata.
- Do not commit `.build/`, `DerivedData/`, or generated `.xcodeproj` files.
- The app targets macOS 15 or newer.
- The overlay should remain click-through and transparent.
- Calendar access requires `NSCalendarsUsageDescription` and `NSCalendarsFullAccessUsageDescription` in the generated app bundle.
- Animation speed should flow through `FlightPreferences` so the menu slider and overlay stay in sync.
- Prefer focused tests in `PhysicsEngineTests.swift` for flight-path or rig behavior.

## Verification

Before committing code changes, run:

```sh
swift test
```

For changes that affect app packaging or permissions, also run:

```sh
./scripts/build-app.sh
```
