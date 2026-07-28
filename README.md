# Linkrunner iOS SDK

A Swift package for integrating Linkrunner functionality into your iOS applications.

## Documentation

For setup instructions, usage examples, and API reference, please visit:

[Linkrunner iOS SDK Documentation](https://docs.linkrunner.io/sdk/ios/installation)

## Google On-Device Measurement (ODM)

From 4.1.0 LinkrunnerKit depends on [`GoogleAdsOnDeviceConversion`](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk), which supplies the `odm_info` value used by Google Integrated Conversion Measurement.

### Linker flags

The Google framework requires two flags in **Other Linker Flags** on your app target:

```
-ObjC -lc++
```

CocoaPods applies these for you. Swift Package Manager and manual integrations must add them.

### Version compatibility with Firebase Analytics

If your app also uses Firebase Analytics (GA4F) 11.14.0+, it already pulls `GoogleAdsOnDeviceConversion` transitively. The two must agree or you will hit build or runtime failures. Google's compatibility table:

| GA4F SDK | GoogleAdsOnDeviceConversion |
| --- | --- |
| 12.16.0 | 3.6.1 |
| 12.15.0 | 3.6.0 |
| 12.14.0 | 3.6.0 |
| 12.13.0 | 3.5.0 |
| 12.12.1 | 3.5.0 |
| 12.12.0 | 3.4.0 |
| 12.11.0 | 3.4.0 |
| 12.10.0 | 3.3.0 |
| 12.5.0 – 12.9.0 | 3.2.0 |
| 12.4.0 | 3.1.0 |
| 12.3.0 | 3.0.0 |
| 12.2.0 | 2.3.0 |
| 12.1.0 | 2.2.0 |
| 11.15.0 – 12.0.0 | 2.1.0 |
| 11.14.0 | 2.0.0 |

LinkrunnerKit pins `~> 3.6`. If you need a different version, override the dependency in your `Podfile` or `Package.swift` to match your GA4F version.

### Scope

ODM applies to the European Economic Area, the United Kingdom and Switzerland. Elsewhere no value is produced and the SDK simply omits the field. ODM does not require ATT authorization or IDFA.

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details.

Copyright (c) 2025 Linkrunner Private Limited
