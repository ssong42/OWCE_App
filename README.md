# OWCE for iOS

Onewheel Community Edition (OWCE) is an independent SwiftUI app for connecting to Onewheel boards over Bluetooth Low Energy. This fork focuses on the native iOS app; the Android and legacy Xamarin projects have been removed. A native watchOS dashboard target is included for Apple Watch users.

> OWCE is not endorsed by, affiliated with, or a replacement for Future Motion or the official Onewheel app. Ride within your ability, wear appropriate protective equipment, and respect all pushback and safety alerts.

## Features

- Board discovery, connection, live telemetry, and board details
- Ride-mode selection and mode information
- Manual GPS and BLE ride recording, ride history, logs, and CSV export
- Ride submission with serial-number removal enabled by default
- Metric/imperial display settings
- Optional Apple Watch dashboard using WatchConnectivity

The native port is still in progress. Board-specific behavior and ride-mode writes need broader physical-device testing. **Pint firmware 5040 (hardware revision 5312) has been tested** for BLE connection and telemetry. Other board and firmware combinations are not equally validated. Some firmware may not expose battery voltage or other values. The app does not patch board firmware; use of firmware modification tools is outside this project’s scope.

## Build and run locally

See [Local iOS build and testing guide](HOW_TO_RUN_LOCALLY.md) for Xcode setup, signing, device permissions, and BLE testing.

Quick start: open `OWCE/OWCE.xcodeproj`, select the **OWCE** scheme, select an iPhone destination, configure your Apple development team under Signing & Capabilities, and run. A physical iPhone is required to connect to a board; the simulator is suitable only for UI/build checks.

## Project contents

- `OWCE/OWCE.xcodeproj` — Xcode project
- `OWCE/OWCE.Native/` — SwiftUI iPhone app
- `OWCE/OWCE.Watch/` — native watchOS dashboard source and target

Ride data is stored locally on the iPhone. Location permission is needed for GPS route and distance recording. Review exported or submitted data before sharing it.
