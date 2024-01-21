// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

// Usage:
//
// swift build \
//     --toolchain /Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2024-01-14-a.xctoolchain/ \
//     --triple armv6m-none-none-eabi

import PackageDescription

let package = Package(
    name: "RP2040",
    products: [
        .library(name: "App", type: .static, targets: ["App"]),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: ["MMIOVolatile"],
            cSettings: [
                .define("NDEBUG"),
                .unsafeFlags([
                    "-mfloat-abi=soft",
                    "-march=armv6m",
                    "-nostdlib",
                ]),
            ],
            swiftSettings: [
                .enableExperimentalFeature("Embedded"),
                .unsafeFlags([
                    "-whole-module-optimization",
                    "-Xfrontend", "-function-sections",
                ]),
            ]
        ),
        .target(
            name: "MMIOVolatile",
            publicHeadersPath: ""
        ),
    ]
)
