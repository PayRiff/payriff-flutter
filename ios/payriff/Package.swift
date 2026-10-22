// swift-tools-version: 5.9
// Swift Package Manager manifest for the payriff Flutter plugin (iOS).
// CocoaPods uses ../payriff.podspec with the same sources.

import PackageDescription

let package = Package(
    name: "payriff",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "payriff", targets: ["payriff"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "payriff",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
