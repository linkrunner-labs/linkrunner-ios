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
    // Intentionally dependency-free. Google's On-Device Measurement SDK is detected at
    // runtime rather than linked (see ODMService), so apps that do not use Integrated
    // Conversion Measurement carry none of its weight. Apps that do want ICM add
    // GoogleAdsOnDeviceConversion themselves, or get it via the Firebase iOS SDK.
    dependencies: [],
    targets: [
        .target(
            name: "LinkrunnerKit",
            dependencies: [],
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
