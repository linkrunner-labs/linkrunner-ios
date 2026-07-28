# Linkrunner iOS SDK

A Swift package for integrating Linkrunner functionality into your iOS applications.

## Documentation

For setup instructions, usage examples, and API reference, please visit:

[Linkrunner iOS SDK Documentation](https://docs.linkrunner.io/sdk/ios/installation)

## Google Integrated Conversion Measurement (ICM)

ICM improves Google App Campaign attribution when no click identifier or advertising ID is available. It needs Google's [On-Device Measurement SDK](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk), which produces the `odm_info` value LinkrunnerKit forwards.

**LinkrunnerKit does not bundle that SDK.** It is detected at runtime, so if you don't use ICM you carry none of its weight — no extra dependency, no change to how LinkrunnerKit links, no size increase. This matches how Branch and Kochava integrate the same SDK.

### Opting in

Add Google's SDK to your app. If you already use the Firebase iOS SDK (11.14.0+) you have it — nothing further to do.

**CocoaPods**

```ruby
pod 'GoogleAdsOnDeviceConversion'
```

**Swift Package Manager** — add `https://github.com/googleads/google-ads-on-device-conversion-ios-sdk` and select the `GoogleAdsOnDeviceConversion` product.

That's the whole integration. LinkrunnerKit picks it up automatically on the next launch; there is no API to call.

### Linker flags

**CocoaPods: nothing to do.** CocoaPods adds `-ObjC` and `-lc++` to your target automatically when it links Google's static framework.

**Swift Package Manager and manual integration:** add this to **Build Settings → Other Linker Flags** on your app target:

```
-ObjC
```

LinkrunnerKit finds Google's class through the Objective-C runtime rather than importing it, so nothing references it at link time. Google ships a static library, and linkers only keep static-library members that something references. Without `-ObjC` the class is stripped, the lookup finds nothing, and ICM silently does nothing while your build still succeeds. `-lc++` is applied for you by Google's `Package.swift`.

### Verifying it is active

With `debug: true`, initialization logs:

```
Linkrunner: odm_available=true odm_fetch_result=success odm_fetch_latency_ms=…
```

`odm_available=false` with `odm_fetch_result=unavailable` means Google's SDK is not linked. On Swift Package Manager, check that `-ObjC` is set, since a missing flag strips the class with no build warning. The raw `odm_info` value is never logged.

### Scope

ICM applies to the European Economic Area, the United Kingdom and Switzerland. Elsewhere Google may return no value and the field is simply omitted. ODM requires neither ATT authorization nor IDFA.

For EEA/UK/Swiss users you should also supply consent via `setConsent(_:)` or `enableTCFConsentCollection(true)` — without it consent is reported as unknown, which limits attribution.

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.

Copyright (c) 2025 Linkrunner Private Limited
