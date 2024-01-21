// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RP2040",
    products: [
        .library(name: "App", type: .static, targets: ["App"]),
        .plugin(name: "Link", targets: ["Link"]),
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
        .plugin(
            name: "Link",
            capability: .command(
                intent: .custom(
                    verb: "link",
                    description: "Links the final executable for the RP2040"
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "Creates the final executable")
                ]
            )
        ),
    ]
)
