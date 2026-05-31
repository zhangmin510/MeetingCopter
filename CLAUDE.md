# CLAUDE.md

This repository contains MeetingCopter, a Swift/macOS menu bar reminder app.

## What This App Does

MeetingCopter asks for calendar access, polls upcoming events, and displays a full-screen transparent reminder animation before meetings. The animation is a red helicopter flying horizontally across the center of the screen while towing a banner with the reminder text.

## How To Work On It

Use the Swift package directly:

```sh
swift test
swift run MeetingCopter
```

Build a runnable macOS app bundle with:

```sh
./scripts/build-app.sh
open .build/MeetingCopter.app
```

## Source Map

- `Sources/MeetingCopter/AppDelegate.swift`: app lifecycle, status item, popover wiring.
- `Sources/MeetingCopter/MenuBarView.swift`: menu UI, test button, speed slider.
- `Sources/MeetingCopter/CalendarMonitor.swift`: EventKit permission and polling.
- `Sources/MeetingCopter/HelicopterOverlay.swift`: transparent overlay window and helicopter/banner rendering.
- `Sources/MeetingCopter/PhysicsEngine.swift`: flight rig and path progression.
- `Sources/MeetingCopter/FlightPreferences.swift`: persisted animation speed preference.
- `Tests/MeetingCopterTests/PhysicsEngineTests.swift`: behavior tests for the flight engine.

## Conventions

- Keep user-facing naming as `MeetingCopter`.
- Keep the helicopter flight smooth, horizontal, and non-jittery unless the task explicitly changes it.
- Put speed-related behavior behind `FlightPreferences`.
- Avoid broad refactors when changing UI or animation details.
- Do not commit build products from `.build/`.

## Pre-commit Check

Run `swift test` before committing. Run `./scripts/build-app.sh` when touching bundle metadata, permissions, signing, or packaging.
