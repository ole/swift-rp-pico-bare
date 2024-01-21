import Foundation
import PackagePlugin

@main
struct Link: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let appProduct = try context.package.products(named: ["App"])[0]

        let buildParams = PackageManager.BuildParameters(
            configuration: .release,
            logging: .concise
        )
        let buildResult = try packageManager.build(
            .product("App"),
            parameters: buildParams
        )
        guard buildResult.succeeded else {
            print(buildResult.logText)
            Diagnostics.error("Build failed")
            return
        }

        let appStaticLib = buildResult.builtArtifacts[0]

        let rp2040SupportFiles = [
            "bs2_default_padded_checksummed.S.obj",
            "crt0.S.obj",
            "bootrom.c.obj",
            "pico_int64_ops_aeabi.S.obj",
        ]
        let rp2040SupportDir = context.package.directory
            .appending(subpath: "RP2040Support")

        let executableFilename = "\(appProduct.name).elf"
        let linkedExecutable = context.pluginWorkDirectory
            .appending(subpath: executableFilename)

        let clang = try context.tool(named: "clang")
        let clangURL = URL(fileURLWithPath: clang.path.string, isDirectory: false)
        var clangArgs = [
            "--target=armv6m-none-eabi",
            "-mfloat-abi=soft",
            "-march=armv6m",
            "-nostdlib",
            "-Wl,--build-id=none",
            "-O3",
            "-Xlinker", "--script=RP2040Support/memmap_default.ld",
            "-Xlinker", "-z", "-Xlinker", "max-page-size=4096",
            "-Xlinker", "--gc-sections",
            "-Xlinker", "--wrap=__aeabi_lmul",
        ]
        clangArgs.append(appStaticLib.path.string)
        clangArgs.append(contentsOf: rp2040SupportFiles.map { filename in
            rp2040SupportDir.appending(subpath: filename).string
        })
        clangArgs.append(contentsOf: ["-o", linkedExecutable.string])

        let process = try Process.run(clangURL, arguments: clangArgs)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            Diagnostics.error("Clang failed")
            return
        }

        print("Executable: \(linkedExecutable)")
    }
}
