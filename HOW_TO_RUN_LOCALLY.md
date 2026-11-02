# Local iOS build and testing guide

## Requirements

- A Mac running a version of macOS supported by your installed Xcode
- Xcode 26 or newer (the project has been built with Xcode 26.6)
- An Apple ID; a paid Apple Developer Program membership is not required for basic personal-device testing
- An iPhone running iOS 17 or newer
- A physical Onewheel for Bluetooth testing; the simulator cannot connect to BLE hardware

## Get the project

Clone your fork and open the Xcode project:

```sh
git clone https://github.com/ssong42/OWCE_App.git
cd OWCE_App
open OWCE/OWCE.xcodeproj
```

If you are building your own fork, replace the clone URL with your repository URL.

## Build for the iPhone simulator

1. In Xcode, select the **OWCE** scheme.
2. Choose an iPhone simulator destination.
3. Select **Product → Build** (or press **⌘B**).

The simulator is useful for checking the interface. Bluetooth board scanning, GPS ride tracking, and WatchConnectivity cannot be fully exercised there.

## Install on a physical iPhone

1. Connect and unlock the iPhone; tap **Trust** if prompted.
2. In Xcode, select the **OWCE** scheme and your iPhone as the run destination.
3. Select the project in the navigator, then select the **OWCE** target → **Signing & Capabilities**.
4. Enable **Automatically manage signing** and select your Personal Team or Apple Developer team. If Xcode reports a bundle-identifier conflict, change `PRODUCT_BUNDLE_IDENTIFIER` in the OWCE target’s Build Settings to a unique identifier you control.
5. Press **⌘R**. On the phone, approve the Bluetooth and location prompts when using those features. If iOS blocks the developer app, follow the on-device prompt under **Settings → General → VPN & Device Management**.

Ride recording is manual: connect to the board, then tap **Start ride recording** when you are ready. Location access is used to collect GPS route and distance data. Denying it prevents GPS recording; Bluetooth telemetry can still be viewed.

## Connect to a board

1. Turn on the board and keep the iPhone nearby.
2. Open OWCE and tap **Scan**. Select the board when it appears.
3. Allow Bluetooth access. On some boards/firmware, the official Onewheel app may be needed to activate the board first. If telemetry remains inactive, disconnect from OWCE, activate it using the official app, force-quit that app, and reconnect with OWCE.
4. Verify the board model, firmware, battery, and telemetry before relying on displayed values. Known tested hardware/firmware combinations are listed in the main README; all others should be treated as unverified.

Do not use ride-mode controls while moving. Board behavior and available telemetry vary by model and firmware; an app display is not a substitute for the board’s safety warnings or the manufacturer’s instructions.

## Apple Watch target

`OWCEWatch` is a separate watchOS target in this project. The phone publishes dashboard values through WatchConnectivity. Build the **OWCEWatch** scheme with a paired Watch destination and configure signing for both targets. The current target arrangement has not been validated for automatic companion installation on a physical paired Watch; the iPhone app is the primary supported local build.

## Command-line builds

List targets and schemes:

```sh
xcodebuild -list -project OWCE/OWCE.xcodeproj
```

Example unsigned build checks (these do not install an app):

```sh
xcodebuild -project OWCE/OWCE.xcodeproj -target OWCE \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build

xcodebuild -project OWCE/OWCE.xcodeproj -target OWCE \
  -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Privacy and troubleshooting

- Ride recordings are stored locally on the iPhone. CSV exports and ride submissions can contain ride telemetry and route data.
- Ride submission removes board/battery serial data by default. Check privacy options and preview the submission before uploading.
- If the board is not found, confirm Bluetooth is enabled, the board is awake, OWCE has Bluetooth permission, and the official app is not connected at the same time.
- If telemetry is missing or implausible, disconnect and reconnect, compare with the official app where possible, and do not rely on that reading for riding decisions.
- Use Xcode’s **View → Debug Area → Activate Console** to inspect runtime logs.
