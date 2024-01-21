// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RP2040",
    products: [
        .library(name: "App", type: .static, targets: ["App"]),
        .library(name: "RP2040Boot2", type: .static, targets: ["RP2040Boot2"]),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: ["MMIOVolatile", "RP2040Support"],
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
        .target(
            name: "RP2040Support",
            resources: [
                .copy("linker-script/memmap_default.ld"),
            ],
            publicHeadersPath: "",
            cSettings: [
                .headerSearchPath("headers"),
                .define("NDEBUG"),
                .unsafeFlags([
                    "-mfloat-abi=soft",
                    "-march=armv6m",
                    "-ffunction-sections",
                    "-fdata-sections",
                ]),
            ]
        ),
        .target(
            name: "RP2040Boot2",
            resources: [
                .copy("linker-script/boot_stage2.ld"),
                .copy("pad-checksum/pad_checksum"),
            ],
            publicHeadersPath: "",
            cSettings: [
                .headerSearchPath("headers"),
                .define("NDEBUG"),
                .unsafeFlags([
                    "-mfloat-abi=soft",
                    "-march=armv6m",
                    "-ffunction-sections",
                    "-fdata-sections",
                ]),
            ]
        ),
        .plugin(
            name: "Link",
            capability: .command(
                intent: .custom(
                    verb: "link",
                    description: "Links the final executable for the RP2040"
                )
            )
        ),
    ]
)
