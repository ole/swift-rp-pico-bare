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
        .executable(name: "Executable", targets: ["Executable"]),
    ],
    targets: [
        .executableTarget(
            name: "Executable",
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
                    "-Xlinker", "--script=RP2040Support/memmap_default.ld",
                    "-nostartfiles",
                    "-Xlinker", "-Wl,--build-id=none",
                    "-Xlinker", "-nostdlib",
                    "-Xlinker", "-z", "-Xlinker", "max-page-size=4096",
                    "-Xlinker", "--gc-sections",
                    "-Xlinker", "RP2040Support/bs2_default_padded_checksummed.S.obj",
                    "-Xlinker", "RP2040Support/crt0.S.obj",
                    "-Xlinker", "RP2040Support/bootrom.c.obj",
                    "-Xlinker", "RP2040Support/pico_int64_ops_aeabi.S.obj",
                ]),
            ]
        ),
        .target(
            name: "MMIOVolatile",
            publicHeadersPath: ""
        ),
    ]
)
