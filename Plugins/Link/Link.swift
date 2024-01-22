import Foundation
import PackagePlugin

@main
struct Link: CommandPlugin {
    static let pluginName: String = "link"

    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let clang = try context.tool(named: "clang")
        let clangURL = URL(
            fileURLWithPath: clang.path.string,
            isDirectory: false
        )
        Diagnostics.remark("[\(Self.pluginName)] clang: \(clang.path.string)")
        let commonClangArgs = [
            "--target=armv6m-none-eabi",
            "-mfloat-abi=soft",
            "-march=armv6m",
            "-O3",
            "-nostdlib",
        ]

        let buildParams = PackageManager.BuildParameters(
            configuration: .release,
            logging: .concise
        )

        // Build RP2040 second-stage bootloader (boot2)
        let boot2Product = try context.package.products(named: ["RP2040Boot2"])[0]
        Diagnostics.remark("[\(Self.pluginName)] Building product '\(boot2Product.name)'")
        let boot2BuildResult = try packageManager.build(
            .product(boot2Product.name),
            parameters: buildParams
        )
        guard boot2BuildResult.succeeded else {
            print(boot2BuildResult.logText)
            Diagnostics.error("[\(Self.pluginName)] Building product '\(boot2Product.name)' failed")
            // TODO: Exit with error code
            return
        }
        let boot2StaticLib = boot2BuildResult.builtArtifacts[0]

        // Create directory for intermediate files
        let intermediatesDir = context.pluginWorkDirectory
            .appending(subpath: "intermediates")
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: intermediatesDir.string, isDirectory: true),
            withIntermediateDirectories: true
        )

        // Postprocess boot2
        Diagnostics.remark("[\(Self.pluginName)] Boot2 processing")
        //
        // 1. Extract .o file from static library build product (.a)
        // For some reason, if I try to link the .a file with Clang, it doesn't work.
        // I need to pass in the .o file. What's the difference?
        // The only difference I can see (with `file`) is that the .a file doesn't
        // contain debug info, whereas the .o file does. Is this relevant? I don't
        // think so because when I extract the .o file from the .a file, the debug
        // info is back (according to `file`).
        // How does SwiftPM create the .a file? Anything suspicious?
        let ar = try context.tool(named: "ar")
        let boot2ObjFile = intermediatesDir.appending(subpath: "compile_time_choice.S.o")
        let arArgs = [
            "x",
            boot2StaticLib.path.string,
            boot2ObjFile.lastComponent // ar always extracts to the current dir
        ]
        try runProgram(ar.path, arguments: arArgs, workingDirectory: intermediatesDir)

        // 2. Apply boot2 linker script
        let boot2ELF = intermediatesDir.appending(subpath: "bs2_default.elf")
        let boot2LinkerScript = boot2Product
            .sourceModules[0]
            .sourceFiles(withSuffix: "ld")
            .first(where: { $0.type == .resource && $0.path.lastComponent == "boot_stage2.ld" })!
        var boot2ELFClangArgs = commonClangArgs
        boot2ELFClangArgs.append(contentsOf: [
            "-DNDEBUG",
            "-Wl,--build-id=none",
            "-Xlinker", "--script=\(boot2LinkerScript.path.string)",
            boot2ObjFile.string,
            "-o", boot2ELF.string
        ])
        boot2ELFClangArgs.append(contentsOf: boot2BuildResult.builtArtifacts.map(\.path.string))
        try runProgram(clang.path, arguments: boot2ELFClangArgs)

        // 3. Convert boot2.elf to boot2.bin
        let boot2Bin = intermediatesDir.appending(subpath: "bs2_default.bin")
        let objcopy = try context.tool(named: "objcopy")
        let objcopyURL = URL(fileURLWithPath: objcopy.path.string, isDirectory: false)
        let objcopyArgs = [
            "-Obinary",
            boot2ELF.string,
            boot2Bin.string
        ]
        try runProgram(objcopy.path, arguments: objcopyArgs)

        // 4. Calculate checksum and write into assembly file
        let boot2ChecksummedAsm = intermediatesDir
            .appending(subpath: "bs2_default_padded_checksummed.s")
        let padChecksumScript = boot2Product
            .sourceModules[0]
            .sourceFiles
            .first(where: { $0.type == .resource && $0.path.lastComponent == "pad_checksum" })!
        let padChecksumArgs = [
            "-s", "0xffffffff",
            boot2Bin.string,
            boot2ChecksummedAsm.string
        ]
        try runProgram(padChecksumScript.path, arguments: padChecksumArgs)

        // 5. Assemble checksummed boot2 loader
        let boot2ChecksummedObj = intermediatesDir.appending(subpath: "bs2_default_padded_checksummed.s.o")
        var boot2ObjClangArgs = commonClangArgs
        boot2ObjClangArgs.append(contentsOf: [
            "-c", boot2ChecksummedAsm.string,
            "-o", boot2ChecksummedObj.string
        ])
        try runProgram(clang.path, arguments: boot2ObjClangArgs)

        // Build the app
        let appProduct = try context.package.products(named: ["App"])[0]
        let appBuildResult = try packageManager.build(
            .product(appProduct.name),
            parameters: buildParams
        )
        guard appBuildResult.succeeded else {
            print(appBuildResult.logText)
            Diagnostics.error("[\(Self.pluginName)] Building product '\(appProduct.name)' failed")
            // TODO: Exit with error code
            return
        }
        let appStaticLib = appBuildResult.builtArtifacts[0]

        // Link the app
        let executableFilename = "\(appProduct.name).elf"
        let linkedExecutable = context.pluginWorkDirectory
            .appending(subpath: executableFilename)
        let appLinkerScript = appProduct
            .targets[0]
            .recursiveTargetDependencies
            .first(where: { $0.name == "RP2040Support" })!
            .sourceModule!
            .sourceFiles(withSuffix: "ld")
            .first(where: { $0.type == .resource && $0.path.lastComponent == "memmap_default.ld" })!
        var appClangArgs = commonClangArgs
        appClangArgs.append(contentsOf: [
            "-DNDEBUG",
            "-Wl,--build-id=none",
            "-Xlinker", "--gc-sections",
            "-Xlinker", "--script=\(appLinkerScript.path.string)",
            "-Xlinker", "-z", "-Xlinker", "max-page-size=4096",
            "-Xlinker", "--wrap=__aeabi_lmul",
            appStaticLib.path.string,
            boot2ChecksummedObj.string,
            "-o", linkedExecutable.string,
        ])
        try runProgram(clang.path, arguments: appClangArgs)

        print("Executable: \(linkedExecutable)")
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
        Diagnostics.remark("[\(Self.pluginName)] \(logMessage)")

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
            Diagnostics.error("[\(Self.pluginName)] \(executable.lastComponent) exited with code \(process.terminationStatus)")
            throw ExitCode(process.terminationStatus)
        }
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
