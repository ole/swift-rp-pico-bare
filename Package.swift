// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RP2040",
    products: [
        // The main executable for the RP2040, written in Swift.
        // This is the program we want to flash to the RP2040.
        //
        // Ideally, this would be an executable product, but I couldn't get that
        // to work under Embedded Swift. So we build a static library and then
        // use the Link plugin to link it into an .elf file.
        .library(name: "App", type: .static, targets: ["App"]),
        .library(name: "RP2040Boot2", type: .static, targets: ["RP2040Boot2"]),
    ],
    targets: [
        // The main executable for the RP2040, written in Swift.
        .target(
            name: "App",
            dependencies: ["RP2040"],
            swiftSettings: [
                .enableExperimentalFeature("Embedded"),
                .unsafeFlags([
                    "-whole-module-optimization",
                    "-Xfrontend", "-function-sections",
                ]),
            ]
        ),
        // Our RP2040 "SDK", written in Swift. Vends the APIs used by the app.
        .target(
            name: "RP2040",
            dependencies: ["MMIOVolatile", "RP2040Support"],
            swiftSettings: [
                .enableExperimentalFeature("Embedded"),
                .unsafeFlags([
                    "-whole-module-optimization",
                    "-Xfrontend", "-function-sections",
                ]),
            ]
        ),
        .target(name: "MMIOVolatile", publicHeadersPath: ""),
        // Minimal RP2040 runtime support, linker script, etc.
        .target(
            name: "RP2040Support",
            exclude: [
                "linker-script",
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
        // The second-stage bootloader (Boot2) for the RP2040.
        .target(
            name: "RP2040Boot2",
            exclude: [
                "linker-script",
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
        // SwiftPM plugin for linking the final executable.
        // This creates the .elf file we can flash to the RP2040.
        .plugin(
            name: "Link",
            capability: .command(
                intent: .custom(
                    verb: "link",
                    description: "Links the final executable for the RP2040"
                )
            ),
            dependencies: [
                "RP2040Boot2Checksum",
            ]
        ),
        // Computes the CRC32 checksum for the second-stage bootloader.
        .executableTarget(name: "RP2040Boot2Checksum"),
    ]
)
