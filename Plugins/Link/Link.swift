import Foundation
import PackagePlugin

@main
struct LinkCommand: CommandPlugin {
    static let pluginName: String = "link"

    static var logPrefix: String {
        "[\(pluginName)]"
    }

    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        // Create directory for intermediate files
        let intermediatesDir = context.pluginWorkDirectory
            .appending("intermediates")
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: intermediatesDir.string, isDirectory: true),
            withIntermediateDirectories: true
        )

        // TODO: Can we use the default build parameters the user is specifying on the command line (`-c release`, `--verbose`)?
        let buildParameters = PackageManager.BuildParameters(
            configuration: .release,
            logging: .concise
        )

        // Find external tools
        let clang = try context.tool(named: "clang")
        let commonClangArgs = [
            "--target=armv6m-none-eabi",
            "-mfloat-abi=soft",
            "-march=armv6m",
            "-O3",
            "-nostdlib",
        ]
        let objcopy = try context.tool(named: "objcopy")
        Diagnostics.remark("\(Self.logPrefix) clang: \(clang.path.string)")
        Diagnostics.remark("\(Self.logPrefix) objcopy: \(objcopy.path.string)")

        // Build boot2
        let boot2Product = try context.package.products(named: ["RP2040Boot2"])[0]
        let boot2Outputs = try buildAndPostprocessBoot2(
            product: boot2Product,
            packageManager: packageManager,
            buildParameters: buildParameters,
            intermediatesDir: intermediatesDir,
            clang: clang,
            commonCFlags: commonClangArgs,
            objcopy: objcopy
        )

        // Build the app
        Diagnostics.remark("\(Self.logPrefix) Creating app executable")
        let appProduct = try context.package.products(named: ["App"])[0]
        Diagnostics.remark("\(LinkCommand.logPrefix) Building product '\(appProduct.name)' with config '\(buildParameters.configuration.rawValue)'")
        let buildResult = try packageManager.build(
            .product(appProduct.name),
            parameters: buildParameters
        )
        guard buildResult.succeeded else {
            // TODO: Is printing correct? Or will this result in duplicated output? Should this be a Diagnostic?
            print(buildResult.logText)
            Diagnostics.error("\(Self.logPrefix) Building product '\(appProduct.name)' failed")
            throw BuildError()
        }
        let appStaticLib = buildResult.builtArtifacts[0]

        // Link the app
        let executableFilename = "\(appProduct.name).elf"
        let linkedExecutable = context.pluginWorkDirectory
            .appending(executableFilename)
        let rp2040SupportTarget = appProduct
            .targets[0]
            .recursiveTargetDependencies
            .first(where: { $0.name == "RP2040Support" })!
        let appLinkerScript = rp2040SupportTarget
            .directory
            .appending("linker-script", "memmap_default.ld")
        var appClangArgs = commonClangArgs
        appClangArgs.append(contentsOf: [
            "-DNDEBUG",
            "-Wl,--build-id=none",
            "-Xlinker", "--gc-sections",
            "-Xlinker", "--script=\(appLinkerScript.string)",
            "-Xlinker", "-z", "-Xlinker", "max-page-size=4096",
            "-Xlinker", "--wrap=__aeabi_lmul",
        ])
        appClangArgs.append(contentsOf: boot2Outputs.map(\.string))
        appClangArgs.append(contentsOf: [
            appStaticLib.path.string,
            "-o", linkedExecutable.string,
        ])
        try runProgram(clang.path, arguments: appClangArgs)

        print("Executable: \(linkedExecutable)")
    }
}

