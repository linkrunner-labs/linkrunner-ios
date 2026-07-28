// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LinkrunnerKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v15)],
    products: [
        // Default library - SPM will choose appropriate linkage based on client needs
        .library(
            name: "LinkrunnerKit",
            targets: ["LinkrunnerKit"]
        ),
        // Static library for when static linking is explicitly required
        .library(
            name: "LinkrunnerKitStatic",
            type: .static,
            targets: ["LinkrunnerKit"]
        ),
        // Dynamic library for when dynamic linking is explicitly required
        .library(
            name: "LinkrunnerKitDynamic",
            type: .dynamic,
            targets: ["LinkrunnerKit"]
        )
    ],
    dependencies: [
        // Google On-Device Measurement (ODM) — produces the opaque `odm_info` value
        // required by Google Integrated Conversion Measurement on iOS.
        // Pinned to the minor: Google ships the GA4F compatibility table per minor
        // (see README), and mismatches surface as build/runtime failures in apps
        // that also pull ODM transitively via Firebase Analytics.
        .package(
            url: "https://github.com/googleads/google-ads-on-device-conversion-ios-sdk.git",
            .upToNextMinor(from: "3.6.1")
        )
    ],
    targets: [
        .target(
            name: "LinkrunnerKit",
            dependencies: [
                .product(
                    name: "GoogleAdsOnDeviceConversion",
                    package: "google-ads-on-device-conversion-ios-sdk"
                )
            ],
            path: "Sources/Linkrunner",
            exclude: ["include"],
            cSettings: [
                .define("SWIFT_PACKAGE")
            ],
            swiftSettings: [
                .define("LINKRUNNERKIT_SPM"),
                // This is important for binary frameworks to maintain ABI stability
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        .testTarget(
            name: "LinkrunnerKitTests",
            dependencies: ["LinkrunnerKit"],
            path: "Tests/LinkrunnerKitTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
