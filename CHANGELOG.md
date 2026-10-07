# Changelog

All notable changes to the LinkRunner iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Build facts for Test mode** (LIN-3369). `device_data` on every request, including `initialize`, now carries facts the server uses to decide whether an install is live or test. They come from the OS and the app's signing, never from a developer flag, and there is no separate test token:
  - `build_facts_version`: `1`. Its presence tells the server this SDK sends build facts; older SDKs are always treated as live.
  - `is_debuggable`: `true` when the app is development-signed (`get-task-allow` is true in the embedded provisioning profile) or StoreKit reports the `xcode` environment.
  - `installer_package`: always an empty string on iOS (Android only).
  - `app_store_environment`: on iOS 16+, `AppTransaction.shared.environment` as `production`, `sandbox` (TestFlight) or `xcode`. The lookup starts at the top of `initialize`, is waited for at most 1.5 seconds and is cached for the process. Below iOS 16, or when StoreKit cannot answer in time, the SDK falls back to `development` when an `embedded.mobileprovision` is present (development, ad hoc or enterprise signing), then `sandbox` when the receipt file is `sandboxReceipt`, otherwise an empty string. The SDK never guesses `production`.
  - `is_emulator`: `true` on the iOS Simulator. Informational only, not a test signal.
- With `debug: true` in `initialize`, the SDK prints one line with these facts, for example `Linkrunner build facts: debuggable=true, installer=(n/a on iOS), environment=xcode, simulator=true`, so you can see what the server will use.

## [4.1.0] - 2026-07-27

### Added

- **Google Integrated Conversion Measurement (ICM)**: the SDK now forwards Google's On-Device Measurement `odm_info` value to Linkrunner, enabling Google App Campaign attribution when no click identifier or advertising ID is available. Applies to the EEA, UK and Switzerland.
  - **LinkrunnerKit remains dependency-free.** Google's SDK is detected at runtime, so apps that do not use ICM are entirely unaffected — no new dependency, no change to linkage, no size increase.
  - To opt in, add `GoogleAdsOnDeviceConversion` to your app (via CocoaPods, SPM, or the Firebase iOS SDK 11.14.0+, which already includes it) and add `-ObjC -lc++` to Other Linker Flags. See the README.
  - No API change is required: the fetch runs automatically during `initialize`, bounded by a 5 second timeout, and is skipped silently when Google's SDK is absent.
- **Consent model** for Google Ads: `LinkrunnerConsent` carries `isEEA`, `hasConsentForDataUsage` and `hasConsentForAdsPersonalization` as `granted` / `denied` / `unknown`. Call `setConsent(_:)` before `initialize`, and call it again whenever your CMP state changes — the new values replace the old ones. Unknown is never reported as granted.
  - Consent is persisted, so a returning user keeps their state without the app re-supplying it every launch. Because it persists, **you must call `setConsent(_:)` again whenever the user changes their choice** — otherwise the previous value keeps being sent after they have withdrawn it.
- **Automatic consent collection from an IAB TCF CMP.** Call `enableTCFConsentCollection(true)` and the SDK derives consent from the CMP's standard `IABTCF_*` keys, using Google's published TCF mapping — `ad_user_data` from purposes 1 and 7, `ad_personalization` from purposes 3 and 4, both gated on vendor consent for Google (TCF vendor 755). Anything set explicitly via `setConsent` still wins, per signal.
  - Opt-in rather than automatic, because interpreting a TC string on your behalf is a legal judgement. Only enable it if you use a TCF v2.2/2.3-compliant CMP — custom consent screens and Firebase Consent Mode do not write these keys.
  - Consent is re-read on every payload, so a CMP that resolves after launch is picked up rather than being pinned to `unknown` for the process. Note that `initialize` is the call that becomes `first_open`, so call it once your CMP has resolved if you want consent on that request.
  - Unlike `setConsent(_:)`, this setting is **not** persisted — it is a per-launch configuration flag, so call it on every launch before `initialize`.
- Device payloads now include `att_status`, `device_model` (the hardware identifier, e.g. `iPhone17,3`) and, on install, `first_open_timestamp`.

### Changed

- The AdServices attribution token is now fetched once and cached for the install, rather than on every network request.

## [4.0.1] - 2026-07-09

### Added

- Exposed ad-network attribution fields on the attribution response: `adNetworkCampaignId`, `adSetId`, `adSetName`, `adCreativeId`, `adCreativeName` (all optional).

## [4.0.0] - 2026-06-30

### Changed

- **Breaking:** `paymentId` is now required in `capturePayment`; the event is not dispatched when it is missing

## [3.10.0] - 2026-04-03

### Added

- **Deeplink Handling for Re-engagement**: Added `handleDeeplink(url:)` method
  - Enables re-engagement attribution tracking when app is opened via deeplink

## [3.9.0] - 2026-03-21

### Added

- **Netcore Device GUID Support**: Added `netcoreDeviceGuid` field to `UserData` model
  - Allows tracking Netcore device GUID for integration with Netcore services
  - Available in `signup` and `setUserData` functions

## [3.8.0] - 2026-02-24

### Added

- Enhanced payment capture with support for optional event data attributes.
- Added support for Meta Commerce Event Manager.

## [3.7.1] - 2025-01-XX

### Added

- **GA Session ID Support**: Added `gaSessionId` field to `UserData` model
  - Allows tracking Google Analytics session ID alongside `gaAppInstanceId`

## [3.7.0] - 2025-12-16

### Added

- **AdServices Attribution Token**: Added support for Apple's AdServices attribution token
  - Automatically retrieves attribution token using `AAAttribution.attributionToken()` during SDK initialization
  - Attribution token is included in init requests for improved ad attribution tracking
  - Gracefully handles cases where AdServices framework is unavailable
  - Available on iOS 14.3+

## [3.3.0] - 2025-09-26

### Added

- **Retry Mechanism**: Implemented exponential backoff retry mechanism for API calls
  - Retries up to 4 times for HTTP server errors and network failures
  - Exponential backoff delays: 2s, 4s, 8s, 16s between retry attempts

### Changed

- **Enhanced Error Handling**: Non-blocking error handling for all public methods
  - All public methods now log errors instead of throwing them
  - Prevents SDK errors from crashing the application

- **Backward Compatibility**:
  - Returns empty `LRAttributionDataResponse` object instead of `nil` on errors to maintain backward compatibility

### Removed

- **Trigger Deeplink**: Removed the deprecated trigger deeplink method

---

_This changelog follows the [Keep a Changelog](https://keepachangelog.com/) format._