/// Builds the RP2040 second-stage bootloader (boot2).
///
/// - Returns: An array of paths to object files that must be linked into the
///   main app to create a valid RP2040 executable.
private func buildAndPostprocessBoot2(
    product: some Product,
    packageManager: PackageManager,
    buildParameters: PackageManager.BuildParameters,
    intermediatesDir: Path,
    clang: PluginContext.Tool,
    commonCFlags: [String],
    objcopy: PluginContext.Tool
) throws -> [Path] {
    Diagnostics.remark("\(LinkCommand.logPrefix) Building second-stage bootloader (boot2)")
    Diagnostics.remark("\(LinkCommand.logPrefix) Building product '\(product.name)' with config '\(buildParameters.configuration.rawValue)'")
    let buildResult = try packageManager.build(
        .product(product.name),
        parameters: buildParameters
    )
    guard buildResult.succeeded else {
        // TODO: Is printing correct? Or will this result in duplicated output? Should this be a Diagnostic?
        print(buildResult.logText)
        Diagnostics.error("\(LinkCommand.logPrefix) Building product '\(product.name)' failed")
        throw BuildError()
    }
    let staticLib = buildResult.builtArtifacts[0]

    // Postprocessing
    Diagnostics.remark("\(LinkCommand.logPrefix) Calculating boot2 checksum and embedding it into the binary")

    // 1. Link boot2 into .elf file
    let boot2Target = product.targets[0]
    let linkerScript = boot2Target
        .directory
        .appending("linker-script", "boot_stage2.ld")
    let preChecksumELF = intermediatesDir.appending("bs2_default.elf")
    var preChecksumClangArgs = commonCFlags
    preChecksumClangArgs.append(contentsOf: [
        "-DNDEBUG",
        "-Wl,--build-id=none",
        // We must tell the linker to keep all .o files in the .a file.
        // Without this, the linker will create an empty .elf file because no
        // symbols are referenced.
        //
        // On macOS, we may need -all_load or similar here.
        "-Xlinker", "--whole-archive",
        "-Xlinker", "--script=\(linkerScript.string)",
        "-o", preChecksumELF.string
    ])
    preChecksumClangArgs.append(contentsOf: buildResult.builtArtifacts.map(\.path.string))
    try runProgram(clang.path, arguments: preChecksumClangArgs)

    // 2. Convert .elf to .bin
    let preChecksumBin = intermediatesDir.appending("\(preChecksumELF.stem).bin")
    let objcopyArgs = [
        "-Obinary",
        preChecksumELF.string,
        preChecksumBin.string
    ]
    try runProgram(objcopy.path, arguments: objcopyArgs)

    // 3. Calculate checksum and write into assembly file
    let checksummedAsm = intermediatesDir.appending("bs2_default_padded_checksummed.s")
    let padChecksumScript = boot2Target
        .directory
        .appending("pad-checksum", "pad_checksum")
    let padChecksumArgs = [
        "-s", "0xffffffff",
        preChecksumBin.string,
        checksummedAsm.string
    ]
    try runProgram(padChecksumScript, arguments: padChecksumArgs)

    // 4. Assemble checksummed boot2 loader
    let checksummedObj = intermediatesDir.appending("bs2_default_padded_checksummed.s.o")
    var checksummedObjClangArgs = commonCFlags
    checksummedObjClangArgs.append(contentsOf: [
        "-c", checksummedAsm.string,
        "-o", checksummedObj.string
    ])
    try runProgram(clang.path, arguments: checksummedObjClangArgs)

    return [checksummedObj]
}

/// Runs an external program and waits for it to finish.
///
/// Emits SwiftPM diagnostics:
/// - `remark` with the invocation (exectuable + arguments)
/// - `error` on non-zero exit code
///
/// - Throws:
///   - When the program cannot be launched.
///   - Throws `ExitCode` when the program completes with a non-zero status.
private func runProgram(
    _ executable: Path,
    arguments: [String],
    workingDirectory: Path? = nil
) throws {
    // If the command is longer than approx. one line, format it neatly
    // on multiple lines for logging.
    let fullCommand = "\(executable.string) \(arguments.joined(separator: " "))"
    let logMessage = if fullCommand.count < 70 {
        fullCommand
    } else {
        """
        \(executable.string) \\
            \(arguments.joined(separator: " \\\n    "))
        """
    }
    Diagnostics.remark("\(LinkCommand.logPrefix) \(logMessage)")

    let process = Process()
    process.executableURL = URL(
        fileURLWithPath: executable.string,
        isDirectory: false
    )
    process.arguments = arguments
    if let workingDirectory {
        process.currentDirectoryURL = URL(
            fileURLWithPath: workingDirectory.string,
            isDirectory: true
        )
    }
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        Diagnostics.error("\(LinkCommand.logPrefix) \(executable.lastComponent) exited with code \(process.terminationStatus)")
        throw ExitCode(process.terminationStatus)
    }
}

struct ExitCode: RawRepresentable, Error {
    var rawValue: Int32

    init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    init(_ code: Int32) {
        self.init(rawValue: code)
    }
}

struct BuildError: Error {}
