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
        arguments commandLineArguments: [String]
    ) async throws {
        let arguments = try parseArguments(commandLineArguments)
        guard !arguments.shouldShowHelp else {
            print(
                """
                link: A SwiftPM command plugin for building an executable
                for the RP2040 microcontroller.

                USAGE:
                  swift package --triple armv6m-none-none-eabi link [options]

                OPTIONS:
                  --help        Display this help message.
                  --objcopy     Path to LLVM's objcopy tool, e.g. llvm-objcopy.
                                If omitted, we look for a tool named objcopy in
                                your PATH.
                """
            )
            return
        }

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
        let clang = CommandLineTool(try context.tool(named: "clang"))
        let commonClangArgs = [
            "--target=armv6m-none-eabi",
            "-mfloat-abi=soft",
            "-march=armv6m",
            "-O3",
            "-nostdlib",
        ]

        let objcopy: CommandLineTool
        do {
            // tool(named:) will find the tool if it's in the PATH, but it won't
            // find it if arguments.objcopyPath is a fully specified absolute or
            // relative path to a specific executable in a directory.
            let tool = try context.tool(named: arguments.objcopyPath ?? "objcopy")
            objcopy = CommandLineTool(tool)
        } catch {
            if let objcopyPath = arguments.objcopyPath {
                // Try to resolve the given path against the current working dir.
                let toolURL = URL(fileURLWithPath: objcopyPath, isDirectory: false).absoluteURL
                objcopy = CommandLineTool(name: "objcopy", url: toolURL)
            } else {
                throw error
            }
        }

        Diagnostics.remark("\(Self.logPrefix) clang: \(clang.path)")
        Diagnostics.remark("\(Self.logPrefix) objcopy: \(objcopy.path)")

        // Build and postprocess boot2
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
        Diagnostics.remark("\(Self.logPrefix) Building product '\(appProduct.name)' with config '\(buildParameters.configuration.rawValue)'")
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
        let executable = context.pluginWorkDirectory
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
            "-o", executable.string,
        ])
        try runProgram(clang.url, arguments: appClangArgs)

        print("Executable: \(executable)")
    }
}

struct CLIArguments {
    var shouldShowHelp: Bool
    var objcopyPath: Optional<String> = nil
}

private func parseArguments(_ arguments: [String]) throws -> CLIArguments {
    var argumentExtractor = ArgumentExtractor(arguments)
    let shouldShowHelp = argumentExtractor.extractFlag(named: "help") > 0
    let objcopyArgs = argumentExtractor.extractOption(named: "objcopy")
    if objcopyArgs.count > 1 {
        Diagnostics.error("\(LinkCommand.logPrefix) Argument --objcopy specified multiple times")
        throw BuildError()
    }
    if !argumentExtractor.remainingArguments.isEmpty {
        Diagnostics.error("\(LinkCommand.logPrefix) Unrecognized arguments: \(argumentExtractor.remainingArguments.joined(separator: " "))")
        throw BuildError()
    }
    return CLIArguments(
        shouldShowHelp: shouldShowHelp,
        objcopyPath: objcopyArgs.first
    )
}

/// Duplicate of `PluginContext.Tool`. Needed because that struct has no public
/// initializer.
struct CommandLineTool {
    var name: String
    var url: URL

    var path: String {
        url.path
    }
}

extension CommandLineTool {
    init(_ pluginContextTool: PluginContext.Tool) {
        self.name = pluginContextTool.name
        self.url = URL(fileURLWithPath: pluginContextTool.path.string, isDirectory: false)
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
    clang: CommandLineTool,
    commonCFlags: [String],
    objcopy: CommandLineTool
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
    try runProgram(clang.url, arguments: preChecksumClangArgs)

    // 2. Convert .elf to .bin
    let preChecksumBin = intermediatesDir.appending("\(preChecksumELF.stem).bin")
    let objcopyArgs = [
        "-Obinary",
        preChecksumELF.string,
        preChecksumBin.string
    ]
    try runProgram(objcopy.url, arguments: objcopyArgs)

    // 3. Calculate checksum and write into assembly file
    let checksummedAsm = intermediatesDir.appending("bs2_default_padded_checksummed.s")
    let padChecksumScript = URL(filePath: boot2Target.directory.string, directoryHint: .isDirectory)
        .appending(components: "pad-checksum", "pad_checksum")
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
    try runProgram(clang.url, arguments: checksummedObjClangArgs)

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
    _ executable: URL,
    arguments: [String],
    workingDirectory: Path? = nil
) throws {
    // If the command is longer than approx. one line, format it neatly
    // on multiple lines for logging.
    let fullCommand = "\(executable.path) \(arguments.joined(separator: " "))"
    let logMessage = if fullCommand.count < 70 {
        fullCommand
    } else {
        """
        \(executable.path) \\
            \(arguments.joined(separator: " \\\n    "))
        """
    }
    Diagnostics.remark("\(LinkCommand.logPrefix) \(logMessage)")

    let process = Process()
    process.executableURL = executable
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
        Diagnostics.error("\(LinkCommand.logPrefix) \(executable.lastPathComponent) exited with code \(process.terminationStatus)")
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
