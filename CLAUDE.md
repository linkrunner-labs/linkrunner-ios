# LinkrunnerKit (iOS SDK)

Swift SDK distributed through CocoaPods (`LinkrunnerKit`) and Swift Package Manager. It runs
inside customer apps, and the React Native, Flutter, Expo, Cordova and Unity SDKs wrap it. A bug
here ships in every app that updates, so review changes for host-app safety first.

## Layout

- `Sources/Linkrunner/Linkrunner.swift`: the public API (`LinkrunnerSDK.shared`, mostly
  `async` methods) plus device data, storage and networking.
- `Models.swift`: public request and response types. `ODMService.swift`: Google On-Device
  Measurement, detected at runtime. `TCFConsent.swift`: IAB TCF consent reading.
  `SKAdNetworkService.swift`, `KeychainHelper.swift`, request signing and `SHA256.swift`.
- `Tests/LinkrunnerKitTests`: XCTest unit tests.
- `LinkrunnerKit.podspec` and `Package.swift` must describe the same sources and platforms.

## Build and test

The package only targets iOS (15+), so `swift build` and `swift test` on a Mac host do not work.
Use the script, which picks an available iPhone simulator:

```bash
Scripts/test.sh          # build and run the unit tests
Scripts/test.sh build    # build the package and tests only
```

Releases follow `.claude/skills/deploy-sdk`.

## Rules for changes

- Never crash the host app. No `fatalError`, `try!`, `precondition` or force unwraps on data
  that comes from the network, storage or the app. Public methods log and return instead of
  throwing.
- Keep work off the main thread. Only UI and ATT prompts hop to the main actor.
- The public API is a contract with the wrapper SDKs. Removing or renaming a public type,
  method, parameter or response field is a breaking change: it needs a major version bump and a
  "Breaking" entry in `CHANGELOG.md`.
- Request field names are a contract with the backend and with the Android SDK. Keep the same
  JSON names and the same semantics on both platforms (for example, PII is hashed as lowercase
  hex SHA-256 of the value as given, with no normalisation).
- LinkrunnerKit has no dependencies. Do not add one to `Package.swift` or the podspec; optional
  SDKs such as Google's On-Device Measurement are detected at runtime (see `ODMService`).
- Never log PII, tokens, secret keys or signatures.
- Consent and device IDs: an unknown consent value is never sent as granted. IDFA is only read
  when `disableIdfa` is false and ATT allows it.
- Persisted state uses the existing keys. Renaming a `UserDefaults` or Keychain key loses the
  value for every existing install, so treat it as a migration.
- A version bump changes `s.version` in `LinkrunnerKit.podspec`, `getPackageVersion()` in
  `Linkrunner.swift`, and adds a `CHANGELOG.md` entry, all together.
- Behaviour changes come with a unit test in `Tests/LinkrunnerKitTests`.
