# Courier Radar — Native SwiftUI

Complete native SwiftUI code, not a WebView wrapper. Existing Vercel/Supabase backend is reused.

Technology: MapKit, Swift Charts, Keychain, Vision OCR, PhotosPicker, App Intents, Core Location background updates, Swift Package RadarCore, async URLSession and a finite-horizon cash optimizer.

## Windows: install with free Apple Account and no Mac

1. Open the [Native iOS GitHub Actions workflow](https://github.com/ya1-oa/courier-radar/actions/workflows/native-ios.yml).
2. Download artifact **CourierRadar-iOS-unsigned-and-project** from the latest successful run.
3. Extract **CourierRadar-unsigned.ipa**. This file is UNSIGNED, so it cannot be installed directly.
4. Use [AltStore Classic for Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) or your own trustworthy IPA signing tool to sign with your personal Apple ID. Trust your iPhone and enable Developer Mode under Privacy & Security.
5. Re-sign and reinstall after approximately seven days. Apple Personal Team provisioning profiles expire after seven days. A free account has app and device registration limits.

Radar does not receive your Apple password. GitHub Actions compiles the unsigned device IPA on an Apple-hosted macOS runner. You sign it locally on your device with your own account.

## Mac: run with Personal Team

1. Clone the repository; install Xcode and XcodeGen (Homebrew: brew install xcodegen).
2. From the ios directory, run xcodegen generate --spec project.yml.
3. Open CourierRadar.xcodeproj and set the app target Signing & Capabilities team to your Apple Account (Personal Team), Automatic Signing. Change bundle ID to a unique value if necessary.
4. Connect the iPhone, enable Developer Mode if prompted, run from Xcode. Reinstall after seven days.

No paid Apple membership is required for personal test installation. Background location tracks only during an explicitly started Radar shift and requires the user's Location Services permission.

## First launch

- Settings: enter the Radar server URL and existing Vercel CAPTURE_TOKEN. The default hostname is https://delivery-intelligence-ten.vercel.app.
- The token is stored in iOS Keychain, never in UserDefaults.
- Home: start shift only while Uber is online. Permit location so your personal GPS wait-zone data accumulates.
- Use Home → SCREENSHOT to select an Uber screenshot, or create the Back Tap Shortcut below.
- Home → NEXT STAGE is a manual fallback for Accepted → Arrived → Picked up → Delivered. The app never presses Uber buttons for you.
- Settings → UBER TOTAL: reconcile actual cash, since missed captures can undercount income.

## One-tap Uber screenshot shortcut

Create an iOS Shortcut: Take Screenshot → Extract Text from Image → Radar: Analyze Uber Screen. Assign extracted text to the action's Screenshot Text argument, optionally use Get Current Location for latitude/longitude, and Show Result. Assign your Shortcut to Settings → Accessibility → Touch → Back Tap → Double Tap.

The private capture token stays in Radar Keychain. Vision OCR executes locally, then sends text to your own Radar endpoint. Unknown screens do not trigger fabricated offers or declines. Lifecycle transitions advance only one step with on-screen evidence.

## Optimizer

The RadarCore Swift module performs a memoized five-minute finite-horizon semi-Markov model for maximizing expected daily cash, not a per-order dollar/hour floor. It learns personal contextual offer-arrival rates, payout/duration distributions, dropoff states, remaining shift time and battery constraints.

- TAKE = payout + value of expected location following delivery.
- SKIP = value of waiting for replacement offers, with uncertainty margin and minimum samples.
- WAIT / MOVE / RETURN = real observed offer exposure versus travel cost, with conservative confidence requirements.
- CHARGE = low estimated range. CHECK = missing offer or unsafe range.
- First configured workday can be a take-all calibration day.

The system does not know Uber's proprietary matching algorithm, other couriers, uncaptured offers or proven causal penalties for declines. Its money estimates do not guarantee any particular daily earnings.

Core test: swift test --package-path ios.
Native build: cd ios; xcodegen generate --spec project.yml; xcodebuild -project CourierRadar.xcodeproj -scheme CourierRadar -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build.

Apple Personal Team rules: https://developer.apple.com/help/account/basics/about-your-developer-account
Apple background location: https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates


## iOS shift-ready features (2026-09-29)

- **GPS:** Radar requests a foreground location fix when the app opens or resumes. Only an active Radar shift uploads GPS samples for waiting-time learning.
- **Waiting advice:** collapsed by default on Home; expand for model evidence and optional navigation.
- **Action Button:** create an iPhone Shortcut with **Take Screenshot** → **Courier Radar: Analyze Uber Screenshot**. Pass the screenshot image into the Radar action. Assign that Shortcut in iPhone Settings → Action Button → Shortcut. The screenshot is processed by Vision OCR on-device; only text goes to the Radar API. A local alert can show the TAKE/SKIP/CHECK verdict.
- **No continuous Uber monitoring or over-Uber floating overlay** is installed. iOS doesn't provide arbitrary screen access to third-party apps.
- **Battery voltage:** tap **VOLTS** on Home while safely stopped. Enter resting voltage and optionally bike trip-odometer miles. Settings → E-bike range chooses a 36V/48V/52V nominal pack and real-world full-charge mileage. Voltage is manually read, not connected to the BMS; percentage and usable miles are rough conservative estimates. The latest 200 readings stay in local iOS preferences.
- **Reminders:** optionally enable 90-minute local voltage reminders in Settings; they are scheduled on shift start, reset when logging, and canceled on shift end.
- **Cash model:** estimates total earnings through the selected stop time, including uncertain replacement offers, time, location, battery, and after-dropoff positioning. It is **not** a fixed $/hour filter and does not know Uber's private matching algorithm. Calibration is off by default and must be explicitly enabled.
- **Verification:** Build on a real iPhone and confirm location, token, one Action Button screenshot, notification permission, voltage profile, and battery reserve before relying on recommendations.

### Pull and compile on a Mac

    git pull --ff-only origin main
    cd ios
    swift test
    xcodegen generate --spec project.yml
    open CourierRadar.xcodeproj

Select your iPhone and Apple Personal Team, then run (Command-R). The generated AppIcon is resized to 1024 × 1024 by XcodeGen.

Remote CI is intentionally skipped for this source-only update; run `swift test` and Xcode locally. The iPhone build has not yet been verified on your device.
