// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "NCCOpenAppleSearchAdsInstallAttribution",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NCCOpenAppleSearchAdsInstallAttribution",
            targets: ["NCCOpenAppleSearchAdsInstallAttribution"]),
    ],
    targets: [
        .target(
            name: "NCCOpenAppleSearchAdsInstallAttribution"),
        .testTarget(
            name: "NCCOpenAppleSearchAdsInstallAttributionTests",
            dependencies: ["NCCOpenAppleSearchAdsInstallAttribution"]),
    ]
)
