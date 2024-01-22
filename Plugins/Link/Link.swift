import Foundation
import PackagePlugin

@main
struct Link: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let clang = try context.tool(named: "clang")
        let clangURL = URL(
            fileURLWithPath: clang.path.string,
            isDirectory: false
        )
        let commonClangArgs = [
            "--target=armv6m-none-eabi",
            "-mfloat-abi=soft",
            "-march=armv6m",
            "-O3",
            "-DNDEBUG",
            "-nostdlib",
            "-Wl,--build-id=none",
        ]

        let buildParams = PackageManager.BuildParameters(
            configuration: .release,
            logging: .concise
        )

        // Build RP2040 second-stage bootloader (boot2)
        let boot2Product = try context.package.products(named: ["RP2040Boot2"])[0]
        let boot2BuildResult = try packageManager.build(
            .product(boot2Product.name),
            parameters: buildParams
        )
        guard boot2BuildResult.succeeded else {
            print(boot2BuildResult.logText)
            Diagnostics.error("Building product '\(boot2Product.name)' failed")
            // TODO: Exit with error code
            return
        }
        let boot2StaticLib = boot2BuildResult.builtArtifacts[0]

        // Create directory for intermediate files
        let intermediatesDir = context.pluginWorkDirectory
            .appending(subpath: "intermediates")
        let intermediatesDirURL = URL(fileURLWithPath: intermediatesDir.string, isDirectory: true)
        try FileManager.default.createDirectory(
            at: intermediatesDirURL,
            withIntermediateDirectories: true
        )

        // Postprocess boot2
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
        let arURL = URL(fileURLWithPath: ar.path.string, isDirectory: false)
        let boot2ObjFile = intermediatesDir.appending(subpath: "compile_time_choice.S.o")
        let arArgs = [
            "x",
            boot2StaticLib.path.string,
            boot2ObjFile.lastComponent // ar always extracts to the current dir
        ]
        let arProcess = Process()
        arProcess.executableURL = arURL
        arProcess.arguments = arArgs
        arProcess.currentDirectoryURL = intermediatesDirURL
        try arProcess.run()
        arProcess.waitUntilExit()
        guard arProcess.terminationStatus == 0 else {
            Diagnostics.error("ar failed")
            // TODO: Exit with error code
            return
        }

        // 2. Apply boot2 linker script
        let boot2ELF = intermediatesDir.appending(subpath: "bs2_default.elf")
        let boot2LinkerScript = boot2Product
            .sourceModules[0]
            .sourceFiles(withSuffix: "ld")
            .first(where: { $0.type == .resource && $0.path.lastComponent == "boot_stage2.ld" })!
        var boot2ELFClangArgs = commonClangArgs
        boot2ELFClangArgs.append(contentsOf: [
            "-Xlinker", "--script=\(boot2LinkerScript.path.string)",
            boot2ObjFile.string,
            "-o", boot2ELF.string
        ])
        boot2ELFClangArgs.append(contentsOf: boot2BuildResult.builtArtifacts.map(\.path.string))
        let boot2ELFProcess = try Process.run(clangURL, arguments: boot2ELFClangArgs)
        boot2ELFProcess.waitUntilExit()
        guard boot2ELFProcess.terminationStatus == 0 else {
            Diagnostics.error("Clang failed linking boot2 elf file before checksumming")
            // TODO: Exit with error code
            return
        }

        // 3. Convert boot2.elf to boot2.bin
        let boot2Bin = intermediatesDir.appending(subpath: "bs2_default.bin")
        let objcopy = try context.tool(named: "objcopy")
        let objcopyURL = URL(fileURLWithPath: objcopy.path.string, isDirectory: false)
        let objcopyArgs = [
            "-Obinary",
            boot2ELF.string,
            boot2Bin.string
        ]
        let objcopyProcess = try Process.run(objcopyURL, arguments: objcopyArgs)
        objcopyProcess.waitUntilExit()
        guard objcopyProcess.terminationStatus == 0 else {
            Diagnostics.error("objcopy failed")
            // TODO: Exit with error code
            return
        }

        // 4. Calculate checksum and write into assembly file
        let boot2ChecksummedAsm = intermediatesDir
            .appending(subpath: "bs2_default_padded_checksummed.s")
        let padChecksumScript = boot2Product
            .sourceModules[0]
            .sourceFiles
            .first(where: { $0.type == .resource && $0.path.lastComponent == "pad_checksum" })!
        let padChecksumURL = URL(fileURLWithPath: padChecksumScript.path.string, isDirectory: false)
        let padChecksumArgs = [
            "-s", "0xffffffff",
            boot2Bin.string,
            boot2ChecksummedAsm.string
        ]
        let padChecksumProcess = try Process.run(padChecksumURL, arguments: padChecksumArgs)
        padChecksumProcess.waitUntilExit()
        guard padChecksumProcess.terminationStatus == 0 else {
            Diagnostics.error("pad_checksum failed")
            // TODO: Exit with error code
            return
        }

        // 5. Assemble checksummed boot2 loader
        let boot2ChecksummedObj = intermediatesDir.appending(subpath: "bs2_default_padded_checksummed.s.o")
        var boot2ObjClangArgs = commonClangArgs
        boot2ObjClangArgs.append(contentsOf: [
            "-c", boot2ChecksummedAsm.string,
            "-o", boot2ChecksummedObj.string
        ])
        let boot2ObjProcess = try Process.run(clangURL, arguments: boot2ObjClangArgs)
        boot2ObjProcess.waitUntilExit()
        guard boot2ObjProcess.terminationStatus == 0 else {
            Diagnostics.error("Clang failed linking boot2 obj file")
            // TODO: Exit with error code
            return
        }

        // Build the app
        let appProduct = try context.package.products(named: ["App"])[0]
        let appBuildResult = try packageManager.build(
            .product(appProduct.name),
            parameters: buildParams
        )
        guard appBuildResult.succeeded else {
            print(appBuildResult.logText)
            Diagnostics.error("Building product '\(appProduct.name)' failed")
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
            "-Xlinker", "--gc-sections",
            "-Xlinker", "--script=\(appLinkerScript.path.string)",
            "-Xlinker", "-z", "-Xlinker", "max-page-size=4096",
            "-Xlinker", "--wrap=__aeabi_lmul",
            appStaticLib.path.string,
            boot2ChecksummedObj.string,
            "-o", linkedExecutable.string,
        ])
        let appClangProcess = try Process.run(clangURL, arguments: appClangArgs)
        appClangProcess.waitUntilExit()
        guard appClangProcess.terminationStatus == 0 else {
            Diagnostics.error("Clang failed linking app executable")
            // TODO: Exit with error code
            return
        }

        print("Executable: \(linkedExecutable)")
    }
}
