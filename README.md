# MeetingCopter

A small macOS menu bar app that watches your calendar and flies a red helicopter across the center of the screen with a banner reminder before meetings.

## Features

- Menu bar status item for calendar access and upcoming meetings
- Red helicopter reminder animation with a banner message
- Adjustable animation speed from the menu
- Test button for previewing the reminder immediately

## Requirements

- macOS 15 or newer
- Swift 6 toolchain

## Run From Source

```sh
swift run MeetingCopter
```

## Build The App

```sh
./scripts/build-app.sh
open .build/MeetingCopter.app
```

The app asks for calendar access so it can detect upcoming events. The menu bar popover includes a speed slider and a test button.
