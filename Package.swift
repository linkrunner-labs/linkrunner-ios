// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Linkrunner",
    defaultLocalization: "en",
    platforms: [.iOS(.v15)],
    products: [
        // Default library - SPM will choose appropriate linkage based on client needs
        .library(
            name: "Linkrunner",
            targets: ["Linkrunner"]
        ),
        // Static library for when static linking is explicitly required
        .library(
            name: "LinkrunnerStatic",
            type: .static,
            targets: ["Linkrunner"]
        ),
        // Dynamic library for when dynamic linking is explicitly required
        .library(
            name: "LinkrunnerDynamic",
            type: .dynamic,
            targets: ["Linkrunner"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Linkrunner",
            dependencies: [],
            path: "Sources/Linkrunner",
            cSettings: [
                .define("SWIFT_PACKAGE")
            ],
            swiftSettings: [
                .define("LINKRUNNER_SPM"),
                // Enable library evolution for better binary compatibility
                .unsafeFlags(["-enable-library-evolution"]),
                // This is important for binary frameworks to maintain ABI stability
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        ),
        .testTarget(
            name: "LinkrunnerTests",
            dependencies: ["Linkrunner"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
