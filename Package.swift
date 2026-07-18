// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacMeter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacMeter", targets: ["MacMeter"])
    ],
    targets: [
        .target(
            name: "MacMeterSensors",
            path: "Sources/MacMeterSensors",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "MacMeter",
            dependencies: ["MacMeterSensors"],
            path: "Sources/MacMeter",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .testTarget(
            name: "MacMeterTests",
            dependencies: ["MacMeter"],
            path: "Tests/MacMeterTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
